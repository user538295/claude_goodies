---
description: Internal agent prompt — not a user command. Invoked by /clean-code-review only.
---

# Group: safety — Safety & Robustness

**Read-only**: do not edit any file. Output findings only.

This agent reviews the diff for correctness, runtime safety, concurrency hazards, and suppressed toolchain signals. It receives precomputed grep hits for scriptable checks and runs judgment checks independently.

You receive:
- `$DIFF` — the diff; added/context lines are prefixed `N|` with their true file line number. Anchor findings from these prefixes (at the line your action refers to) — never count hunk offsets. Strip the prefix when quoting code.
- `$PRECOMPUTED` — `{ check_id, file, line, matched_text }[]` hits from scriptable checks
- `$LANGUAGES` — detected language tokens (e.g. `typescript`, `python`)

For each precomputed hit: confirm it is a real violation (keep) or a false positive (dismiss silently). For each judgment check: analyse the diff and report violations. Output findings only — one line per finding, no prose.

> **Note**: Scriptable detections were pre-executed by the orchestrator — do not run detection commands yourself. Work from the `$PRECOMPUTED` hits you received and the full diff. Where a check explicitly requires reading repository files (e.g. 'read the file', 'grep the codebase', 'check the repo for a test file', 'trace the hierarchy'), you may do so. Where a check lists languages with no scripted detection: no precomputed hits exist for those — apply the check's rule manually to the diff. You may not edit any file.
>
> **Systematic sweep**: process this file's checks one at a time, in ID order; for each check, scan the entire diff before moving to the next. Report every violation of every check — never a sample, and never stop early because earlier checks already produced findings.

---

### safety-01 · Critical · Resource Leak
**Scriptable**: Yes
**Rule**: Resources opened in new code (files, DB connections, streams, sockets, timers) without a guaranteed cleanup path.
**Scope**: `diff`
**Finding action template**: Wrap `{resource}` in `{using/try-with-resources/defer}` to guarantee cleanup at `{file}:{line}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: the patterns find resources being opened, and already exclude the scoped forms that guarantee cleanup on the same line (`with` in Python, `using` in C#, try-with-resources in Java). A hit is only a finding if nothing else guarantees the close — before flagging, read the surrounding lines for a `finally`, `defer`, `use {}`, `.close()` on every path, or a wrapper object that owns the lifetime. Dismiss resources handed to a caller or a container that takes ownership. The patterns cannot see multi-line ownership, so also apply the rule manually to resource-opening calls in the diff that produced no hit. Some rows use a per-file pairing pattern (unscoped `ProcessPoolExecutor`/`ThreadPoolExecutor` construction with no `.shutdown()` anywhere in the file; `NotificationCenter…addObserver` with no `removeObserver` anywhere in the file) — those hits have already been checked for an in-file release, so dismiss one only when the lifetime is owned elsewhere (release in another file, or the observer/executor handed off to a container).

**C++**: the cpp rows pair an acquisition with its release per file — `new` with `delete`/`delete[]`, `fopen` with `fclose`, `malloc`/`calloc` with `free`, `lock()` with `unlock()` — so a hit means the file releases nowhere. Dismiss when RAII owns the lifetime (a `unique_ptr`/`shared_ptr`/`make_unique`, a `std::lock_guard`/`std::scoped_lock`, or a destructor that releases), and apply the rule by hand to ownership the line pattern cannot see.

---

### safety-02 · Critical · Unsafe Null Dereference / Force Unwrap
**Scriptable**: Yes
**Rule**: Non-null assertions applied to values that could be null at runtime — `!!`, `!`, `.Value` on nullable, `as!` in Swift.
**Scope**: `diff`
**Finding action template**: Replace force unwrap of `{expression}` with a guard clause, safe unwrap, or Optional chain

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 4 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- javascript: not applicable — no force unwrap syntax
- python: not applicable
- java: not applicable — no force unwrap syntax
- cpp: not applicable — C++ has no null-forgiving/force-unwrap operator (no `!!`, `!`, `.Value`, `as!`); a raw-pointer deref is not a syntactic assertion.

NOTE for agent: dismiss `!=` and `!==` comparisons. In TypeScript, dismiss `!` at end of type declarations (e.g. `field!: string` in class body). Only flag runtime dereferences. Dismiss TypeScript definite-assignment assertions on field declarations (`field!: Type`) and `!=`/`!==` operators. The pattern targets force-unwraps on expressions, not declarations.

For C#: the `.Value` pattern has a high false-positive rate. Only flag `Nullable<T>.Value` (i.e., when the containing type is `T?` or `Nullable<T>`). Dismiss `.Value` on `Result<T>`, `Option<T>`, `KeyValuePair`, `XElement`, `XAttribute`, `Enum`, and any type whose name ends in `Result`, `Option`, `Either`, `Maybe`, `Value`. When uncertain about the type, check the variable's declaration in the same file.

---

### safety-03 · Major · Fire-and-Forget Async Without Error Handling
**Scriptable**: Yes
**Rule**: Async calls that are neither awaited nor have a `.catch()`/error callback — silent failures leave the system in an inconsistent state.
**Scope**: `diff`
**Finding action template**: Await `{asyncCall}` or attach an explicit `.catch()` error handler at `{file}:{line}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: For TypeScript/JavaScript the pattern only finds the explicit discard form — `void someCall()` / `void obj?.method()`, including `void x?.()`. It deliberately does not match `void 0` or a `: void` return annotation. That form is the *only* scriptable one, so the agent must still inspect the diff by hand for the far commoner shape: an async call that is neither awaited nor given `.then()`/`.catch()` and whose return value is simply dropped (`this.service.sendEmail(x)` on a statement line). A `void` hit is a finding when the callee can return a promise — check its declared return type; dismiss it when the callee is genuinely synchronous. For C#: grep finds all Async method calls. The agent must check: (1) is the calling method declared `async`? (2) is there an `await` on this line or is the result assigned? If neither, flag it. For Swift the pattern reads each `Task {` closure body via `mbody` and drops a hit whose body carries a `catch` (its own `do`/`catch` — the dominant false positive), and it drops a `Task` assigned to a variable (`x = Task {`), which is tracked and cancellable rather than fire-and-forget. For Python `asyncio.create_task`/`ensure_future` and `x.create_task`, a hit whose call is the right-hand side of an assignment is dropped: an assigned task is later awaitable/cancellable (e.g. `t = asyncio.create_task(...)`, a `TaskGroup`'s `tasks = [tg.create_task(...) ...]`), so only a bare, discarded call survives. A `create_task` mentioned inside a string literal is a residual false positive the pattern cannot see.

