# FEAT-004 — `--dry-run` flag for install.sh
**Purpose**: Let users preview every action `install.sh` would perform — without touching the filesystem — so they can audit before committing.
**Audience**: Anyone running `install.sh`: first-time users, users upgrading after a gap.
**Status**: To Do

---

## Background
`install.sh` moves scripts, `install.sh` itself, and conditionally `CLAUDE.md` into `~/.claude`. There is no safe way to preview this before running it. Adding `--dry-run` replaces every destination write with a `[DRY RUN] Would …` log line, runs the full staging pipeline, and exits with a summary count — leaving the filesystem untouched.

## Goal
`install.sh --dry-run` (optionally combined with `--overwrite` or `--keep-claude-md`) prints every action the real run would take, prefixed with `[DRY RUN]`, prints `"N file(s) would be installed."`, and exits 0. No file, directory, or permission change is made to `$INSTALL_DEST`.

---

## Scope

### In Scope
- `--dry-run` flag parsed in `parse_flags()` alongside existing flags; sets `DRY_RUN=1`
- `dry_mkdir()`, `dry_mv()`, `dry_cp()` wrapper functions: in dry-run mode print and count; in real mode execute
- `move_files()` refactored to use the three wrappers
- `handle_claude_md()` updated with per-branch dry-run output per the decision table
- `main()` prints the `WRITE_COUNT` summary line instead of "installed successfully" in dry-run mode
- `usage()` updated to document `--dry-run`
- BATS test file `tests/test_install_dry_run.bats` with 16 test cases

### Out of Scope
- Standalone `--diff` flag (full file-by-file diff); the TTY diff in `--dry-run --overwrite` reuses the existing `--overwrite` diff logic
- Machine-readable exit codes (exit 1 on changes)
- `--check` alias

---

## Acceptance criteria

> Acceptance criteria are verified in the final task. See [Task 3.1 — Final verification & documentation update].

---

## What does NOT change
- All existing install behavior when `--dry-run` is absent — `move_files()` refactor must be behaviorally identical in non-dry-run mode
- Flag mutual-exclusion check (`--overwrite` + `--keep-claude-md` → exit 1) — untouched
- `check_prereqs`, `do_clone`, `stage_files`, `set_permissions` — run unchanged in both modes
- EXIT trap cleanup — runs in both modes
- Existing BATS tests — must all still pass after changes

---

## Known limitations / accepted trade-offs
- `--dry-run` still performs a real `git clone` (network I/O). Offline users can use `INSTALL_SKIP_CLONE=1` with `INSTALL_FIXTURE_DIR`.
- In `--dry-run --overwrite` TTY mode, the diff is shown but the prompt is not interactive; CLAUDE.md is counted as "would be installed" regardless of what the user would have answered.
- Always exits 0 — no machine-readable "would change" signal.

---

## Architecture

### New globals (set in `parse_flags` AND at module level)
- `DRY_RUN` (integer, default `0`) — set to `1` when `--dry-run` is passed
- `WRITE_COUNT` (integer, default `0`) — incremented by `dry_mv()` and `dry_cp()` (not `dry_mkdir()`); drives the summary line

Both `DRY_RUN=0` and `WRITE_COUNT=0` must be initialized at **module level** alongside `DEST_DIR` and `REPO_URL` (lines 8–9 of `install.sh`) for source-safety in isolated unit tests, in addition to being reset inside `parse_flags()`.

### New wrapper functions (defined after `set_permissions`, before `move_files`)

```bash
# dry_mkdir DIR
#   DRY_RUN=1: print "[DRY RUN] Would create directory DIR"; no I/O; WRITE_COUNT unchanged
#   DRY_RUN=0: mkdir -p DIR
dry_mkdir() { ... }

# dry_mv SRC DST
#   DRY_RUN=1: print "[DRY RUN] Would install BASENAME(DST)"; WRITE_COUNT++; no I/O
#   DRY_RUN=0: mv SRC DST; on failure, cp SRC DST; on cp failure, exit 1 with error
dry_mv() { ... }

# dry_cp SRC DST
#   DRY_RUN=1: print "[DRY RUN] Would install BASENAME(DST)"; WRITE_COUNT++; no I/O
#   DRY_RUN=0: cp SRC DST; on failure, exit 1 with error
dry_cp() { ... }
```

The `dry_mv` and `dry_cp` error messages use `$dst` directly for maximum diagnostics:
```bash
cp "$src" "$dst" || { echo "Error: failed to install $dst" >&2; exit 1; }
```

