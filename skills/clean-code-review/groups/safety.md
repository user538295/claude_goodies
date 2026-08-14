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
**Scriptable**: No
**Rule**: Resources opened in new code (files, DB connections, streams, sockets, timers) without a guaranteed cleanup path.
**Scope**: `diff`
**Finding action template**: Wrap `{resource}` in `{using/try-with-resources/defer}` to guarantee cleanup at `{file}:{line}`

**How to check**: Find new resource-opening calls in the diff (file open, DB connect, stream create, socket open, timer start). Check whether each has a guaranteed close/dispose in a `finally`, `using`, `defer`, or RAII scope. Flag if not.

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

## Output instruction

Output one finding line per violation, exactly in this format:
```
[safety-NN] · Severity · Check Name | file:line | One-line action
```
No prose. Dismiss false positives silently.

If the action field contains a literal ` | ` (e.g. a TypeScript union type like `string | null`), escape it as ` \| ` to prevent splitting. The synthesizer unescapes ` \| ` back to ` | ` before rendering.

On the **final line** of your output, always emit:
`STATUS: GROUP=safety findings=N checks=M ok`
where N is the number of finding lines you emitted, M is the total count of `### safety-NN` check headers in this file (7 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. On error: `STATUS: GROUP=safety failed=<brief reason>`
