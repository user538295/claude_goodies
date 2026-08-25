---
description: Internal agent prompt — not a user command. Invoked by /clean-code-review only.
---

# Group: clarity — Clean Code · Naming & Code Clarity

You are a review agent for the **Naming & Code Clarity** group of `/clean-code-review`.

You receive:
- `$DIFF` — the diff; added/context lines are prefixed `N|` with their true file line number. Anchor findings from these prefixes (at the line your action refers to) — never count hunk offsets. Strip the prefix when quoting code.
- `$PRECOMPUTED` — `{ check_id, file, line, matched_text }[]` hits from scriptable checks
- `$LANGUAGES` — detected language tokens (e.g. `typescript`, `python`)

For each precomputed hit: confirm it is a real violation (keep) or a false positive (dismiss silently).
For each non-scriptable check: analyse the diff and report violations.
Output findings only — one line per finding, no prose.

**Read-only**: do not edit any file. Output findings only.

> **Note**: Scriptable detections were pre-executed by the orchestrator — do not run detection commands yourself. Work from the `$PRECOMPUTED` hits you received and the full diff. Where a check explicitly requires reading repository files (e.g. 'read the file', 'grep the codebase', 'check the repo for a test file', 'trace the hierarchy'), you may do so. Where a check lists languages with no scripted detection: no precomputed hits exist for those — apply the check's rule manually to the diff. You may not edit any file.
>
> **Systematic sweep**: process this file's checks one at a time, in ID order; for each check, scan the entire diff before moving to the next. Report every violation of every check — never a sample, and never stop early because earlier checks already produced findings.

---

### clarity-01 · Minor · Variable Naming
**Scriptable**: No
**Rule**: Names must be intention-revealing, pronounceable, and searchable — no single letters outside loops, no Hungarian notation (`strName`, `iCount`), no encodings.
**How to check**: For each new/changed variable in the diff, assess whether the name conveys what it holds without reading its usage.
**Finding action template**: Rename `{name}` to `{suggestion}`

---

### clarity-02 · Minor · Function/Method Naming
**Scriptable**: No
**Rule**: Names must be verbs describing what the function does, not how — no `doProcess`, `handleData`, `manageX`.
**How to check**: Every new/changed function name — is it a verb? Does it describe the outcome, not the mechanism?
**Finding action template**: Rename `{name}` to `{suggestion}`

> Agent note: this rule has two distinct violations — name the right one in the action text. (1) Not a verb: say "name must be a verb". (2) Already a verb but describes the mechanism instead of the outcome (e.g. `probe_llama_server` → `fetch_llama_model_ids`): say "name describes the mechanism, not the outcome" — do NOT claim the name isn't a verb.

---

### clarity-03 · Minor · Class/Module Naming
**Scriptable**: No
**Rule**: Names must be nouns revealing a single, clear responsibility — no verb-noun hybrids like `ProcessOrder`.
**How to check**: Every new/changed class or module name — is it a noun? Does it imply exactly one responsibility?
**Finding action template**: Rename `{name}` to `{suggestion}`

---

### clarity-04 · Minor · Verb/Noun Convention
**Scriptable**: No
**Rule**: Classes = nouns, functions/methods = verbs — a class named `ProcessOrder` or a method named `OrderProcessor` violates this.
**How to check**: Scan all new/changed class and function names. Flag any class that reads as a verb phrase or any method that reads as a noun.
**Finding action template**: Rename `{name}` — classes must be nouns, methods must be verbs

---

### clarity-05 · Major · Consistent Naming
**Scriptable**: No
**Rule**: The same domain concept must use the same name everywhere in the diff — synonyms (`user`/`account`/`member` for the same thing) are a finding.
**How to check**: Identify domain concepts referenced in the diff. For each concept, list every name used. Flag any concept that has more than one name.
**Finding action template**: Unify `{synonymA}` and `{synonymB}` — choose one name for this concept across the codebase

---

### clarity-06 · Minor · Noise Words in Names
**Scriptable**: Yes
**Rule**: Suffixes `Manager`, `Processor`, `Data`, `Info`, `Handler`, `Helper`, `Util`/`Utils` add no meaning to any identifier.
**Scope**: `diff`
**Finding action template**: Remove noise word from `{name}` or replace with a meaningful term

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/clarity.tsv`.

NOTE for agent: Anchored to declaration sites (class/interface/etc.) — import sites and usage sites are excluded. Dismiss framework types (HttpMessageHandler, EventHandler, RequestHandler, FormData, ChangeEvent, IFormatProvider, ThreadPoolExecutor, Metadata, ErrorRequestHandler).

---

### clarity-07 · Minor · Comments Explaining WHAT
**Scriptable**: No
**Rule**: A comment that describes what the code does (not why) is a naming failure — the code should be renamed until the comment is redundant.
**How to check**: In the diff, find new inline comments (lines starting with `//`, `#`, `/*`). For each, decide: does it say WHY (business constraint, workaround, non-obvious invariant) or WHAT (restates what the immediately following code already expresses)? Flag WHAT-comments only.
**Finding action template**: Remove comment and rename `{symbol}` to make the name self-explanatory

