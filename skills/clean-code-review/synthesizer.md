# Synthesizer — /clean-code-review

You receive finding lines and STATUS lines from multiple review agents, plus metadata from the orchestrator. Deduplicate, group by file, sort by severity, output the final report.

## Inputs you are given
- Finding lines from all group agents
- STATUS lines: `STATUS: GROUP=XX findings=N checks=M ok` or `STATUS: GROUP=XX failed=<reason>`
- Active groups list
- Detected language tokens list
- Skipped files list (`$SKIPPED`)
- Unmapped extensions (`unanalysed.txt`), if any — shown in report header as "Unanalysed: .ext1, .ext2"
- Expected check counts per group: clarity=17, smells=23, solid=15, arch=11, tests=13, safety=21, ddd=9
- The review target (from `mode.txt` — e.g. `staged unstaged untracked`, `ref: main..HEAD`, or `files`)
- `WARN-CAP:` lines (hit-cap warnings, when findings were truncated after added-line filtering)
- `WARN-DETECT:` lines (detection-failure warnings, when a detection command errored)
- `NOTICE-LARGE-DIFF:` (if the target covers more than 100 files)

`{checks_run}` = sum of the expected check counts for the active groups (clarity=17, smells=23, solid=15, arch=11, tests=13, safety=21, ddd=9). Do not count headers — use the expected-count table.

## Agent failure handling

- STATUS line contains `failed=` → add a warning after the report: `⚠ XX agent failed: <reason>`.
- No STATUS line from an agent → treat as `failed: no status received`.
- Finding line missing `file:line` → include as `[ID-NN] · Severity · Check Name | (location unknown) | One-line action`.
- If a group agent emitted finding lines **before** a `failed=` STATUS (or before a truncated response with no STATUS): **include those findings** in the report. Append the partial-failure note after the closing `---` separator, alongside all other agent-failure warnings. Format: `⚠ {GROUP} agent failed (partial): <reason> — findings received before failure are included above`.

M-mismatch and N-mismatch warnings (described in the next section) are output in the same post-`---` block as agent-failure warnings.

For each group's STATUS line:
- Compare `checks=M` against its expected count. If M differs, emit: `⚠ {GROUP} reported {M}/{expected} checks — evaluation may have been partial.`
- Compare declared `findings=N` against the actual count of finding lines received from that group. If they differ, emit: `⚠ {GROUP} declared {N} findings but {actual} lines received — response may have been truncated.`

## Parsing finding lines

Split each finding line on the **first two** occurrences of ` | ` only. The part after the second ` | ` is the action field — treat it as verbatim text and do not split further (it may contain ` | ` for type-union examples like `string | null`). Agents that include a literal ` | ` in an action should escape it as ` \| `. Before rendering the action field in the output report, unescape any ` \| ` back to ` | ` — agents escape literal pipes in action text to avoid splitting ambiguity.

## Deduplication rules

- Same `check_id` + `file` + `line` → keep one, drop duplicates.
- **Cross-group semantic duplicates**: when two findings from different groups describe the same underlying defect in the same file and the same function/fixture — even at different lines (e.g. a missing-teardown defect flagged by both safety-01 and tests-06) — merge them: keep the finding whose anchor and action are more actionable, use the higher of the two severities, and append `(see also: {other_id})`. Apply this only when the described defect is clearly the same; overlapping but distinct concerns stay separate.
- Same `file` + `line` + **different `check_id` → keep all findings, unless the pair appears in the table below** (in which case apply the table rule). Default if no entry: keep both and append `(see also: {other_id})` to the higher-severity finding. **Exception**: do NOT apply the default `(see also)` annotation to findings anchored at `:1` (the pseudo-anchor used by smells-01 and tests-01 for file-level findings). These represent distinct structural concerns that should not imply a relationship. This exemption applies **both** to the default see-also rule AND to pair-specific rows that specify 'keep both (see also)' — do not add the `(see also:)` annotation to any finding whose location is `:1`. **Tie-break when severities are equal**: annotate the finding from the lower group ordinal (clarity < smells < solid < arch < tests < safety < ddd). **Secondary tie-break for same-group pairs**: annotate the finding with the lower check number (e.g. clarity-09 before clarity-15 when both are Moderate on the same line).
- Same `file` + `line` + check IDs from overlapping categories → apply the pair-specific rule in the table below (this is the override for the preceding rule).

If a single finding accumulates multiple `(see also:)` annotations from separate pair applications, combine them into one: `(see also: X, Y)` — not two separate suffixes.

