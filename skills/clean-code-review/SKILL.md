---
description: Structured clean code review — 110 checks across 7 groups (clarity, smells, solid, arch, tests, safety, ddd). Flexible targets — local changes (default), staged/unstaged/untracked, a git ref/range, or explicit files (works without git). Runs scripted detections, spawns one agent per group, synthesizes findings.
---

# /clean-code-review

## Usage
`/clean-code-review [TARGET ...] [GROUP ...]`

**Targets** (default: `local` — all local changes):
- *(none)* or `local` — staged + unstaged + untracked changes
- `staged` · `unstaged` · `untracked` — only those areas; combinable (e.g. `staged untracked`)
- a git ref or range — `main..HEAD`, `HEAD~3`, `abc123..def456`. A single ref diffs against the worktree. Not combinable with the keywords above.
- one or more file paths — review the whole files; the only mode that works outside a git repository

**Groups** (case-insensitive): `clarity` · `smells` · `solid` · `arch` · `tests` · `safety` · `ddd`. Omit to run all 7.

Expected check counts: clarity=17, smells=23, solid=15, arch=12, tests=13, safety=21, ddd=9 (110 total).

## Severity
- **Critical**: blocks correctness, security, or safety
- **Major**: significant design flaw, missing requirement, or likely bug
- **Moderate**: suboptimal but workable
- **Minor**: style, naming, or nitpick

---

## Step 1 — Parse arguments

Split `$ARGUMENTS` into tokens:
- Tokens that match a group name (case-insensitive) select active groups. No group tokens → all 7 active. A group-name token is always treated as a group, never as a file or ref.
- **Every other token is passed through to `collect.sh` unchanged** — the script validates targets and rejects unknown tokens itself. Do not pre-validate refs or files yourself.

## Step 2 — Collect (scripted)

```bash
bash ~/.claude/skills/clean-code-review/scripts/collect.sh <non-group tokens...>
```

- **Non-zero exit**: report the script's stderr message to the user verbatim and stop.
- **Success**: stdout is an output directory (`$OUTDIR`) containing:

| File | Content |
|---|---|
| `mode.txt` | resolved target (`staged`/`unstaged`/`untracked` lines, `ref: X`, or `files`) |
| `files.txt` | files under review (vendor/generated already excluded) |
| `skipped.txt` | excluded files |
| `languages.txt` | detected language tokens |
| `unanalysed.txt` | code extensions with no language mapping |
| `addedlines.txt` | `file:line` index of added/changed lines |
| `diff.patch` | the raw unified diff (untracked/file targets appear as whole-file additions) |
| `numbered.patch` | the same diff with each added/context line prefixed `N\|` (its true file line number) — this is what agents receive |
| `hits.txt` | detection hits, already filtered to added lines and capped |
| `warnings.txt` | `WARN-CAP:` / `WARN-DETECT:` / `NOTICE-LARGE-DIFF:` lines |

The script needs no GNU grep or other extras — detection patterns run via perl (preinstalled on macOS/Linux). Paths with spaces are handled.

## Step 3 — Language gate

If `languages.txt` is empty, abort the review: `No supported language files detected. Supported: TypeScript, JavaScript, C#, Python, Swift, Kotlin, Java. Unanalysed: {contents of unanalysed.txt}.` Do not spawn agents.

## Step 4 — Spawn review agents

Spawn **one agent per active group in parallel** (Agent tool). Group prompt files:

| Group | File | Checks |
|---|---|---|
| clarity | `~/.claude/skills/clean-code-review/groups/clarity.md` | 17 |
| smells | `~/.claude/skills/clean-code-review/groups/smells.md` | 23 |
| solid | `~/.claude/skills/clean-code-review/groups/solid.md` | 15 |
| arch | `~/.claude/skills/clean-code-review/groups/arch.md` | 12 |
| tests | `~/.claude/skills/clean-code-review/groups/tests.md` | 13 |
| safety | `~/.claude/skills/clean-code-review/groups/safety.md` | 21 |
| ddd | `~/.claude/skills/clean-code-review/groups/ddd.md` | 9 |

Before spawning, get the diff size: `DIFF_LINES=$(wc -l < "$OUTDIR/numbered.patch")`.

