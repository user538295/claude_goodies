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

NOTE for agent: the patterns find resources being opened, and already exclude the scoped forms that guarantee cleanup on the same line (`with` in Python, `using` in C#, try-with-resources in Java). A hit is only a finding if nothing else guarantees the close — before flagging, read the surrounding lines for a `finally`, `defer`, `use {}`, `.close()` on every path, or a wrapper object that owns the lifetime. Dismiss resources handed to a caller or a container that takes ownership. The patterns cannot see multi-line ownership, so also apply the rule manually to resource-opening calls in the diff that produced no hit.

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
Scripted (hits arrive in `$PRECOMPUTED`): 5 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- typescript: non-scriptable — see NOTE
- javascript: non-scriptable — see NOTE

NOTE for agent: For TypeScript/JavaScript: the agent must inspect the diff manually. Look for async function calls that are neither awaited nor have `.then()`/`.catch()` attached, and whose return value is discarded. Common patterns: `this.service.sendEmail(x)` with no `await`, `void somePromise` without a catch. For C#: grep finds all Async method calls. The agent must check: (1) is the calling method declared `async`? (2) is there an `await` on this line or is the result assigned? If neither, flag it.

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

NOTE for agent: only flag when the blocking call appears inside an async function/coroutine/suspend function. Dismiss in synchronous contexts. For Java `.get()` and `.join()`, only flag when called on a `CompletableFuture`, `Future`, or `CompletionStage` variable — dismiss getter methods, map lookups, and `String.join()`. For C#: dismiss `.Result` on types named `Result<T>`, `Option<T>`, `Either<L,R>`, or similar functional result types — flag `.Result` and `.Wait()` only when the containing type is `Task`, `ValueTask`, or their generic variants.

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

NOTE for agent: dismiss a hit when a timeout is configured elsewhere and provably covers this call — a client built with a default timeout, an enclosing `withTimeout`/`CancellationTokenSource`, or a framework-wide policy. The finding is a call that can wait forever, not a call missing a specific argument. Expect one recurring false positive you must resolve by reading nearby lines: options passed as a prebuilt variable (`const opts = { signal }; fetch(url, opts)`) look identical to no options at all, because the pattern only sees the call line. For the languages with no pattern, apply the rule by reading the diff.

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

NOTE for agent: this is distinct from smells-12, which owns exceptions that are swallowed. Here the exception does propagate; what is lost is the origin. In C# and Java flag `throw ex;` and prefer bare `throw;`. In TypeScript and JavaScript flag a new error built from only `err.message`, which drops the original. For Python, read the diff for a `raise` inside an `except` that omits `from`.

---

### safety-11 · Major · Unabstracted Clock, Randomness, or Identifier in Production Code
**Scriptable**: Yes
**Rule**: Production code reading the current time, random numbers, or fresh identifiers directly cannot be tested for behaviour that depends on them, and a naive local timestamp is wrong for every reader in another timezone.
**Scope**: `diff`
**Finding action template**: Inject a clock, random source, or identifier generator into `{ClassName}` instead of calling `{call}` directly at `{file}:{line}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: tests-04 owns this inside test files; these patterns deliberately exclude test paths so the two never overlap. Flag when the value affects a decision, a stored record, or an output the caller can observe. Dismiss logging timestamps, metrics, cache keys, and one-off scripts, where injecting a source buys nothing. Treat a naive local-time call as a finding on its own even when testability is not at stake.

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
**Rule**: `assert` is removed when Python runs optimised, so any check written as an assertion silently disappears from the deployed program.
**Scope**: `diff`
**Finding action template**: Replace the assertion at `{file}:{line}` with an explicit check that raises `{ExceptionType}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 1 language(s). Patterns: `scripts/checks/safety.tsv`.
No scripted detection for:
- typescript: not applicable — no assertion statement stripped by an optimiser
- javascript: not applicable — no assertion statement stripped by an optimiser
- csharp: covered by the compiler's own conditional-compilation rules
- java: not applicable — assertions are disabled by default and rarely used for validation
- kotlin: not applicable — no assertion statement stripped by an optimiser
- swift: not applicable — `precondition` survives optimisation and is the correct tool

NOTE for agent: the pattern already excludes test paths, where assertions are correct. Flag assertions that validate input, arguments, or external data. Dismiss assertions that state an internal invariant the code itself guarantees — those are documentation, and losing them under optimisation is harmless.

---

### safety-14 · Critical · Hardcoded Credential
**Scriptable**: Yes
**Rule**: A password, key, or token written into source is readable by everyone with repository access and stays valid in the history after it is deleted.
**Scope**: `diff`
**Finding action template**: Move `{name}` out of source at `{file}:{line}` into configuration or a secret store, and rotate the exposed value

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: dismiss obvious non-secrets — empty strings, placeholders such as `changeme` or `xxx`, values that are plainly test fixtures, and public identifiers that merely have a secret-sounding name (a client id, a public key, a header name). Flag anything that looks like a live credential even in a test file: committed test credentials are frequently real. When the value is genuinely a secret, say so plainly in the action and include rotation, because deleting the line does not un-expose it.

---

### safety-15 · Critical · Query Built by String Concatenation
**Scriptable**: Yes
**Rule**: A query assembled by joining or interpolating values into its text lets any value that contains query syntax change what the query does.
**Scope**: `diff`
**Finding action template**: Replace the concatenated query at `{file}:{line}` with a parameterised statement binding `{value}` as a parameter

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/safety.tsv`.

NOTE for agent: the pattern requires both a statement shape and an interpolation or concatenation on the same line, and skips comment lines, so most hits are real. Dismiss a hit when every interpolated part is a compile-time constant the caller cannot influence — a fixed table name from an enum, for example. Dismiss the safe placeholder forms that only look similar: `%s` with a separate parameter tuple, `?`, `$1`, and `@named` bindings. When the value comes from outside the program, the severity stands as written.

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

## Output instruction

Output one finding line per violation, exactly in this format:
```
[safety-NN] · Severity · Check Name | file:line | One-line action
```
No prose. Dismiss false positives silently.

If the action field contains a literal ` | ` (e.g. a TypeScript union type like `string | null`), escape it as ` \| ` to prevent splitting. The synthesizer unescapes ` \| ` back to ` | ` before rendering.

On the **final line** of your output, always emit:
`STATUS: GROUP=safety findings=N checks=M ok`
where N is the number of finding lines you emitted, M is the total count of `### safety-NN` check headers in this file (16 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. On error: `STATUS: GROUP=safety failed=<brief reason>`
