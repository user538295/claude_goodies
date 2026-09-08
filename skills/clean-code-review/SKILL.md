---
description: Structured clean code review — 128 checks across 7 groups (clarity, smells, solid, arch, tests, safety, ddd). Flexible targets — local changes (default), staged/unstaged/untracked, a git ref/range, or explicit files (works without git). Runs scripted detections, spawns one agent per group, synthesizes findings.
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

Expected check counts: clarity=17, smells=27, solid=15, arch=15, tests=13, safety=32, ddd=9 (128 total).

## Configuration (optional)

A project may silence specific rules with a `.clean-code-review-config.json` file at its repo root (or, outside git, the working directory):

```json
{ "deny": ["ddd", "clarity-08", "safety-25"] }
```

- `deny` is the only key. Each entry is a **group name** (`ddd` → all its checks) or a **check id** (`clarity-08`). Only string entries are honored; a non-string entry (number, boolean, `null`) is ignored — a number surfaces as an unknown-entry `WARN-CONFIG:`, while `true`/`null` are dropped silently.
- Denied checks are never run, reported, or counted — the review proceeds on the remaining rules with no "partial evaluation" warning.
- `collect.sh` resolves entries (matched literally) against the real check universe, writes the concrete silenced ids to `denied.txt`, and slices those checks out of the per-group MD copies each agent reads (`$OUTDIR/groups/{group}.md`) — so a denied check's definition never reaches the model, not merely an instruction to skip it. A group with every check denied is dropped entirely.
- A broken config never aborts the run: an unknown entry, invalid JSON, or a `deny` value that isn't an array each produces a `WARN-CONFIG:` line (surfaced in the report) and is otherwise ignored — the review continues on the valid entries (possibly none).

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

First resolve this skill's install directory (works for both a manual `~/.claude/skills/` install and a plugin install) and reuse the result as `$BASE` for every path in this skill:

```bash
p="${CLAUDE_PLUGIN_ROOT:-}"; [ -n "$p" ] || p=$(jq -r 'first(.plugins | to_entries[] | select(.key | startswith("claude-goodies@")) | .value[0].installPath) // empty' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null); [ -f "$p/skills/clean-code-review/scripts/collect.sh" ] || p="$HOME/.claude"; echo "$p/skills/clean-code-review"
```

Capture the printed path as `$BASE`, then run:

```bash
bash "$BASE/scripts/collect.sh" <non-group tokens...>
```

- **Non-zero exit**: report the script's stderr message to the user verbatim and stop.
- **Success**: stdout is an output directory (`$OUTDIR`) containing:

| File | Content |
|---|---|
| `mode.txt` | resolved target (`staged`/`unstaged`/`untracked` lines, `ref: X`, or `files`) |
| `files.txt` | files under review (vendor/generated already excluded) |
| `files_prod.txt` | `files.txt` minus test files — the `SKIP_TESTS` checks (`ddd-01`, `safety-06`, `solid-06`, `solid-08`, `solid-09`, `arch-14`) run against this list instead |
| `skipped.txt` | excluded files |
| `languages.txt` | detected language tokens |
| `unanalysed.txt` | code extensions with no language mapping |
| `addedlines.txt` | `file:line` index of added/changed lines |
| `diff.patch` | the raw unified diff (untracked/file targets appear as whole-file additions) |
| `numbered.patch` | the same diff with each added/context line prefixed `N\|` (its true file line number) — this is what agents receive |
| `hits.txt` | detection hits, already filtered to added lines and capped |
| `denied.txt` | resolved check ids silenced by project config (one per line; empty when no config) — see Configuration |
| `groups/{group}.md` | one allow-listed copy per group (always written) — verbatim when the group has no denied checks, otherwise with denied checks sliced out; agents always read these |
| `warnings.txt` | `WARN-CAP:` / `WARN-DETECT:` / `WARN-CONFIG:` / `NOTICE-LARGE-DIFF:` lines |

The script needs no GNU grep or other extras — detection patterns run via perl (preinstalled on macOS/Linux). Paths with spaces are handled.

## Step 3 — Language gate

If `languages.txt` is empty, abort the review: `No supported language files detected. Supported: TypeScript, JavaScript, C#, Python, Swift, Kotlin, Java, C++. Unanalysed: {contents of unanalysed.txt}.` Do not spawn agents.

## Step 4 — Spawn review agents

Spawn **one agent per active group in parallel** (Agent tool). Group prompt files:

