# Script-effectiveness measurement on real projects

Goal: measure the precision of the 60 scriptable checks (`scripts/checks/*.tsv`)
on real code, plus a recall reference from an LLM-only pass, reported per check
in an xlsx. Ground truth does not exist on real projects, so:

- **Precision** = LLM-adjudicated true positives / script hits.
- **Recall reference** (not true recall) = scriptable-check findings an LLM-only
  pass reports that the script did not flag ("script misses").

## Fixed inputs

- File set: `files.tsv` (frozen, 46 files, 5 projects, 4 languages — py, swift,
  ts/tsx, cs). Never re-randomize.
- `HIT_CAP=200` stays as shipped. Per-project file mode on ≤10 files should not
  trigger it; if `WARN-CAP` appears in warnings, split that project's collect
  into two batches and merge `hits.txt`.
- All LLM agents run `model: sonnet`.
- Checks in scope: the 60 check ids present in `scripts/checks/*.tsv` only.
  Judgment-only checks are out of scope.

## Phase 1 — Script sweep (0 tokens)

Ran upfront for ALL 46 files (one `collect.sh` invocation per file, so the
per-check HIT_CAP never binds). All hits ingested into `results/hits.tsv`
before the LLM phases — the xlsx shows the complete script picture
immediately. No cap warnings occurred.

## Phase 2 — Precision adjudication (sonnet agents, serial per file)

- Sample: files 1–12 were judged on the first **15 hits per check per file**
  (hits.txt order, deterministic); from file 13 on, **all hits** are judged
  (cap lifted at user request — the remaining files are small).
- Agents: one adjudicator per file, covering all groups. It gets the file's
  sampled hits + the relevant check-definition sections, reads the
  surrounding code itself, and returns per hit: `TP | FP` + one-line reason.
- Adjudicators never see whether other hits were confirmed (independence).

## Phase 3 — LLM-only pass (sonnet agents, serial per file, 1 repeat)

- Purpose: what would sonnet find on the same files for the same 60 checks
  with **no** script hints.
- One agent per file evaluates **all 60 scriptable checks** (catalog of
  id/severity/title provided; hits withheld). Max 15 reported rows per check.
  1 repeat only (token budget) — run-to-run variance is not measured.
- Note the design difference vs the skill (7 specialist group agents): this is
  a recall *reference*, not a faithful skill run — recorded in the Method sheet.
- Matching: LLM finding matches a script hit if same check id + file and within
  ±3 lines (tolerance from `benchmark/README.md`). File-level script hits
  (file length, file-wide counts — anchored at line 1) match any LLM finding
  for that check in that file, line ignored. Unmatched = script misses.

## Phase 4 — xlsx (python + openpyxl, rebuilt after every file)

`measurement/report.xlsx`. Raw rows live in `data_hits` / `data_adj` /
`data_llm` sheets; every aggregate is an Excel formula (COUNTIFS/SUM/IF) over
them.

1. **Summary** — one row per check (60): severity, title, hits per project
   (5 cols), hits total, adjudicated, TP, FP, precision %, LLM-only found,
   overlap w/ script, script misses, script coverage % (overlap/LLM found),
   est. true hits (hits total × precision). Conditional formatting: 3-color
   scale on precision, grey (formula rule) for zero-hit checks.
2. **Per-project sheets (5)** — same columns scoped to the project.
3. **Files** — the frozen list with per-file hit count (formula) + processed flag.
4. **Method** — model, sampling rules, matching, HIT_CAP note — so future runs
   are comparable.

## Execution mode (as run)

Phase 1 upfront for all files; then serially per file: adjudicate → LLM-only →
append TSVs → rebuild xlsx. One agent at a time, `model: sonnet`.

## Known limitations (report them, don't hide them)

- No true recall: a check whose pattern never fires AND that sonnet also misses
  is invisible here. The planted benchmark covers that side.
- Top-heavy sampling biases toward size-correlated checks; the p25/p50/p75
  picks only soften this.
- financialwell locale smoke tests are near-duplicates; only the French one is
  in the set to avoid triple-counting identical hits.
