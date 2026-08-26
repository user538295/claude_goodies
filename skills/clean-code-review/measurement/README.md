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

## Baseline (2026-08-24, sonnet agents)

2,602 hits, 2,602 adjudicated, 830 LLM-only findings. Overall precision **41%** (archon-search 47%, dddd 41%, financialwell 41%, moonset 22%, udemy 18%). Script coverage of LLM findings: 46%. 19 of 60 scriptable checks produced zero hits on this corpus. See `2026-08-24-report.xlsx`. Data archived under `results/2026-08-24/`.

## Full rerun (2026-08-26, sonnet agents)

The whole measurement re-run from scratch on the frozen 46-file corpus with the **live round-8 scripts** (the workbook had gone stale — rounds 3-8 changed patterns without regenerating it). `results/*.tsv` and `report.xlsx` regenerated; deliverable `2026-08-26-report.xlsx`.

**Headline:** 1,811 hits, all 1,811 adjudicated, 979 LLM-only findings. Overall precision **74.9%** (archon-search 75%, moonset 79%, financialwell 77%, dddd 75%, udemy 15%). Script coverage of LLM findings (recall proxy, ±3 lines): **60%** (588/979). 43 of 60 scriptable checks fired; 17 produced zero hits on this corpus.

This confirms the cumulative effect of rounds 1-8: hits fell **2,602 → 1,811** and corpus-wide precision rose **41% → 75%** on a clean, full re-adjudication (not a verdict-join).

**Method deltas from the baseline** (recorded in the Method sheet):
- All hits adjudicated on every file (the baseline capped files 1-12 at 15 hits/check).
- Adjudication + LLM-only agents chunked by project (≤150 hits/agent) instead of one agent per file; each file is still read and judged independently. Run serially.
- LLM-only is a fresh single pass (979 findings vs the baseline's 830), so coverage is measured against this run's findings.

Model, file set, and ±3-line matching are unchanged, so precision is comparable to the baseline.

## Full rerun (2026-08-26, 15:58, sonnet agents)

Complete re-run from scratch on the frozen 46-file corpus with the live scripts, and a new `quality rate` column (S) added to every check sheet. Script sweep upfront (46 files, 0 cap warnings); adjudication in 18 packets (≤150 hits) and the LLM-only pass in 19 file batches, all `model: sonnet`. `results/*.tsv` and `report.xlsx` regenerated; deliverable `2026-08-26-15-58-report.xlsx`. Prior 11:47 data archived under `results/2026-08-26-1147/`.

**Headline:** 1,855 hits, all 1,855 adjudicated, 661 LLM-only findings. Overall precision **71.8%** (moonset 85%, financialwell 78%, archon-search 70%, dddd 60%, udemy 15%). Script coverage of LLM findings (recall proxy, ±3 lines): **66%** (437/661). Overall quality rate (TP / LLM-only) **2.02** — the script confirmed ~2× the real violations the unaided LLM pass surfaced. 43 of 60 scriptable checks fired.

Model, file set, and ±3-line matching unchanged from the baseline, so precision stays comparable. The LLM-only pass is a fresh single run (661 findings vs the 08-26 11:47 run's 979); run-to-run variance in that pass is not measured, so coverage and quality rate move with it.

## Improvements (2026-08-24)

Precision **41% → 46.5%**; false positives 1,538 → 1,222.

- **`smells-08`** narrowed to returns + typed params — 555 → 327 hits, 32% → **54%**, 3 TPs lost.
- **`SKIP_TESTS`** in `collect.sh` — `ddd-01/solid-06/08/09` skip test files (their NOTEs already say to) — 91 hits, **0 TPs lost**.

Verified: re-ran all 46 files; only those five checks moved, zero novel hits.