| Group | File | Checks |
|---|---|---|
| clarity | `$OUTDIR/groups/clarity.md` | 17 |
| smells | `$OUTDIR/groups/smells.md` | 27 |
| solid | `$OUTDIR/groups/solid.md` | 15 |
| arch | `$OUTDIR/groups/arch.md` | 15 |
| tests | `$OUTDIR/groups/tests.md` | 13 |
| safety | `$OUTDIR/groups/safety.md` | 32 |
| ddd | `$OUTDIR/groups/ddd.md` | 9 |

The `Checks` column is each group's full catalog size. `collect.sh` writes one copy of every group MD to `$OUTDIR/groups/{group}.md` — always the file to pass an agent — with any denied checks already sliced out, so the actual count may be lower (see below).

Before spawning, get the diff size: `DIFF_LINES=$(wc -l < "$OUTDIR/numbered.patch")`.

**Drop fully-denied groups.** A group's **effective check count** is the number of `### {group}-` headers in its `$OUTDIR/groups/{group}.md`. If that count is 0 (every check in the group denied), **drop the group** — do not spawn its agent, and remove it from the active set (and from Step 5's counts). If every active group is dropped, abort: `All active groups are silenced by .clean-code-review-config.json — nothing to review.`

Pass each agent:
- The path to `numbered.patch` as `$DIFF` and its exact length: "The diff file is {DIFF_LINES} lines. You MUST read all {DIFF_LINES} lines — keep issuing Read calls with increasing `offset` until you have seen the final line. Reviewing a partially-read diff is a failure." Each added/context line is prefixed `N|` with its true file line number.
- Its group MD file path `$OUTDIR/groups/{group}.md` (agent reads it; it already contains only the checks to evaluate)
- `$PRECOMPUTED`: its group's lines from `hits.txt` (those starting `{group}-`). Line formats, tab-separated after the check id:
  - `id<TAB>file:line:text` → `{ check_id, file, line, matched_text }` — split on the **first two** colons only (paths and text may contain colons)
  - `tests-13` `<TAB>file:count` → `{ check_id, file, count }`
  - `smells-01` `<TAB>count file` → `{ check_id, file, line_count }`
- `$LANGUAGES`: contents of `languages.txt`
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

After all group agents complete, spawn a synthesizer agent following `$BASE/synthesizer.md`. Pass it:
- All finding lines and STATUS lines
- Active groups (fully-denied groups already dropped), `languages.txt`, `skipped.txt`, `unanalysed.txt`, `mode.txt`
- The **effective** expected check count per active group = the number of `### {group}-` headers in the MD passed to that group's agent (collect.sh already sliced out denied checks) — this is the count table the synthesizer must use for reconciliation and `{checks_run}`
- All lines from `warnings.txt` (including any `WARN-CONFIG:` lines)

## Step 6 — Output

Present the synthesizer output directly, **exactly once** — do not repeat, re-summarize, or echo any section of it, and add no commentary before or after it (no dedup narration, no framing text). Then delete `$OUTDIR` (a mktemp directory this skill created), falling back to the trash if `rm` fails:

```bash
rm -rf "$OUTDIR" || trash "$OUTDIR"
```

---

## Edge cases

- **Ref-target line drift**: detection patterns scan worktree file contents, while `addedlines.txt` comes from the requested diff. If the worktree has drifted far from the ref being reviewed, some scripted hits may be filtered out; judgment checks still see the true diff.
- **Partially visible hierarchies** (solid/ddd checks): agents must state the limitation rather than guess — their MD files define the severity-downgrade rules.
- **Testing this skill**: run all three suites after any change to `scripts/`:
  - `tests/test_collect.sh` — target resolution, filtering, caps, numbered diff
  - `tests/test_checks.sh` — every detection command executes cleanly
  - `tests/test_corpus.sh` — pattern semantics: per check+language, `tests/corpus.tsv` defines code that MUST match and near-misses that must NOT. When adding or changing a detection pattern, add its MATCH/NOMATCH rows to `corpus.tsv`.
- **Recall benchmark** (manual eval, not CI): `benchmark/` contains deliberately flawed Python, TypeScript, C#, Swift, and C++ files with 119 catalogued violations (`benchmark/planted.tsv`) plus precision traps. The catalogue exercises 88 of the 128 checks; the C++ fixture added safety-16/17/19, but most of the checks added later (the rest of safety-08 through safety-32, smells-20 through smells-27, arch-11 through arch-15, tests-13, ddd-06 through ddd-09) still have no planted violations, so a benchmark run cannot measure their recall. The eleven judgment checks arch-15, safety-25/26/27/28/29/30/31/32, and smells-24/25 are non-scriptable, so `tests/corpus.tsv` does not cover them either — they ship unmeasured until the fixtures catch up. Run the skill on those files and score against the catalog after changing agent prompts or models — see `benchmark/README.md`. Never "fix" the benchmark files.