---

### clarity-08 · Moderate · Magic Numbers/Strings
**Scriptable**: No
**Rule**: Raw numeric literals (except `0`, `1`, `-1`) and raw string constants encoding a domain concept must be named constants.
**How to check**: Scan added lines in the diff for literals that encode a domain rule — numbers like `365`, `86400`, a retry count of `3`, or status strings like `"pending"`. Judgment-only: mechanical number matching is far too noisy to script.
**Finding action template**: Extract `{literal}` into a named constant `{SUGGESTED_NAME}`

> Agent note: dismiss numbers in array index expressions (`[0]`, `[1]`), obvious loop boundaries (`i < 3` for a known-size collection), and test data literals. Flag numbers like `365`, `86400`, `3`, `7`, `42` that encode a domain rule (e.g. `7` for days-of-week, `3` for retry count). Dismiss version numbers, port numbers (3000, 8080, 443), HTTP status codes (200, 404, 500), known domain constants, and timeout values where purpose is obvious from context.

---

### clarity-09 · Moderate · Complex Boolean Conditions Not Extracted
**Scriptable**: Yes
**Rule**: An `if` condition with more than two sub-expressions must be extracted into a named predicate function or variable.
**Finding action template**: Extract condition into a named predicate `{suggestedName}({params})`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/clarity.tsv`.

NOTE for agent: the pattern finds two or more `&&`/`||` (or `and`/`or` in Python) within one statement, i.e. three or more joined terms. It is no longer restricted to `if`/`while`/`guard`: ternary conditions, JSX render guards (`{a && b && (`), inline callback predicates and assertion arguments now produce hits too. The brace blind spot is gone — `if (validate({ key: 1 }) && a && b)` is found; the scan now stops at `;`, not `{`.

Lines that already name the condition are excluded by the pattern: comments, `return …`, and lines that *begin* a `const`/`let`/`var`/`val` assignment. Python keeps its `if`/`elif`/`while` anchor because `and`/`or` are English words and an unanchored scan reads prose out of docstrings.

Two blind spots remain, and they need your eyes on the diff:
1. A condition split across lines still produces no hit on the `if` line itself. Python partly compensates: a continuation line that *starts* with `and`/`or` and carries a second operator is flagged, so a multi-line python condition surfaces at its second or third line — anchor the finding at the `if`.
2. A continuation line of a multi-line **named** assignment (`const ok =` on one line, `a && b && c` on the next) looks identical to a bare condition and will be flagged. Dismiss it — the condition already carries a name.

Also dismiss hits where the operators belong to separate statements rather than one condition, and where the nested operator is a null-coalescing default rather than a third term (`x == a and (y.get(k) or DEFAULT) == b` is two terms, not three).

---

### clarity-10 · Moderate · Code Clarity (Abstraction Level)
**Scriptable**: No
**Rule**: All statements in a function body must sit at the same abstraction level — mixing business-level calls with raw string formatting or bit manipulation in the same body is a finding.
**How to check**: For each new/changed function, scan its body. Does it mix high-level orchestration (call `processPayment()`) with low-level detail (build a raw SQL string, format bytes)? Flag the mismatch.
**Finding action template**: Extract low-level detail in `{functionName}` into a private helper, keep only high-level steps in the body

---

### clarity-11 · Moderate · Nested Ternary Operators
**Scriptable**: No
**Rule**: A ternary expression nested inside another ternary — cognitive cost matches deep nesting but lacks braces to signal depth.
**Scope**: `diff`
**Finding action template**: Replace nested ternary with an explicit `if/else` block or extract into a named function

**Detection**:
No scripted detection for any language — judge manually from the diff.
- typescript: non-scriptable — nested ternaries are split across lines by standard formatters; agent must read the diff for deeply nested conditional expressions
- javascript: non-scriptable — nested ternaries are split across lines by standard formatters; agent must read the diff for deeply nested conditional expressions
- python: non-scriptable — nested ternaries are split across lines by standard formatters; agent must read the diff for deeply nested conditional expressions
- csharp: non-scriptable — nested ternaries are split across lines by standard formatters; agent must read the diff for deeply nested conditional expressions
- swift: non-scriptable — nested ternaries are split across lines by standard formatters; agent must read the diff for deeply nested conditional expressions
- kotlin: non-scriptable — nested ternaries are split across lines by standard formatters; agent must read the diff for deeply nested conditional expressions
- java: non-scriptable — nested ternaries are split across lines by standard formatters; agent must read the diff for deeply nested conditional expressions

NOTE for agent: Look for a ternary expression (`condition ? thenBranch : elseBranch`) where either the then-branch or else-branch is itself a ternary. Dismiss `?.` (optional chaining), `?:` (TypeScript type suffix or Kotlin Elvis operator), and URLs containing `?`. Dismiss sequential ternaries on one line (`a ? x : y, b ? p : q`) — these are not nested. Standard formatters (Prettier, Black) split multi-condition ternaries across lines, making them invisible to single-line grep.

---

### clarity-12 · Minor · Imperative Loop vs Declarative Pipeline
**Scriptable**: No
**Rule**: A `for` loop that only filters, transforms, and accumulates a collection — with no side effects and no early exit — when a `map`/`filter`/`reduce` pipeline would make intent immediately readable.
**How to check**: Find `for` loops in the diff. If the loop body contains only accumulation/transformation logic with no break, return, or side-effecting call, flag it.
**Finding action template**: Replace loop in `{functionName}` with a `{map/filter/reduce}` pipeline

---

### clarity-13 · Minor · Variable Declared Far from First Use
**Scriptable**: No
**Rule**: A variable declared more than 5 lines before its first usage forces the reader to hold its value in mind unnecessarily.
**How to check**: In new/changed function bodies, locate each variable declaration and its first usage. Flag any gap greater than 5 lines.
**Finding action template**: Move declaration of `{variable}` to line {firstUseLine}

---

### clarity-14 · Major · Command-Query Separation
**Scriptable**: No
**Rule**: A function must either change state (command — returns void) or return a value (query — no side effects). Never both.
**How to check**: For each new/changed function that returns a non-void value, check whether its body also mutates state, writes to a field, appends to a collection, or calls a side-effecting operation.
**Finding action template**: Split `{functionName}` into a command `{commandName}()` (void, changes state) and a query `{queryName}()` (returns value, no side effects)

---

### clarity-15 · Moderate · Deep Nesting
**Scriptable**: No
**Rule**: Any block nested more than 3 levels deep (counting `if`/`else`/`try`/`for`/`while` as level boundaries).
**How to check**: In new/changed functions, track opening blocks. Flag any execution path that reaches depth 4 or greater.
**Finding action template**: Reduce nesting in `{functionName}` with guard clauses / early returns, or extract the inner block into a named function

---

### clarity-16 · Major · Cyclomatic Complexity
**Scriptable**: Yes
**Rule**: Branch count per function (if/else/switch/case/catch/ternary/loop) above 10 is a test and readability risk.
**Scope**: `files`
**Finding action template**: Reduce complexity in `{functionName}` (currently {N} branches) by extracting branch groups into named functions

**Detection** (file-level keyword count — agent must verify per function boundary):
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/clarity.tsv`.

> Agent note: the command yields a total per file. Only raise a finding if you can identify an individual function within a changed file whose branch count in isolation exceeds 10. The awk threshold `$NF > 10` is a heuristic pre-filter to reduce agent workload — it removes the lowest-count files. It is NOT a soundness filter; a file with count ≤10 could theoretically still contain a complex function (e.g. one line with `case 'a': case 'b': case 'c':` counts as 1 but is 3 branches). Verify per-function complexity manually for all flagged files.
>
> Anchor all clarity-16 findings at the line of the function's declaration/signature (the `def`, `function`, `fun`, `func`, or method-header line). Do not anchor at the first statement or closing brace. When reporting, the file and function name are sufficient — anchor at the function's declaration line as found in the diff, not at line 1.
>
> $PRECOMPUTED shape for clarity-16: `{ check_id: "clarity-16", file, count }` — no `line` field (file-level keyword count). Use `count` as a signal; only flag after verifying a specific function in that file exceeds the limit.

---

### clarity-17 · Moderate · Function Length
**Scriptable**: Yes
**Rule**: Any changed function exceeding 150 lines — identify logical sub-units that can be extracted.
**Scope**: `files`
**Finding action template**: Extract logical sub-unit `{suggestedName}` from `{functionName}` (currently {N} lines)

**Detection** (per-function span — declaration line through closing line):
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/clarity.tsv`.

> Agent note: each hit is one function that spans more than 150 lines, already measured — `mfunc` walks python bodies by indentation and brace-language bodies by brace balance. The matched text is the declaration line. Confirm the span before reporting (a brace inside a block comment or a multi-line string literal can inflate it) and dismiss hits where the "function" is generated code or a test-harness block (`describe`/`suite`) rather than a unit of logic. The declaration regex is loose by design — the 150-line threshold does the filtering — so an anonymous callback or a computed property can appear; those are still functions and still count. Nested functions are reported independently, so an inner long function and its long enclosing function are two findings.
>
> Anchor all clarity-17 findings at the line of the function's declaration/signature (the `def`, `function`, `fun`, `func`, or method-header line) — that is the `line` the hit already carries. Do not anchor at line 1.
>
> $PRECOMPUTED shape for clarity-17: `{ check_id: "clarity-17", file, line, matched_text }` — `line` is the function's declaration line.

---

## Output format

One line per confirmed finding:
```
[clarity-NN] · Severity · Check Name | file:line | One-line action
```
No prose. Dismiss false positives silently.

If the action field contains a literal ` | ` (e.g. a TypeScript union type like `string | null`), escape it as ` \| ` to prevent splitting. The synthesizer unescapes ` \| ` back to ` | ` before rendering.

On the **final line** of your output, always emit a STATUS line:
`STATUS: GROUP=clarity findings=N checks=M ok`
where N is the number of finding lines you emitted, M is the total count of `### clarity-NN` check headers in this file (17 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. If an error prevented evaluation: `STATUS: GROUP=clarity failed=<brief reason>`
