# FEAT-003 — Reliable Cross-Platform Install
**Purpose**: Replace the Claude-mediated install path (LLM prompt injection) with a shell one-liner that works on any surface without being blocked by safety-conscious models.
**Audience**: Developers installing or updating Claude Goodies for the first time, using macOS or Linux (including Windows via WSL).
**Status**: To Do

---

## Background

The current README install path asks the user to paste a prompt into Claude and let it fetch and run `install-prompt.md`. Safety-conscious Claude models increasingly refuse or block this pattern — it's prompt injection from the model's perspective. The root fix is removing Claude from the install flow entirely. A shell one-liner sidesteps the problem completely and works on all surfaces (terminal, Claude Code CLI `!` prefix, VS Code/Cursor/Zed terminal pane).

## Goal

Every user on macOS or Linux can run a single shell command, have `install.sh` clone the repo, stage files into a temp directory, and move them into `~/.claude/` via a safe sequential move. The script handles `CLAUDE.md` conflicts safely, is idempotent, and fails fast with human-readable errors. The README install section is replaced with the one-liner. The old Claude-mediated path is removed.

---

## Scope

### In Scope
- `install.sh` at repo root: clone, stage, safe sequential move into `~/.claude/`
- Prerequisites check: bash, git, curl — fail fast with readable error if missing
- Default behavior: overwrite all files except `CLAUDE.md`; if `CLAUDE.md` exists, leave it and print a post-install hint
- Fresh install: `CLAUDE.md` always copied when it doesn't exist at destination
- `--overwrite` flag: overwrite all files; show `diff -u` of `CLAUDE.md`, ask yes/no; in non-interactive context, overwrite without prompting
- `--keep-claude-md` flag: overwrite all files except `CLAUDE.md`, no prompt
- Staged copy with safe sequential move: any failure cleans up temp dirs and leaves existing install in a re-runnable state
- README install section replaced with shell one-liner; old Claude-mediated path removed
- Windows support documented as WSL only

### Out of Scope
- Native Windows PowerShell support
- Git Bash on Windows
- Changes to any `.sh` files in `scripts/`
- Automated CI testing of `install.sh`
- `settings.json` / `settings.local.json` — user config, not touched by installer
- Skills (`skills/` directory) — user-created; the installer does not touch them
- `agents/` and `commands/` directories — these are Claude Code built-in directories managed by Claude; the installer does not touch them

---

## Acceptance criteria

> Acceptance criteria are verified in the final task. See [Task 3.1 — Final verification & documentation update].

---

## What does NOT change
- All `.sh` files in `scripts/` — their source content in this repo is not modified by this plan; however, local copies at `~/.claude/scripts/` ARE overwritten by the installer on every run
- `settings.json` / `settings.local.json`
- Any existing `CLAUDE.md` at `~/.claude/CLAUDE.md` (unless `--overwrite` is passed and confirmed)

---

## Known limitations / accepted trade-offs
- No three-way merge for `CLAUDE.md` — `--overwrite` replaces with repo version after showing diff; user must manually reconcile if they want a merge
- HTTPS clone only — SSH not attempted; users who prefer SSH clone manually and run `install.sh` from local clone
- No version pinning in this iteration — `install.sh` always installs HEAD of main branch
- macOS ships bash 3.2 — `install.sh` must not use bash 4+ features
- **Stale file cleanup**: scripts removed from the repo are NOT removed from `~/.claude/scripts/` on update — only new/changed files are installed. Orphan files from previous versions persist.
- **User modifications to installed scripts**: files in `~/.claude/scripts/` are overwritten on every install/update run with no backup, no diff, and no flag to prevent it. Users who have modified local copies should back them up before re-running the installer. Only `CLAUDE.md` receives the careful diff-and-confirm treatment.
- **Partial install on mid-sequence failure**: files already moved before a failure remain in the destination. The script is safe to re-run to complete a partial install; no NEW partial state is introduced by a re-run.
- **Truncated download risk**: the `bash <(curl ...)` one-liner executes whatever bash receives. If the network drops mid-download, bash may execute a truncated script. `set -e` and the EXIT trap mitigate partial execution, but cannot guarantee clean state if truncation occurs before the trap is registered. Users who want to inspect the script before running can download it first: `curl -fsSL <URL> -o /tmp/install.sh && bash /tmp/install.sh`.

