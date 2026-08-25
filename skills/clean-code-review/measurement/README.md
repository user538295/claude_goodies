# Real-project script-effectiveness measurement

This folder measures how effective the **scripted layer** of `/clean-code-review` (the 60 regex-detectable checks in `../scripts/checks/*.tsv`) is on real code, independent of the planted benchmark in `../benchmark/`. It answers two questions per check: **precision** (of the hits the script produced, how many are real violations?) and a **recall proxy** (of what an unaided LLM finds for the same checks on the same files, how much did the script also catch?).

There is no ground truth on real projects, so "true/false positive" verdicts come from LLM adjudication: a sonnet agent reads each script hit in its code context and judges it against the check's definition in `../groups/*.md`. The LLM-only findings are themselves unverified claims — treat "script misses" as leads, not proven violations.

## Contents

- `report.xlsx` — **the deliverable.** Raw rows live in the `data_hits` / `data_adj` / `data_llm` sheets; every aggregate on the Summary and per-project sheets is an Excel formula (COUNTIFS/SUM/IF) over them, so the workbook is auditable and recomputes if you edit the data sheets.
- `files.tsv` — the frozen 46-file corpus (5 projects, 4 languages). Selection rule is documented in its header. **Never re-randomize**; results are only comparable on the same file set.
- `PLAN.md` — the measurement design and the execution mode actually used.
- `build_xlsx.py` — regenerates `report.xlsx` from `results/*.tsv`. Idempotent; run after any data change: `python3 build_xlsx.py`.
- `ingest_hits.py` — parses one `collect.sh` `hits.txt` into `results/hits.tsv` and prints the adjudication sample.
- `results/` — the accumulated raw data: `hits.tsv` (script hits), `adjudications.tsv` (TP/FP verdicts with reasons), `llmonly.tsv` (LLM-only findings), `progress.tsv` (processed files), `catalog.txt` (the 60 scriptable checks as id · severity · title), `scriptable_ids.txt`.

## How to read report.xlsx

Open the **Summary** sheet. One row per scriptable check:

- `hits:<project>` / `hits total` — raw script findings (complete for all 46 files).
- `adjudicated`, `TP`, `FP`, `precision %` — the verdict layer. Precision = TP / adjudicated. In the 2026-08-24 run every hit was adjudicated (adjudicated = hits total), so precision is exact, not sampled.
- `LLM-only found` — what a sonnet reviewer found for that check with no script hints (capped at 15 per check per file, so it under-counts repetitive violations by design).
- `overlap w/ script` — LLM findings within ±3 lines of a script hit (file-level checks like file length match by file, line ignored).
- `script misses` — LLM findings the script did not flag (= found − overlap). Unverified.
- `script coverage %` — overlap / LLM-only found: the recall proxy.
- `est. true hits` — hits total × precision: the script's haul corrected for false positives; the fair number to compare against `LLM-only found`.

Grey rows = the check's pattern ran on every file but matched nothing in this corpus (not evidence the check is broken — this corpus just doesn't exercise it). The **Method** sheet records model, sampling rules, and matching tolerance; a future run is only comparable if those match. The **Files** sheet shows per-file hit counts and which files were processed.

Interpretation guide: a check with high precision AND high coverage is a good scripted check. Zero-precision checks with many hits (in the 2026-08-24 run: solid-12, safety-06, ddd-01, tests-06) are noise generators — fix the pattern or demote the check to judgment-only. Low coverage on a high-precision check usually means a granularity mismatch (script counts per file, LLM counts per function), not a bad check.

## How to re-run

Prerequisites: `python3` with `openpyxl`; the five projects checked out at the paths in `files.tsv`.