Pass each agent:
- The path to `numbered.patch` as `$DIFF` and its exact length: "The diff file is {DIFF_LINES} lines. You MUST read all {DIFF_LINES} lines — keep issuing Read calls with increasing `offset` until you have seen the final line. Reviewing a partially-read diff is a failure." Each added/context line is prefixed `N|` with its true file line number.
- Its group MD file path (agent reads it)
- `$PRECOMPUTED`: its group's lines from `hits.txt` (those starting `{group}-`). Line formats, tab-separated after the check id:
  - `id<TAB>file:line:text` → `{ check_id, file, line, matched_text }` — split on the **first two** colons only (paths and text may contain colons)
  - `clarity-16` / `tests-13` `<TAB>file:count` → `{ check_id, file, count }`
  - `clarity-17` / `smells-01` `<TAB>count file` → `{ check_id, file, line_count }`
- `$LANGUAGES`: contents of `languages.txt`
- Its expected check count (table above)
- The `skipped.txt` list with instruction: "Files in this list are excluded — report NO findings for them."
- This instruction:

> **Read-only**: do not edit any file. Report findings only.
> Scriptable detections were pre-executed — work from `$PRECOMPUTED` and the diff; do not re-run detections. Where a check explicitly requires reading repository files, you may do so.
> Read your group MD file. For each precomputed hit: confirm it is a real violation (keep) or a false positive (dismiss silently).
> **Systematic sweep — this is the required work protocol**: process your group's checks one at a time, in ID order. For each check, scan the ENTIRE diff for violations of that check before moving to the next check. Report EVERY violation you find, not a representative sample — two findings of the same check in different files are two finding lines. Do not skip a check because early checks already produced findings. Output findings only — one line per finding, no prose.
> **Anchoring**: added/context lines in `$DIFF` are prefixed `N|` with their true file line number. Anchor every finding at the line your action text refers to, taking the number from that prefix — never compute line numbers from `@@` hunk offsets yourself. If your action names a specific call, symbol, or statement, the anchor MUST be the `N|` of the exact line containing it — not the line before it, not the enclosing block's first line. Strip the `N|` prefix when quoting code.
> End with a status line: `STATUS: GROUP={group} findings=N checks=M ok` (N = finding lines emitted, M = number of `### {group}-NN` headers in your MD file) or `STATUS: GROUP={group} failed=<reason>`.

**Finding format:**
```
[{group}-NN] · Severity · Check Name | file:line | One-line action
```
A literal ` | ` inside the action field must be escaped as ` \| `. Example:
```
[clarity-08] · Moderate · Magic Numbers/Strings | src/payment/calculator.ts:42 | Extract 365 into named constant DAYS_IN_YEAR
```

## Step 5 — Synthesize

After all group agents complete, spawn a synthesizer agent following `~/.claude/skills/clean-code-review/synthesizer.md`. Pass it:
- All finding lines and STATUS lines
- Active groups, `languages.txt`, `skipped.txt`, `unanalysed.txt`, `mode.txt`
- Expected check counts (table above)
- All lines from `warnings.txt`

## Step 6 — Output

Present the synthesizer output directly, **exactly once** — do not repeat, re-summarize, or echo any section of it, and add no commentary before or after it (no dedup narration, no framing text). Then delete `$OUTDIR` (`rm -rf` of the temp dir is fine — it is a mktemp directory this skill created).

---

## Edge cases

- **Ref-target line drift**: detection patterns scan worktree file contents, while `addedlines.txt` comes from the requested diff. If the worktree has drifted far from the ref being reviewed, some scripted hits may be filtered out; judgment checks still see the true diff.
- **Partially visible hierarchies** (solid/ddd checks): agents must state the limitation rather than guess — their MD files define the severity-downgrade rules.
- **Testing this skill**: run all three suites after any change to `scripts/`:
  - `tests/test_collect.sh` — target resolution, filtering, caps, numbered diff
  - `tests/test_checks.sh` — every detection command executes cleanly
  - `tests/test_corpus.sh` — pattern semantics: per check+language, `tests/corpus.tsv` defines code that MUST match and near-misses that must NOT. When adding or changing a detection pattern, add its MATCH/NOMATCH rows to `corpus.tsv`.
- **Recall benchmark** (manual eval, not CI): `benchmark/` contains deliberately flawed Python, TypeScript, C#, and Swift files with 96 catalogued violations (`benchmark/planted.tsv`) plus precision traps. The catalogue covers the original 85 checks; the 25 added later (safety-08 through safety-21, smells-20 through smells-23, arch-11, tests-13, ddd-06 through ddd-09, arch-12) have no planted violations yet, so a benchmark run cannot measure their recall. Their patterns are covered by `tests/corpus.tsv` instead. Run the skill on those files and score against the catalog after changing agent prompts or models — see `benchmark/README.md`. Never "fix" the benchmark files.
