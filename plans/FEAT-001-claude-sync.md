# FEAT-001 — claude-sync: Config-Driven Git Sync for ~/.claude
**Purpose**: Eliminate manual error in deciding which `~/.claude` files belong in the public repo
**Audience**: Single power user (repo owner), running manually ad-hoc
**Status**: To Do

---

## Background
Managing `~/.claude` as a git repo requires constant judgement about what to track vs ignore vs delete. Without a single authoritative record, files get missed or wrong things get committed. This script makes a config file the single source of truth and automates all git state management from it.

An existing `~/.claude/scripts/claude-sync.sh` handles only untracked-file classification (`r`/`i` states, no `d` state, no full state machine). This plan is a complete rewrite with full state management. The conf file format (`path=state`) is backward-compatible — existing `sync-answers.conf` files will parse correctly, but all currently-tracked files will appear as pending on first run (requiring classification).

## Goal
Running `claude-sync.sh` (optionally with `--dry-run`) always produces a correct, idempotent git state: the right files are tracked, the right are gitignored, pending decisions are surfaced in the report, and the user is prompted for a commit message once before push. Two consecutive runs with no intervening file changes produce no diff and exit "Nothing to commit."

---

## Scope

### In Scope
- Four file states: `r` (repo/tracked), `i` (gitignore), `d` (delete from disk+repo), `` (pending)
- All 12 non-identity state transitions across the 4×4 state matrix
- Drift correction: auto-fix divergence between conf state and actual git/disk state
- Script-owned `.gitignore` sentinel section, fully rebuilt each run
- `--dry-run` mode: full simulation, nothing written
- Single commit per sync run with user-provided message
- Pre-flight: abort with clear message if `trash` is not installed
- Directory entries as single entries (trailing `/`)

### Out of Scope
- Automated/scheduled runs
- Per-file granularity inside directories — one entry represents the whole dir
- Concurrent run safety
- Multi-remote support
- Filenames containing `=`

---

## Acceptance criteria

> Acceptance criteria are verified in the final task. See [Task 6.1 — Final verification & documentation update].

---

## What does NOT change
- Hand-written `.gitignore` entries outside the `# BEGIN claude-sync` / `# END claude-sync` sentinel block
- `sync-answers.conf` itself — never committed, always excluded from scanning and git tracking
- Files not referenced in `sync-answers.conf` — no implicit actions on unclassified files

---

## Known limitations / accepted trade-offs
- Filenames containing `=` are not supported (conf format limitation; accepted as out-of-scope)
- `trash` provides no programmatic restore — recovery from trash is always manual
- Atomicity is per-operation sequential, not transactional; crash mid-run leaves drift that the next run corrects
- `git push` failure leaves a local commit; user retries manually
- Temp files from interrupted runs (matching `*.XXXXXX` in `$CLAUDE_DIR`) may remain after a crash; they are safe to delete manually
- First run after migration from the old script: all tracked files that were not in the old conf will appear as new pending entries. Classification can proceed incrementally.

---

## Architecture

### Script location
- `~/.local/bin/claude-sync.sh` — single bash file, no external dependencies except `bats-core` (dev only) and `trash` (runtime)

### Source guard pattern
```bash
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
```
Allows `source claude-sync.sh` in bats tests to call individual functions without executing `main`.

### Shell conventions
`set -euo pipefail` is set globally. Git helper functions return 0/1/2 as raw exit codes — they do NOT use `|| true` internally.

**Minimum bash version: 4.0** (required for associative arrays via `declare -A`). macOS ships bash 3.2 by default; users must install a newer bash (e.g., via Homebrew: `brew install bash`). Pre-flight check should verify bash version: `[[ ${BASH_VERSINFO[0]} -ge 4 ]] || { echo "ERROR: bash 4.0+ required (found: $BASH_VERSION)"; exit 1; }`

**Array iteration guard (bash 4.0+):** All array iterations over potentially-empty arrays must guard against empty: use `${array[@]+"${array[@]}"}` or check `[[ ${#array[@]} -eq 0 ]]` before iterating. The `"${arr[@]}"` form under `set -u` raises "unbound variable" on bash 4.0-4.3; using `"${arr[@]+"${arr[@]}"}"` is the portable guard.

**Key existence check in write_conf:** to check if a key exists in CONF_STATE regardless of its value (including empty string), use `${CONF_STATE[$path]+exists}` (expands to "exists" if key is set, empty if not). Do NOT use `-n "${CONF_STATE[$path]:-}"` which would silently skip empty-state ('') entries.

**Parallel array iteration (sparse-safe):** All iterations over `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS` MUST use `for i in "${!CONF_ORDER_TYPES[@]}"` (sparse-safe index enumeration). NEVER use `for ((i=0; i<${#CONF_ORDER_TYPES[@]}; i++))` — the compact-range form breaks silently after any `unset CONF_ORDER_TYPES[i]` (holes) because `${#array[@]}` counts SET elements, not the highest index. Since parse_conf deduplication and handle_deleted_files both use `unset` to remove elements, holes are expected at runtime.

**Calling convention for multi-value return codes (0/1/2):**
```bash
# Use the && ... || rc=$? idiom — this is safe under set -e because || always resolves
local rc
git_is_ignored "$path" && rc=0 || rc=$?
case $rc in
  0) ACTUAL_STATE[$path]='ignored' ;;
  1) ;;  # not ignored — continue
  2) log_error "git_is_ignored fatal: $GIT_CHECK_ERR"; exit 1 ;;
esac
```

**For binary calls (success/fail only):**
```bash
if git_is_tracked "$path"; then
  ACTUAL_STATE[$path]='tracked'
fi
```

**For non-zero-tolerant commands (git add, git rm, trash, git restore) in transition functions:**
```bash
git add -- "$path" && rc=0 || rc=$?
if [[ $rc -ne 0 ]]; then
  REPORT_ERRORS+=("$path: git add failed (exit $rc)")
  return
fi
```

This pattern ensures: (a) `set -e` never kills the script on expected non-zero, (b) every error is captured, (c) multi-value codes are distinguished correctly.

### Global state variables
```bash
declare -A CONF_STATE        # path → state ('r','i','d','')
declare -a CONF_ORDER_TYPES  # parallel array: element type ('entry','comment','blank')
declare -a CONF_ORDER_PATHS  # parallel array: path (for 'entry'), verbatim text (for 'comment'), empty (for 'blank')
# CONF_ORDER uses two parallel arrays to avoid type-prefix collision with filenames.
# CONF_ORDER_TYPES[i] is 'entry', 'comment', or 'blank'.
# CONF_ORDER_PATHS[i] is: the conf key (for 'entry'), verbatim line text (for 'comment'), '' (for 'blank').
# Previously a single CONF_ORDER array with prefixes 'E:', 'C:', 'B:' was specified; this has been
# replaced with the parallel-array scheme to eliminate prefix collision with filenames like 'E:something'.
declare -A ACTUAL_STATE      # path → actual git/disk state ('tracked','ignored','untracked','missing')
declare -A CONF_ORDER_PATH_INDEX=()  # lookup set for O(1) membership checks on CONF_ORDER_PATHS; CONF_ORDER_PATH_INDEX[$path]=1 when adding entries
CLAUDE_DIR="$HOME/.claude"
CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
GITIGNORE_FILE="$CLAUDE_DIR/.gitignore"
SENTINEL_BEGIN="# BEGIN claude-sync"
SENTINEL_END="# END claude-sync"
DRY_RUN=false
declare -a REPORT_APPLIED    # "path: old_state → new_state"
declare -a REPORT_DRY_RUN    # "path: would old_state → new_state (dry-run)" — used in DRY_RUN mode only
declare -a REPORT_ERRORS     # "path: error message"
declare -a REPORT_PENDING    # paths with empty state
GIT_CHECK_ERR=""             # captures stderr from git_is_ignored on fatal error
declare -a TMPFILES=()       # temp files registered for cleanup on EXIT trap
declare -a SKIP_PATHS=()     # paths that handle_deleted_files failed to restore; apply_transitions and apply_drift_correction must not process them
```

### Key functions
```bash
reset_globals()                            # reinitialize DRY_RUN=false and ALL global mutable arrays to empty; called first by main()
preflight_check()                          # verify bash version, trash, git repo; abort on failure
parse_conf()                               # read CONF_FILE → CONF_STATE + CONF_ORDER_TYPES + CONF_ORDER_PATHS
write_conf()                               # CONF_STATE + CONF_ORDER_* → CONF_FILE (respects DRY_RUN)
scan_files()                               # stdout: one path per line, dirs as "dir/"
git_is_tracked(path)                       # returns 0=yes 1=no 2=error
git_is_ignored(path)                       # returns 0=yes 1=no 2=error (treats exit 128 as error)
build_actual_state()                       # populates ACTUAL_STATE for all paths
write_sentinel_section()                   # full rebuild of sentinel block in .gitignore
handle_deleted_files()                     # handle paths in CONF_STATE missing from disk+git; called before apply_transitions
apply_transitions()                        # main loop: for each path, compute old→new, call handler
apply_from_r(path, new_state)              # handles r→i, r→d, r→empty
apply_from_i(path, new_state)              # handles i→r, i→d, i→empty
apply_from_d(path, new_state)              # handles d→r, d→i, d→empty
apply_from_empty(path, new_state)          # handles empty→r, empty→i, empty→d
apply_drift_correction(path)               # fix divergence between conf and actual
generate_report()                          # print applied, errors, pending sections
commit_and_push()                          # prompt message+confirm, commit, push
main(args...)                              # arg parse, preflight, parse conf, scan, reconcile, report, commit
```