---

### safety-04 · Major · Invalid State Representable in Type System
**Scriptable**: No
**Rule**: Classes where a combination of fields allows illegal states to coexist at runtime (e.g. `isActive=true` and `deletedAt=<date>`, or `status="shipped"` with `shippedAt=null`).
**Scope**: `diff`
**Finding action template**: Eliminate illegal state in `{ClassName}` — use a discriminated union / sealed class hierarchy, or enforce the invariant in the constructor

**How to check**: For each new/changed class in the diff, list all nullable or boolean fields. Can any combination of their values represent a state that should be impossible? Flag if yes.

---

### safety-05 · Critical · Check-Then-Act Race Condition
**Scriptable**: Yes
**Rule**: Shared state checked and then acted on in two separate non-atomic steps.
**Scope**: `diff`
**Finding action template**: Replace check-then-act on `{sharedState}` with an atomic operation (`computeIfAbsent`, compare-and-swap, or a lock covering both steps)

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: Only flag when the check and act steps can be interleaved by a separate thread, coroutine, asynchronous continuation, or concurrent process. TOCTOU on filesystem paths (`fs.existsSync` then `fs.writeFileSync`, `os.path.exists` then `open()`) is a race against external processes even in single-threaded runtimes — flag these. Dismiss when both the check and the act operate on a local variable or a request-scoped object that cannot be accessed by any other execution context. Python `if x in y:` (membership test) is NOT a safety-05 violation — it does not probe the filesystem. Flag only `os.path.exists`, `Path(...).exists()`, and similar filesystem checks before open/modify operations. The script no longer flags membership predicates (`.has`/`.includes`/`.contains`); a bare existence read with no create/delete/write to the same path afterward, and an `assert`, are not check-then-act. Also treat as a race a value snapshotted from a shared store (`list_tables()`, a cache or count read) then acted on before re-checking — even when the check line reads as a pure local test — since a line-local pattern cannot span snapshot→check→act.

---