### `handle_claude_md` decision table (dry-run output)

| Condition | Dry-run output | Count? |
|-----------|----------------|--------|
| CLAUDE.md absent at dest | `[DRY RUN] Would copy CLAUDE.md` | Yes |
| CLAUDE.md exists, no flags | `[DRY RUN] Would skip CLAUDE.md (use --overwrite to replace)` | No |
| `--keep-claude-md`, CLAUDE.md exists | *(no output)* | No |
| `--keep-claude-md`, CLAUDE.md absent | `[DRY RUN] Would copy CLAUDE.md` | Yes |
| `--overwrite`, TTY | show diff; print `[DRY RUN] Would prompt: Overwrite CLAUDE.md? [y/N]` — no stdin read | Yes |
| `--overwrite`, non-TTY | `[DRY RUN] Would overwrite CLAUDE.md` | Yes |

### Output format contract

The following exact strings must be used by the implementation and matched by test assertions:

- **Script file install**: `[DRY RUN] Would install <basename>`
- **Directory creation**: `[DRY RUN] Would create directory <path>`
- **CLAUDE.md messages**: per the decision table above
- **Summary line**: `<N> file(s) would be installed.` *(note the trailing period)*

### Execution order (unchanged)
`check_prereqs` → `do_clone` → `stage_files` → `set_permissions` → `move_files` → `handle_claude_md` → print summary → EXIT trap

---

## Task breakdown

### Phase 1 — BATS test suite
> **Written first (TDD)**. Tests are written against the interface specified in the Architecture section. All tests in Task 1.1 WILL FAIL until Phase 2 implementation is complete — that is expected and correct. Phase 1 is releasable as a failing-test PR that documents the intended contract.

#### Task 1.1 — Write `tests/test_install_dry_run.bats` covering all 16 test cases
- [x] **File**: `tests/test_install_dry_run.bats`
- **Depends on**: nothing (tests are written against the Architecture spec, before implementation)
- **Description**:
  - Single BATS file containing all 16 tests for the `--dry-run` feature
  - Every test uses `INSTALL_SKIP_CLONE=1` and `INSTALL_FIXTURE_DIR` pointing to the fixture dir created in `setup()` — following the inline fixture pattern used in `test_install_copy.bats` (fixture dir is created by `setup()`, not pre-existing on disk)
  - `setup()` creates a temp `INSTALL_DEST` dir and a temp fixture dir populated with representative scripts; `teardown()` removes both
  - Every test sets `_INSTALL_IS_TTY=0` unless explicitly testing TTY behavior
  - **TTY test**: sets `_INSTALL_IS_TTY=1 _INSTALL_PAGER=cat`; the `timeout` command goes INSIDE the `run` call: `run timeout 5 bash "$SCRIPT" --dry-run --overwrite` — NOT wrapping the `run` itself
  - **Zero-writes invariant**: marker file is `touch`-ed AFTER `setup()` creates all fixture files and BEFORE the `run` invocation, so only changes made by the script under test are caught by `find "$INSTALL_DEST" -newer "$marker"` asserts empty — confirms no files or directories were created under the destination
  - **Per-file output assertion** (case 14): loops over known fixture files; asserts each appears in output as `[DRY RUN] Would install <name>`. The loop covers files processed by `move_files()` — `scripts/*` and `install.sh` only. `CLAUDE.md` is NOT included here; it has its own branch-specific assertion in the CLAUDE.md test cases.
  - **Staging cleanup** (case 15): uses `INSTALL_STAGE_DIR` injection to track the dir; asserts `[[ ! -d "$INSTALL_STAGE_DIR" ]]` after run
  - **Brief case 11 note** (staging populated): brief case 11 ("assert $STAGE_DIR is populated during dry-run") is not directly testable in isolation because the EXIT trap removes STAGE_DIR before any assertion can run. It is implicitly covered by case 14 (per-file output assertion) — if staging had failed, no `[DRY RUN] Would install` lines would appear. No separate "staging populated" test is needed.
  - **Regression gate** (case 12): runs existing test suite inside a `run` call: `run bats tests/test_install_prereqs.bats tests/test_install_copy.bats tests/test_install_claude_md.bats tests/test_install_e2e.bats`; asserts `$status -eq 0`; on failure, `echo "$output"` for diagnostics. Note: individual inner test names are only visible in the outer BATS report if the inner run fails.
  - Covers all 16 brief test cases plus unit-level wrapper function tests and real-mode regression tests (~29 total). Tests from Tasks 2.1–2.5 all live in this single file.
  - All output string assertions must use the exact strings from the Architecture → Output format contract section