### Error Handling Policy
- Each file is processed independently. Failures in one file do NOT abort processing of other files.
- Fatal errors (git not a repo, trash not installed, git index corrupt — exit 128): abort entire script immediately.
- Per-file errors (git rm --cached fails, trash fails, git add fails): log to REPORT_ERRORS, leave CONF_STATE unchanged for that file, continue to next file.
- write_conf and write_sentinel_section failures: abort with error (these are idempotent and retryable but indicate serious environment problems).

### Test location
`~/.claude/tests/` — bats test files, one per functional area

### Config file format
```
# comment lines preserved verbatim
relative/path=r
another/path=i
dir/=i
pending/file=
deleted/file=d
```

---

## Task breakdown

### Phase 1 — Foundation: Pre-flight, Config I/O
> **Releasable**: after this phase, the script can safely read, parse, and round-trip rewrite `sync-answers.conf` without corrupting comments or duplicates

#### Task 1.1 — Pre-flight checks
- [x] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: nothing
- **Description**:
  - `preflight_check()` — called first in `main()`; aborts entire script on any failure
  - Checks: (1) `command -v trash >/dev/null 2>&1` — if missing, print `"ERROR: 'trash' is required. Install with: brew install trash"` and `exit 1`
  - Checks: (2) `git -C "$CLAUDE_DIR" rev-parse --git-dir >/dev/null 2>&1` — if fails, print `"ERROR: $CLAUDE_DIR is not a git repository"` and `exit 1`
  - Checks: (3) `[[ ${BASH_VERSINFO[0]} -ge 4 ]]` — if fails, print `"ERROR: bash 4.0+ required. Install with: brew install bash"` and `exit 1`
  - `DRY_RUN` is already set before `preflight_check()` is called; pre-flight runs identically in dry-run mode (no writes happen in this function anyway)
  - **Releasable**: after this task, the script fails fast with clear messages before doing any work
- **Tests (TDD)** — `~/.claude/tests/test_preflight.bats`:
  - Setup: create temp git repo at `$BATS_TMPDIR/test-claude`; manipulate `PATH` to mock presence/absence of `trash`
  - Unit: `test_preflight_fails_without_trash` — remove trash from PATH, assert exit 1 and error message contains "trash"
  - Unit: `test_preflight_fails_outside_git_repo` — run from non-git dir, assert exit 1 and error message contains "git repository"
  - Unit: `test_preflight_passes_with_trash_and_git` — both present, assert exit 0
  - Unit: `test_preflight_runs_in_dry_run_mode` — DRY_RUN=true, assert same behavior
  - Unit: `test_preflight_fails_on_bash_3` — mock BASH_VERSINFO to simulate bash 3; assert exit 1 and error message contains "bash 4.0+"
  - Checkpoint: `bats ~/.claude/tests/test_preflight.bats`

#### Task 1.2 — Config parser
- [x] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 1.1
- **Description**:
  - `parse_conf()` — reads `$CONF_FILE` into `CONF_STATE` and `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS`; safe to call if file does not exist (treats as empty conf)
  - Line format: `key=value` where value is `r`, `i`, `d`, or empty string
  - Comment lines (`#...`) and blank lines are preserved in `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS` as type `'comment'`/`'blank'`
  - Entry lines are stored with type `'entry'` in `CONF_ORDER_TYPES[i]` and the path key in `CONF_ORDER_PATHS[i]`; `CONF_STATE[path]=state`
  - Duplicate entries: last one wins; earlier index for the same path is removed from the parallel arrays, keeping the later one (deduplication on read)
  - Lines with `=` in the path (unsupported filenames) are stored as type `'comment'` (verbatim text) with a warning logged to stderr
  - Encoding: `CONF_ORDER_TYPES[i]` = `'entry'`, `'comment'`, or `'blank'`; `CONF_ORDER_PATHS[i]` = path (for entry), verbatim line text (for comment), `''` (for blank)
  - Path validation in `parse_conf()`: reject entries where the path (a) is absolute (starts with `/`), (b) contains `..` as a path component, or (c) is empty. For any such entry: log a warning `"WARNING: Skipping invalid path: '$path' (contains absolute or traversal component)"`, store as type `'comment'` in `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS` (verbatim line text) to preserve it, and do not add to CONF_STATE.
  - The `..` check is component-based: split the path on `/` and reject if any component is exactly `..`. This prevents both `../../etc` and `foo/../../etc`. The check must NOT reject filenames that merely CONTAIN `..` as a substring (e.g., `file..name.sh` is valid).
  - **CONF_ORDER_PATH_INDEX population**: for each 'entry' line successfully parsed and added to CONF_STATE, set `CONF_ORDER_PATH_INDEX[$path]=1`. When deduplicating (an earlier duplicate is removed from the parallel arrays), the index entry stays (there is only one entry in CONF_ORDER_PATHS after dedup anyway). Invalid paths stored as 'comment' are NOT added to CONF_ORDER_PATH_INDEX.
- **Releasable**: after this task, `CONF_STATE` and `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS` are reliably populated from any valid conf file
- **Tests (TDD)** — `~/.claude/tests/test_conf_io.bats`:
  - Setup: `CONF_FILE="$BATS_TMPDIR/sync-answers.conf"` (override global before sourcing)
  - Unit: `test_parse_empty_file` — empty conf, CONF_STATE empty and CONF_ORDER_TYPES/CONF_ORDER_PATHS both empty arrays
  - Unit: `test_parse_basic_entries` — `scripts/=i\nCLAUDE.md=r`, verify CONF_STATE keys and values
  - Unit: `test_parse_preserves_comments` — `# my comment\nfoo=r`, CONF_ORDER_TYPES includes a 'comment' element for the comment line
  - Unit: `test_parse_deduplicates_last_wins` — `foo=r\nfoo=i`, CONF_STATE[foo]='i', CONF_ORDER_TYPES/CONF_ORDER_PATHS has exactly one 'entry' for 'foo'
  - Unit: `test_parse_empty_state` — `foo=`, CONF_STATE[foo]=''
  - Unit: `test_parse_missing_file` — CONF_FILE doesn't exist, exits cleanly, CONF_STATE empty
  - Unit: `test_parse_rejects_absolute_path` — conf contains `/etc/passwd=r`; assert NOT in CONF_STATE; warning logged
  - Unit: `test_parse_rejects_traversal_path` — conf contains `../../etc/passwd=d`; assert NOT in CONF_STATE; warning logged
  - Unit: `test_parse_rejects_embedded_traversal_path` — conf contains `foo/../../etc/passwd=r`; assert NOT in CONF_STATE; assert it IS stored as a 'comment' entry in CONF_ORDER_TYPES/CONF_ORDER_PATHS; assert warning logged
  - Unit: `test_parse_path_with_space` — `my file.md=r`; assert CONF_STATE["my file.md"]='r'
  - Unit: `test_parse_equals_in_filename_stored_as_comment` — conf contains `key=value.txt=r` (filename with `=`); assert this path is NOT added to CONF_STATE; assert it IS stored as a 'comment' entry in CONF_ORDER_TYPES/CONF_ORDER_PATHS; assert warning logged
  - Unit: `test_parse_rejects_bare_dotdot` — conf contains `..=r`; assert NOT in CONF_STATE; assert warning logged
  - Unit: `test_parse_populates_path_index` — conf contains `foo=r` and `bar=i`; after parse_conf(), assert `CONF_ORDER_PATH_INDEX["foo"]=1` and `CONF_ORDER_PATH_INDEX["bar"]=1`
  - Checkpoint: `bats ~/.claude/tests/test_conf_io.bats`

#### Task 1.3 — Config writer
- [x] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 1.2
- **Description**:
  - `write_conf()` — rewrites `$CONF_FILE` from `CONF_STATE` + `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS`; respects `DRY_RUN` (no-op if true, logs "DRY-RUN: would write conf")
  - Iterate parallel arrays by index: for type `'comment'`, emit `CONF_ORDER_PATHS[i]` verbatim. For type `'blank'`, emit an empty line. For type `'entry'`, emit `path=${CONF_STATE[$path]}` if key exists in CONF_STATE, skip if removed.
  - After iterating `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS`, append any paths in `CONF_STATE` that are not yet represented (new entries added during the run), in alphabetical order. For each appended path, also set `CONF_ORDER_PATH_INDEX[$path]=1`. Note: the second `write_conf` call (post-commit tombstone removal in Task 5.3) may also append new `CONF_ORDER_PATH_INDEX` entries if any paths were added to CONF_STATE after the first `write_conf` call.
  - Writes atomically: create temp file in same directory as target with `TMPFILE=$(mktemp "$CONF_FILE.XXXXXX")`, write content to `$TMPFILE`, then `mv "$TMPFILE" "$CONF_FILE"`. Temp file is in the same directory as target, guaranteeing `mv` is always atomic.
  - Must produce exact round-trip: `parse_conf → write_conf → parse_conf` yields identical `CONF_STATE` and `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS`