1. **Script sweep (free, no LLM):** for each file in `files.tsv`, run `bash ../scripts/collect.sh <file>` and feed its output dir to `python3 ingest_hits.py <project> <outdir>/hits.txt >> sample.tsv`. Start with empty `results/hits.tsv` / `adjudications.tsv` / `llmonly.tsv` / `progress.tsv` — move the old ones aside first (they are the previous run's data).
2. **Adjudication (sonnet agent per file):** give the agent the file's hits (check_id, line, excerpt), the relevant `### <check-id>` sections extracted from `../groups/*.md`, and the source path. It returns one `TP|FP + reason` per hit; append to `results/adjudications.tsv` as `project, file, check, line, verdict, reason`.
3. **LLM-only pass (sonnet agent per file):** give the agent `results/catalog.txt` and the source path, hits withheld, max 15 rows per check. Append to `results/llmonly.tsv` as `project, file, check, line, note`.
4. **After every file:** append the file path + `done` to `results/progress.tsv` and run `python3 build_xlsx.py`.

Record the model and any rule changes in the Method sheet (edit the rows in `build_xlsx.py`) — scores across runs are only comparable with the same model, file set, and rules. Do not "fix" anything in the five target projects to improve scores.

## Baseline (2026-08-24, sonnet agents)

2,602 hits, 2,602 adjudicated, 830 LLM-only findings. Overall precision **41%** (archon-search 47%, dddd 41%, financialwell 41%, moonset 22%, udemy 18%). Script coverage of LLM findings: 46%. 19 of 60 scriptable checks produced zero hits on this corpus. See `2026-08-24-report.xlsx`.

## Improvements (2026-08-24)

Precision **41% → 46.5%**; false positives 1,538 → 1,222.

- **`smells-08`** narrowed to returns + typed params — 555 → 327 hits, 32% → **54%**, 3 TPs lost.
- **`SKIP_TESTS`** in `collect.sh` — `ddd-01/solid-06/08/09` skip test files (their NOTEs already say to) — 91 hits, **0 TPs lost**.

Verified: re-ran all 46 files; only those five checks moved, zero novel hits.

## Round 2 (2026-08-24, four parallel agents)

Sweep **2,283 → 2,195**: 393 lost (392 adjudicated `FP`; the one `TP` is a mis-adjudication — that file does have a test), 305 gained. **Real TP loss: zero.** Precision on surviving adjudicated hits **46% → 56%**. The 305 gains are agent-sampled (48–100% per check), not independently adjudicated — re-adjudicate before quoting a post-change figure.

Recall (primary goal): `arch-08` 0 → 39 (39/39 real; the Swift locator is `X.shared`, not `Container.resolve(`), `solid-10` 5 → 51 (Swift/Python have no `new` — match collaborator suffixes), `smells-10` 29 → 60 (Rule says 3 *hops*; pattern demanded 3 calls or 4 properties), `solid-15` 12 → 35, `clarity-09` 23 → 37, `smells-21` 11 → 25, `safety-13` 9 → 18, `arch-05` 0 → 4.

Precision, zero TP cost: `safety-06` 121 → 2 (`Task.sleep` excluded, added to `SKIP_TESTS`), `solid-08` 91 → 36 (whole-file reassignment scan replaces the line-local regex), `tests-06` 45 → 12, `ddd-01` 45 → 19, `tests-01` 38 → 21, `arch-02` 18 → 2, `solid-06` 113 → 103. New `notested()` in `lib.sh` gives `tests-01` the repo lookup its NOTE asked for by hand; outside git it drops nothing.

Rejected: **`smells-01`** is not defective (100% precision at 1,000 lines; a stricter bar is policy, not a fix). **`clarity-16/17`** have no recall gap — file-level recall is ~100%; the apparent gap compared per-function findings to per-file pre-filter hits. Per-function segmentation needs an `mfunc` helper, not shipped. **`smells-02`** is unreachable — 96 of the 4+-param signatures are multi-line and `mgrep` has no multiline state. **`tests-06` hook gate** (45 → 1): a file that resets one field and leaks another is exactly this bug; indentation fix kept, gate dropped.

**Correction to round 1:** the layer-gated set is **337** hits, not 326, and excludes `arch-03`/`arch-05` (zero hits): `solid-12` 250, `ddd-01` 56, `arch-02` 18, `arch-12` 7, `ddd-07` 3, `arch-09` 2, `safety-08` 1.

**Open (closed in round 3):** `solid-12` (250 hits, 0 TP) — flags every `logger.` call, needs layer inference. Directory-based inference was rejected (1 of 5 projects has `Domain/`/`Application/`); naming convention generalises and is what the shipped exclusions use.

## Round 3 (2026-08-25)

Three checks, each fixed and swept separately on the frozen 46-file corpus.

| check | fix | hits | TP | FP | new hits |
|---|---|---|---|---|---|
| `smells-02` | count params across wrapped signatures (`mparams()`) | 13 → **72** | 12 → 12 | 1 → **0** | +60 |
| `solid-12` | only scan domain-named files; match `*Log` façades | 250 → **22** | 0 → 0 | 250 → **5** | +17 |
| `smells-12` | read the `catch`/`except` body (`mbody()`) | 105 → **92** | 77 → 77 | 28 → **2** | +13 |

### Corpus totals

| | before | after |
|---|---|---|
| hits | 2,195 | 2,013 |
| true positives | 1,038 | **1,038** |
| false positives | 809 | **537** |
| precision | 56% | **66%** |
| LLM findings caught by the right check | 515/830 (62%) | **552/830 (67%)** |

`TP`/`FP` count only hits carrying a 2026-08-24 verdict. `new hits` did not exist before this round, so no verdict exists for them — they were verified separately.

### How the new hits were verified

- **60** `smells-02`: parameter counts checked against Python's `ast` — 64/64 correct.
- **17** `solid-12`: `AppLog.*` calls inside `Models/` domain classes; 10 match LLM findings.
- **13** `smells-12`: Swift `try?`/log-only catches; 12 match LLM findings, 1 read in source.

**Zero true positives lost.** Every dropped hit already carried an `FP` verdict.

### What each fix does

- **`smells-02`** — `mparams()` joins a wrapped signature to its continuation lines, then splits on top-level commas, so nesting, quoted defaults and the `*`/`/` markers no longer distort the count. python/csharp/java/kotlin/swift; ts/js keep the single-line count and its declaration-vs-call guard. Retires round 2's "unreachable" verdict.
- **`solid-12`** — the rows gate the file list to a `domain/`, `entities/`, `models/`, `aggregates/` or `value-objects/` segment, or a `*Entity`/`*Aggregate`/`*ValueObject`/`*Model` filename (`*ViewModel` excluded): the layer test the NOTE already asked the agent for. The swift row also matches any `*Log`/`*Logger` façade but skips `*.assert*`, which safety-13 owns. Cost: a domain class in an unconventionally named file is no longer pre-flagged, so `benchmark/planted.tsv`'s two `solid-12` rows are now `judgment`. The 5 surviving `FP` are raw `print(` calls in a domain model.
- **`smells-12`** — `mbody()` reads the block a `catch`/`except` opens. Python drops an `except` that re-raises: wrapping in a domain error is handling, not swallowing. Swift gains the log-only catch and the discarded statement-position `try?`.

### Correction to the baseline

`clarity-16`'s 25% precision and 2% coverage in `report.xlsx` are a harness artifact, not a defect: the check emits `file:count`, but `ingest_hits.py` read `file:N` as `file:line`, so the branch count was adjudicated as a line number. Matched at file level it covers **44 of 44** of its LLM findings. `ingest_hits.py` now records the count form as file-level.

### Not pursued

- `smells-21` — 29 of its 33 apparent misses already reach the agent through safety-07 and safety-02, the owners its own NOTE names.
- `solid-07` — its true positives are the same `*_id: str` shape as its false positives. Judgment, not regex.
- `solid-09` — round 2's pattern already catches those misses.

## Round 4 (2026-08-25, three parallel agents)

Three checks fixed separately. **New: each was also swept over the five projects in full — 1,581 files.** The corpus gives precision (it has verdicts); the whole-project sweep gives the volume a real review sees.

### Corpus (46 files, 2026-08-24 verdicts)

| check | fix | hits | TP | FP | new |
|---|---|---|---|---|---|
| `clarity-17` | per-function span (`mfunc()`) replaces file line count | 32 → **23** | 11 → 11 | 21 → **1** | +23 |
| `tests-05` | drop import paths and self-declared helpers; add `patch.object`/`setattr` | 347 → **291** | 257 → 257 | 90 → **15** | +19 |
| `smells-08` | `msig()` signature membership; `let`/`var`/`val` excluded | 327 → **214** | 177 → 177 | 150 → **37** | 0 |

Totals: hits 2,013 → **1,835**, FP 558 → **349**, precision 66% → **75%**, LLM findings matched within ±3 lines 444 → **465** of 830.
`clarity-17` moved file-level → line-level, so all 32 old hits formally "drop" — that is the whole 1,060 → 1,049 TP difference. **Zero TPs lost:** all 11 `TP` files still hit on the named function, and all 188 dropped verdict-carrying hits are `FP`.

### Whole projects (1,581 files)

| check | archon-search | dddd | financialwell | moonset | total |
|---|---|---|---|---|---|
| `clarity-17` | 539 → 56 | 53 → 25 | 109 → 4 | 40 → 1 | 742 → **86** |
| `tests-05` | 4,099 → 3,821 | — | — | — | 4,099 → **3,821** |
| `smells-08` | 1,572 → 1,158 | 95 → 44 | 480 → 197 | 44 → 12 | 2,191 → **1,411** |

`tests-05` moves least in net, most in substance: 666 dropped (335 `from pkg._x import …`, rest `self._helper(…)`) against **388 new** — 345 `patch.object`, 43 `getattr`/`setattr`. All archon-search: no other project has python tests.
Harness: rows run straight through `lib.sh`, not per-file `collect.sh` (75 min/sweep). Faithful here — none is in `SKIP_TESTS`, and `files` mode makes line filtering a no-op. Validated: pre-fix rows over the 46 files reproduce 32 / 347 / 327.

**Verification.** `ast.parse` over all 838 python files finds exactly 56 functions >150 lines; `clarity-17` finds **56 — zero missed, zero false**. Its 30 non-python hits all measured >150 in source.
All 19 new `tests-05` corpus hits are `patch.object(syncer, "_private_method")`, read in source. `smells-08` gained nothing — purely subtractive.

**Judgment calls.** `smells-08` swift dropped `-> Type?` — 178 whole-project drops, adjudicated 18 FP / 1 TP, and that TP still hits via its `= nil` default. Swift now anchors on `return nil`, deliberately inconsistent with kotlin/python.
`clarity-17` counts `describe(…)` as a function (24 of 30 non-python hits). Dropping them drops a round-1 `TP` whose sibling file carries an `FP` for the identical construct. **Open question of the round.**

**Tests.** Green: `test_checks` 358 commands, `test_collect` 109/0, `test_corpus` **1,051/0**. `clarity-17`'s one threshold assertion became seven per-language, with new fixtures `thr/longfn.<ext>` (must flag) and `thr/manyfns.<ext>` (must not).

**Corrections / not pursued.** Round 2's "`clarity-16/17` have no recall gap, `mfunc` not shipped" is retired for `clarity-17`; `clarity-16` is genuinely file-level.
Kotlin/Java have no real-code coverage (zero `.kt`/`.java`, six `.cs` files). C# verbatim identifiers escape `mfunc`. `results/*.tsv` and `report.xlsx` are not regenerated, as in round 3.
