---
description: Internal agent prompt — not a user command. Invoked by /clean-code-review only.
---

# Group: BDD & Testing (tests)

**Read-only**: do not edit any file. Output findings only.

You are the BDD & Testing review agent for `/clean-code-review`. You receive:
- `$DIFF` — the diff; added/context lines are prefixed `N|` with their true file line number. Anchor findings from these prefixes (at the line your action refers to) — never count hunk offsets. Strip the prefix when quoting code.
- `$PRECOMPUTED` — `{ check_id, file, line, matched_text }[]` hits from scriptable checks
- `$LANGUAGES` — detected language tokens (e.g. `typescript`, `python`)

For each precomputed hit: confirm it is a real violation (keep) or a false positive (dismiss silently).
For each judgment check: analyse the diff and report violations.
Output findings only — one line per finding, no prose.

> **Note**: Scriptable detections were pre-executed by the orchestrator — do not run detection commands yourself. Work from the `$PRECOMPUTED` hits you received and the full diff. Where a check explicitly requires reading repository files (e.g. 'read the file', 'grep the codebase', 'check the repo for a test file', 'trace the hierarchy'), you may do so. Where a check lists languages with no scripted detection: no precomputed hits exist for those — apply the check's rule manually to the diff. You may not edit any file.
>
> **Systematic sweep**: process this file's checks one at a time, in ID order; for each check, scan the entire diff before moving to the next. Report every violation of every check — never a sample, and never stop early because earlier checks already produced findings.

---

## Test file naming conventions

| Language | Pattern |
|---|---|
| typescript/javascript | `*.test.ts`, `*.spec.ts`, `*.test.tsx`, `*.spec.tsx`, `*.test.js`, `*.spec.js`, `*.test.jsx`, `*.spec.jsx`, any file under `__tests__/` (maps to production file of same name) |
| python | `test_*.py`, `*_test.py`, `conftest.py` (test infrastructure — exclude from production module scanning) |
| csharp | `*Tests.cs`, `*Test.cs` |
| swift | `*Tests.swift` |
| kotlin | `*Test.kt`, `*Tests.kt`, `*Spec.kt` |
| java | `*Test.java`, `*Tests.java` |

---

> **IMPORTANT: The test-file patterns below MUST be kept in sync with: (1) the `grep -vE` exclusion in tests-01 and the `grep -E` inclusions in tests-04/05/06/08/09 inside `scripts/checks/tests.tsv`, and (2) synthesizer.md's test-file identification table.**

## Canonical test-file path patterns

| Language | grep `-E` pattern |
|---|---|
| typescript/javascript | `\.(test\|spec\|cy\|e2e\|stories)\.(ts\|tsx\|js\|jsx\|mts\|mjs)$\|(^\|/)__tests__/` |
| python | `(^\|/)(test_[^/]+\|[^/]+_test)\.py$\|(^\|/)tests?/\|conftest\.py$` |
| kotlin | `(Tests?\|Spec)\.kts?$\|(^\|/)src/test/` |
| swift | `Tests?\.swift$\|(^\|/)[^/]*Tests?/` |
| csharp | `(Test\|Tests)\.cs$\|(^\|/)[^/]*\.Tests?/` |
| java | `Tests?\.java$\|(^\|/)src/test/` |

tests-01's `grep -vE` exclusion and tests-04/05/06/08/09's `grep -E` inclusion use these exact patterns.

---

## Checks