- **Releasable**: after this task, conf I/O is complete and round-trip safe
- **Tests (TDD)** — `~/.claude/tests/test_conf_io.bats` (extend same file):
  - Unit: `test_write_round_trip` — Input fixture contains interleaved elements: comment line, entry (`foo=r`), blank line, entry (`bar=i`), comment line. After parse → write → parse: assert CONF_STATE identical AND CONF_ORDER_TYPES identical (same type sequence) AND CONF_ORDER_PATHS identical (same path/text sequence).
  - Unit: `test_write_preserves_comments` — conf with comments, write, read back, comments present in same positions
  - Unit: `test_write_appends_new_entries` — add key to CONF_STATE not yet in CONF_ORDER_TYPES/CONF_ORDER_PATHS, write, verify appended
  - Unit: `test_write_skips_removed_entries` — remove key from CONF_STATE, write, verify absent in output
  - Unit: `test_write_dry_run_no_write` — DRY_RUN=true, call write_conf, assert file unchanged
  - Unit: `test_write_atomic` — verify temp file is gone after write
  - Checkpoint: `bats ~/.claude/tests/test_conf_io.bats`

---

### Phase 2 — Scanner & Git State
> **Releasable**: after this phase, the script can accurately describe the current state of every file under `~/.claude` relative to git

