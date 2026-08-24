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

**Open:** `solid-12` (250 hits, 0 TP) — flags every `logger.` call, needs layer inference. Directory-based inference was rejected (1 of 5 projects has `Domain/`/`Application/`); naming convention generalises and is what the shipped exclusions use.