**Transitive closure**: when three or more findings share the same `file:line`, apply all pair-specific rules iteratively until a full pass produces no drops. **Evaluation order within each pass**: process candidate pairs in ascending order of (left member's group ordinal: clarity<smells<solid<arch<tests<safety<ddd; then left member's check number). When two pairs share the same left member (same group ordinal and check number), break the tie by right member's group ordinal (ascending), then right member's check number (ascending). This gives a total order over all candidate pairs and makes the closure deterministic regardless of the order findings arrive. Drops are final — if a finding is dropped, remove it from all remaining comparisons. Example: solid-06 and ddd-01 fire on a Kotlin test-class `var config: Config = …` alongside tests-06. Pass 1 — candidate pairs sorted: `(solid-06, tests-06)` [solid=2, tests=4] before `(solid-06, ddd-01)` [solid=2, ddd=6] because tests(4) < ddd(6) on the secondary key. Apply `solid-06↔tests-06` → drop solid-06. `(ddd-01, tests-06)` applies → drop ddd-01. Result: tests-06 alone. Confluent.

**Test-file identification**: For all test-file-conditional rows in the table below, a file is a test file if its path matches any of the following conventions:

| Language | grep `-E` pattern |
|---|---|
| TypeScript/JavaScript | `\.(test\|spec\|cy\|e2e\|stories)\.(ts\|tsx\|js\|jsx\|mts\|mjs)$\|(^\|/)__tests__/` |
| Python | `(^\|/)(test_[^/]+\|[^/]+_test)\.py$\|(^\|/)tests?/\|conftest\.py$` |
| Kotlin | `(Tests?\|Spec)\.kts?$\|(^\|/)src/test/` |
| Swift | `Tests?\.swift$\|(^\|/)[^/]*Tests?/` |
| C# | `(Test\|Tests)\.cs$\|(^\|/)[^/]*\.Tests?/` |
| Java | `Tests?\.java$\|(^\|/)src/test/` |

(These patterns must stay in sync with the canonical table in groups/tests.md.)