#### Task 2.1 — File system scanner
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 1.1
- **Description**:
  - `scan_files()` — prints one path per line to stdout, relative to `$CLAUDE_DIR`
  - Uses `find "$CLAUDE_DIR" -mindepth 1` with explicit prunes:
    - Prune `.git/`: `-path "$CLAUDE_DIR/.git" -prune`
    - Prune `sync-answers.conf`: skip in post-processing (it's a file, not a dir, so filter in output)
    - Prune `.gitignore` itself from scan output (post-processing, same as `sync-answers.conf`). Rationale: `.gitignore` is managed by the script as part of sentinel section operations and should not appear as a user-classifiable file. If the user wants to track `.gitignore` in git, it is automatically tracked via the script's own sentinel write operation — no conf entry needed.
    - Prune conf-declared directories: for each `path/` in `CONF_STATE` with any state, add `-path "$CLAUDE_DIR/path" -prune -o` so contents are skipped
  - Directory entries from conf are emitted as `dirname/` (trailing slash); their contents are not emitted separately
  - Files are emitted as plain relative paths
  - Symlinks are not followed (`find` default — no `-L`)
  - Output is sorted
  - `sync-answers.conf` and `.gitignore` are excluded from output even if `find` returns them
- **Releasable**: after this task, the scanner correctly identifies all files/dirs respecting directory-boundary suppression
- **Tests (TDD)** — `~/.claude/tests/test_scanner.bats`:
  - Setup: `CLAUDE_DIR="$BATS_TMPDIR/test-claude"`, init git repo, create controlled file tree
  - Unit: `test_scan_excludes_git_dir` — assert `.git/` and its contents not in output
  - Unit: `test_scan_excludes_conf_file` — assert `sync-answers.conf` not in output
  - Unit: `test_scan_directory_entry_suppresses_contents` — CONF_STATE[scripts/]=i, assert `scripts/` in output but `scripts/foo.sh` not in output
  - Unit: `test_scan_emits_files_as_plain_paths` — create `CLAUDE.md`, assert `CLAUDE.md` in output without trailing slash
  - Unit: `test_scan_emits_dirs_with_slash` — create dir `projects/` with files inside and add to CONF_STATE, assert `projects/` in output
  - Unit: `test_scan_symlink_treated_as_file` — create `CLAUDE_DIR/mylink -> /tmp/target`; assert `mylink` appears in scan output as a plain path (not followed, not expanded)
  - Unit: `test_scan_symlink_to_dir_not_descended` — create `CLAUDE_DIR/dirlink -> /tmp/dir`; assert `dirlink` appears in scan but its target contents do not
  - Unit: `test_scan_file_with_space_in_name` — create `CLAUDE_DIR/my file.md`; assert it appears in scan output correctly
  - Unit: `test_scan_excludes_gitignore` — assert `.gitignore` does NOT appear in scan output
  - Unit: `test_scan_broken_symlink` — create `CLAUDE_DIR/deadlink -> /tmp/nonexistent`; assert `deadlink` appears in scan output (broken symlinks are listed, not silently skipped). Note: `find` without `-type f` will list broken symlinks; the test verifies this behavior is intentional.
  - Unit: `test_scan_nested_conf_dirs` — CONF_STATE has `a/=i` (not `a/b/=i`). Filesystem has `a/b/c/file.txt`. Assert only `a/` in scan output, NOT `a/b/` or `a/b/c/file.txt`.
  - Unit: `test_scan_two_hierarchical_conf_dirs` — CONF_STATE has both `a/=i` AND `a/b/=r`. Assert behavior: `a/` pruning takes precedence, `a/b/` does NOT appear separately. Note: nested directory entries where a parent directory is also in CONF_STATE are redundant; the parent prune suppresses all child entries.
  - Checkpoint: `bats ~/.claude/tests/test_scanner.bats`

#### Task 2.2 — Git state helpers
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 1.1
- **Description**:
  - `git_is_tracked(path)` — returns 0=tracked, 1=not tracked, 2=git error
    - Implementation for files: use the `cmd && rc=0 || rc=$?` idiom:
      ```bash
      git -C "$CLAUDE_DIR" ls-files --error-unmatch -- "$path" >/dev/null 2>&1 && rc=0 || rc=$?
      case $rc in
        0) return 0 ;;
        1) return 1 ;;
        *) return 2 ;;  # exit 128 = git fatal error; NOT treated as "not tracked"
      esac
      ```
    - Implementation for directories: use `if/else` to avoid `set -e` killing the function on grep exit 1:
      ```bash
      if git -C "$CLAUDE_DIR" ls-files -- "$path/" | grep -q .; then
        return 0
      else
        return 1
      fi
      ```
      Note: the `if/else` form is safe under `set -e` because the exit code of the `if` condition is never bare; the `| grep -q .` returning 1 (no matches) causes the `else` branch to run, not a script abort.
    - For both files and directories: exit 128 (git fatal error) returns 2. Callers must handle rc=2.
  - `git_is_ignored(path)` — returns 0=ignored, 1=not ignored, 2=git error
    - Implementation: `GIT_CHECK_ERR=$(git -C "$CLAUDE_DIR" check-ignore -q -- "$path" 2>&1)` so that stderr is captured in `GIT_CHECK_ERR` and can be included in error logs.
    - Exit 0 → ignored, exit 1 → not ignored, exit 128 → error (bad path or not a repo)
    - On exit 128: log `$GIT_CHECK_ERR` to stderr and return 2; caller must handle return 2 as fatal
    - Note: stderr is not written to any file; exit code 128 alone is sufficient to detect fatal errors.
  - Both functions work correctly with paths containing spaces (always quoted with `--` separator)
  - Callers MUST use the `cmd && rc=0 || rc=$?` idiom for multi-value return codes. See Shell Conventions for the full calling convention.
  - Return code 2 can occur if git itself errors (not a repo, corrupt index). Callers of `git_is_tracked` must check for rc=2 and treat it as fatal (abort), not as rc=1 (not tracked). This mirrors the existing rc=2 handling for `git_is_ignored`. See Task 2.3 algorithm step 2 for the required caller pattern.
- **Releasable**: after this task, git state can be queried safely for any path
- **Tests (TDD)** — `~/.claude/tests/test_git_helpers.bats`:
  - Setup: temp git repo, create and commit a file, gitignore another
  - Unit: `test_tracked_file_returns_0` — committed file, assert git_is_tracked returns 0
  - Unit: `test_untracked_file_returns_1` — new file not yet added, assert returns 1
  - Unit: `test_ignored_file_returns_0_for_git_is_ignored` — file matching .gitignore pattern, assert 0
  - Unit: `test_non_ignored_file_returns_1` — normal file, assert git_is_ignored returns 1
  - Unit: `test_git_is_ignored_distinguishes_error_from_not_ignored` — run outside git repo, assert returns 2
  - Unit: `test_script_survives_untracked_file_scan` — run `build_actual_state` against a repo where 5 of 10 files are untracked; assert script exits 0 and all 10 files have correct ACTUAL_STATE values (not just the first untracked one)
  - Unit: `test_tracked_directory_returns_0` — create `somedir/` with files, git add and commit; assert `git_is_tracked "somedir/"` returns 0
  - Unit: `test_partially_tracked_directory_returns_0` — create `somedir/` with 3 files, git add only 1; assert `git_is_tracked "somedir/"` returns 0 (at least one tracked file)
  - Unit: `test_empty_directory_returns_1` — empty dir (git doesn't track empty dirs); assert `git_is_tracked "emptydir/"` returns 1
  - Unit: `test_untracked_directory_returns_1_without_crashing` — create dir with untracked files only (no git add); call `git_is_tracked "somedir/"`; assert return value is 1 (not tracked) AND script does not crash (set -e safety check). This tests the `if/else` implementation of the directory variant under `set -euo pipefail`.
  - Checkpoint: `bats ~/.claude/tests/test_git_helpers.bats`

#### Task 2.3 — Actual state builder
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 2.1, Task 2.2
- **Description**:
  - `build_actual_state()` — populates `ACTUAL_STATE[path]` for every path returned by `scan_files()`
  - Also includes any paths in `CONF_STATE` not returned by scan (for deleted-file handling)
  - State values: `tracked` (git ls-files knows it), `ignored` (git check-ignore says yes), `untracked` (exists on disk, not tracked, not ignored), `missing` (not on disk at all)
  - Algorithm per path:
    1. If path missing from disk → `missing`
    2. `git_is_tracked "$path" && rc=0 || rc=$?`
       - rc=0 → `ACTUAL_STATE[$path]='tracked'`; continue
       - rc=2 → `log_error "git_is_tracked fatal for $path"`; exit 1
       - rc=1 → fall through to step 3
    3. `git_is_ignored "$path" && rc=0 || rc=$?`
       - rc=0 → `ACTUAL_STATE[$path]='ignored'`; continue
       - rc=2 → `log_error "git_is_ignored fatal: $GIT_CHECK_ERR"`; exit 1
       - rc=1 → fall through to step 4
    4. Otherwise → `ACTUAL_STATE[$path]='untracked'`
  - Abort means: print error, exit 1
- **Releasable**: after this task, the full picture of actual vs desired state is available
- **Tests (TDD)** — `~/.claude/tests/test_scanner.bats` (extend):
  - Unit: `test_actual_state_tracked` — committed file → ACTUAL_STATE='tracked'
  - Unit: `test_actual_state_ignored` — file matching sentinel → ACTUAL_STATE='ignored'
  - Unit: `test_actual_state_untracked` — new file, not ignored → ACTUAL_STATE='untracked'
  - Unit: `test_actual_state_missing` — conf has path but file deleted → ACTUAL_STATE='missing'
  - Unit: `test_build_actual_state_aborts_on_git_error` — mock `git check-ignore` to return exit 128; call `build_actual_state()`; assert script exits 1 with an error message containing the path
  - Checkpoint: `bats ~/.claude/tests/test_scanner.bats`

---

### Phase 3 — Sentinel Section Management
> **Releasable**: after this phase, the sentinel section in `.gitignore` can be safely rebuilt from conf without corrupting hand-written entries

#### Task 3.1 — Sentinel section writer
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 1.3
- **Description**:
  - `write_sentinel_section()` — fully rebuilds the `# BEGIN claude-sync` / `# END claude-sync` block in `$GITIGNORE_FILE`; respects `DRY_RUN`
  - Algorithm:
    1. If `$GITIGNORE_FILE` does not exist, treat as empty: `before_lines=()`, `after_lines=()`, and proceed to write the sentinel block. The function creates `.gitignore` if it does not exist.
    2. If file exists, read it line by line into `before_lines[]` (lines before sentinel), `after_lines[]` (lines after sentinel); discard old sentinel content entirely
    3. If no sentinel exists yet in an existing file, `before_lines` = full file, `after_lines` = empty
    4. Build `sentinel_lines[]`: one entry per path in `CONF_STATE` where `state == 'i'`, sorted alphabetically. Before writing each path to the sentinel, escape gitignore metacharacters: prepend `\` before `[`, `]`, `?`, `*`. If path starts with `#`, prepend `\`. If path starts with `!`, prepend `\`. If path starts with a space, prepend `\`. This ensures paths with special characters produce correct `.gitignore` entries that match only the intended path.
    5. Write: `before_lines` + blank line (if before_lines non-empty and doesn't end with blank) + `# BEGIN claude-sync` + sentinel entries + `# END claude-sync` + after_lines
    6. Atomic write: create temp file in same directory with `TMPFILE=$(mktemp "$GITIGNORE_FILE.XXXXXX")`, write content to `$TMPFILE`, then `mv "$TMPFILE" "$GITIGNORE_FILE"`. Temp file is in the same directory as target, guaranteeing `mv` is always atomic.
  - If `CONF_STATE` has no `i` entries, the sentinel block is written empty (just begin/end markers) — never omitted entirely (idempotency)
  - Hand-written lines outside the sentinel are never modified
  - The sentinel parser MUST handle `.gitignore` files with no trailing newline. Use `while IFS= read -r line || [[ -n "$line" ]]; do` (the `|| [[ -n "$line" ]]` catches the last line when no trailing newline is present).
- **Releasable**: after this task, `.gitignore` sentinel management is safe and idempotent
- **Tests (TDD)** — `~/.claude/tests/test_sentinel.bats`:
  - Setup: `GITIGNORE_FILE="$BATS_TMPDIR/.gitignore"`, `CONF_STATE` populated manually, git repo initialized at `$BATS_TMPDIR` with `git init`
  - Unit: `test_sentinel_created_from_scratch` — no prior .gitignore, CONF_STATE has one `i` entry, assert sentinel block written with that entry
  - Unit: `test_sentinel_creates_gitignore_if_not_exists` — no `.gitignore` present, call `write_sentinel_section()`, assert `.gitignore` created with sentinel block
  - Unit: `test_sentinel_replaces_existing_block` — existing sentinel with stale entries, new CONF_STATE, assert only new entries present
  - Unit: `test_sentinel_preserves_lines_before` — hand-written lines before sentinel survive unchanged
  - Unit: `test_sentinel_preserves_lines_after` — hand-written lines after sentinel survive unchanged
  - Unit: `test_sentinel_empty_block_when_no_i_entries` — CONF_STATE has no `i`, assert begin/end markers present, no entries between them
  - Unit: `test_sentinel_dry_run_no_write` — DRY_RUN=true, assert .gitignore unchanged
  - Unit: `test_sentinel_idempotent` — run twice, assert .gitignore identical after both runs
  - Unit: `test_sentinel_escapes_metacharacters` — Initialize git repo at BATS_TMPDIR; create test files with metacharacter names; call `write_sentinel_section()`; assert each path is written with correct `\\` escaping; run `git -C $BATS_TMPDIR check-ignore -- <path>` to verify escaped pattern matches the intended file.
  - Unit: `test_sentinel_parses_file_without_trailing_newline` — `.gitignore` has sentinel at EOF with no trailing newline after `# END claude-sync`; assert `write_sentinel_section` reads BEGIN/END markers correctly and preserves all content outside the sentinel; assert no duplication on second run.
  - Checkpoint: `bats ~/.claude/tests/test_sentinel.bats`

---

### Phase 4 — State Transitions
> **Releasable**: after each task, the corresponding source-state transitions are fully executable; after the full phase, all 12 non-identity transitions plus drift correction work correctly

#### Task 4.1 — Transitions from `r`
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 2.2, Task 3.1
- **Description**:
  - `apply_from_r(path, new_state)` — `new_state` ∈ `{i, d, ''}`
  - **r → i**: `git rm --cached [-r for dirs] -- "$path"` + update `CONF_STATE[path]='i'`; sentinel rebuild happens at end of full run via `write_sentinel_section()`
  - **r → d**: `git rm --cached [-r] -- "$path"` + `trash "$CLAUDE_DIR/$path"` (or `trash` the dir). Keep `CONF_STATE[path]='d'` as tombstone. On `trash` failure: log error, skip trash, keep `d` in conf.
  - **r → empty**: `git rm --cached [-r] -- "$path"`. Log warning: "Staging deletion of $path — this will remove it from the repo on next commit." Update `CONF_STATE[path]=''`. The commit prompt will surface this.
  - For all: detect dir vs file by trailing `/` in path; use `-r` flag for git operations on dirs
  - In `DRY_RUN`: log intended action to `REPORT_DRY_RUN` with `(dry-run)` suffix, skip all git/trash operations, do NOT update CONF_STATE in memory (preserves real state for accurate second-run comparison)
  - On `git rm --cached` failure: log error to `REPORT_ERRORS`, skip transition, leave CONF_STATE unchanged
  - **Error handling pattern**: All `git` and `trash` commands in transition functions MUST use the `cmd && rc=0 || rc=$?` pattern (see Shell Conventions). Example: `git rm --cached -- "$path" && rc=0 || rc=$?; if [[ $rc -ne 0 ]]; then REPORT_ERRORS+=(...); return; fi`. This applies to ALL git and trash calls throughout Tasks 4.1–4.4 and 5.4.
- **Releasable**: after this task, all `r →` transitions are safe to invoke
- **Tests (TDD)** — `~/.claude/tests/test_transitions_r.bats`:
  - Setup: temp git repo with committed test files; mock `trash` with a shell function that records calls
  - Unit: `test_r_to_i_unstages_file` — run apply_from_r path i, assert `git ls-files` no longer shows path; CONF_STATE='i'
  - Unit: `test_r_to_d_unstages_and_trashes` — assert git unstaged AND mock trash called with correct path; CONF_STATE='d' (tombstone)
  - Unit: `test_r_to_d_trash_failure_leaves_tombstone` — mock trash returns 1, assert CONF_STATE still 'd', error logged
  - Unit: `test_r_to_empty_stages_deletion_with_warning` — CONF_STATE='', warning in REPORT_ERRORS or report log
  - Unit: `test_r_transitions_dir_uses_recursive_flag` — path ending `/`, assert `git rm --cached -r`
  - Unit: `test_r_transitions_dry_run_no_git_ops` — DRY_RUN=true, assert git repo unchanged, CONF_STATE NOT modified (still 'r'), intended action present in REPORT_DRY_RUN
  - Unit: `test_r_to_i_path_with_space` — `git rm --cached` on a path with space; assert success
  - Checkpoint: `bats ~/.claude/tests/test_transitions_r.bats`

#### Task 4.2 — Transitions from `i`
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 4.1
- **Description**:
  - `apply_from_i(path, new_state)` — `new_state` ∈ `{r, d, ''}`
  - **i → r**: Run `git add -f -- "$CLAUDE_DIR/$path"` first (force-add bypasses gitignore at the git level regardless of CONF_STATE value). Check rc: only if rc=0, update `CONF_STATE[path]='r'`. On failure: log error to REPORT_ERRORS, leave CONF_STATE='i'. The sentinel section will be rebuilt at the end of `apply_transitions()` (excluding this path since its state is now 'r'), after which the path is no longer gitignored. For directories: `git add -f -- "$CLAUDE_DIR/$path/"` (recursive add, force). Note: this stages all currently-existing files in the directory.
  - **i → d**: update `CONF_STATE[path]='d'`; `trash "$CLAUDE_DIR/$path"`. Sentinel rebuild at end removes the `i` entry. Tombstone stays until commit.
  - **i → empty**: update `CONF_STATE[path]=''`. Sentinel rebuild removes the `i` entry. File becomes untracked — will appear as pending on next scan.
  - `git add -f` failure (file missing from disk): log error to `REPORT_ERRORS`; CONF_STATE stays `'i'` (never updated since operation failed)
  - Same DRY_RUN behavior as Task 4.1: log to REPORT_DRY_RUN with `(dry-run)` suffix; do NOT update CONF_STATE
  - Error handling: use `cmd && rc=0 || rc=$?` pattern per Shell Conventions and Task 4.1 error handling pattern.
- **Releasable**: after this task, all `i →` transitions are safe to invoke
- **Tests (TDD)** — `~/.claude/tests/test_transitions_i.bats`:
  - Setup: temp git repo with files in gitignored state (sentinel section in .gitignore)
  - Unit: `test_i_to_r_adds_to_git` — after transition, `git ls-files` shows path; CONF_STATE='r'
  - Unit: `test_i_to_r_uses_force_add` — assert `git add -f` is called (not plain `git add`) for i→r transitions
  - Unit: `test_i_to_d_trashes_file` — mock trash called; CONF_STATE='d'; file no longer in sentinel
  - Unit: `test_i_to_empty_removes_from_conf_state` — CONF_STATE=''; file stays on disk
  - Unit: `test_i_to_r_git_add_failure_reverts_state` — file missing from disk; git add -f fails; assert CONF_STATE remains 'i' (never updated), error logged
  - Unit: `test_i_transitions_dry_run` — DRY_RUN=true, git and trash not invoked; assert CONF_STATE[path] remains 'i' (not updated to 'r')
  - Checkpoint: `bats ~/.claude/tests/test_transitions_i.bats`

#### Task 4.3 — Transitions from `d`
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 4.1
- **Description**:
  - `apply_from_d(path, new_state)` — `new_state` ∈ `{r, i, ''}`
  - **d → r**:
    - If file exists on disk: `git add -- "$CLAUDE_DIR/$path"`. CONF_STATE='r'.
    - If file missing but was committed: `git restore --source=HEAD -- "$CLAUDE_DIR/$path"` then `git add`. CONF_STATE='r'. `--source=HEAD` is required because the file may have been removed from the git index via `git rm --cached`. Restoring from the index would fail for such files.
    - If file missing and never committed: log error `"Cannot restore $path — recover manually from ~/.Trash/ and re-run"`. Leave CONF_STATE='d'.
  - **d → i**:
    - If file exists on disk: update CONF_STATE='i'. Sentinel rebuild adds the entry at end of run.
    - **d → i when file is missing: BLOCKED.** Log error: `'Cannot transition $path from d to i: file is gone. To restore: change state to r. To clear the entry: change state to empty.'` Leave CONF_STATE='d'. Do NOT update CONF_STATE to 'i'. **Rationale**: This is an intentional departure from the original brief, which proposed adding the sentinel entry anyway. This plan blocks the transition because ignoring a deleted file serves no purpose and may mask a user error. The user should either restore the file (change state to 'r') or clear the entry (change state to '').
  - **d → empty**:
    - If file exists on disk: leave it. CONF_STATE=''.
    - If file missing but committed: `git restore --source=HEAD -- "$CLAUDE_DIR/$path"`. CONF_STATE=''. `--source=HEAD` is required because the file may have been removed from the git index.
    - If file missing and never committed: log error (same as d→r case). Leave CONF_STATE='d'.
  - `git restore` is the preferred command (not deprecated `git checkout --`).
  - Error handling: use `cmd && rc=0 || rc=$?` pattern per Shell Conventions and Task 4.1 error handling pattern.
- **Releasable**: after this task, all `d →` transitions are safe to invoke
- **Tests (TDD)** — `~/.claude/tests/test_transitions_d.bats`:
  - Setup: temp git repo; test cases create files in various states (committed, never committed, already trashed)
  - Unit: `test_d_to_r_file_exists_adds_to_git` — file on disk, assert git adds it; CONF_STATE='r'
  - Unit: `test_d_to_r_file_missing_but_committed_restores_and_adds` — trash file, assert git restore + git add; CONF_STATE='r'
  - Unit: `test_d_to_r_never_committed_logs_error` — file gone and never committed; CONF_STATE stays 'd'; error logged
  - Unit: `test_d_to_i_file_exists_updates_conf` — CONF_STATE='i'; sentinel will pick it up
  - Unit: `test_d_to_i_missing_file_is_blocked` — CONF='d', file missing; call apply_from_d(path, 'i'); assert CONF_STATE stays 'd'; assert error logged with guidance
  - Unit: `test_d_to_empty_file_missing_committed_restores` — git restore --source=HEAD called; CONF_STATE=''
  - Unit: `test_d_transitions_dry_run` — DRY_RUN=true, no git/trash ops; assert CONF_STATE[path] remains 'd'
  - Checkpoint: `bats ~/.claude/tests/test_transitions_d.bats`

#### Task 4.4 — Transitions from `empty`
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 4.1
- **Description**:
  - `apply_from_empty(path, new_state)` — `new_state` ∈ `{r, i, d}`
  - **empty → r**: `git add -- "$CLAUDE_DIR/$path"`. CONF_STATE='r'. Remove from sentinel if somehow present.
  - **empty → i**: CONF_STATE='i'. Sentinel rebuild adds the entry. File stays on disk.
  - **empty → d**: check `git ls-files -- "$path"` first — if tracked, also run `git rm --cached`. Then `trash "$CLAUDE_DIR/$path"`. CONF_STATE='d' as tombstone.
  - `git add` failure on `empty → r`: log error, leave CONF_STATE=''
  - Error handling: use `cmd && rc=0 || rc=$?` pattern per Shell Conventions and Task 4.1 error handling pattern.
- **Releasable**: after this task, all 12 non-identity transitions are implemented
- **Tests (TDD)** — `~/.claude/tests/test_transitions_empty.bats`:
  - Unit: `test_empty_to_r_adds_to_git` — assert tracked; CONF_STATE='r'
  - Unit: `test_empty_to_i_updates_conf_file_stays` — file on disk; CONF_STATE='i'; git not invoked
  - Unit: `test_empty_to_d_untracked_trashes` — untracked file; mock trash called; CONF_STATE='d'
  - Unit: `test_empty_to_d_tracked_unstages_then_trashes` — `git rm --cached` then trash; CONF_STATE='d'
  - Unit: `test_empty_to_r_git_add_failure_leaves_empty` — file missing; CONF_STATE=''
  - Unit: `test_empty_transitions_dry_run` — DRY_RUN=true, nothing written; assert CONF_STATE[path] remains ''
  - Checkpoint: `bats ~/.claude/tests/test_transitions_empty.bats`

#### Task 4.5 — Drift correction
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 2.3, Task 4.1, Task 4.2, Task 4.3, Task 4.4
- **Description**:
  - `apply_drift_correction(path)` — called **inside** `apply_transitions()`, per-path. It verifies the actual git/disk state matches the conf-expected state and corrects any divergence.
  - All checks in `apply_drift_correction` query git/disk state live (not from ACTUAL_STATE), since ACTUAL_STATE may be stale after the apply_from_X call.
  - **Calling frequency**: `apply_drift_correction` is called for EVERY path in CONF_STATE where state is 'r', 'i', or 'd', regardless of whether a transition occurred. This ensures stable-state drift (e.g., a file that should be tracked but was manually `git rm --cached`'d between runs) is always corrected. See Task 5.1 for the dispatch logic.
  - **SKIP_PATHS**: If a path is in `SKIP_PATHS`, do not run drift correction for it. `SKIP_PATHS` is populated by `handle_deleted_files()` for paths that failed to restore.
  - Cases:
    - CONF='r', ACTUAL='untracked' (file exists but not tracked): `git add -- "$CLAUDE_DIR/$path" && rc=0 || rc=$?`; if rc != 0, log error
    - CONF='r', ACTUAL='missing': `git restore --source=HEAD -- "$CLAUDE_DIR/$path"` (see deleted-file handling from brief). `--source=HEAD` is required because the file may have been removed from the git index.
    - CONF='r', ACTUAL='ignored': Log warning `"Warning: $path is gitignored but conf says r — this may indicate a sentinel corruption or a conflict with a hand-written .gitignore entry. Running git add -f to force-track per conf."` Then `git add -f "$CLAUDE_DIR/$path" && rc=0 || rc=$?`; if rc != 0, log error.
    - CONF='i', ACTUAL not in sentinel: `write_sentinel_section()` will fix this at end of run; no per-file action needed
    - CONF='d', ACTUAL='tracked': Run `git rm --cached -- "$CLAUDE_DIR/$path" && rc=0 || rc=$?`; if rc != 0, log error. Then `trash "$CLAUDE_DIR/$path" && rc=0 || rc=$?`. If only trash fails, log error. CONF_STATE stays 'd'.
    - CONF='d', ACTUAL='untracked': `trash "$CLAUDE_DIR/$path" && rc=0 || rc=$?`; if rc != 0, log error. (No git rm needed — file is already not tracked.) **This case covers both drift from a prior crash AND recovery from a partial apply_from_r/apply_from_i/apply_from_empty failure where `git rm --cached` succeeded but `trash` failed. In all cases: attempt trash again.**
    - CONF='r', live check shows file is tracked: no action (stable state; file is in git as expected)
    - CONF='i', live check shows file is gitignored: no action (stable state)
    - CONF='d', file not on disk AND not in git index: no action (stable state; tombstone cleanup handled by two-phase write in commit_and_push)
    - CONF='', any state: no action — the scan will have already added it to REPORT_PENDING
    - Any combination not listed above: log warning `"Unexpected state for $path: conf=$conf_state, actual=<live>; no action taken"` to REPORT_ERRORS and take no action
  - Drift correction is **not** a substitute for explicit transitions; it is a safety net for partial-run recovery
  - All corrections are logged to `REPORT_APPLIED` with note "(drift corrected)"
- **Releasable**: after this task, idempotency guarantee holds even after crash mid-run
- **Tests (TDD)** — `~/.claude/tests/test_drift.bats`:
  - Unit: `test_drift_r_tracked_is_noop` — CONF='r', file committed and tracked; call `apply_drift_correction(path)`; assert NO git commands executed; assert REPORT_APPLIED does NOT contain this path.
  - Unit: `test_drift_r_untracked_adds_file` — CONF='r', file on disk untracked; assert git add called
  - Unit: `test_drift_r_missing_restores_file` — CONF='r', file deleted; assert git restore called
  - Unit: `test_drift_r_ignored_force_adds_with_warning` — CONF='r', ACTUAL='ignored'; assert warning is logged AND git add -f called
  - Unit: `test_drift_d_file_still_exists_trashes` — CONF='d', file on disk; assert trash called
  - Unit: `test_drift_empty_no_action` — CONF='', any actual state; assert no git/trash operations
  - Unit: `test_drift_i_no_per_file_action` — CONF='i', actual not in sentinel; assert no git calls (sentinel handled globally)
  - Unit: `test_drift_d_unstaged_file_retries_trash` — set up committed file; run `git rm --cached` manually (simulating partial r→d where git rm succeeded but trash failed); set CONF_STATE='d'; file still on disk. Call `apply_drift_correction()`. Assert trash was called. Assert REPORT_APPLIED contains "(drift corrected)".
  - Checkpoint: `bats ~/.claude/tests/test_drift.bats`

---

### Phase 5 — Orchestration, Reporting & CLI
> **Releasable**: after this phase, the complete script is functional end-to-end

#### Task 5.1 — Transition dispatcher (`apply_transitions`)
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 4.5
- **Description**:
  - `apply_transitions()` — main reconcile loop; iterates all paths from union of `scan_files()` output and `CONF_STATE` keys
  - **ACTUAL_STATE is NOT rebuilt during or after transitions.** Transition functions may change git/disk state, but ACTUAL_STATE reflects the state from the initial scan only. Drift correction (called after each apply_from_X) re-queries git state via `git_is_tracked` / `git_is_ignored` directly rather than reading from ACTUAL_STATE — this ensures drift correction sees current state, not the stale snapshot.
  - **SKIP_PATHS**: skip any path in the `SKIP_PATHS` array entirely (do not call apply_from_X or apply_drift_correction for it).
  - For each path:
    1. Determine `conf_state = CONF_STATE[$path]` (default '' if not in conf)
    2. Determine `actual_state = ACTUAL_STATE[$path]`
    3. Skip path if it is in `SKIP_PATHS`
    4. Add new paths (conf_state='', not yet in CONF_ORDER_PATH_INDEX) to `CONF_STATE` and append to `CONF_ORDER_TYPES`/`CONF_ORDER_PATHS` as pending 'entry'; set `CONF_ORDER_PATH_INDEX[$path]=1`; add to `REPORT_PENDING`. To check membership: use `${CONF_ORDER_PATH_INDEX[$path]+exists}` (O(1) lookup via the CONF_ORDER_PATH_INDEX associative array). Do NOT scan CONF_ORDER_PATHS linearly for membership checks — use the index.
    5. Dispatch logic:
       - Determine source_state: map actual_state to conf-equivalent:
         - actual='tracked'   → source_state='r'
         - actual='ignored'   → source_state='i'
         - actual='untracked' → source_state='empty'
         - actual='missing'   → source_state='empty' (treat as if nothing is there)
       - If source_state == conf_state (identity): skip dispatch (no apply_from_X call).
         Exception: conf='d' is never equal to source_state (no stable actual state maps to 'd'), so conf='d' is handled differently — see below.
       - If source_state != conf_state: dispatch to `apply_from_{source_state}(path, conf_state)`.
         This calls the function for the CURRENT state and passes the DESIRED state.
       - Special case for conf='d':
         - actual='tracked' → dispatch `apply_from_r(path, 'd')`
         - actual='untracked' → dispatch `apply_from_empty(path, 'd')`
         - actual='missing' → skip dispatch entirely (file is already gone; drift correction and tombstone removal handle git-index cleanup if needed)
       - Skip dispatch entirely if conf_state is empty/pending ('')
    6. Call `apply_drift_correction(path)` for EVERY path where conf_state is 'r', 'i', or 'd' — regardless of whether apply_from_X was called. This catches stable-state drift (e.g., CONF='r', actual='tracked' but then manually unstaged between runs). Drift correction skips paths in SKIP_PATHS.
    7. Log result to `REPORT_APPLIED` or `REPORT_ERRORS`
  - **DRY_RUN behavior**: In DRY_RUN mode, do NOT update CONF_STATE or ACTUAL_STATE. Instead, add planned actions to `REPORT_DRY_RUN` with a `(dry-run)` suffix. write_conf and write_sentinel_section already no-op in DRY_RUN; CONF_STATE must also NOT be modified so that post-loop logic does not branch as-if operations succeeded.
  - After loop: call `write_sentinel_section()` once (full rebuild)
  - After sentinel: call `write_conf()` (first conf rewrite — pre-commit)
  - New paths are added to `REPORT_PENDING` (they need a conf edit and re-run)
- **Releasable**: after this task, the full reconcile cycle can be driven end-to-end
- **Tests (TDD)** — `~/.claude/tests/test_orchestration.bats`:
  - Integration: `test_new_file_added_as_pending` — scan finds file not in conf; REPORT_PENDING contains it; CONF_STATE[path]=''
  - Integration: `test_transition_r_to_i_full_cycle` — conf says i, file was r; after apply_transitions: not tracked, in sentinel
  - Integration: `test_idempotent_second_run` — run apply_transitions twice with no file changes; REPORT_APPLIED empty on second run
  - Integration: `test_partial_failure_does_not_corrupt_conf` — set up 3 transitions; mock the second one to fail (git rm --cached returns error); assert: (a) first transition applied successfully, (b) second transition logged as error in REPORT_ERRORS, (c) third transition applied successfully, (d) conf written with first and third transitions reflected, second left in original state.
  - Integration: `test_multi_state_coexistence` — set up 4 files in repo: fileA (CONF='i', was 'r' → i transition needed), fileB (CONF='r', was 'i' → r transition needed), fileC (CONF='', new file → pending), fileD (CONF='d', exists on disk → delete needed). Run `apply_transitions()`. Assert: fileA not in git index and in sentinel; fileB in git index and not in sentinel; fileC in REPORT_PENDING; fileD trashed and CONF_STATE='d' (tombstone). Assert CONF_STATE has exactly the expected values for each file.
  - Integration: `test_skip_paths_prevents_transition_and_drift` — set up CONF='r' path that cannot be restored (never committed, file deleted); call `handle_deleted_files()` (populates SKIP_PATHS); call `apply_transitions()`; assert neither `apply_from_r` nor `apply_drift_correction` was invoked for that path (mock or trace); assert path remains in CONF_STATE with state 'r'.
  - Checkpoint: `bats ~/.claude/tests/test_orchestration.bats`

#### Task 5.2 — Report generator
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 5.1
- **Description**:
  - `generate_report()` — prints structured output to stdout after transitions complete
  - Sections (always printed, even if empty):
    ```
    === Applied ===
    CLAUDE.md: '' → r (added to repo)
    scripts/: r → i (gitignored)
    
    === Errors ===
    broken/file.sh: git rm --cached failed (exit 1)
    
    === Pending (need conf edit + re-run) ===
    new-file.sh
    new-dir/
    ```
  - Pending section is always printed before commit prompt (even with zero entries); zero entries prints "  (none)"
  - Transition descriptions use human-readable labels: `r`="in repo", `i`="gitignored", `d`="deleted", `''`="pending"
  - **DRY_RUN mode**: In DRY_RUN mode, the `=== Applied ===` section is replaced with `=== Would Apply (dry-run) ===` and reads from REPORT_DRY_RUN instead of REPORT_APPLIED. REPORT_APPLIED is not printed in dry-run mode.
- **Releasable**: after this task, the user sees a clear picture of what happened and what still needs classification
- **Tests (TDD)** — `~/.claude/tests/test_report.bats`:
  - Unit: `test_report_shows_applied_transitions` — populate REPORT_APPLIED, assert output contains path and states
  - Unit: `test_report_shows_errors` — populate REPORT_ERRORS, assert error section present
  - Unit: `test_report_pending_always_printed` — empty REPORT_PENDING, assert "(none)" in pending section
  - Unit: `test_report_pending_lists_files` — populate REPORT_PENDING, assert files listed
  - Unit: `test_report_dry_run_shows_dry_run_actions` — populate REPORT_DRY_RUN with entries, set DRY_RUN=true, call `generate_report()`; assert output contains "=== Would Apply (dry-run) ===" header and "(dry-run)" entries; assert "=== Applied ===" is NOT present.
  - Checkpoint: `bats ~/.claude/tests/test_report.bats`

#### Task 5.3 — Commit and push
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 5.2
- **Description**:
  - `commit_and_push()` — called after `generate_report()`; skipped entirely in `DRY_RUN` mode
  - Check for staged changes: `git -C "$CLAUDE_DIR" diff --cached --quiet`; if no staged changes, print "Nothing to commit." and return
  - Prompt: `read -r -p "Commit message: " commit_msg`; if empty, print "Aborted." and return
  - Confirm: `read -r -p "Push to remote? [y/N] " confirm`
  - Commit: `git -C "$CLAUDE_DIR" commit -m "$commit_msg"`
  - **Two-phase conf write**: after successful commit, call `write_conf()` again to remove `d` tombstones. For each path in CONF_STATE where state='d': if `[[ ! -e "$CLAUDE_DIR/$path" ]]` AND the file is not in the git index (`git -C "$CLAUDE_DIR" ls-files -- "$path"` returns empty output), remove the entry from CONF_STATE, CONF_ORDER_TYPES/CONF_ORDER_PATHS, AND `unset 'CONF_ORDER_PATH_INDEX[$path]'`. Do NOT use ACTUAL_STATE for this check — ACTUAL_STATE was populated at the start of the run and does not reflect deletions performed during this run. Only the live filesystem and git index check is authoritative here.
  - **Directory tombstone persistence**: For directory entries ('dir/'), the git ls-files check returns all tracked files under the directory. If a partial `git rm --cached -r` left some files in the index, the tombstone persists until drift correction on the next run clears the remaining tracked files. This is self-healing: at most one additional run is needed.
  - Push (if confirmed): `git -C "$CLAUDE_DIR" push`; on failure, print `"Push failed. Commit is local — push manually when ready."`; exit 0 (not an error)
  - If user declines push: print "Commit created. Push manually when ready."
- **Releasable**: after this task, the full sync cycle is complete including git history
- **Tests (TDD)** — `~/.claude/tests/test_commit.bats`:
  - Setup: temp git repo with staged changes
  - Unit: `test_nothing_to_commit_when_no_staged_changes` — no staged changes; assert "Nothing to commit" printed; no commit created
  - Unit: `test_empty_message_aborts` — simulate empty input; assert no commit
  - Unit: `test_commit_created_with_message` — provide message; assert `git log` shows commit with that message
  - Unit: `test_d_tombstones_removed_from_conf_after_commit` — Set up file with CONF='d'; file exists and is tracked at scan time (ACTUAL_STATE deliberately set to 'tracked', simulating a stale snapshot). Run `apply_transitions` (trashes file, git rm --cached). Commit. Assert tombstone IS removed from CONF_STATE — proving the post-commit check uses live filesystem (not stale ACTUAL_STATE='tracked'). This test would FAIL if the implementation used ACTUAL_STATE instead of the live check.
  - Unit: `test_push_failure_does_not_error` — mock `git push` to return 1; assert script exits 0
  - Unit: `test_dry_run_skips_commit` — DRY_RUN=true; assert no commit created
  - Unit: `test_d_tombstone_persists_when_no_commit` — set CONF_STATE['file']='d', file trashed; run through apply_transitions (first write_conf); do NOT commit (simulate user aborting); on next run parse_conf, assert 'd' is still in CONF_STATE; assert second run still attempts trash (drift correction)
  - Checkpoint: `bats ~/.claude/tests/test_commit.bats`

#### Task 5.4 — Deleted file handling at scan time
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 2.3
- **Description**:
  - `handle_deleted_files()` — called by `main()` in execution step 5, before `apply_transitions()` in step 6 (NOT called by `apply_transitions()`); handles paths that are in `CONF_STATE` but missing from both disk and scan output
  - Cases (from brief's "Deleted files" section):
    - CONF='r': `git restore --source=HEAD -- "$CLAUDE_DIR/$path"` to recover; on success: update `ACTUAL_STATE[$path]='tracked'` (file is back in working tree and in git index from HEAD). On failure (never committed): log warning, leave as 'r' in conf, add path to `SKIP_PATHS`. `apply_transitions` and `apply_drift_correction` will skip this path because it is in SKIP_PATHS. `--source=HEAD` is required because the file may have been removed from the git index via `git rm --cached`.
    - CONF='i': check git index first: `git -C "$CLAUDE_DIR" ls-files -- "$path"`.
      - If NOT tracked in git index: remove from CONF_STATE, CONF_ORDER_TYPES, CONF_ORDER_PATHS, and `unset 'CONF_ORDER_PATH_INDEX[$path]'`; no git op needed.
      - If tracked in git index: run `git rm --cached -- "$CLAUDE_DIR/$path" && rc=0 || rc=$?`. On success: remove from CONF_STATE, CONF_ORDER_TYPES, CONF_ORDER_PATHS, and `unset 'CONF_ORDER_PATH_INDEX[$path]'`. On failure: log error to REPORT_ERRORS, leave in CONF_STATE; drift correction or next run will retry.
    - CONF='d': check git index: `git -C "$CLAUDE_DIR" ls-files -- "$path"` returns empty → file not in index, tombstone can be removed safely (remove from CONF_STATE, CONF_ORDER_TYPES/CONF_ORDER_PATHS, and `unset 'CONF_ORDER_PATH_INDEX[$path]'`). If file IS in index: run `git rm --cached` (use `&& rc=0 || rc=$?` pattern); on success, remove from CONF_STATE, CONF_ORDER_TYPES/CONF_ORDER_PATHS, and `unset 'CONF_ORDER_PATH_INDEX[$path]'`; on failure, log error and leave tombstone (drift correction or next run will retry).
    - CONF='': remove from CONF_STATE, CONF_ORDER_TYPES/CONF_ORDER_PATHS, and `unset 'CONF_ORDER_PATH_INDEX[$path]'`
  - This runs before the main transition loop so these paths are already resolved when transitions execute
  - Error handling: use `cmd && rc=0 || rc=$?` pattern per Shell Conventions and Task 4.1 error handling pattern.
  - **Postconditions after `handle_deleted_files()` returns:**
    - All paths in CONF_STATE that were missing from disk AND had state 'i' (not tracked in git), 'd' (not in git index), or '' have been REMOVED from CONF_STATE, CONF_ORDER_TYPES/CONF_ORDER_PATHS, and CONF_ORDER_PATH_INDEX.
    - Paths with CONF='i' that were missing from disk but still tracked in git: git rm --cached was attempted; on success, removed from all three structures; on failure, retained in CONF_STATE and CONF_ORDER_PATH_INDEX.
    - Paths with CONF='r' that were missing and successfully restored are still in CONF_STATE with state 'r'; ACTUAL_STATE is explicitly updated by `handle_deleted_files` for restored paths: `ACTUAL_STATE[$path]='tracked'`.
    - Paths with CONF='r' where restore failed remain in CONF_STATE with state 'r' AND are added to `SKIP_PATHS`; `apply_transitions` and `apply_drift_correction` skip paths in SKIP_PATHS.
    - Paths with CONF='d' where the file was already gone and not in the git index have been removed from CONF_STATE and CONF_ORDER_PATH_INDEX. If the file was in the git index and git rm --cached failed, the tombstone is retained.
    - `apply_transitions` must NOT re-process paths that were removed from CONF_STATE by `handle_deleted_files`.
- **Releasable**: after this task, deleted files do not trigger erroneous transition attempts in the main loop
- **Tests (TDD)** — `~/.claude/tests/test_deleted_files.bats`:
  - Unit: `test_deleted_r_file_restored` — CONF='r', file missing from disk; assert git restore called; CONF_STATE still 'r'
  - Unit: `test_deleted_r_file_never_committed_logs_warning` — git restore fails; CONF_STATE stays 'r'; warning logged; path added to SKIP_PATHS
  - Unit: `test_deleted_i_file_removed_from_conf` — CONF='i', file gone, not tracked in git index; CONF_STATE key removed; CONF_ORDER_PATH_INDEX entry unset
  - Unit: `test_deleted_i_file_tracked_runs_git_rm_cached` — CONF='i', file missing from disk but committed and tracked in git index; call `handle_deleted_files()`; assert `git rm --cached` was called; assert CONF_STATE key removed; assert file is no longer in git index; assert CONF_ORDER_PATH_INDEX entry unset
  - Unit: `test_deleted_d_tombstone_cleared` — CONF='d', file gone, not in git index; CONF_STATE key removed; CONF_ORDER_PATH_INDEX entry unset
  - Unit: `test_deleted_pending_removed_from_conf` — CONF='', file gone; CONF_STATE key removed; CONF_ORDER_PATH_INDEX entry unset
  - Integration: `test_ordering_deleted_files_before_transitions` — set up: (a) create file `foo.sh`, commit it, then delete it from disk; (b) set conf to 'i' (desired state). Run `handle_deleted_files()` then `apply_transitions()`. Expected: `handle_deleted_files` sees CONF='i' for missing file (not tracked in git) → removes from CONF_STATE. `apply_transitions` never encounters `foo.sh` (it was removed from CONF_STATE). Final state: `foo.sh` NOT in CONF_STATE, NOT in git index, NOT on disk. The 'i' transition was never attempted for a missing file. Assert that apply_from_i was never called for `foo.sh` (mock or trace).
  - Unit: `test_skip_paths_r_restore_success_stays_in_conf` — CONF='r', file missing from disk, git restore succeeds; call `handle_deleted_files()`; assert CONF_STATE still contains path with state 'r'; assert path NOT in SKIP_PATHS; assert ACTUAL_STATE[path]='tracked'
  - Unit: `test_skip_paths_r_restore_failure_path_in_skip_list` — CONF='r', file missing from disk, git restore fails (never committed); call `handle_deleted_files()`; assert CONF_STATE still contains path with state 'r'; assert path IS in SKIP_PATHS
  - Checkpoint: `bats ~/.claude/tests/test_deleted_files.bats`

#### Task 5.5 — Main entry point and CLI
- [ ] **File**: `~/.local/bin/claude-sync.sh`
- **Depends on**: Task 5.3, Task 5.4
- **Description**:
  - `main(args...)` — argument parsing and top-level orchestration
  - Args: `--dry-run` sets `DRY_RUN=true`; unknown args print usage and `exit 1`
  - Shebang: `#!/usr/bin/env bash`; `set -euo pipefail`
  - Set up a trap in `main()` to clean up any temp files on exit: capture TMPFILE paths in the global array `TMPFILES=()` and remove them in the trap: `trap '[[ ${#TMPFILES[@]} -gt 0 ]] && rm -f "${TMPFILES[@]}" 2>/dev/null' EXIT`. Each `mktemp` call in `write_conf` and `write_sentinel_section` appends to `TMPFILES`.
  - Execution order:
    0. `reset_globals()` (reinitialize all mutable globals — must be first)
    1. Parse args (`DRY_RUN`)
    2. `preflight_check()`
    3. `parse_conf()`
    4. `build_actual_state()` (calls `scan_files()` internally)
    5. `handle_deleted_files()`
    6. `apply_transitions()` (includes `write_sentinel_section()` + first `write_conf()`)
    7. `generate_report()`
    8. `commit_and_push()` (skipped in `DRY_RUN`)
  - Dry-run header: if `DRY_RUN=true`, print `"=== DRY RUN — no changes will be written ==="` before any output. In DRY_RUN mode, `commit_and_push()` is skipped entirely. CONF_STATE is not modified in dry-run, so the report reflects what would happen, not what did happen. See Task 5.2 for `generate_report()` DRY_RUN behavior.
  - `main()` must call `reset_globals()` as its very first action (before arg parsing). `reset_globals()` reinitializes: `DRY_RUN=false`; ALL global mutable arrays to empty: CONF_STATE, CONF_ORDER_TYPES, CONF_ORDER_PATHS, CONF_ORDER_PATH_INDEX, ACTUAL_STATE, REPORT_APPLIED, REPORT_DRY_RUN, REPORT_ERRORS, REPORT_PENDING, TMPFILES, SKIP_PATHS. This ensures multiple `main()` calls within the same bash session (as occurs in bats test suites) do not accumulate state from prior calls — including `DRY_RUN` leaking from a `--dry-run` invocation into a subsequent non-dry-run invocation.
  - Source guard at bottom of file: `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"`
  - Script must be executable: `chmod +x ~/.local/bin/claude-sync.sh`
- **Releasable**: after this task, the script is fully invokable as `claude-sync.sh` and `claude-sync.sh --dry-run`
- **Tests (TDD)** — `~/.claude/tests/test_main.bats`:
  - E2E: `test_dry_run_flag_no_writes` — run `claude-sync.sh --dry-run` against test fixture with pending transitions; assert no files changed AND assert the output includes the dry-run header AND lists at least one `(dry-run)` action from REPORT_DRY_RUN for the transitions that would have occurred (not just 'nothing to do'); assert CONF_STATE is not modified
  - E2E: `test_unknown_flag_exits_1` — `claude-sync.sh --unknown`; assert exit 1 and usage message
  - E2E: `test_full_run_idempotent` — run twice, assert second run output "Nothing to commit"
  - E2E: `test_full_run_new_file_appears_in_pending` — add file to fixture, run; assert file in pending section of report
  - E2E: `test_full_run_r_to_i_transition` — conf has path with new state 'i', was 'r'; run; assert gitignored, not tracked
  - Unit: `test_no_orphan_tempfiles_after_run` — run script to completion (normal and dry-run); assert no `*.XXXXXX` files remain in `$CLAUDE_DIR`
  - Unit: `test_empty_conf_and_empty_scan_exits_cleanly` — init empty git repo, empty conf, run `main()`; assert exit 0, output contains "Nothing to commit."
  - Unit: `test_source_does_not_call_main` — source `claude-sync.sh` in a subshell with no args; assert exit 0; assert no output on stdout/stderr; assert no git operations performed; assert no files created in `$CLAUDE_DIR`. This verifies the source guard pattern `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"` works correctly.
  - E2E: `test_full_lifecycle_new_to_tracked_to_deleted` — multi-step scenario:
    1. Create git repo, create `newfile.txt`, run script → file appears as pending
    2. Edit conf: `newfile.txt=r`, run script → file is tracked, committed
    3. Run script again → "Nothing to commit" (idempotency)
    4. Edit conf: `newfile.txt=d`, run script → file trashed, tombstone in conf
    4.5. Edit conf: `newfile.txt=r`. Run script. Expected: `handle_deleted_files` sees CONF='r', file missing → runs `git restore --source=HEAD` → file restored; `ACTUAL_STATE[$path]='tracked'`. `apply_transitions`: conf='r', source_state='r' (actual='tracked') → identity, no dispatch. Drift correction: stable, no action. Report: file in 'Applied' as restored. Run script again → "Nothing to commit."
    5. Provide commit message → tombstone removed from conf post-commit
    6. Run script again → "Nothing to commit"
  - Checkpoint: `bats ~/.claude/tests/test_main.bats`

---

### Phase 6 — Verification & Documentation

#### Task 6.1 — Final verification & documentation update
- [ ] **File**: N/A (agent task)
- **Depends on**: all prior tasks
- **Description**:
  - Spawn an agent to discover all documentation in `~/.claude` (README files, CLAUDE.md, the brief) and update every file whose content is affected by the delivered implementation. The agent must not update docs unrelated to claude-sync.
  - Verify all acceptance criteria below are met before marking this task complete.
- **Releasable**: after this task, the feature is fully verified and all documentation reflects the delivered implementation.
- **Acceptance criteria** (must all pass):
  - [ ] `bats ~/.claude/tests/` passes all tests (0 failures)
  - [ ] `claude-sync.sh --dry-run` run against real `~/.claude` exits 0 with dry-run header and a report
  - [ ] `claude-sync.sh` run twice with no intervening changes produces "Nothing to commit." on second run
  - [ ] Hand-written `.gitignore` entries outside the sentinel block are unchanged after a full run
  - [ ] `sync-answers.conf` is not tracked by git and not modified by a dry-run
  - [ ] A file changed from `r` to `i` in conf is no longer tracked and appears in the sentinel section after one run
  - [ ] A file changed from `i` to `d` is sent to Trash and its `d` tombstone is removed from conf after the commit
  - [ ] Script exits 1 with a clear message if `trash` is not installed
  - [ ] Script exits 1 with a clear message if `~/.claude` is not a git repo
- **Tests (TDD)**: N/A — this is a verification and documentation task.
- **Checkpoint**: manually confirm every acceptance criterion above is checked.