---

## Architecture

`install.sh` is a self-contained bash 3.2-compatible shell script at the repo root. No external dependencies beyond bash, git, and curl.

### Env var overrides (for testing and advanced use)
- `DEST_DIR="${INSTALL_DEST:-${HOME}/.claude}"` — overrides install destination; tests set this to `$BATS_TMPDIR/test_dest`
- `REPO_URL="${INSTALL_REPO_URL:-https://github.com/user538295/claude_goodies.git}"` — overrides clone URL; e2e tests set this to `file://$BATS_TMPDIR/fixture_repo` (a regular local git repo)
- `INSTALL_STAGE_DIR` — if set, skip `mktemp` for staging and use this pre-created directory instead; enables unit testing of individual phases
- `INSTALL_SKIP_CLONE=1` — skip the git clone entirely; use a local fixture repo at `INSTALL_FIXTURE_DIR`; enables unit testing without network access. Requires `INSTALL_FIXTURE_DIR` to be set; the script validates this and exits 1 if `INSTALL_FIXTURE_DIR` is unset or empty when `INSTALL_SKIP_CLONE=1`.
- `_INSTALL_IS_TTY` — override TTY detection: `0` = non-TTY, `1` = TTY, empty = detect via `[ -t 0 ]`; tests always set `_INSTALL_IS_TTY=0`. Both prompt and pager decisions use this single check (stdin fd 0); if stdin is a terminal, stdout is assumed to also be a terminal.
- `_INSTALL_PAGER` — override pager for diff display (default: `less` when `_INSTALL_IS_TTY=1`); tests set `_INSTALL_PAGER=cat` to avoid `less` stdin conflicts

### Flow
1. Parse flags (`--overwrite`, `--keep-claude-md`, `--help`)
2. Check prerequisites (git, curl, bash >= 3.2) — exit 1 with message on missing
3. Initialize `STAGE_DIR=""`; create `CLONE_DIR=$(mktemp -d)` || exit 1; IMMEDIATELY register `cleanup()` trap on EXIT; THEN create `STAGE_DIR=$(mktemp -d)` || exit 1
4. Stage all files to `$STAGE_DIR`:
   - Copy `scripts/*` (ALL files) → `$STAGE_DIR/scripts/`
   - Copy `install.sh` → `$STAGE_DIR/install.sh`
5. Stage `CLAUDE.md` → `$STAGE_DIR/CLAUDE.md`
6. `find "$STAGE_DIR/scripts" -name "*.sh" -exec chmod +x {} \;` and `chmod +x "$STAGE_DIR/install.sh"` (find form is safe when no .sh files match)
7. `mkdir -p "$DEST_DIR/scripts"`
8. Safe sequential move — for each file in the staging directory (excluding `CLAUDE.md`), `mv "$STAGE_DIR/$file" "$DEST_DIR/$file" || { cp "$STAGE_DIR/$file" "$DEST_DIR/$file" && rm "$STAGE_DIR/$file"; }` — the `||` pattern suppresses `set -e` for the `mv` so the `cp`+`rm` fallback runs on cross-device link failure. For scripts, iterate over `$STAGE_DIR/scripts/*`. This is purely flat file operations — no directory tree complexity. NOTE: files already moved before a mid-sequence failure remain in the destination — this is not a full rollback. The script is safe to re-run to complete a partial install.
9. Call `handle_claude_md()` — copies staged `CLAUDE.md` to dest conditionally based on flags and existing state (see CLAUDE.md decision table)
10. Print post-install summary; remind user to restart Claude Code

### CLAUDE.md decision table