### safety-06 · Major · Blocking I/O in Async Context
**Scriptable**: Yes
**Rule**: Synchronous blocking calls inside async methods — causes thread-pool starvation under load.
**Scope**: `diff`
**Finding action template**: Replace blocking `{call}` inside async `{methodName}` with its async equivalent

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: this rule fires ONLY when the blocking call starves an async runtime — an event loop or an async thread-pool. Blocking a plain thread is fine and often correct, so the enclosing scope decides the verdict, not the call itself. Procedure: from the hit, trace UP to the nearest enclosing function declaration and check for the async marker. FLAG only if that declaration is `async def` (Python), `suspend fun` (Kotlin), `async func` / an awaited actor method (Swift), an `async Task`/`async ValueTask`/`async void` method (C#), or the body runs as an `await`-reached coroutine or an async request handler on a hot path. DISMISS in every synchronous context, and these cues are decisive, not hints: a plain `def`/`func`/method with no `async` keyword; a daemon or worker thread body; a CLI command handler (`main`, `__main__`, Click/Typer/argparse); an installer, setup, bootstrap, or migration routine; a sync polling/retry/backoff helper (`_poll_*`, `_wait_*`, `withRetry`); or startup/init code that runs before the event loop. Swift `DispatchGroup.wait()`, `DispatchSemaphore` waits, and PromiseKit `.wait()` are synchronous-concurrency primitives — dismiss unless the enclosing function itself carries `async`. When you cannot find an enclosing `async` declaration, dismiss — do not flag on suspicion. Also dismiss any hit in a test file — a blocking call in a synchronous test method cannot violate this rule, and the collector already excludes test files for this check. For Java `.get()` and `.join()`, only flag when called on a `CompletableFuture`, `Future`, or `CompletionStage` variable — dismiss getter methods, map lookups, and `String.join()`. For C#: dismiss `.Result` on types named `Result<T>`, `Option<T>`, `Either<L,R>`, or similar functional result types — flag `.Result` and `.Wait()` only when the containing type is `Task`, `ValueTask`, or their generic variants. In Swift the bare `sleep(...)` alternative excludes `Task.sleep(...)`, which suspends the task rather than blocking a thread and is therefore not a violation of this rule; `Thread.sleep`, C `sleep`, and semaphore/dispatch-group waits still match. The Python pattern now flags blocking filesystem/`tarfile`/`zipfile`/`shutil`/`subprocess`/`os`/`Path` calls too, not just `time.sleep` — apply the same trace-up rule: flag only inside an `async def`, dismiss in synchronous code. Blocking calls hidden behind custom app methods still produce no hit — read the diff for those by hand.

**C++**: there is no language-level async marker to trace up to, so flag a blocking wait (`std::this_thread::sleep_for`, `future.get()`, `condition_variable::wait`, a `.lock()` on a hot path) only inside a coroutine (`co_await`/`co_return`) or a documented async/event-loop callback. Dismiss it in ordinary synchronous or worker-thread code.

---

### safety-07 · Moderate · Suppressed Compiler/Linter Warnings
**Scriptable**: Yes
**Rule**: `@SuppressWarnings`, `// nolint:`, `#pragma warning disable`, `@Suppress`, `// eslint-disable`, `// swiftlint:disable` in new code hide real toolchain signals.
**Scope**: `diff`
**Finding action template**: Remove suppression of `{warningName}` at `{file}:{line}` — fix the underlying issue or document why it is intentional

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

---

### safety-08 · Major · External Call Without Timeout or Cancellation
**Scriptable**: Yes
**Rule**: A network or database call with no timeout, deadline, or cancellation token hangs forever when the far side stops answering, holding its caller with it.
**Scope**: `diff`
**Finding action template**: Give `{call}` a timeout or cancellation token at `{file}:{line}` so a hung dependency cannot stall the caller

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 6 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- java: non-scriptable — the timeout is set on the client or request builder, usually several lines from the call
- kotlin: non-scriptable — same as java; `withTimeout` wraps the call from an enclosing line
- swift: non-scriptable — `URLSession` timeouts live on the session configuration, not the call site

NOTE for agent: dismiss a hit when a timeout is configured elsewhere and provably covers this call — a client built with a default timeout, an enclosing `withTimeout`/`CancellationTokenSource`, or a framework-wide policy. The finding is a call that can wait forever, not a call missing a specific argument. Expect one recurring false positive you must resolve by reading nearby lines: options passed as a prebuilt variable (`const opts = { signal }; fetch(url, opts)`) look identical to no options at all, because the pattern only sees the call line. All four scripted languages (typescript, javascript, python, csharp) require *a* `)` to appear somewhere on the same line as the call — not necessarily the call's own closing paren — so a multi-line call whose first line already contains an unrelated `)` (e.g. `fetch(url, buildOpts(x)` opening a nested call) still produces a hit even though the outer call isn't closed until a later line. The more common failure mode is the opposite: a multi-line call with no such stray `)` (`fetch(url, {` on one line, `signal: controller.signal,` and the closing `});` on later lines; the equivalent split across lines in `requests.get(`/`client.GetAsync(`) never produces a hit at all — for these, apply the rule by hand: read forward from the call to its closing `)` before deciding whether a timeout/signal/cancellation token is present. This is a known, accepted false-negative trade-off: a genuinely signal-less multi-line call is silently skipped rather than risk mismatching the guard against the wrong line. For the languages with no pattern, apply the rule by reading the diff. safety-08 covers any blocking outward call, not just the SDK names the script knows: flag calls through app gateways (`embedder.embed_*`, `store.*search*`, `lancedb.*`, `*.create_index`) and blocking waits (`future.result()`, `pool.submit(...).result()`) when no timeout/deadline/cancellation is passed — the script cannot see these. `httpx` carries a 5s default timeout, so httpx-without-explicit-timeout is dismissable unless the default was overridden to `None`, whereas `requests` defaults to no timeout and stays a finding; a client/session built with a default or explicit timeout covers its calls.

---

### safety-09 · Critical · Fire-and-Forget Async Method Declaration
**Scriptable**: Yes
**Rule**: An `async void` method cannot be awaited and its failure cannot be caught by the caller — the exception reaches the runtime and takes the process down.
**Scope**: `diff`
**Finding action template**: Change `async void {methodName}` to `async Task` at `{file}:{line}` so callers can await it and observe its failure

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 1 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- typescript: not applicable — no `async void` form
- javascript: not applicable — no `async void` form
- python: not applicable — no `async void` form
- java: not applicable — no `async void` form
- kotlin: covered by safety-03, which owns `launch {}` and `GlobalScope`
- swift: covered by safety-03, which owns detached `Task {}`
- cpp: not applicable — C++ has no `async`/`await` keywords or `async void` method form.

NOTE for agent: this check is about the declaration; safety-03 owns un-awaited call sites. Dismiss the one legitimate use, an event handler required by a framework signature, but only when the body cannot throw or catches everything it can throw.

---

### safety-10 · Major · Exception Cause Discarded on Rethrow
**Scriptable**: Yes
**Rule**: Rethrowing in a way that resets the stack trace or drops the original exception leaves the failure correctly propagated but no longer diagnosable.
**Scope**: `diff`
**Finding action template**: Preserve the original failure at `{file}:{line}` — use bare `throw`, or pass the caught exception as the cause

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 5 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- python: non-scriptable — a missing `from e` can only be judged against the enclosing `except` block
- kotlin: non-scriptable — same as python
- swift: not applicable — `throw` does not carry or reset a stack trace

NOTE for agent: this is distinct from smells-12, which owns exceptions that are swallowed. Here the exception does propagate; what is lost is the origin. In C# flag `throw ex;` and prefer bare `throw;` — `throw;` is not valid Java syntax, so in Java flag `throw new X(e.getMessage())`, which drops the caught exception as the cause, and prefer `throw new X(msg, e)` instead. In TypeScript and JavaScript flag a new error built from only `err.message`, which drops the original. For Python, read the diff for a `raise` inside an `except` that omits `from`.

---

### safety-11 · Major · Unabstracted Clock, Randomness, or Identifier in Production Code
**Scriptable**: Yes
**Rule**: Production code reading the current time, random numbers, or fresh identifiers directly cannot be tested for behaviour that depends on them, and a naive local timestamp is wrong for every reader in another timezone.
**Scope**: `diff`
**Finding action template**: Inject a clock, random source, or identifier generator into `{ClassName}` instead of calling `{call}` directly at `{file}:{line}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: tests-04 owns this inside test files; these patterns deliberately exclude test paths so the two never overlap. The vocabulary covers wall clocks (`new Date()`, `Date.now`, `datetime.now`, `time.time`, `time.monotonic`, `DateTime.UtcNow`, `Instant.now`), randomness (`Math.random`, `random.*`, `secrets.*`, `crypto.getRandomValues`, `Int.random`), and fresh identifiers (`crypto.randomUUID`, `uuidv4()`, `nanoid()`, `uuid4()`, `Guid.NewGuid`, `UUID()`). Flag when the value affects a decision, a stored record, or an output the caller can observe. Dismiss logging timestamps, metrics, cache keys, and one-off scripts, where injecting a source buys nothing — in particular, `time.monotonic()`/`performance.now()` bracketing a block purely to record its latency is a metric, not a finding, whereas the same call driving a TTL or expiry decision is. Treat a naive local-time call as a finding on its own even when testability is not at stake.

**C++**: the sources matched are `rand()`/`std::rand`, `std::random_device`, `std::mt19937`, `time(nullptr)`, `GetTickCount`, and `std::chrono::…::now()`.

---

### safety-12 · Major · Mutable Default Parameter Value
**Scriptable**: Yes
**Rule**: A list, dict, or set used as a default argument is created once and shared by every call, so one caller's changes silently appear in the next call.
**Scope**: `diff`
**Finding action template**: Default `{parameter}` to `None` at `{file}:{line}` and create the collection inside the function body

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 1 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- typescript: not applicable — default expressions are evaluated per call
- javascript: not applicable — default expressions are evaluated per call
- csharp: not applicable — only compile-time constants may be defaults
- java: not applicable — no default parameter values
- kotlin: not applicable — default expressions are evaluated per call
- swift: not applicable — default expressions are evaluated per call
- cpp: not applicable — C++ evaluates default arguments at every call, so the shared-mutable-default trap does not exist.

NOTE for agent: this is always a finding when the default is mutated anywhere in the body. When the default is only read, it is still a latent trap and stays a finding, though the fix is cheaper.

---

### safety-13 · Major · Assertion Used as Production Validation
**Scriptable**: Yes
**Rule**: `assert` is removed when the program is built optimised — Python under `-O`, Swift under `-O` (the default Release configuration) — so any check written as an assertion silently disappears from the deployed program.
**Scope**: `diff`
**Finding action template**: Replace the assertion at `{file}:{line}` with an explicit check that raises `{ExceptionType}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 3 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- typescript: not applicable — no assertion statement stripped by an optimiser
- javascript: not applicable — no assertion statement stripped by an optimiser
- csharp: covered by the compiler's own conditional-compilation rules
- java: not applicable — assertions are disabled by default and rarely used for validation
- kotlin: not applicable — no assertion statement stripped by an optimiser

NOTE for agent: the patterns already exclude test paths, where assertions are correct. Flag assertions that validate input, arguments, or external data. Dismiss assertions that state an internal invariant the code itself guarantees — those are documentation, and losing them under optimisation is harmless.

For Swift the pattern matches `assert(...)` and `assertionFailure(...)` only. Both have their condition removed entirely under `-O`, so the sequence `assert(x != nil)` followed by `x!` is the classic finding: the guard vanishes in Release and the force-unwrap crashes. `precondition`/`preconditionFailure` are deliberately NOT matched — they survive `-O` and are the correct tool — and neither are project-local wrappers such as `AppLog.assertion(...)`, which are ordinary functions the optimiser keeps. Dismiss an `assertionFailure()` that merely marks a branch the code proves unreachable and that already returns a safe fallback — most commonly an `assertionFailure(...); return nil` (or other safe default) at the exhausted tail of an if/switch chain over the code's own enum cases or internal state. Keep flagging an `assertionFailure`/`assert` that validates external, parsed, or locale/currency data, even when a fallback follows, and especially when a force-unwrap or dereference of that value comes next.

---

### safety-14 · Critical · Hardcoded Credential
**Scriptable**: Yes
**Rule**: A password, key, or token written into source is readable by everyone with repository access and stays valid in the history after it is deleted.
**Scope**: `diff`
**Finding action template**: Move `{name}` out of source at `{file}:{line}` into configuration or a secret store, and rotate the exposed value

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: dismiss obvious non-secrets — empty strings, placeholders such as `changeme` or `xxx`, values that are plainly test fixtures, and public identifiers that merely have a secret-sounding name (e.g. `stripePublicApiKey = "pk_live_51Hxxxxxxxxxxxx"` — a publishable key, not a secret, even though the variable name ends in `ApiKey`). Flag anything that looks like a live credential even in a test file: committed test credentials are frequently real. Unlike safety-15, this pattern does not exclude comment lines — a commented-out credential (`// password = "..."`) still gets flagged, because a committed secret stays exposed in history whether or not the line is live code. When the value is genuinely a secret, say so plainly in the action and include rotation, because deleting the line does not un-expose it.

---

### safety-15 · Critical · Query Built by String Concatenation
**Scriptable**: Yes
**Rule**: A query assembled by joining or interpolating values into its text lets any value that contains query syntax change what the query does.
**Scope**: `diff`
**Finding action template**: Replace the concatenated query at `{file}:{line}` with a parameterised statement binding `{value}` as a parameter

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: the pattern requires both a statement shape and an interpolation or concatenation on the same line, and skips comment lines, so most hits are real. Python additionally matches a bare clause fragment that carries the same injection surface without ever naming `SELECT`: a `where`/`values(` line that interpolates a value *inside* a quoted literal (`where=f"chunk_id = '{chunk_id}'"`), and a SQL predicate assembled by `+`-concatenation or f-string interpolation of a variable — an uppercase `OR`/`AND` connective spliced between expressions (`pred + " OR " + other`), an `IN (...)` list (`f"col IN ({items})"`), or an `IS NULL`/comparison/`LIKE`/`=` predicate whose value is concatenated (`"col >= " + quote(v)`, `"path LIKE " + p`). The SQL keywords are matched case-sensitively (uppercase) so English prose `or`/`and`/`in` concatenated for display does not match. Dismiss a hit when every interpolated part is a compile-time constant the caller cannot influence — a fixed table name from an enum, for example. Dismiss the safe placeholder forms that only look similar: `%s` with a separate parameter tuple, `?`, `$1`, and `@named` bindings. When the value comes from outside the program, the severity stands as written.

---

### safety-16 · Major · Money Held in a Binary Floating-Point Type
**Scriptable**: Yes
**Rule**: Binary floating-point cannot represent most decimal fractions exactly, so money kept this way drifts by rounding and totals stop reconciling.
**Scope**: `diff`
**Finding action template**: Change `{field}` at `{file}:{line}` to a decimal type or an integer count of minor units

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- javascript: not applicable — every number is binary floating-point, so the finding is the absence of a decimal library rather than a type choice

NOTE for agent: this is a correctness check and is distinct from solid-07, which asks whether the concept deserves a named type. Both can be true of one line. The name vocabulary deliberately excludes a bare `total`, because `totalCount`, `totalItems`, and `totalPages` are quantities rather than money — real money names such as `totalPrice` and `totalAmount` still match on their `price` and `amount` parts. Dismiss remaining non-money values despite the name: a ratio, a rate, a percentage, or a score — an FX conversion field such as `exchangePrice`, `euroPrice`, or `basePrice` is a rate, not money (the script now excludes the `exchange` prefix, but `euroPrice`/`basePrice` still surface and must be dismissed). Apply the rule by hand to a money field the vocabulary does not know. In JavaScript, and in TypeScript where `number` is unavoidable, flag arithmetic performed on money rather than the declaration.

---

### safety-17 · Critical · Weak or Broken Cryptographic Primitive
**Scriptable**: Yes
**Rule**: A cryptographically broken hash or cipher used for a security purpose — MD5 or SHA-1 for signatures/passwords/integrity, DES/3DES/RC4 for encryption, or ECB mode — is practically forgeable or decryptable and must be replaced.
**Scope**: `diff`
**Finding action template**: Replace weak primitive `{algorithm}` at `{file}:{line}` with a modern one (SHA-256+/HMAC for hashing, AES-GCM for encryption)

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: dismiss when the weak primitive is provably not security-relevant — a non-cryptographic checksum for cache keys, ETags, or deduplication where an adversary gains nothing from a collision. MD5/SHA-1 for password hashing, token or signature generation, or integrity verification of untrusted data is always a finding. A password stored with a plain fast hash (even SHA-256) rather than a KDF (bcrypt/scrypt/argon2/PBKDF2) is a related finding you may raise here.

---

### safety-18 · Critical · TLS or Certificate Verification Disabled
**Scriptable**: Yes
**Rule**: Turning off TLS certificate or hostname verification makes the client accept any certificate, so an attacker on the network path can impersonate the server and read or alter the traffic.
**Scope**: `diff`
**Finding action template**: Remove the verification bypass at `{file}:{line}` and trust the system CA store — pin a certificate only through a proper pinning API, never by accepting all

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- swift: non-scriptable — disabling verification lives inside a `URLSessionDelegate` `didReceive challenge` method that calls the completion handler with `.useCredential`/`URLCredential(trust:)`, spread across several lines; agent must read the delegate body in the diff.

NOTE for agent: dismiss only when the bypass is unreachable in production — guarded by a build flag that is off in release builds, or confined to a test/fixture path. A bypass reachable from a shipping code path is always a finding, regardless of comments claiming it is temporary.

---

### safety-19 · Critical · OS Command or Code Injection Surface
**Scriptable**: Yes
**Rule**: Running a command through a shell (`shell=True`, `os.system`, `Runtime.exec` of a shell string, `child_process.exec`) or evaluating a string as code (`eval`, `exec`, `new Function`) lets any interpolated value execute arbitrary commands or code.
**Scope**: `diff`
**Finding action template**: Replace the shell/eval call at `{file}:{line}` with an argument-array exec (`execFile`/`spawn`/`subprocess.run([...])`/`ProcessBuilder` with a list) or remove the dynamic evaluation

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: the finding is the injection surface, not proof of a reachable exploit — flag it whenever any part of the command or evaluated string could carry a value the program did not fix at author time. Dismiss when every argument is a compile-time constant the caller cannot influence. For C#, `Process.Start` on a fixed filename or a URL (opening a browser) is not shell execution — dismiss those; flag when a shell (`cmd.exe`/`/bin/sh` with `/c`/`-c`) or an interpolated command line is involved. `eval`/`exec` on any non-constant input is always a finding.

---

### safety-20 · Critical · Unsafe Deserialization of Untrusted Data
**Scriptable**: Yes
**Rule**: Deserializing with a mechanism that can instantiate arbitrary types or run code during construction — Python `pickle`/`yaml.load`, Java native `readObject`, .NET `BinaryFormatter` or `TypeNameHandling` — turns any attacker-controlled bytes into remote code execution.
**Scope**: `diff`
**Finding action template**: Replace the unsafe deserializer at `{file}:{line}` with a data-only format (JSON / `yaml.safe_load` / `unarchivedObject(ofClass:)`) or restrict it to an explicit allow-list of types

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: dismiss when the serialized bytes provably never cross a trust boundary — a value the program itself wrote to a location only it can write, within the same process lifetime. Dismiss `yaml.load(..., Loader=SafeLoader)` and `yaml.safe_load` — those are the safe forms. Any deserialization of a request body, a user-supplied file, a queue message, or cache/session data from a shared store is a finding.

---

### safety-21 · Major · String or Object Compared by Reference in Java
**Scriptable**: Yes
**Rule**: In Java, `==`/`!=` on a `String` (or any boxed/reference type) compares object identity, not value — it happens to work for interned literals and fails silently for any computed or boxed value.
**Scope**: `diff`
**Finding action template**: Replace reference comparison at `{file}:{line}` with `{a}.equals({b})` (or `Objects.equals(a, b)` to stay null-safe)

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 1 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- typescript: not applicable — `===` is value equality for strings
- javascript: not applicable — `===` is value equality for strings
- python: not applicable — `==` is value equality; `is` on strings is the analogous bug but rare and handled by linters
- csharp: not applicable — `==` is overloaded to value equality for `string`
- kotlin: not applicable — `==` compiles to `.equals()`; `===` is the explicit reference check
- swift: not applicable — `==` is value equality via `Equatable`
- cpp: not applicable — for `std::string`, `==` is a value comparison, so the reference-identity pitfall this check targets does not apply.

NOTE for agent: the pattern flags comparison against a string literal (`x == "shipped"`), the unambiguous form. Also flag, by reading the diff, the variable-to-variable form (`a == b` where both are `String` or a boxed type such as `Integer`) — the pattern cannot see the types. Dismiss `== null`/`!= null` (identity is correct there) and comparisons of `char` literals written in single quotes (those are value types). The pattern's comment guard only suppresses full-line comments, so also dismiss a `==`/`!=` that appears inside a **trailing** `//` comment (e.g. `doStuff(); // status == "old"`).

---

### safety-22 · Critical · Sensitive Data Written to Logs
**Scriptable**: Yes
**Rule**: A logging, print, or console call whose arguments name a credential (`password`, `secret`, `api_key`, `access_token`, `private_key`, `ssn`, `card_number`, `authorization`) leaks that value into log files, aggregators, and crash reports where it outlives the request and escapes access control.
**Scope**: `diff`
**Finding action template**: Remove the sensitive value from the log call at `{file}:{line}` — log a redacted placeholder or a non-reversible identifier instead

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: distinct from safety-14 (a hardcoded credential in source) — this is the runtime *leak* of a secret through a log sink. The pattern matches a log/print token followed by a secret-named identifier on the same line; it cannot see field names it does not know, so also flag a log call that passes a whole object (`logger.info(user)`, `console.log(req.body)`) whose shape carries secrets. Dismiss when the named value is provably not the secret itself — a boolean `hasPassword`, a length `passwordLength`, an already-redacted or masked string, or a field name used only as a map key with no value interpolated.

---

### safety-23 · Critical · User-Controlled Path Reaching the Filesystem
**Scriptable**: Yes
**Rule**: A filesystem open/read/write whose path derives from request input (`req`, `request`, `params`, `query`, `body`, `argv`, user input) without normalization lets an attacker traverse with `../` or absolute paths to read or overwrite files outside the intended directory.
**Scope**: `diff`
**Finding action template**: Resolve and confine the path at `{file}:{line}` — canonicalize it and verify it stays within an allowed base directory before opening

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: this completes the injection trio with safety-19 (command/eval) and safety-15 (SQL) — same taint principle, filesystem sink. The pattern only catches the request-derived value and the open call on one line; when the tainted path is assigned to a variable first and opened later, follow it in the diff yourself. Dismiss when the path is confined before use — a canonicalized path checked against a base dir, a value constrained to a fixed allow-list, or a filename component with traversal characters already stripped. A constant or config-derived path is never a finding.

---

### safety-24 · Major · Float Equality Comparison
**Scriptable**: Yes
**Rule**: Comparing a floating-point value with `==`/`!=` against a decimal literal is unreliable — the value that results from arithmetic almost never equals the literal bit-for-bit, so the branch silently never (or always) fires.
**Scope**: `diff`
**Finding action template**: Replace the exact float comparison at `{file}:{line}` with a tolerance check (`abs(a - b) < epsilon`) or compare a decimal/integer-minor-unit type

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 8 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: distinct from safety-16 (money stored as float) — this is the *comparison* bug, not the storage choice; both can be true of one line. The pattern flags `==`/`!=`/`===`/`!==` against a decimal literal (`x == 3.14`) in either order. Dismiss a comparison against `0.0`/`0` used purely as a sentinel where exactness is intended and the value is never the result of arithmetic (e.g. a freshly initialized field), and dismiss version strings or dotted identifiers the literal guard already excludes. Also flag, by reading the diff, the variable-to-variable form (`a == b` where both are `float`/`double`) that the literal-only pattern cannot see.

---

### safety-25 · Major · Unsynchronised Shared Mutable State
**Scriptable**: No
**Rule**: State reachable from more than one thread, coroutine, or async continuation and mutated without a lock, atomic, or confinement — or a compound read-modify-write on such state that is not atomic — races and corrupts.
**Scope**: `diff`
**Finding action template**: Guard shared state `{name}` at `{file}:{line}` with a lock or atomic (or confine it to one owner)

**How to check**: For each new/changed mutation of state that outlives a single execution context (a shared field, module global, captured variable, or a container handed to concurrent workers), decide whether concurrent access is possible and unguarded. Flag: a compound update on shared state (`counter += 1`, `if key not in d: d[key] = …`, `list.append` on a shared list from concurrent tasks) with no lock/atomic; state mutated from a spawned thread/task while another context can read it. Dismiss request-scoped or thread-confined state, immutable state, single-threaded code where no `await` interleaves the two steps, and mutations already inside a lock/atomic/actor.

NOTE for agent: this extends safety-05 (check-then-act) and safety-06 (blocking I/O in async) to the wider concurrency surface — do not re-report a hit those two already own. Unpropagated cancellation belongs to safety-32, not here. The hazard requires genuine concurrency: prove two contexts can reach the state before flagging, and dismiss on suspicion when you cannot.

---

### safety-26 · Moderate · Unobservable Failure Path
**Scriptable**: No
**Rule**: A failure branch that recovers — a `catch`/`except`/`rescue` that returns a fallback, or an early error-return with a default — while emitting no log, metric, or trace record makes the failure invisible in production, so it cannot be diagnosed or alerted on.
**Scope**: `diff`
**Finding action template**: Record the failure at `{file}:{line}` — emit a log, metric, or trace on the branch (or let it propagate to a layer that records it) so it is diagnosable

**How to check**: For each new error-handling branch in the diff (a `catch`/`except`/`rescue`, or a failure early-return such as `if (!ok) return default`), check whether it records the failure (a logger/metric/trace call) or propagates it to a caller that will. Flag branches that recover to a fallback or default with no signal. Dismiss branches that re-throw or propagate the error, expected control paths that are not failures (a cache miss, a validation returning a typed error to the caller), and test files.

NOTE for agent: smells-12 owns whether an exception should have been swallowed at all; this owns the observability of a failure the code has *deliberately* recovered from — the two co-fire only when a genuine swallow is also unlit, in which case report smells-12. safety-07 owns suppression comments. This is the counterweight to solid-12 (no logging inside the domain): satisfy both by recording the failure at the boundary/adapter, not in a domain type.

---

### safety-27 · Major · Unbounded In-Memory Growth
**Scriptable**: No
**Rule**: A long-lived container that only ever grows — an instance field, module global, cache, or queue appended to or inserted into with no size cap, eviction policy, or TTL — grows without bound until it exhausts memory.
**Scope**: `diff`
**Finding action template**: Bound `{container}` at `{file}:{line}` with a max size, an eviction policy (LRU/TTL), or periodic pruning so it cannot grow without bound

**How to check**: For each collection, cache, map, or queue written in the diff that outlives a single request (a field, module-level global, or captured variable), check for a bound: a max size, eviction, TTL, or a removal path that keeps it bounded. Flag an append/insert into an unbounded long-lived container. Dismiss request-scoped or local collections discarded when the function returns, containers with a known small fixed cardinality, and containers that already carry a cap or eviction. You may read the repository to confirm a bounding mechanism defined elsewhere on the type.

NOTE for agent: distinct from safety-01, which owns an unclosed handle (file, connection, socket, timer, executor, observer) on a code path — this owns growth of an in-memory container over the object's lifetime. A per-request cache with no eviction and a module-level list that every call appends to are the archetypes.

---

### safety-28 · Major · Inverted or Wrong Condition
**Scriptable**: No
**Rule**: A guard or branch condition that is logically inverted or uses the wrong operator — `&&` where `||` is meant (or the reverse), a missing or spurious `!`, `<` where `<=`/`>` is meant, `==` where `!=` — so the branch admits the cases it should reject or rejects the cases it should admit.
**Scope**: `diff`
**Finding action template**: Correct the condition at `{file}:{line}` to `{correctForm}` — as written it routes `{concreteInput}` to the wrong branch

**How to check**: For each new/changed conditional in the diff, work out which inputs take each branch and compare that against what the surrounding code clearly intends (variable names, comments, the branch bodies). Flag only when you can name a concrete input the condition routes the wrong way. Dismiss when the condition is defensible, when intent is unclear, or when you are merely suspicious.

NOTE for agent: correctness check — the classic logic bug, not a style call. The precision bar is a **named failure**: a specific value or state and the wrong branch it takes. If you cannot state input → wrong outcome, do not flag. safety-28 owns a wrong *logical or comparison operator* in a non-iteration guard. A `<`/`<=` (or inclusive/exclusive) boundary error in a loop, index, slice, or range belongs to safety-29, not here; a wrong *variable or operand* (rather than the operator itself) belongs to safety-30. Distinct from safety-24 (float equality comparison) and smells-19 (exception as control flow).

---

### safety-29 · Major · Off-by-One / Boundary Error
**Scriptable**: No
**Rule**: A loop bound, index, slice, or range comparison off by one — `<=` where `<` is meant (or the reverse), an index that reads one past the end or skips the first/last element, or an inclusive/exclusive range mismatch between where a value is produced and where it is consumed.
**Scope**: `diff`
**Finding action template**: Fix the boundary at `{file}:{line}` to `{correctBound}` — as written it {overruns/skips} `{concreteElement}`

**How to check**: For each new/changed loop, index expression, slice, or range in the diff, evaluate the first and last iteration (or the boundary value) concretely. Flag only when a specific index is read out of range, an element is processed twice, or a first/last element is skipped. Dismiss when the bounds are correct or intent is ambiguous.

NOTE for agent: correctness check. The **named failure** is the boundary element and what goes wrong at it — an out-of-range read, a duplicated element, or an omitted one. No concrete boundary case → no finding. safety-29 owns the `<`/`<=` and inclusive/exclusive boundary in loops, indices, slices, and ranges — do not also report that same boundary bug under safety-28.

---

### safety-30 · Major · Wrong Variable or Operator
**Scriptable**: No
**Rule**: A computation that uses the wrong operand — a sibling or copy-paste variable (`x` where `y` was meant), the wrong field of an object, or the wrong arithmetic/bitwise operator (`+` where `*`, `-` where `+`, `|` where `&`) — producing a wrong result that the types still accept.
**Scope**: `diff`
**Finding action template**: Use `{correctSymbol}` at `{file}:{line}` instead of `{wrongSymbol}` — the current form computes `{wrongResult}` for `{concreteInput}`

**How to check**: For each new/changed assignment or expression in the diff, check each operand and operator against what the surrounding code intends — a repeated near-identical block where one line kept a sibling's variable, a field that does not match the computation's purpose, an operator inconsistent with the name or unit. Flag only when you can name the wrong result for a concrete input. Dismiss when the code is defensible or intent is unclear.

NOTE for agent: correctness check — the copy-paste and typo bugs the compiler cannot catch because the wrong operand type-checks. **Named failure required**: concrete input → wrong value. safety-30 owns a wrong operand (variable or field) or a wrong *arithmetic/bitwise* operator; a wrong *logical or comparison operator* in a condition belongs to safety-28. Distinct from safety-21, which owns the `==`-on-objects reference-equality error in Java specifically.

---

### safety-31 · Major · Missing Early Return / Fallthrough
**Scriptable**: No
**Rule**: A guard that detects an invalid or terminal state but does not stop execution — no `return`/`break`/`throw`/`continue` — so control falls through into code that assumes the state was already handled and then uses the invalid value.
**Scope**: `diff`
**Finding action template**: Stop execution after the guard at `{file}:{line}` (return/throw/break) — without it, `{concreteInvalidState}` falls through into `{code}` that assumes validity

**How to check**: For each new/changed guard in the diff (a validation, a null/empty check, an error detection, a `switch`/`if` handling a case), check whether the branch actually exits or is followed by the required stop. Flag only when a concrete invalid input passes the guard and reaches code that misuses it. Dismiss deliberate fallthrough that is correct, and cases where later code independently handles the state.

NOTE for agent: correctness check — includes a missing `break` in a `switch` that falls into the next case, and a validation whose body logs but does not `return`. **Named failure required**: the invalid input and the unsafe code it reaches. Distinct from smells-12 (swallowed exception) and safety-26 (a failure path that recovers but goes unlogged) — here the failure is not handled at all.

---

### safety-32 · Major · Unpropagated Cancellation
**Scriptable**: No
**Rule**: A cancellation token, deadline, or timeout that the code receives or creates but never forwards to the downstream call it should stop — so cancelling the caller leaves the inner work running.
**Scope**: `diff`
**Finding action template**: Forward the cancellation token/deadline to `{downstreamCall}` at `{file}:{line}` so cancelling the caller stops the downstream work

**How to check**: For each new/changed function in the diff that receives or creates a `CancellationToken`/`AbortSignal`/`context.Context`/structured-cancellation scope, check whether every long-running or outward call it makes is passed that token. Flag a token that is accepted or created and then dropped — an inner call made without it, or a `catch` of a cancellation that swallows it instead of propagating. Dismiss functions with no cancellable downstream work, and a token deliberately withheld to protect a critical section.

NOTE for agent: distinct from safety-08, which owns a call that has *no* timeout or cancellation token at all — safety-32 owns a token that *exists* but is not forwarded. Distinct from safety-03 (fire-and-forget async without error handling). Split out of safety-25, which owns only shared-state races.

---

## Output instruction

Output one finding line per violation, exactly in this format:
```
[safety-NN] · Severity · Check Name | file:line | One-line action
```
No prose. Dismiss false positives silently.

If the action field contains a literal ` | ` (e.g. a TypeScript union type like `string | null`), escape it as ` \| ` to prevent splitting. The synthesizer unescapes ` \| ` back to ` | ` before rendering.

On the **final line** of your output, always emit:
`STATUS: GROUP=safety findings=N checks=M ok`
where N is the number of finding lines you emitted, M is the total count of `### safety-NN` check headers in this file (32 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. On error: `STATUS: GROUP=safety failed=<brief reason>`
