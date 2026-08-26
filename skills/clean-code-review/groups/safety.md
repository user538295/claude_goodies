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
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: the patterns find resources being opened, and already exclude the scoped forms that guarantee cleanup on the same line (`with` in Python, `using` in C#, try-with-resources in Java). A hit is only a finding if nothing else guarantees the close — before flagging, read the surrounding lines for a `finally`, `defer`, `use {}`, `.close()` on every path, or a wrapper object that owns the lifetime. Dismiss resources handed to a caller or a container that takes ownership. The patterns cannot see multi-line ownership, so also apply the rule manually to resource-opening calls in the diff that produced no hit. Some rows use a per-file pairing pattern (unscoped `ProcessPoolExecutor`/`ThreadPoolExecutor` construction with no `.shutdown()` anywhere in the file; `NotificationCenter…addObserver` with no `removeObserver` anywhere in the file) — those hits have already been checked for an in-file release, so dismiss one only when the lifetime is owned elsewhere (release in another file, or the observer/executor handed off to a container).

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

NOTE for agent: dismiss `!=` and `!==` comparisons. In TypeScript, dismiss `!` at end of type declarations (e.g. `field!: string` in class body). Only flag runtime dereferences. Dismiss TypeScript definite-assignment assertions on field declarations (`field!: Type`) and `!=`/`!==` operators. The pattern targets force-unwraps on expressions, not declarations.

For C#: the `.Value` pattern has a high false-positive rate. Only flag `Nullable<T>.Value` (i.e., when the containing type is `T?` or `Nullable<T>`). Dismiss `.Value` on `Result<T>`, `Option<T>`, `KeyValuePair`, `XElement`, `XAttribute`, `Enum`, and any type whose name ends in `Result`, `Option`, `Either`, `Maybe`, `Value`. When uncertain about the type, check the variable's declaration in the same file.

---

### safety-03 · Major · Fire-and-Forget Async Without Error Handling
**Scriptable**: Yes
**Rule**: Async calls that are neither awaited nor have a `.catch()`/error callback — silent failures leave the system in an inconsistent state.
**Scope**: `diff`
**Finding action template**: Await `{asyncCall}` or attach an explicit `.catch()` error handler at `{file}:{line}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

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
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: Only flag when the check and act steps can be interleaved by a separate thread, coroutine, asynchronous continuation, or concurrent process. TOCTOU on filesystem paths (`fs.existsSync` then `fs.writeFileSync`, `os.path.exists` then `open()`) is a race against external processes even in single-threaded runtimes — flag these. Dismiss when both the check and the act operate on a local variable or a request-scoped object that cannot be accessed by any other execution context. Python `if x in y:` (membership test) is NOT a safety-05 violation — it does not probe the filesystem. Flag only `os.path.exists`, `Path(...).exists()`, and similar filesystem checks before open/modify operations.

---

### safety-06 · Major · Blocking I/O in Async Context
**Scriptable**: Yes
**Rule**: Synchronous blocking calls inside async methods — causes thread-pool starvation under load.
**Scope**: `diff`
**Finding action template**: Replace blocking `{call}` inside async `{methodName}` with its async equivalent

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: only flag when the blocking call appears inside an async function/coroutine/suspend function. Dismiss in synchronous contexts, and dismiss any hit in a test file — a blocking call in a synchronous test method cannot violate this rule, and the collector already excludes test files for this check. For Java `.get()` and `.join()`, only flag when called on a `CompletableFuture`, `Future`, or `CompletionStage` variable — dismiss getter methods, map lookups, and `String.join()`. For C#: dismiss `.Result` on types named `Result<T>`, `Option<T>`, `Either<L,R>`, or similar functional result types — flag `.Result` and `.Wait()` only when the containing type is `Task`, `ValueTask`, or their generic variants. In Swift the bare `sleep(...)` alternative excludes `Task.sleep(...)`, which suspends the task rather than blocking a thread and is therefore not a violation of this rule; `Thread.sleep`, C `sleep`, and semaphore/dispatch-group waits still match. The Python pattern only knows `time.sleep` — synchronous filesystem and network calls inside an `async def` (`Path.mkdir`, `Path.read_text`, `tarfile.open`, a blocking `requests` call) produce no hit at all, so read the diff for those by hand.

---

### safety-07 · Moderate · Suppressed Compiler/Linter Warnings
**Scriptable**: Yes
**Rule**: `@SuppressWarnings`, `// nolint:`, `#pragma warning disable`, `@Suppress`, `// eslint-disable`, `// swiftlint:disable` in new code hide real toolchain signals.
**Scope**: `diff`
**Finding action template**: Remove suppression of `{warningName}` at `{file}:{line}` — fix the underlying issue or document why it is intentional

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

---

### safety-08 · Major · External Call Without Timeout or Cancellation
**Scriptable**: Yes
**Rule**: A network or database call with no timeout, deadline, or cancellation token hangs forever when the far side stops answering, holding its caller with it.
**Scope**: `diff`
**Finding action template**: Give `{call}` a timeout or cancellation token at `{file}:{line}` so a hung dependency cannot stall the caller

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 4 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- java: non-scriptable — the timeout is set on the client or request builder, usually several lines from the call
- kotlin: non-scriptable — same as java; `withTimeout` wraps the call from an enclosing line
- swift: non-scriptable — `URLSession` timeouts live on the session configuration, not the call site

NOTE for agent: dismiss a hit when a timeout is configured elsewhere and provably covers this call — a client built with a default timeout, an enclosing `withTimeout`/`CancellationTokenSource`, or a framework-wide policy. The finding is a call that can wait forever, not a call missing a specific argument. Expect one recurring false positive you must resolve by reading nearby lines: options passed as a prebuilt variable (`const opts = { signal }; fetch(url, opts)`) look identical to no options at all, because the pattern only sees the call line. All four scripted languages (typescript, javascript, python, csharp) require *a* `)` to appear somewhere on the same line as the call — not necessarily the call's own closing paren — so a multi-line call whose first line already contains an unrelated `)` (e.g. `fetch(url, buildOpts(x)` opening a nested call) still produces a hit even though the outer call isn't closed until a later line. The more common failure mode is the opposite: a multi-line call with no such stray `)` (`fetch(url, {` on one line, `signal: controller.signal,` and the closing `});` on later lines; the equivalent split across lines in `requests.get(`/`client.GetAsync(`) never produces a hit at all — for these, apply the rule by hand: read forward from the call to its closing `)` before deciding whether a timeout/signal/cancellation token is present. This is a known, accepted false-negative trade-off: a genuinely signal-less multi-line call is silently skipped rather than risk mismatching the guard against the wrong line. For the languages with no pattern, apply the rule by reading the diff.

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

NOTE for agent: this check is about the declaration; safety-03 owns un-awaited call sites. Dismiss the one legitimate use, an event handler required by a framework signature, but only when the body cannot throw or catches everything it can throw.

---

### safety-10 · Major · Exception Cause Discarded on Rethrow
**Scriptable**: Yes
**Rule**: Rethrowing in a way that resets the stack trace or drops the original exception leaves the failure correctly propagated but no longer diagnosable.
**Scope**: `diff`
**Finding action template**: Preserve the original failure at `{file}:{line}` — use bare `throw`, or pass the caught exception as the cause

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 4 language(s). Patterns: `scripts/checks/safety.tsv`.
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
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: tests-04 owns this inside test files; these patterns deliberately exclude test paths so the two never overlap. The vocabulary covers wall clocks (`new Date()`, `Date.now`, `datetime.now`, `time.time`, `time.monotonic`, `DateTime.UtcNow`, `Instant.now`), randomness (`Math.random`, `random.*`, `secrets.*`, `crypto.getRandomValues`, `Int.random`), and fresh identifiers (`crypto.randomUUID`, `uuidv4()`, `nanoid()`, `uuid4()`, `Guid.NewGuid`, `UUID()`). Flag when the value affects a decision, a stored record, or an output the caller can observe. Dismiss logging timestamps, metrics, cache keys, and one-off scripts, where injecting a source buys nothing — in particular, `time.monotonic()`/`performance.now()` bracketing a block purely to record its latency is a metric, not a finding, whereas the same call driving a TTL or expiry decision is. Treat a naive local-time call as a finding on its own even when testability is not at stake.

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

NOTE for agent: this is always a finding when the default is mutated anywhere in the body. When the default is only read, it is still a latent trap and stays a finding, though the fix is cheaper.

---

### safety-13 · Major · Assertion Used as Production Validation
**Scriptable**: Yes
**Rule**: `assert` is removed when the program is built optimised — Python under `-O`, Swift under `-O` (the default Release configuration) — so any check written as an assertion silently disappears from the deployed program.
**Scope**: `diff`
**Finding action template**: Replace the assertion at `{file}:{line}` with an explicit check that raises `{ExceptionType}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 2 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- typescript: not applicable — no assertion statement stripped by an optimiser
- javascript: not applicable — no assertion statement stripped by an optimiser
- csharp: covered by the compiler's own conditional-compilation rules
- java: not applicable — assertions are disabled by default and rarely used for validation
- kotlin: not applicable — no assertion statement stripped by an optimiser

NOTE for agent: the patterns already exclude test paths, where assertions are correct. Flag assertions that validate input, arguments, or external data. Dismiss assertions that state an internal invariant the code itself guarantees — those are documentation, and losing them under optimisation is harmless.

For Swift the pattern matches `assert(...)` and `assertionFailure(...)` only. Both have their condition removed entirely under `-O`, so the sequence `assert(x != nil)` followed by `x!` is the classic finding: the guard vanishes in Release and the force-unwrap crashes. `precondition`/`preconditionFailure` are deliberately NOT matched — they survive `-O` and are the correct tool — and neither are project-local wrappers such as `AppLog.assertion(...)`, which are ordinary functions the optimiser keeps. Dismiss an `assertionFailure()` that merely marks a branch the code proves unreachable and that already returns a safe fallback.

---

### safety-14 · Critical · Hardcoded Credential
**Scriptable**: Yes
**Rule**: A password, key, or token written into source is readable by everyone with repository access and stays valid in the history after it is deleted.
**Scope**: `diff`
**Finding action template**: Move `{name}` out of source at `{file}:{line}` into configuration or a secret store, and rotate the exposed value

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: dismiss obvious non-secrets — empty strings, placeholders such as `changeme` or `xxx`, values that are plainly test fixtures, and public identifiers that merely have a secret-sounding name (e.g. `stripePublicApiKey = "pk_live_51Hxxxxxxxxxxxx"` — a publishable key, not a secret, even though the variable name ends in `ApiKey`). Flag anything that looks like a live credential even in a test file: committed test credentials are frequently real. Unlike safety-15, this pattern does not exclude comment lines — a commented-out credential (`// password = "..."`) still gets flagged, because a committed secret stays exposed in history whether or not the line is live code. When the value is genuinely a secret, say so plainly in the action and include rotation, because deleting the line does not un-expose it.

---

### safety-15 · Critical · Query Built by String Concatenation
**Scriptable**: Yes
**Rule**: A query assembled by joining or interpolating values into its text lets any value that contains query syntax change what the query does.
**Scope**: `diff`
**Finding action template**: Replace the concatenated query at `{file}:{line}` with a parameterised statement binding `{value}` as a parameter

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: the pattern requires both a statement shape and an interpolation or concatenation on the same line, and skips comment lines, so most hits are real. Python additionally matches a bare clause fragment that carries the same injection surface without ever naming `SELECT`: a `where`/`values(` line that interpolates a value *inside* a quoted literal (`where=f"chunk_id = '{chunk_id}'"`), and a SQL predicate assembled by `+`-concatenation or f-string interpolation of a variable — an uppercase `OR`/`AND` connective spliced between expressions (`pred + " OR " + other`), an `IN (...)` list (`f"col IN ({items})"`), or an `IS NULL`/comparison/`LIKE`/`=` predicate whose value is concatenated (`"col >= " + quote(v)`, `"path LIKE " + p`). The SQL keywords are matched case-sensitively (uppercase) so English prose `or`/`and`/`in` concatenated for display does not match. Dismiss a hit when every interpolated part is a compile-time constant the caller cannot influence — a fixed table name from an enum, for example. Dismiss the safe placeholder forms that only look similar: `%s` with a separate parameter tuple, `?`, `$1`, and `@named` bindings. When the value comes from outside the program, the severity stands as written.

---

### safety-16 · Major · Money Held in a Binary Floating-Point Type
**Scriptable**: Yes
**Rule**: Binary floating-point cannot represent most decimal fractions exactly, so money kept this way drifts by rounding and totals stop reconciling.
**Scope**: `diff`
**Finding action template**: Change `{field}` at `{file}:{line}` to a decimal type or an integer count of minor units

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 6 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- javascript: not applicable — every number is binary floating-point, so the finding is the absence of a decimal library rather than a type choice

NOTE for agent: this is a correctness check and is distinct from solid-07, which asks whether the concept deserves a named type. Both can be true of one line. The name vocabulary deliberately excludes a bare `total`, because `totalCount`, `totalItems`, and `totalPages` are quantities rather than money — real money names such as `totalPrice` and `totalAmount` still match on their `price` and `amount` parts. Dismiss remaining non-money values despite the name: a ratio, a rate, a percentage, or a score. Apply the rule by hand to a money field the vocabulary does not know. In JavaScript, and in TypeScript where `number` is unavoidable, flag arithmetic performed on money rather than the declaration.

---

### safety-17 · Critical · Weak or Broken Cryptographic Primitive
**Scriptable**: Yes
**Rule**: A cryptographically broken hash or cipher used for a security purpose — MD5 or SHA-1 for signatures/passwords/integrity, DES/3DES/RC4 for encryption, or ECB mode — is practically forgeable or decryptable and must be replaced.
**Scope**: `diff`
**Finding action template**: Replace weak primitive `{algorithm}` at `{file}:{line}` with a modern one (SHA-256+/HMAC for hashing, AES-GCM for encryption)

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: dismiss when the weak primitive is provably not security-relevant — a non-cryptographic checksum for cache keys, ETags, or deduplication where an adversary gains nothing from a collision. MD5/SHA-1 for password hashing, token or signature generation, or integrity verification of untrusted data is always a finding. A password stored with a plain fast hash (even SHA-256) rather than a KDF (bcrypt/scrypt/argon2/PBKDF2) is a related finding you may raise here.

---

### safety-18 · Critical · TLS or Certificate Verification Disabled
**Scriptable**: Yes
**Rule**: Turning off TLS certificate or hostname verification makes the client accept any certificate, so an attacker on the network path can impersonate the server and read or alter the traffic.
**Scope**: `diff`
**Finding action template**: Remove the verification bypass at `{file}:{line}` and trust the system CA store — pin a certificate only through a proper pinning API, never by accepting all

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 6 language(s). Patterns: `scripts/checks/safety.tsv`.
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
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: the finding is the injection surface, not proof of a reachable exploit — flag it whenever any part of the command or evaluated string could carry a value the program did not fix at author time. Dismiss when every argument is a compile-time constant the caller cannot influence. For C#, `Process.Start` on a fixed filename or a URL (opening a browser) is not shell execution — dismiss those; flag when a shell (`cmd.exe`/`/bin/sh` with `/c`/`-c`) or an interpolated command line is involved. `eval`/`exec` on any non-constant input is always a finding.

---

### safety-20 · Critical · Unsafe Deserialization of Untrusted Data
**Scriptable**: Yes
**Rule**: Deserializing with a mechanism that can instantiate arbitrary types or run code during construction — Python `pickle`/`yaml.load`, Java native `readObject`, .NET `BinaryFormatter` or `TypeNameHandling` — turns any attacker-controlled bytes into remote code execution.
**Scope**: `diff`
**Finding action template**: Replace the unsafe deserializer at `{file}:{line}` with a data-only format (JSON / `yaml.safe_load` / `unarchivedObject(ofClass:)`) or restrict it to an explicit allow-list of types

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

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

NOTE for agent: the pattern flags comparison against a string literal (`x == "shipped"`), the unambiguous form. Also flag, by reading the diff, the variable-to-variable form (`a == b` where both are `String` or a boxed type such as `Integer`) — the pattern cannot see the types. Dismiss `== null`/`!= null` (identity is correct there) and comparisons of `char` literals written in single quotes (those are value types). The pattern's comment guard only suppresses full-line comments, so also dismiss a `==`/`!=` that appears inside a **trailing** `//` comment (e.g. `doStuff(); // status == "old"`).

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
where N is the number of finding lines you emitted, M is the total count of `### safety-NN` check headers in this file (21 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. On error: `STATUS: GROUP=safety failed=<brief reason>`