| Existing `~/.claude/CLAUDE.md` | Flag | Action |
|---|---|---|
| No | any | Copy from repo — always |
| Yes | (none) | Skip; print hint to re-run with `--overwrite` |
| Yes | `--keep-claude-md` | Skip silently |
| Yes | `--overwrite`, TTY | Show `diff -u`, ask yes/no; yes → overwrite, no → skip |
| Yes | `--overwrite`, non-TTY | Overwrite without prompting |

### File manifest installed
- `~/.claude/CLAUDE.md` (conditional — see decision table)
- `~/.claude/scripts/*` (ALL files from `scripts/` in repo — includes `.sh`, `.awk`, `.template`, etc.)
- `~/.claude/install.sh` (installer script itself, from repo root)

### One-liner format
```
bash <(curl -fsSL https://raw.githubusercontent.com/user538295/claude_goodies/main/install.sh)
```
Process substitution avoids piping stdin, keeping interactive prompts functional. Works on bash 3.2.

### Source-safe script structure
The script must be source-safe: define all functions first, then call the main entry point only when `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` (i.e., not when sourced). This enables bats tests to source the script with `. install.sh` and call individual functions (e.g. `parse_flags`, `check_prereqs`) directly without triggering the full install flow.

IMPORTANT: `set -euo pipefail` MUST be placed inside `main()` (or inside the `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard), NOT at the top level of the script. If placed at the top level, bats tests that source `install.sh` will inherit these shell options, causing test failures. Only function definitions should execute at the top level when sourced.

### Test Infrastructure
- **Framework**: bats (Bash Automated Testing System) — matches existing `tests/*.bats` pattern in this repo
- **Mocking `command -v <tool>`**: prepend a stub directory to PATH: `export PATH="$BATS_TMPDIR/mock_bin:$PATH"` where `mock_bin/<tool>` is a script that exits 1
- **Mocking user input for `read`**: `echo "y" | bash install.sh --overwrite ...` or use process substitution
- **Overriding TTY detection**: set `_INSTALL_IS_TTY=0` (non-TTY) or `_INSTALL_IS_TTY=1` (TTY) in all tests; never rely on actual terminal state
- **Working directory fixture (for unit tests with `INSTALL_SKIP_CLONE=1`)**: a plain directory containing: `scripts/plan-progress.sh` (`.sh` example), `scripts/task_section.awk` (`.awk` example), `scripts/progress-header-flat.template` (`.template` example), `CLAUDE.md` (with some content), `install.sh` (minimal content). This ensures non-`.sh` files are tested. Set `INSTALL_FIXTURE_DIR` to this plain directory. No git involved.
- **Clone fixture (for e2e tests)**: same file structure as the working directory fixture, but committed to a regular (not bare) local git repo that `git clone` can use: `git init $BATS_TMPDIR/fixture_repo && <copy files> && git -C $BATS_TMPDIR/fixture_repo add . && git -C $BATS_TMPDIR/fixture_repo commit -m "fixture"`. Set `INSTALL_REPO_URL` to `file://$BATS_TMPDIR/fixture_repo`. File structure: `scripts/*`, `CLAUDE.md`, `install.sh` (no `agents/`, `commands/`, or `skills/`).
- **Test lifecycle**: `setup()` creates `$BATS_TMPDIR/test_dest` and sets all required env vars (`INSTALL_DEST`, `INSTALL_REPO_URL`, `_INSTALL_IS_TTY=0`); `teardown()` removes temp dirs
- **Skipping network/clone**: set `INSTALL_SKIP_CLONE=1` and `INSTALL_FIXTURE_DIR` to a working directory fixture (plain directory)
- **Pager in tests**: always set `_INSTALL_IS_TTY=0` so diff output goes to stdout with no pager (no `less` hang)
- **Pager in TTY tests**: always set `_INSTALL_PAGER=cat` when testing with `_INSTALL_IS_TTY=1` to prevent `less` from conflicting with piped stdin

---

## Task breakdown

### Phase 1 — install.sh

> **Releasable**: after this phase — `install.sh` exists and can be run from a local clone or via the one-liner

#### Task 1.1 — install.sh: prerequisites check and flag parsing
- [x] **File**: `install.sh`
- **Depends on**: nothing
- **Description**:
  - Bash 3.2-compatible (`#!/usr/bin/env bash`)
  - Structure: place `set -euo pipefail` inside `main()` (or inside the `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard), not at script top level. See Architecture "Source-safe script structure" note.
  - Initialize all flag variables before the parsing loop: `OVERWRITE=0`, `KEEP_CLAUDE_MD=0`
  - Parse positional flags: `--overwrite` sets `OVERWRITE=1`; `--keep-claude-md` sets `KEEP_CLAUDE_MD=1`; `--help` prints usage and exits **0**; unknown flag exits 1 with usage message
  - Mutually exclusive: if both `--overwrite` and `--keep-claude-md` are passed, exit 1 with error
  - `check_prereqs()` function: verify `git` and `curl` exist via `command -v`; verify bash version >= 3.2 using `${BASH_VERSINFO[0]}` and `${BASH_VERSINFO[1]}`; print `"Error: <tool> is required but not installed."` and exit 1 for each missing tool or unsupported version
  - No network access in this task — only local checks
  - `DEST_DIR="${INSTALL_DEST:-${HOME}/.claude}"` — overridable via env var for testing
  - `REPO_URL="${INSTALL_REPO_URL:-https://github.com/user538295/claude_goodies.git}"` — overridable via env var for testing
- **Releasable**: after this task, flag parsing and prereq checks work and can be tested in isolation
- **Tests (TDD)** — `tests/test_install_prereqs.bats`:
  - Unit: `test_missing_git_exits_1` — mock `command -v git` to fail; assert exit code 1 and error message contains "git"
  - Unit: `test_missing_curl_exits_1` — mock `command -v curl`; assert exit 1 + message
  - Unit: `test_unknown_flag_exits_1` — call with `--foo`; assert exit 1 + usage output
  - Unit: `test_help_flag_prints_usage_exits_0` — call with `--help`; assert exit code 0 and output contains usage text
  - Unit: `test_conflicting_flags_exits_1` — call with `--overwrite --keep-claude-md`; assert exit 1
  - Unit: `test_valid_flags_accepted` — source `install.sh` (`. install.sh`) to load functions without executing the main body; call `parse_flags --overwrite` directly; assert `OVERWRITE=1` and function returns cleanly. The script must be structured so sourcing it defines functions but does not run the main flow (see Architecture note below). Test `--keep-claude-md` the same way.
  - All tests: set `INSTALL_DEST=$BATS_TMPDIR/test_dest`, `INSTALL_REPO_URL` to `file://$BATS_TMPDIR/fixture_repo`, `_INSTALL_IS_TTY=0`
  - Checkpoint: `bats tests/test_install_prereqs.bats`

#### Task 1.2 — install.sh: clone, stage, and safe sequential move
- [x] **File**: `install.sh`
- **Depends on**: Task 1.1
- **Description**:
  - Before creating temp dirs, initialize `STAGE_DIR=""` so the cleanup trap references a defined variable under `set -u`.
  - Temp dir creation order: `STAGE_DIR=""`; then `CLONE_DIR=$(mktemp -d) || { echo 'Error: cannot create temp directory in /tmp'; exit 1; }` — the `||` disables `set -e` for the left side and lets the custom message print before exit; then `trap 'rm -rf "${CLONE_DIR:-}" "${STAGE_DIR:-}"' EXIT`; then `STAGE_DIR=$(mktemp -d) || { echo 'Error: cannot create temp directory in /tmp'; exit 1; }`.
  - If `INSTALL_SKIP_CLONE=1`: guard that `INSTALL_FIXTURE_DIR` is set and non-empty — if not, exit 1 with `'Error: INSTALL_SKIP_CLONE=1 requires INSTALL_FIXTURE_DIR to be set'`; do NOT use `:-` default substitution. Use `INSTALL_FIXTURE_DIR` as the source. Otherwise: `git clone --depth 1 "$REPO_URL" "$CLONE_DIR"` — on failure exit 1 with `"Error: failed to clone repository"`
  - If `INSTALL_STAGE_DIR` is set: use it instead of `mktemp` for staging (enables unit testing of individual phases)
  - Stage: copy the file manifest into `$STAGE_DIR`:
    - `cp "$CLONE_DIR/CLAUDE.md" "$STAGE_DIR/CLAUDE.md"`
    - `mkdir -p "$STAGE_DIR/scripts"` then copy scripts: `if ls "$CLONE_DIR/scripts/"* >/dev/null 2>&1; then cp "$CLONE_DIR/scripts/"* "$STAGE_DIR/scripts/"; else echo 'Warning: scripts/ is empty'; fi` (ALL files, not just `.sh`; the guard prevents set -e failure if scripts/ is empty)
    - `cp "$CLONE_DIR/install.sh" "$STAGE_DIR/install.sh"`
  - Make `.sh` files executable: `find "$STAGE_DIR/scripts" -name "*.sh" -exec chmod +x {} \;` and `chmod +x "$STAGE_DIR/install.sh"` — use find form to avoid set -e failure when no .sh files exist (only `.sh` files get executable bit; `.awk`, `.template`, etc. do not)
  - `mkdir -p "$DEST_DIR/scripts"`
  - Safe sequential move: for `install.sh` and all files in `$STAGE_DIR/scripts/*`, use `mv "$STAGE_DIR/$file" "$DEST_DIR/$file" || { cp "$STAGE_DIR/$file" "$DEST_DIR/$file" && rm "$STAGE_DIR/$file"; }` — the `||` pattern suppresses `set -e` for the `mv` so the `cp`+`rm` fallback runs on cross-device link failure. CLAUDE.md is staged but NOT moved in this task — it is handled conditionally by `handle_claude_md()` in Task 1.3. This is purely flat file operations — no directory tree complexity.
  - On any copy/move failure: print `"Error: failed to install <file>"` and exit 1; cleanup trap removes remaining temp dirs; files already moved remain at destination (not a full rollback — re-run to complete)
  - All tests: set `INSTALL_SKIP_CLONE=1`, `INSTALL_FIXTURE_DIR` to a working directory fixture (plain directory), `INSTALL_DEST=$BATS_TMPDIR/test_dest`, `INSTALL_REPO_URL` to `file://$BATS_TMPDIR/fixture_repo`, `_INSTALL_IS_TTY=0`
- **Releasable**: after this task, the script installs all non-CLAUDE.md files; CLAUDE.md is staged but not yet moved (Task 1.3 adds the conditional logic). NOTE: Task 1.2's intermediate state (CLAUDE.md staged but not installed) is not user-safe for shipping; Task 1.3 completes the implementation.
- **Tests (TDD)** — `tests/test_install_copy.bats`:
  - Unit: `test_all_manifest_files_copied_to_dest` — run against fixture; assert `scripts/*` and `install.sh` are at dest; assert CLAUDE.md is NOT yet at dest (Task 1.3 handles it); assert `agents/`, `commands/`, `skills/` are NOT created at dest
  - Unit: `test_scripts_are_executable` — assert `chmod +x` applied to `.sh` files in `scripts/`; assert `.awk` and `.template` files do NOT have executable bit set
  - Unit: `test_cleanup_on_failure` — simulate copy failure; assert temp dirs removed
  - Unit: `test_dest_dir_created_if_missing` — run with no dest dir; assert `$DEST_DIR/scripts/` created
  - Unit: `test_existing_install_untouched_on_failure` — pre-place files at dest; simulate failure; assert originals unchanged
  - Unit: `test_skip_clone_without_fixture_dir_exits_1` — set `INSTALL_SKIP_CLONE=1`, unset `INSTALL_FIXTURE_DIR`; assert exit 1 and output contains 'INSTALL_FIXTURE_DIR'
  - Unit: `test_cross_device_fallback` — mock `mv` to fail (exit 1) for the first call via PATH stub (`export PATH="$BATS_TMPDIR/mock_bin:$PATH"` where `mock_bin/mv` exits 1); assert `cp` + `rm` fallback executes and file arrives at dest
  - Unit: `test_non_sh_files_copied_to_dest` — assert `scripts/task_section.awk` and `scripts/progress-header-flat.template` are present at dest
  - Unit: `test_non_sh_files_not_executable` — assert `.awk` and `.template` files at dest do NOT have the executable bit set
  - Checkpoint: `bats tests/test_install_copy.bats`

#### Task 1.3 — install.sh: CLAUDE.md handling
- [x] **File**: `install.sh`
- **Depends on**: Task 1.2
- **Description**:
  - `handle_claude_md()` function — implements the CLAUDE.md decision table from Architecture section
  - Fresh install (no `$DEST_DIR/CLAUDE.md`): always copy from staging, regardless of flags
  - Default (no flags, file exists): skip copy; print `"CLAUDE.md already exists. Re-run with --overwrite to update it."`
  - `--keep-claude-md` (file exists): skip copy, no output
  - `--overwrite` + TTY: run `diff -u "$DEST_DIR/CLAUDE.md" "$STAGE_DIR/CLAUDE.md" || true` to show the diff (diff exits 1 when files differ; suppress with `|| true` to avoid `set -e` termination); pipe output through `${_INSTALL_PAGER:-less}` if `_INSTALL_IS_TTY` (or `[ -t 0 ]`) indicates TTY and the pager command exists, otherwise `cat`; prompt `"Overwrite CLAUDE.md? [y/N] "`; read answer; `y` or `Y` → copy; anything else → skip and print `"CLAUDE.md left unchanged."`
  - `--overwrite` + non-TTY: overwrite without prompting; print `"Non-interactive: CLAUDE.md overwritten."`
  - TTY detection: use `_INSTALL_IS_TTY` env var if set (`0`=non-TTY, `1`=TTY); otherwise detect via `[ -t 0 ]`
  - The `_INSTALL_IS_TTY=0` env var also disables pager use — diff output goes to stdout with no pager; tests always set `_INSTALL_IS_TTY=0` to avoid `less` hanging
- **Releasable**: after this task, `install.sh` is complete and handles all CLAUDE.md scenarios
- **Tests (TDD)** — `tests/test_install_claude_md.bats`:
  - Unit: `test_fresh_install_copies_claude_md` — no existing file; assert copied
  - Unit: `test_default_skips_existing_claude_md` — existing file; no flag; assert unchanged + message printed
  - Unit: `test_keep_claude_md_skips_silently` — existing file; `--keep-claude-md`; assert unchanged, no output about CLAUDE.md
  - Unit: `test_overwrite_noninteractive_overwrites` — existing file; `--overwrite`; `_INSTALL_IS_TTY=0`; assert overwritten
  - Unit: `test_overwrite_interactive_yes_overwrites` — `_INSTALL_IS_TTY=1`, `_INSTALL_PAGER=cat` + `y` input via pipe; assert overwritten
  - Unit: `test_overwrite_interactive_no_leaves_unchanged` — `_INSTALL_IS_TTY=1`, `_INSTALL_PAGER=cat` + `n` input via pipe; assert unchanged + message
  - All tests: set `INSTALL_SKIP_CLONE=1`, `INSTALL_FIXTURE_DIR` to a local test fixture, `INSTALL_DEST=$BATS_TMPDIR/test_dest`, `_INSTALL_IS_TTY=0`
  - Checkpoint: `bats tests/test_install_claude_md.bats`
- **Integration tests (TDD)** — `tests/test_install_e2e.bats`:
  - Integration: `test_full_install_fresh_dest` — set `INSTALL_REPO_URL` to `file://$BATS_TMPDIR/fixture_repo`, `INSTALL_DEST` to temp dir; run full script; assert `scripts/*`, `install.sh`, and `CLAUDE.md` are present and `.sh` files are executable; assert `agents/`, `commands/`, `skills/` do NOT exist at dest
  - Integration: `test_idempotent_second_run` — run full script twice against the same `INSTALL_DEST`; assert second run exits 0, `CLAUDE.md` at dest is unchanged (default mode), all `scripts/*` are present and `.sh` files are executable. Note: temp dir cleanup is verified by `test_cleanup_on_failure` in `test_install_copy.bats`; the e2e tests do not re-verify this.
  - All tests: set `INSTALL_REPO_URL` to `file://$BATS_TMPDIR/fixture_repo` (a regular — not bare — local git repo with committed file structure); set `INSTALL_DEST` to `$BATS_TMPDIR/test_dest`; set `_INSTALL_IS_TTY=0`
  - Checkpoint: `bats tests/test_install_e2e.bats`

---

### Phase 2 — README update

> **Releasable**: after this phase — README reflects the new shell install path; old Claude-mediated path is removed

#### Task 2.1 — Replace README install section with shell one-liner
- [ ] **File**: `README.md`
- **Depends on**: Task 1.3
- **Description**:
  - Replace the `## Install · Update` section content with:
    - Shell one-liner using process substitution: `bash <(curl -fsSL https://raw.githubusercontent.com/user538295/claude_goodies/main/install.sh)`
    - Note: works in any terminal and in Claude Code CLI with `! ` prefix
    - Flags subsection: `--overwrite` and `--keep-claude-md` documented with one-sentence descriptions each
    - Windows: document WSL only; note Git Bash is unsupported
    - Prerequisites listed: bash, git, curl
  - Remove the existing Claude-prompt-paste install instructions entirely — no trace of the old path
  - Keep the "Restart Claude Code" instruction
  - Match existing README style (no new headers or formatting patterns)
- **Releasable**: after this task, README install section is correct and complete
- **Tests (TDD)** — manual verification only (README content):
  - Confirm old Claude-mediated prompt text is absent
  - Confirm one-liner is present and syntactically correct
  - Confirm `--overwrite` and `--keep-claude-md` are documented
  - Confirm Windows/WSL note is present
  - Checkpoint: `grep -n "curl\|install.sh\|--overwrite\|--keep-claude-md\|WSL" README.md`

---

### Phase 3 — Verification & Documentation

> **Releasable**: after this phase — feature is fully verified, all documentation current

#### Task 3.1 — Final verification & documentation update
- [ ] **File**: N/A (agent task)
- **Depends on**: Task 2.1 (all prior tasks)
- **Description**:
  - Spawn an agent to discover all documentation in the project (README.md, CLAUDE.md, handout HTML pages, install-prompt.md, any other docs that reference the install path) and update every file whose content is affected by the changes delivered in this plan. The agent must not update docs that are unrelated.
  - Specifically check: `install-prompt.md` — assess whether it should be deprecated/removed or updated with a pointer to `install.sh`; `handout/` pages that describe installation; any README badges or quick-start sections.
  - Verify all acceptance criteria below are met before marking this task complete.
- **Releasable**: after this task, the feature is fully verified and all documentation reflects the delivered implementation.
- **Acceptance criteria** (must all pass):
  - `install.sh` exists at repo root and is executable
  - `bash install.sh --help` prints usage and exits 0; `bash install.sh --unknown-flag` prints usage and exits 1
  - Running `install.sh` against a fresh dest copies `scripts/*`, `install.sh`, and `CLAUDE.md`; does NOT create `agents/`, `commands/`, or `skills/` directories
  - Running `install.sh` a second time (idempotent) leaves existing `CLAUDE.md` untouched and prints the hint message; introduces no NEW partial state
  - Running `install.sh --keep-claude-md` overwrites all files except `CLAUDE.md`, no output about CLAUDE.md
  - Running `install.sh --overwrite` in a non-interactive context overwrites `CLAUDE.md`
  - On any failure (missing prereq, failed clone, failed copy), no NEW partial state is introduced in `~/.claude/`; the script is safe to re-run
  - README `## Install · Update` section contains the shell one-liner and no reference to the Claude-prompt-paste method
  - `--overwrite` and `--keep-claude-md` flags are documented in README
  - Windows/WSL note is present in README
  - All `.sh` files copied to `~/.claude/scripts/` are executable
- **Tests (TDD)**: N/A — this is a verification and documentation task.
- **Checkpoint**: manually confirm every acceptance criterion above is checked.