| Pair | Overlap reason | Action |
|---|---|---|
| solid-05 ↔ arch-04 | missing interface / DIP | keep both (see also) |
| clarity-07 ↔ arch-10 | doc comment vs WHAT comment | keep both (see also) |
| smells-02 ↔ smells-15 | constructor with both >3 params AND non-assignment logic | keep both (see also) — smells-02 flags the interface (wrap params in a record), smells-15 flags the implementation (extract initialization to a factory) |
| solid-11 ↔ ddd-04 | anemic model / domain logic placement | keep both (see also) |
| solid-08 ↔ solid-09 | same `let`/`var` — single-assignment and global/module state | keep solid-09 (module-state signal stronger), drop solid-08. This aligns with solid-06↔solid-09 — when both module-level mutability (solid-09) and another mutability check fire on the same line, solid-09 is kept as the dominant signal. |
| solid-06 ↔ solid-08 | same Swift/Kotlin var declaration — field encapsulation vs single-assignment mutability | keep solid-06 (Major, encapsulation signal stronger); drop solid-08 (Minor) |
| solid-06 ↔ ddd-01 | public mutable property (TS: `public x =`; Swift/Kotlin: `var x: T`) — pattern overlap across languages | keep solid-06 (drop ddd-01) |
| safety-07 ↔ tests-05 | `@ts-ignore` in test files — safety-07 is Moderate, tests-05 is Major | keep tests-05 (Major > Moderate); drop safety-07 |
| arch-11 ↔ clarity-08 | same hardcoded address reported as a magic string and as environment coupling | keep arch-11, drop clarity-08 — naming a constant does not fix the coupling, only moving the value into configuration does |
| safety-14 ↔ clarity-08 | same hardcoded credential reported as a magic string | keep safety-14 (Critical), drop clarity-08 |
| safety-16 ↔ solid-07 | same money field — wrong numeric type and a primitive standing in for a domain type | keep both (see also) — safety-16 is the correctness defect (rounding drift), solid-07 is the modelling one |
| smells-21 ↔ safety-07 | TypeScript `as any` next to a suppression comment | keep both only when they sit on different lines; on the same line keep smells-21 (the type) and drop safety-07 (the suppression) |
| safety-06 ↔ tests-04 | blocking sleep in test files (any language: Swift `sleep(`, C#/Java/Kotlin `Thread.sleep`, Python `time.sleep`) | In **test files**: keep tests-04 (Major), drop safety-06. In **production code**: keep safety-06. |
| tests-07 ↔ tests-11 | success-only test suite — tests-11 is more specific | keep tests-11; drop tests-07 |
| tests-02 ↔ tests-10 | tests-10 is more specific (Moderate); tests-02 is Minor | keep tests-10; drop tests-02 |
| solid-06 ↔ tests-06 | same `var`/`self.x =` line in test files (any language) | in test files keep tests-06 (Major), drop solid-06 |
| ddd-01 ↔ tests-06 | Swift/Kotlin `var name:` in test classes | in test files keep tests-06, drop ddd-01 |
| solid-08 ↔ tests-06 | same `let`/`var` line in test files (any language) | in test files keep tests-06 (Major), drop solid-08 (Minor) |
| solid-06 ↔ solid-09 | both match Swift/Kotlin `var` at module level | keep solid-09 (module-state signal stronger), drop solid-06 |
| ddd-01 ↔ solid-09 | same top-level `var` declaration on Kotlin/Swift module | keep solid-09 (module-state signal stronger), drop ddd-01 |
| solid-09 ↔ tests-06 | module-level mutable variable in test files (any language: TS/JS `let`/`var`, Swift/Kotlin `var` at module scope) | in test files keep tests-06 (Major), drop solid-09 (any language) |
| tests-05 ↔ tests-06 | Python `self._cache = {}` matches tests-05 (`\._`) and tests-06 (`^\s*self\.\w+\s*=`) | keep tests-06, drop tests-05 (tests-06 captures assignment; tests-05 targets access not assignment) |
| tests-04 ↔ tests-06 | Swift/Kotlin `var x = Date()`/`Instant.now()` in a test fixture — non-determinism AND shared mutable state | keep tests-04 (non-determinism is the concrete hazard; the field assignment is secondary); drop tests-06 |
| solid-10 ↔ arch-04 | `new ConcreteInfrastructureClass()` inside a use case | keep both (see also) — solid-10 flags the instantiation; arch-04 flags the architectural boundary violation |
| arch-02 ↔ solid-05 | same framework-import line | keep both (see also) — arch-02 flags the pattern, solid-05 judges the DI violation |
| tests-09 ↔ tests-12 | trivial assertion satisfies both checks | keep tests-09 (Critical), drop tests-12 (Major) |
| solid-10 ↔ tests-04 | `new Date()`/`new Random()` in test files — solid-10 Major, tests-04 Major | in test files keep tests-04, drop solid-10 (matches solid-08/solid-09 pattern; solid-10's dismiss-in-test-files NOTE may not always fire) |
| smells-02 ↔ smells-03 | function with >3 params AND a boolean param | keep smells-03 (more specific); drop smells-02 (smells-03 is a superset in this case) |
| smells-12 ↔ solid-12 | one-line log-and-continue catch — smells-12 Major, solid-12 Moderate | keep smells-12 (Major > Moderate); drop solid-12 |
| safety-03 ↔ safety-06 | C# `.BarAsync().Wait()` — safety-03 Moderate, safety-06 Major | keep safety-06 (blocking-wait is the concrete hazard); drop safety-03 |
| clarity-16 ↔ clarity-17 | 200-line 15-branch function — both fire on the function declaration line | keep both (see also) — clarity-16 targets complexity, clarity-17 targets length; distinct concerns |
| smells-08 ↔ smells-16 | nullable field that is also never-initialized | keep both (see also) — smells-08 flags the null contract, smells-16 flags the initialization gap |

(Note: solid-08 and solid-09 dismiss in test files per their agent instructions. These rows act as a safety net in case an agent skips the dismissal.)

(Note: clarity-16 and clarity-17 findings must be anchored at the function's declaration/signature line. This is important for deduplication: if both fire on the same function, they will share the same `file:line` and the clarity-16↔clarity-17 pair rule applies.)

## Severity sort order
Critical → Major → Moderate → Minor

**Severity is fixed by check declaration**: group agents must copy severity verbatim from the check heading in their MD file. The only sanctioned deviations:
- ddd-03 may be reported as Major (one step below Critical) when the aggregate boundary cannot be conclusively determined from the diff alone.
- tests-01's project-has-tests baseline finding may be reported as Major (`[tests-01] · Major · Missing Tests | (project-level):1 | …`) when the repository contains no test suite at all — this prevents flooding with one Critical per file in greenfield repos.
- solid-03 may be reported as Major (one level below Critical) when the full class hierarchy is not visible in the diff alone.

File sections: order by highest severity finding in the file (Critical-containing files first).

## Output format

**Order of work**: write the report body (file sections with finding lines) FIRST, then fill the header counts by tallying the finding lines you actually rendered — count them line by line, per severity. The header must equal exactly what appears in the body; never carry counts over from the input or from memory.

**Unescaping**: when writing each finding line into the body, replace every ` \| ` in the action field with ` | ` (agents escape literal pipes to protect parsing — the rendered report must show the real ` | `, e.g. `str | None`, never `str \| None`).

```
## Clean Code Review

**{N} findings · {X} Critical · {Y} Major · {Z} Moderate · {W} Minor** (post-deduplication)
**Target:** {mode}
**Groups run:** {active_groups} · {checks_run} checks declared
**Languages detected:** {language_tokens}
**Unanalysed:** {ext_list}
**Notices:**
- {large_diff_notice}

---

### `path/to/file.ts`

[safety-01] · Critical · Resource Leak | path/to/file.ts:23 | Wrap FileStream in a using block
[solid-03] · Critical · Liskov Substitution Principle | path/to/file.ts:45 | Restore base class postcondition: never return null where parent returns a value

### `src/service.ts`

[solid-05] · Major · Dependency Inversion Principle | src/service.ts:14 | Replace direct dependency on PostgresClient with an interface — inject the implementation (see also: arch-02)

### `path/to/other.ts`

[clarity-08] · Moderate · Magic Numbers/Strings | path/to/other.ts:12 | Extract 365 into named constant DAYS_IN_YEAR

---

**Skipped files:** {count} files excluded — {examples, up to 3}
**Truncated:** {check_id} findings capped at 200/{N} — narrow your diff for complete coverage (renders WARN-CAP: lines)
**Detection failures:** (one entry per failed check — renders WARN-DETECT: lines)
- {check_id}/{lang} detection error: {stderr_first_line} — results may be incomplete
```

("`checks declared`" = sum of the expected check counts for the active groups: clarity=17, smells=23, solid=15, arch=11, tests=13, safety=21, ddd=9. Do not count headers — use this expected-count table. Checks for languages absent from the diff may have run no scriptable detection.)

Omit the `**Unanalysed:**` line if no unmapped extensions were passed.
Omit the `**Skipped files:**` line entirely if `$SKIPPED` is empty.
Omit the `**Truncated:**` line if no `WARN-CAP:` lines were passed. Emit one line per truncated check.
Omit the `**Notices:**` block if no `NOTICE-LARGE-DIFF:` was passed.
Omit the `**Detection failures:**` label if no `WARN-DETECT:` lines were passed. When present, emit one bullet per failed check; do not merge multiple failures onto one line. Extract `{stderr_first_line}` from the message portion of each `WARN-DETECT:` line (format: `WARN-DETECT: {check_id}/{lang} detection error: {message}` — `{stderr_first_line}` is the `{message}` text).

If any findings have `(location unknown)`:

```
### (location unknown)

[ID-NN] · Severity · Check Name | (location unknown) | One-line action
```

For the `(project-level)` pseudo-path (used by tests-01's no-test-suite baseline finding), group it under a `### (project-level)` section — do NOT backtick-format it. This is the only permitted pseudo-path other than `(location unknown)`.

If zero findings AND all active groups reported STATUS ok AND no `WARN-CAP:` truncation warnings AND no M-mismatch or N-mismatch warnings AND no `WARN-DETECT:` detection-failure warnings AND no `NOTICE-LARGE-DIFF:` notice: output `✓ No findings. Target: {mode}. Groups run: {active_groups} · {checks_run} checks. Languages: {language_tokens}.` Append ` Unanalysed: {ext_list}.` if unmapped extensions exist. If any of those conditions fails, render the full output format with the appropriate slots instead of the ✓ line.

If zero findings BUT one or more groups failed: do NOT output the ✓ line. Render the **full output format** (the `## Clean Code Review` header, counts as `0 findings · 0 Critical · 0 Major · 0 Moderate · 0 Minor`, Groups run, Languages detected, and any Unanalysed/Skipped lines). Always append `---` followed by failure warnings.

In either case (findings or no findings), if any agent failed, always emit a `---` separator followed by the failure warnings.

Output nothing else — no prose, no summaries, no suggestions. Never narrate or explain deduplication decisions (no "dropped X", "annotated Y" commentary) — apply them silently; the report is the only output. Agent failure warnings go after the closing `---`. M-mismatch and N-mismatch warnings go after the closing `---`, alongside agent-failure warnings. They are always emitted when present — on the ✓ path, on the findings path, and on the zero-findings-with-failure path.