### tests-01 · Critical · Missing Tests
**Scriptable**: Yes
**Rule**: Every new module (file or class) introduced in the diff that has no corresponding test file is a finding. If a test file already exists for the module (using the naming conventions below), do not flag individual missing test cases — that requires full test analysis beyond the diff.
**Scope**: `files`
**Finding action template**: Create a test file for `{moduleName}` — no test file exists yet

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/tests.tsv`.

NOTE for agent: this check is file-level, not diff-level. For each public symbol found, check the repo (not just the diff) for a corresponding test file using the naming conventions above. Only flag if **no test file at all** exists for a new module — do not flag if the module already has a test file even if the specific new symbol lacks a dedicated test. Only flag symbols that appear in the diff as *newly added* (lines starting with `+` in the diff). Do not flag pre-existing public symbols in a touched file — those were tested before this change.

**Project-has-tests baseline**: if the entire repository contains no test files at all (no files matching any of the test naming conventions above), emit a single `[tests-01] · Major · Missing Tests | (project-level):1 | Project has no test suite — add a test framework (e.g. Jest, pytest, JUnit) and initial tests` finding instead of per-file Critical findings. This avoids flooding the report in greenfield projects where no test infrastructure exists yet.

If the precomputed hits contain multiple tests-01 entries for the same file (one per exported symbol), collapse them to **one finding per file**: `[tests-01] · Critical · Missing Tests | {file}:1 | Create a test file for {moduleName}` — use line 1 as the anchor since this is a file-level finding.

---

### tests-02 · Minor · Test Naming
**Scriptable**: No
**Rule**: Test names must describe a scenario, not an implementation — use `given_X_when_Y_then_Z` or `should_do_X_when_Y` patterns.
**Finding action template**: Rename `{testName}` to `{given_X_when_Y_then_Z}` pattern

**How to check**: For each new test function/method in the diff, evaluate the name. Flag vague names like `test_save`, `testProcess`, `test1`, `testMethod`.

---

### tests-03 · Major · Excessive Mock Setup
**Scriptable**: No
**Rule**: Test methods where mock/stub/spy configuration is longer than the assertion section — signals the production code has too many dependencies.
**Finding action template**: Reduce mock setup in `{testName}` — production code `{className}` has too many dependencies, consider splitting it

**How to check**: In new test methods in the diff, compare lines of mock setup (`.mock()`, `when(`, `stub(`, `jest.fn()`, etc.) vs. lines of assertions (`expect`, `assert`, `verify`). Flag if setup line count exceeds assertion line count.

---

### tests-04 · Major · Flaky Test Patterns
**Scriptable**: Yes
**Rule**: Real `sleep()`/`Thread.sleep()` calls, `new Date()`/`DateTime.Now` without injection, `Math.random()`/`Random()` without a fixed seed in test code.
**Scope**: `diff`
**Finding action template**: Replace `{pattern}` in `{testName}` with a deterministic alternative — inject time/random as a dependency

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/tests.tsv`.

NOTE for agent: Dismiss `setTimeout`/`setInterval` when the test uses `jest.useFakeTimers()` or equivalent clock-control. Dismiss `new Date()` when the test subject is date-independent (the date is incidental, not the thing being tested).

---

### tests-05 · Major · Test Accessing Private Internals
**Scriptable**: Yes
**Rule**: Tests using reflection, `@VisibleForTesting`, package-private access, or `internal` scope to reach private methods or fields — tests must verify observable behaviour only.
**Scope**: `diff`
**Finding action template**: Rewrite `{testName}` to test through the public interface — remove access to `{privateSymbol}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/tests.tsv`.

NOTE for agent: For Swift: Flag only reflection-based access to private internals (Mirror, NSInvocation). `@testable import` is the standard Swift mechanism for testing internal members and is NOT a violation.

---

### tests-06 · Major · Shared Mutable State Between Tests
**Scriptable**: Yes
**Rule**: Mutable instance fields on the test class modified by individual test methods without being reset in `setUp`/`@BeforeEach` — makes test execution order matter.
**Scope**: `diff`
**Finding action template**: Reset `{fieldName}` in `setUp`/`@BeforeEach` in `{testClass}`, or make it a local variable per test

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/tests.tsv`.

NOTE for agent: only flag mutable instance fields that are reassigned inside individual `@Test`/`it()`/`test()` methods without a corresponding reset in a `setUp`/`@BeforeEach`/`before` block. Dismiss `let sut;` or `let subject;` declared at describe-scope and reset in `beforeEach`/`setUp` — that is the correct pattern. Flag only mutable fields that are assigned inside `it()`/`test()` bodies without a corresponding reset.

---

### tests-07 · Major · Test Edge Case Coverage
**Scriptable**: No
**Rule**: For each new public function that has at least one test, at least one edge case must also be tested (null input, empty collection, boundary value, error condition).
**Finding action template**: Add edge case test for `{functionName}` — cover `{null input / empty collection / boundary value / error condition}`

**How to check**: Find new public functions in the diff that have corresponding tests. Check whether any test covers a non-happy-path scenario. Flag functions where every test only exercises the success path.

---

### tests-08 · Major · Skipped/Ignored Tests
**Scriptable**: Yes
**Rule**: Test cases marked skip/ignore in the diff are either unfinished implementations or suppressed failures — both are blockers.
**Scope**: `diff`
**Finding action template**: Remove skip marker from `{testName}` — fix the underlying issue or delete the test

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/tests.tsv`.

---

### tests-09 · Critical · Tests with No Meaningful Assertions
**Scriptable**: Yes
**Rule**: Test bodies with no assertions, only `assert(true)`, or assertions that can never fail provide zero verification.
**Scope**: `diff`
**Finding action template**: Add a meaningful assertion to `{testName}` — the test currently cannot fail

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/tests.tsv`.

NOTE for agent: also flag test methods whose entire body contains no assertion keyword at all (`expect`, `assert`, `verify`, `should`, `XCTAssert`, `Assert.`). Read the test body, not just the grep hit.

---

### tests-10 · Moderate · Test Describes Implementation Not Behaviour
**Scriptable**: No
**Rule**: Test names referencing internal mechanisms rather than observable business outcomes are a BDD violation.
**Finding action template**: Rename `{testName}` to describe the business scenario — e.g. `{given_businessContext_when_action_then_outcome}`

**How to check**: For each new test name in the diff, determine whether it references a technical mechanism (cache, repository, method name, database) vs. a business scenario (user is premium, order is shipped, payment is declined). Flag any name anchored to implementation details.

---

### tests-11 · Major · Missing Negative/Error Scenario
**Scriptable**: No
**Rule**: New public behaviour with tests covering only the success path and none covering the rejection or error path is underspecified.
**Finding action template**: Add error/rejection test for `{symbol}` — every testable business rule has a failure case

**How to check**: For each new public method, endpoint, or use case in the diff that has tests, check whether any test covers a failure case: invalid input, authentication failure, not-found, business rule rejection, or exception path. Flag if all tests are success-only.

---

### tests-12 · Major · Assertion Doesn't Match Test Name
**Scriptable**: No
**Rule**: A test whose name describes one outcome but whose assertions verify something different or weaker is misleading and untrustworthy.
**Finding action template**: Fix assertion in `{testName}` — name claims `{claimedOutcome}` but assertion only verifies `{actuallyVerified}`

**How to check**: For each new test in the diff, read the name and then read every assertion. If the assertion verifies a weaker condition (e.g. HTTP 200 instead of record created) or a different condition than the name states, flag it.

---

### tests-13 · Critical · Test Module Containing No Assertions
**Scriptable**: Yes
**Rule**: A test file with no assertion anywhere in it verifies nothing — it passes as long as the code does not crash, and reports that as coverage.
**Scope**: `files`
**Finding action template**: Add assertions to `{file}` that verify the observable outcome, or delete the module if it is a placeholder

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/tests.tsv`.

NOTE for agent: the detection is file-level — it names test modules where the assertion count is zero, and carries no line number, so anchor the finding at the first test declaration in the file. This is distinct from tests-09, which finds individual assertions that cannot fail; here there are none at all. The pattern requires the file to contain a test-declaration marker (`def test_`/`class Test...` in python, `@Test` in java/kotlin, `[Fact]`/`[Test]`/`[TestMethod]` in csharp, `func test...` in swift, a `describe(`/`it(`/`test(` call in typescript/javascript) before it counts assertions. The java/kotlin (`@Test`) and csharp (`[Fact]`/`[Test]`/`[TestMethod]`) markers are annotation/attribute matches and only match real test declarations. The other four are name-based and over-match: the python marker (`class\s+\w*Test\w*`) matches any class whose name merely *contains* "Test" anywhere — e.g. a plain `class TestDataFactory` helper with zero assertions triggers tests-13 even though it declares no test methods; the swift marker (`func test\w*`) matches any function whose name *starts with* "test", test method or not; the typescript/javascript marker matches any call to a function literally named `describe`, `it`, or `test`, whatever that function does. So a shared helper, fixture, factory, builder, constants module, or DTO in python/swift/typescript/javascript is NOT automatically safe from the pattern — if its class or function name happens to match one of these markers, it will be flagged and DOES need dismissal: confirm the named declaration is not an actual test (no test methods, no test base class) before dismissing. Dismiss a module whose verification genuinely lives in a custom helper, but only after confirming that helper asserts.

---

## Output instruction

Output one finding line per violation, exactly in this format:
```
[tests-NN] · Severity · Check Name | file:line | One-line action
```
No prose. Dismiss false positives silently.

If the action field contains a literal ` | ` (e.g. a TypeScript union type like `string | null`), escape it as ` \| ` to prevent splitting. The synthesizer unescapes ` \| ` back to ` | ` before rendering.

On the **final line** of your output, always emit:
`STATUS: GROUP=tests findings=N checks=M ok`
where N is the number of finding lines you emitted, M is the total count of `### tests-NN` check headers in this file (13 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. Exception: tests-01's project-has-tests baseline finding (when the repository contains no test suite at all) may be reported as Major instead of Critical — this is a sanctioned deviation listed in the synthesizer. On error: `STATUS: GROUP=tests failed=<brief reason>`