- **Releasable**: test file exists and is syntactically valid; all 16 tests run (failing is acceptable at this stage — Phase 2 makes them pass).
- **Tests (TDD)**: this task IS the test suite.
- **Checkpoint**: `cd /Users/manczg/.claude && bats tests/test_install_dry_run.bats`
  *(Fixture dir is created by each test's `setup()` function; run the whole file or pass `--filter` for a subset.)*

---

### Phase 2 — Core implementation
> **Releasable**: after Task 2.5 — the full dry-run feature is functional in `install.sh` and all Phase 1 tests pass.

#### Task 2.1 — Add `DRY_RUN` and `WRITE_COUNT` to module level, `parse_flags()`, and update `usage()`
- [x] **File**: `install.sh`
- **Depends on**: Task 1.1 (test infrastructure exists)
- **Description**:
  - At **module level** (alongside `DEST_DIR` and `REPO_URL`, lines 8–9), add:
    ```bash
    DRY_RUN=0
    WRITE_COUNT=0
    ```
  - In `parse_flags()`, also initialize `DRY_RUN=0` and `WRITE_COUNT=0` at the top alongside `OVERWRITE=0` and `KEEP_CLAUDE_MD=0`
  - Add `--dry-run` case to the `while/case` loop: `DRY_RUN=1`
  - `--dry-run` is orthogonal to `--overwrite` and `--keep-claude-md` — no new mutual-exclusion check needed; the existing `OVERWRITE + KEEP_CLAUDE_MD` check fires regardless
  - In `usage()`, add `--dry-run` line: `  --dry-run          Preview actions without writing any files`
  - `WRITE_COUNT` is initialized at module level so it is defined before any function checks `$WRITE_COUNT` under `set -u`
- **Releasable**: `--dry-run` is recognized and doesn't produce an "unknown flag" error; `--help` shows it.
- **Tests (TDD)** — `tests/test_install_dry_run.bats` (written in Task 1.1):
  - Unit: `test_dry_run_flag_is_recognized` — `parse_flags --dry-run` exits 0
  - Unit: `test_dry_run_with_overwrite_is_valid` — `parse_flags --dry-run --overwrite` exits 0
  - Unit: `test_dry_run_with_keep_claude_md_is_valid` — `parse_flags --dry-run --keep-claude-md` exits 0
  - Unit: `test_dryrun_no_hyphen_exits_1` — `./install.sh --dryrun` exits 1 with "Unknown flag" error; confirms typo does not silently proceed
  - Unit: `test_dry_run_overwrite_keep_combo_exits_1` — `--dry-run --overwrite --keep-claude-md` exits 1 (mutual-exclusion check fires)
  - Unit: `test_help_includes_dry_run` — `./install.sh --help` output includes `--dry-run`
  - Checkpoint: `cd /Users/manczg/.claude && bats tests/test_install_dry_run.bats --filter "recognized|valid|exits_1|help"`

#### Task 2.2 — Implement `dry_mkdir()`, `dry_mv()`, `dry_cp()` wrapper functions
- [ ] **File**: `install.sh`
- **Depends on**: Task 2.1
- **Description**:
  - Insert the three functions after `set_permissions()` and before `move_files()`:

  ```bash
  # dry_mkdir DIR — guard for mkdir -p to INSTALL_DEST
  dry_mkdir() {
    local dir="$1"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY RUN] Would create directory $dir"
      return 0
    fi
    mkdir -p "$dir"
  }

  # dry_mv SRC DST — guard for mv (with cp fallback) to INSTALL_DEST
  dry_mv() {
    local src="$1" dst="$2"
    local fname
    fname="$(basename "$dst")"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY RUN] Would install $fname"
      WRITE_COUNT=$(( WRITE_COUNT + 1 ))
      return 0
    fi
    if ! mv "$src" "$dst" 2>/dev/null; then
      cp "$src" "$dst" || { echo "Error: failed to install $dst" >&2; exit 1; }
    fi
  }

  # dry_cp SRC DST — guard for cp to INSTALL_DEST
  dry_cp() {
    local src="$1" dst="$2"
    local fname
    fname="$(basename "$dst")"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY RUN] Would install $fname"
      WRITE_COUNT=$(( WRITE_COUNT + 1 ))
      return 0
    fi
    cp "$src" "$dst" || { echo "Error: failed to install $dst" >&2; exit 1; }
  }
  ```

  - `dry_mkdir` does NOT increment `WRITE_COUNT` (directories are not files)
  - `dry_mv` absorbs the mv-with-cp-fallback pattern from `move_files()` — this is the canonical place for that logic going forward
  - Error messages use `$dst` directly for maximum context (e.g. `Error: failed to install /home/user/.claude/scripts/foo.sh`)
  - All three functions are Bash 3.2 compatible (no `local -i`, no associative arrays)
- **Releasable**: wrappers are defined and callable; no behavior change yet (move_files still calls raw mv/cp).
- **Tests (TDD)** — `tests/test_install_dry_run.bats` (written in Task 1.1):
  - Unit: `test_dry_mv_in_dry_run_prints_and_does_not_write` — call `dry_mv /tmp/src /tmp/dst` with `DRY_RUN=1`; assert output contains `[DRY RUN] Would install dst`; assert `/tmp/dst` not created
  - Unit: `test_dry_mv_in_dry_run_increments_write_count` — `WRITE_COUNT=0; dry_mv ...`; assert `WRITE_COUNT=1`
  - Unit: `test_dry_cp_in_dry_run_prints_and_does_not_write` — same as above for `dry_cp`
  - Unit: `test_dry_mkdir_in_dry_run_prints_and_does_not_create` — `dry_mkdir /tmp/newdir` with `DRY_RUN=1`; assert dir not created
  - Unit: `test_dry_mkdir_does_not_increment_write_count` — `WRITE_COUNT=0; dry_mkdir ...`; assert `WRITE_COUNT=0`
  - Unit: `test_dry_mv_in_real_mode_moves_file` — `DRY_RUN=0`; assert file moved to dst
  - Unit: `test_dry_cp_in_real_mode_copies_file` — `DRY_RUN=0`; assert file copied to dst
  - Checkpoint: `cd /Users/manczg/.claude && bats tests/test_install_dry_run.bats --filter "dry_mv|dry_cp|dry_mkdir"`

#### Task 2.3 — Update `move_files()` to use wrapper functions
- [ ] **File**: `install.sh`
- **Depends on**: Task 2.2
- **Description**:
  - Replace `mkdir -p "$DEST_DIR/scripts"` with `dry_mkdir "$DEST_DIR/scripts"`
  - Replace the `mv + cp fallback` block for each script with `dry_mv "$src" "$dst"`
  - Replace the `mv + cp fallback` block for `install.sh` with `dry_mv "$STAGE_DIR/install.sh" "$DEST_DIR/install.sh"`
  - The resulting `move_files()` body:

  ```bash
  move_files() {
    dry_mkdir "$DEST_DIR/scripts"

    for src in "$STAGE_DIR/scripts/"*; do
      [[ -e "$src" ]] || continue
      local fname
      fname="$(basename "$src")"
      dry_mv "$src" "$DEST_DIR/scripts/$fname"
    done

    dry_mv "$STAGE_DIR/install.sh" "$DEST_DIR/install.sh"
  }
  ```

  - Non-dry-run behavior must be identical to before: `dry_mv` carries the mv+cp-fallback logic (see Task 2.2)
  - Remove the per-file error message from `move_files`; it is now inside `dry_mv`
- **Releasable**: in dry-run mode, all script files and `install.sh` print `[DRY RUN] Would install <name>` and are counted; real mode is behaviorally unchanged.
- **Tests (TDD)** — `tests/test_install_dry_run.bats` (written in Task 1.1):
  - Integration: `test_dry_run_scripts_not_written_to_dest` — full install with `--dry-run`; assert `$INSTALL_DEST/scripts/` does not exist or is unchanged
  - Integration: `test_dry_run_install_sh_not_written` — assert `$INSTALL_DEST/install.sh` not created
  - Integration: `test_dry_run_each_script_file_logged` — assert output contains one `[DRY RUN] Would install` line per fixture script file (per-file output assertion — test 14 from brief)
  - Integration: `test_real_mode_scripts_written_correctly` — regression: `DRY_RUN=0`; assert files appear at dest (confirms `move_files` refactor did not break real mode)
  - Checkpoint: `cd /Users/manczg/.claude && INSTALL_SKIP_CLONE=1 INSTALL_FIXTURE_DIR="$fixture_dir" bats tests/test_install_dry_run.bats --filter "scripts_not_written|install_sh_not|each_script|real_mode"`
    *(The `$fixture_dir` variable is created by the test's `setup()` function; the checkpoint runs the whole filtered subset of the test file.)*

#### Task 2.4 — Update `handle_claude_md()` for dry-run output
- [ ] **File**: `install.sh`
- **Depends on**: Task 2.2
- **Description**:
  - Apply the full decision table from the Architecture section. Each branch:

  **Branch 1 — CLAUDE.md absent at dest** (`! -f "$dest"`):
  ```bash
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would copy CLAUDE.md"
    WRITE_COUNT=$(( WRITE_COUNT + 1 ))
    return
  fi
  cp "$staged" "$dest" || { echo "Error: failed to install CLAUDE.md" >&2; exit 1; }
  return
  ```

  **Branch 2 — `--keep-claude-md`, CLAUDE.md exists**: already silent — no change needed.

  **Branch 2b — `--keep-claude-md`, CLAUDE.md absent**: falls through to Branch 1 above (absent check fires first) — no change needed.

  **Branch 3 — `--overwrite`, TTY**:
  ```bash
  if [[ "$DRY_RUN" -eq 1 ]]; then
    local pager="${_INSTALL_PAGER:-less}"
    diff -u "$dest" "$staged" 2>/dev/null | "$pager" || true
    echo "[DRY RUN] Would prompt: Overwrite CLAUDE.md? [y/N]"
    WRITE_COUNT=$(( WRITE_COUNT + 1 ))
    return
  fi
  # ... existing prompt logic unchanged ...
  ```

  **Branch 4 — `--overwrite`, non-TTY**:
  ```bash
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would overwrite CLAUDE.md"
    WRITE_COUNT=$(( WRITE_COUNT + 1 ))
    return
  fi
  cp "$staged" "$dest" || { echo "Error: failed to install CLAUDE.md" >&2; exit 1; }
  ```

  **Branch 5 — default (CLAUDE.md exists, no flags)**:
  ```bash
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would skip CLAUDE.md (use --overwrite to replace)"
    return
  fi
  echo "CLAUDE.md already exists. Re-run with --overwrite to update it."
  ```

  - Note: `handle_claude_md` does NOT use `dry_cp` (messages are branch-specific, not generic); it manages `WRITE_COUNT` directly for the three counting branches.
  - TTY test note: the correct BATS pattern for the TTY branch test is `run timeout 5 bash "$SCRIPT" --dry-run --overwrite` — `timeout` goes INSIDE the `run`, not wrapping `run`.
- **Releasable**: all CLAUDE.md dry-run branches produce correct output; count is accurate for CLAUDE.md.
- **Tests (TDD)** — `tests/test_install_dry_run.bats` (written in Task 1.1):
  - Unit: `test_dry_run_claude_md_absent_prints_would_copy` — no CLAUDE.md at dest; dry-run output contains `[DRY RUN] Would copy CLAUDE.md`
  - Unit: `test_dry_run_claude_md_exists_no_flags_prints_skip_hint` — CLAUDE.md at dest; output contains `[DRY RUN] Would skip CLAUDE.md (use --overwrite to replace)`
  - Unit: `test_dry_run_keep_claude_md_existing_is_silent` — `--keep-claude-md`, CLAUDE.md at dest; no output for CLAUDE.md
  - Unit: `test_dry_run_keep_claude_md_absent_prints_would_copy` — `--keep-claude-md`, no CLAUDE.md; output contains `[DRY RUN] Would copy CLAUDE.md`
  - Unit: `test_dry_run_overwrite_non_tty_prints_would_overwrite` — `--overwrite`, `_INSTALL_IS_TTY=0`; output contains `[DRY RUN] Would overwrite CLAUDE.md`
  - Unit: `test_dry_run_overwrite_tty_shows_diff_and_would_prompt` — `--overwrite`, `_INSTALL_IS_TTY=1`, `_INSTALL_PAGER=cat`; output contains diff content AND `[DRY RUN] Would prompt: Overwrite CLAUDE.md?`; run with `run timeout 5 bash "$SCRIPT" --dry-run --overwrite`
  - Unit: `test_dry_run_claude_md_not_written_in_any_branch` — all 5 branches with `--dry-run`; assert CLAUDE.md not created/modified at dest
  - Checkpoint: `cd /Users/manczg/.claude && INSTALL_SKIP_CLONE=1 INSTALL_FIXTURE_DIR="$fixture_dir" bats tests/test_install_dry_run.bats --filter "claude_md"`
    *(The `$fixture_dir` variable is created by the test's `setup()` function; the checkpoint runs the whole filtered subset of the test file.)*

#### Task 2.5 — Update `main()` to print dry-run summary instead of success messages
- [ ] **File**: `install.sh`
- **Depends on**: Task 2.3, Task 2.4
- **Description**:
  - After `handle_claude_md`, add the conditional summary block:
  ```bash
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo ""
    echo "$WRITE_COUNT file(s) would be installed."
    return
  fi
  ```
  - The existing success lines (`Claude Goodies installed successfully…` and `Restart Claude Code…`) must be inside an `else` block or simply follow the early return — they must NOT print during dry-run
  - The summary prints after `handle_claude_md` (same position as the real success message)
  - `WRITE_COUNT` at this point includes all files counted by `dry_mv`, `dry_cp`, and the CLAUDE.md counting branches
  - Summary line uses a trailing period: `N file(s) would be installed.`
- **Releasable**: end-to-end dry-run works: prints per-file lines, CLAUDE.md branch message, summary count, exits 0. Real mode unchanged.
- **Tests (TDD)** — `tests/test_install_dry_run.bats` (written in Task 1.1):
  - E2E: `test_dry_run_prints_summary_count` — full dry-run with known fixture; assert output ends with `N file(s) would be installed.` (with trailing period) where N matches manifest size
  - E2E: `test_dry_run_summary_excludes_skipped_claude_md` — dry-run without `--overwrite`, CLAUDE.md at dest; assert count = manifest minus 1
  - E2E: `test_dry_run_does_not_print_installed_successfully` — output does NOT contain "installed successfully"
  - E2E: `test_dry_run_exits_0` — exit code is 0
  - E2E: `test_real_mode_still_prints_success_message` — regression: no `--dry-run`; output contains "Claude Goodies installed successfully"
  - Checkpoint: `cd /Users/manczg/.claude && INSTALL_SKIP_CLONE=1 INSTALL_FIXTURE_DIR="$fixture_dir" bats tests/test_install_dry_run.bats --filter "summary|installed_successfully|exits_0|real_mode_still"`
    *(The `$fixture_dir` variable is created by the test's `setup()` function; the checkpoint runs the whole filtered subset of the test file.)*

---

### Phase 3 — Verification & Documentation

#### Task 3.1 — Final verification & documentation update
- [ ] **File**: N/A (agent task)
- **Depends on**: Task 2.5
- **Description**:
  - Spawn an agent to discover all documentation in the project (README, CLAUDE.md, install-prompt.md if still present, any ADRs, plan files, inline comments in `install.sh`) and update every file whose content is affected by this change. At minimum:
    - Confirm `usage()` in `install.sh` documents `--dry-run` (Task 2.1 delivered this; verify)
    - Check if the project README mentions install flags — update if so
    - Check if `install-dry-run-brief.md` should be linked or archived
  - Verify all acceptance criteria below are met before marking complete.
- **Releasable**: feature is fully verified and all documentation reflects the delivered implementation.
- **Acceptance criteria** (must all pass):
  - `./install.sh --help` output includes `--dry-run`
  - `./install.sh --dry-run` (with `INSTALL_SKIP_CLONE=1` + fixture) exits 0 and prints at least one `[DRY RUN] Would install` line
  - `./install.sh --dry-run` does NOT create or modify any file under `$INSTALL_DEST`
  - `./install.sh --dry-run --overwrite` exits 0 with `[DRY RUN] Would overwrite CLAUDE.md` (non-TTY)
  - `./install.sh --dry-run --keep-claude-md` exits 0 with no files written
  - `./install.sh --dryrun` (no hyphen) exits 1 with "Unknown flag" error
  - `./install.sh --dry-run --overwrite --keep-claude-md` exits 1
  - Summary line `"N file(s) would be installed."` (with trailing period) appears and N matches the fixture manifest
  - `bats tests/` runs green (all tests including regression suite)
  - "installed successfully" does NOT appear in dry-run output
- **Tests (TDD)**: N/A — this is a verification and documentation task.
- **Checkpoint**: manually confirm every acceptance criterion above is checked; run `bats tests/` and confirm all pass.
