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
- `quality rate` (col S) — `TP / LLM-only found`: the script's confirmed haul relative to the unaided-LLM haul, per check. Higher is better — above 1 (100%) means the script confirmed more real violations than the LLM-only pass surfaced; below 1 means the LLM-only pass found proportionally more. `IFERROR(…,0)` so a check with zero LLM-only findings reads 0 (a wart: such a check is actually a script win, not a loss — read those alongside the TP and LLM-only columns).

Grey rows = the check's pattern ran on every file but matched nothing in this corpus (not evidence the check is broken — this corpus just doesn't exercise it). The **Method** sheet records model, sampling rules, and matching tolerance; a future run is only comparable if those match. The **Files** sheet shows per-file hit counts and which files were processed.

Interpretation guide: a check with high precision AND high coverage is a good scripted check. Zero-precision checks with many hits (in the 2026-08-24 run: solid-12, safety-06, ddd-01, tests-06) are noise generators — fix the pattern or demote the check to judgment-only. Low coverage on a high-precision check usually means a granularity mismatch (script counts per file, LLM counts per function), not a bad check.

## How to re-run

Prerequisites: `python3` with `openpyxl`; the five projects checked out at the paths in `files.tsv`.

1. **Script sweep (free, no LLM):** for each file in `files.tsv`, run `bash ../scripts/collect.sh <file>` and feed its output dir to `python3 ingest_hits.py <project> <outdir>/hits.txt >> sample.tsv`. Start with empty `results/hits.tsv` / `adjudications.tsv` / `llmonly.tsv` / `progress.tsv` — move the old ones aside first (they are the previous run's data).
2. **Adjudication (sonnet agent per file):** give the agent the file's hits (check_id, line, excerpt), the relevant `### <check-id>` sections extracted from `../groups/*.md`, and the source path. It returns one `TP|FP + reason` per hit; append to `results/adjudications.tsv` as `project, file, check, line, verdict, reason`.
3. **LLM-only pass (sonnet agent per file):** give the agent `results/catalog.txt` and the source path, hits withheld, max 15 rows per check. Append to `results/llmonly.tsv` as `project, file, check, line, note`.
4. **After every file:** append the file path + `done` to `results/progress.tsv` and run `python3 build_xlsx.py`.

Record the model and any rule changes in the Method sheet (edit the rows in `build_xlsx.py`) — scores across runs are only comparable with the same model, file set, and rules. Do not "fix" anything in the five target projects to improve scores.

## C++ corpus registered (2026-08-28, not yet scored)

An `extrafood-cpp` project was appended to `files.tsv` (8 production files from
`/Users/manczg/Documents/development/extrafood/cpp`, selected by the documented
top-5 + p25/p50/p75 rule; that project has no unit-test files, so the test stratum
is empty). These rows are **registered but not yet adjudicated** — no C++ numbers
appear in `report.xlsx` yet. To score them, run the "How to re-run" steps above over
the new rows (or the whole corpus) and regenerate the workbook. Until then, C++
precision/recall is measured only by `../benchmark/` (planted violations) and the
deterministic `../tests/` suites.

## Baseline (2026-08-24, sonnet agents)

2,602 hits, 2,602 adjudicated, 830 LLM-only findings. Overall precision **41%**. Script coverage of LLM findings: 46%. 19 of 60 scriptable checks produced zero hits on this corpus. 

## Full rerun (2026-08-26, sonnet agents)

The whole measurement re-run from scratch on the frozen 46-file corpus with the **live round-8 scripts** (the workbook had gone stale — rounds 3-8 changed patterns without regenerating it). `results/*.tsv` and `report.xlsx` regenerated.

**Headline:** 1,811 hits, all 1,811 adjudicated, 979 LLM-only findings. Overall precision **74.9%**. Script coverage of LLM findings (recall proxy, ±3 lines): **60%** (588/979). 43 of 60 scriptable checks fired; 17 produced zero hits on this corpus.

This confirms the cumulative effect of rounds 1-8: hits fell **2,602 → 1,811** and corpus-wide precision rose **41% → 75%** on a clean, full re-adjudication (not a verdict-join).

**Method deltas from the baseline** (recorded in the Method sheet):
- All hits adjudicated on every file (the baseline capped files 1-12 at 15 hits/check).
- Adjudication + LLM-only agents chunked by project (≤150 hits/agent) instead of one agent per file; each file is still read and judged independently. Run serially.
- LLM-only is a fresh single pass (979 findings vs the baseline's 830), so coverage is measured against this run's findings.

Model, file set, and ±3-line matching are unchanged, so precision is comparable to the baseline.

## Full rerun (2026-08-26, 15:58, sonnet agents)

Complete re-run from scratch on the frozen 46-file corpus with the live scripts, and a new `quality rate` column (S) added to every check sheet. Script sweep upfront (46 files, 0 cap warnings); adjudication in 18 packets (≤150 hits) and the LLM-only pass in 19 file batches, all `model: sonnet`. `results/*.tsv` and `report.xlsx` regenerated. 

**Headline:** 1,855 hits, all 1,855 adjudicated, 661 LLM-only findings. Overall precision **71.8%**. Script coverage of LLM findings (recall proxy, ±3 lines): **66%** (437/661). Overall quality rate (TP / LLM-only) **2.02** — the script confirmed ~2× the real violations the unaided LLM pass surfaced. 43 of 60 scriptable checks fired.

Model, file set, and ±3-line matching unchanged from the baseline, so precision stays comparable. The LLM-only pass is a fresh single run (661 findings vs the 08-26 11:47 run's 979); run-to-run variance in that pass is not measured, so coverage and quality rate move with it.

## Full rerun (2026-08-27, sonnet agents)

Complete re-run from scratch on the frozen 46-file corpus with the **live round-8 scripts** (which now include the checks added since 08-26: arch-13/14, safety-22/23/24, and the safety-25 split). Script sweep upfront (46 files, 0 cap warnings); then a workflow orchestrated the LLM phases — adjudication in 15 packets (≤150 hits, split on file boundaries; the three largest single files exceed the cap and are judged whole) and the LLM-only pass as **one agent per file (46 agents)**. All `model: sonnet`. The run crossed a 3pm session-limit reset (34 agents completed, then the remaining 27 re-ran after reset); no data was affected — every hit is adjudicated exactly once. `results/*.tsv` and `report.xlsx` regenerated.

**Headline:** 1,856 hits, all 1,856 adjudicated, 891 LLM-only findings. Overall precision **68.1%** (1,264 TP / 592 FP). Script coverage of LLM findings (recall proxy, ±3 lines): **85%** (760/891). Overall quality rate (TP / LLM-only) **1.42**. 44 of 60 scriptable checks fired (16 zero-hit on this corpus).

The two remaining zero-precision noise generators (≥10 hits, 0 TP): **safety-15** (18 hits) and **tests-06** (12 hits) — fix the pattern or demote to judgment-only. Highest-precision scripted checks this run: smells-02 (100%, 72/72), arch-08 (100%, 39/39), clarity-16 (96%, 54/56), tests-05 (95%, 276/291).

**Method deltas vs the 08-26 15:58 run:** LLM-only ran one agent per file (46) rather than 19 file batches — more independent (no cross-file contamination) and it surfaced more findings (891 vs 661), which raises coverage and lowers quality rate relative to that run. Precision moved 71.8% → 68.1%, partly from the five newly-added checks entering the corpus for the first time. Model, file set, and ±3-line matching are unchanged, so precision stays comparable across runs.

## Full rerun (2026-08-27, run #2, sonnet agents)

Complete re-run from scratch on the frozen 46-file corpus with the live scripts. Script sweep upfront (46 files, 0 cap warnings); then a workflow spawned **one sonnet agent per file for both phases** — 45 adjudicators (files with hits) + 46 LLM-only reviewers, capped at **5 concurrent**, each agent writing its TSV directly. The run crossed a 9:20pm session-limit reset and resumed from cache; every hit is adjudicated exactly once. `results/*.tsv` and `report.xlsx` regenerated.

**Headline:** 1,718 hits, all 1,718 adjudicated, 695 LLM-only findings. Overall precision **74.6%** (1,281 TP / 437 FP). Script coverage of LLM findings (recall proxy, ±3 lines): **70%** (484/695). Overall quality rate (TP / LLM-only) **1.84**. 43 of 60 scriptable checks fired (17 zero-hit on this corpus).

The two remaining zero-precision noise generators (≥10 hits, 0 TP): **safety-15** (18 hits) and **tests-06** (12 hits) — fix the pattern or demote to judgment-only. Highest-precision scripted checks this run (≥20 adjudicated): smells-02 (100%, 72/72), arch-08 (100%, 39/39), safety-07 (97%, 146/151), clarity-16 (96%, 54/56), tests-05 (93%, 272/291), clarity-17 (91%, 21/23).

**Method deltas vs the 08-27 run #1:** hits fell 1,856 → 1,718 (scripts tightened since that run). Precision rose **68.1% → 74.6%**; the LLM-only pass surfaced fewer findings (695 vs 891) — plausibly ordinary run-to-run variance in that single unmeasured pass — which lowers coverage (85% → 70%) and raises quality rate (1.42 → 1.84). Both phases ran one agent per file here (run #1 packet-chunked adjudication). Model, file set, and ±3-line matching are unchanged, so precision stays comparable.
