#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-drift-src"
mkdir -p "$CLAUDE_DIR" && git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

# ---------------------------------------------------------------------------
# Helper: create a fresh git repo with an initial commit
# ---------------------------------------------------------------------------
_setup_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  touch "$dir/.gitkeep"
  git -C "$dir" add -- ".gitkeep"
  git -C "$dir" commit -m "init" >/dev/null 2>&1
}

setup() {
  TMPDIR_TEST="$BATS_TMPDIR/test-drift-$$-$BATS_TEST_NUMBER"
  _setup_repo "$TMPDIR_TEST"
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  reset_globals
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  REPORT_APPLIED=()
  REPORT_DRY_RUN=()
  REPORT_ERRORS=()
  REPORT_PENDING=()
  SKIP_PATHS=()
}

teardown() { [[ -d "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST"; }

# ---------------------------------------------------------------------------
# test_drift_r_tracked_is_noop
# CONF='r', file committed and tracked; call apply_drift_correction;
# assert REPORT_APPLIED is empty and no git changes
# ---------------------------------------------------------------------------
@test "test_drift_r_tracked_is_noop" {
  # Commit a file so it's tracked
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  git -C "$CLAUDE_DIR" add -- "tracked.txt"
  git -C "$CLAUDE_DIR" commit -m "add tracked.txt" >/dev/null 2>&1

  CONF_STATE["tracked.txt"]="r"

  apply_drift_correction "tracked.txt"

  # REPORT_APPLIED should be empty
  [ "${#REPORT_APPLIED[@]}" -eq 0 ]

  # File should still be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -n "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_drift_r_untracked_adds_file
# CONF='r', file on disk but NOT in git index;
# after correction: file IS tracked; REPORT_APPLIED contains "(drift corrected)"
# ---------------------------------------------------------------------------
@test "test_drift_r_untracked_adds_file" {
  # File on disk but not staged/committed
  echo "content" > "$CLAUDE_DIR/untracked.txt"

  CONF_STATE["untracked.txt"]="r"

  apply_drift_correction "untracked.txt"

  # File should now be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "untracked.txt")
  [ -n "$tracked" ]

  # REPORT_APPLIED contains "(drift corrected)"
  local found=false
  local entry
  for entry in "${REPORT_APPLIED[@]}"; do
    [[ "$entry" == *"(drift corrected)"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_drift_r_missing_restores_file
# CONF='r', file was committed then deleted from disk;
# after correction: file is restored on disk; REPORT_APPLIED contains "(drift corrected)"
# ---------------------------------------------------------------------------
@test "test_drift_r_missing_restores_file" {
  # Commit a file, then delete it from disk (but keep in git index)
  echo "content" > "$CLAUDE_DIR/missing.txt"
  git -C "$CLAUDE_DIR" add -- "missing.txt"
  git -C "$CLAUDE_DIR" commit -m "add missing.txt" >/dev/null 2>&1
  rm "$CLAUDE_DIR/missing.txt"

  CONF_STATE["missing.txt"]="r"

  apply_drift_correction "missing.txt"

  # File should be restored on disk
  [ -f "$CLAUDE_DIR/missing.txt" ]

  # REPORT_APPLIED contains "(drift corrected)"
  local found=false
  local entry
  for entry in "${REPORT_APPLIED[@]}"; do
    [[ "$entry" == *"(drift corrected)"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_drift_r_ignored_force_adds_with_warning
# CONF='r', file in .gitignore;
# after correction: file IS tracked (git add -f);
# REPORT_ERRORS contains warning about gitignored;
# REPORT_APPLIED contains "(drift corrected)"
# ---------------------------------------------------------------------------
@test "test_drift_r_ignored_force_adds_with_warning" {
  # Create a file and add it to .gitignore
  echo "content" > "$CLAUDE_DIR/ignored.txt"
  echo "ignored.txt" > "$CLAUDE_DIR/.gitignore"
  git -C "$CLAUDE_DIR" add -- ".gitignore"
  git -C "$CLAUDE_DIR" commit -m "add .gitignore" >/dev/null 2>&1

  CONF_STATE["ignored.txt"]="r"

  apply_drift_correction "ignored.txt"

  # File should now be force-tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "ignored.txt")
  [ -n "$tracked" ]

  # REPORT_ERRORS contains warning about gitignored
  local found_warn=false
  local entry
  for entry in "${REPORT_ERRORS[@]}"; do
    [[ "$entry" == *"gitignored"* ]] && found_warn=true && break
  done
  [ "$found_warn" = "true" ]

  # REPORT_APPLIED contains "(drift corrected)"
  local found_applied=false
  for entry in "${REPORT_APPLIED[@]}"; do
    [[ "$entry" == *"(drift corrected)"* ]] && found_applied=true && break
  done
  [ "$found_applied" = "true" ]
}

# ---------------------------------------------------------------------------
# test_drift_d_file_still_exists_trashes
# CONF='d', file on disk (untracked);
# after correction: trash called with abs path; REPORT_APPLIED contains "(drift corrected)"
# ---------------------------------------------------------------------------
@test "test_drift_d_file_still_exists_trashes" {
  # File on disk but not tracked
  echo "content" > "$CLAUDE_DIR/todelete.txt"
  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls.txt"

  # Mock trash to record calls
  trash() {
    echo "$1" >> "$TRASH_CALLS_FILE"
    return 0
  }
  export -f trash

  CONF_STATE["todelete.txt"]="d"

  apply_drift_correction "todelete.txt"

  # trash was called with absolute path
  [ -f "$TRASH_CALLS_FILE" ]
  local trash_arg
  trash_arg=$(cat "$TRASH_CALLS_FILE")
  [ "$trash_arg" = "$CLAUDE_DIR/todelete.txt" ]

  # REPORT_APPLIED contains "(drift corrected)"
  local found=false
  local entry
  for entry in "${REPORT_APPLIED[@]}"; do
    [[ "$entry" == *"(drift corrected)"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_drift_empty_no_action
# CONF='', file exists; call apply_drift_correction;
# assert REPORT_APPLIED empty, no git changes
# ---------------------------------------------------------------------------
@test "test_drift_empty_no_action" {
  # File exists on disk
  echo "content" > "$CLAUDE_DIR/pending.txt"

  CONF_STATE["pending.txt"]=""

  apply_drift_correction "pending.txt"

  # REPORT_APPLIED should be empty
  [ "${#REPORT_APPLIED[@]}" -eq 0 ]

  # File should NOT be tracked (no git ops)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "pending.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_drift_i_no_per_file_action
# CONF='i', file exists; assert no git/trash ops
# ---------------------------------------------------------------------------
@test "test_drift_i_no_per_file_action" {
  # File exists on disk, not tracked
  echo "content" > "$CLAUDE_DIR/ignored_file.txt"
  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls.txt"

  # Mock trash to detect if called
  trash() {
    echo "$1" >> "$TRASH_CALLS_FILE"
    return 0
  }
  export -f trash

  CONF_STATE["ignored_file.txt"]="i"

  apply_drift_correction "ignored_file.txt"

  # REPORT_APPLIED should be empty (no per-file action for 'i')
  [ "${#REPORT_APPLIED[@]}" -eq 0 ]

  # trash should NOT have been called
  [ ! -f "$TRASH_CALLS_FILE" ]

  # File should NOT be in git index
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "ignored_file.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_drift_d_unstaged_file_retries_trash
# commit file, git rm --cached (simulates partial failure),
# CONF_STATE='d', file still on disk;
# call apply_drift_correction; assert trash called; REPORT_APPLIED contains "(drift corrected)"
# ---------------------------------------------------------------------------
@test "test_drift_d_untracked_on_disk_trashes" {
  # Commit a file then unstage it (git rm --cached) — file still on disk but no longer tracked
  echo "content" > "$CLAUDE_DIR/partial.txt"
  git -C "$CLAUDE_DIR" add -- "partial.txt"
  git -C "$CLAUDE_DIR" commit -m "add partial.txt" >/dev/null 2>&1
  git -C "$CLAUDE_DIR" rm --cached -- "partial.txt" >/dev/null 2>&1

  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls.txt"

  # Mock trash to record calls
  trash() {
    echo "$1" >> "$TRASH_CALLS_FILE"
    return 0
  }
  export -f trash

  CONF_STATE["partial.txt"]="d"

  apply_drift_correction "partial.txt"

  # trash was called
  [ -f "$TRASH_CALLS_FILE" ]
  local trash_arg
  trash_arg=$(cat "$TRASH_CALLS_FILE")
  [ "$trash_arg" = "$CLAUDE_DIR/partial.txt" ]

  # REPORT_APPLIED contains "(drift corrected)"
  local found=false
  local entry
  for entry in "${REPORT_APPLIED[@]}"; do
    [[ "$entry" == *"(drift corrected)"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_drift_d_stable_tombstone_noop (C1-T-1)
# CONF='d', file not on disk and not in git index — stable tombstone, no action.
# ---------------------------------------------------------------------------
@test "test_drift_d_stable_tombstone_noop" {
  # Do NOT create or commit any file — it doesn't exist on disk or in index
  CONF_STATE["gone.txt"]="d"

  apply_drift_correction "gone.txt"

  # REPORT_APPLIED should be empty (no action taken)
  [ "${#REPORT_APPLIED[@]}" -eq 0 ]

  # REPORT_ERRORS should be empty (stable tombstone is expected)
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_drift_d_tracked_unstages_and_trashes (C1-T-2)
# CONF='d', file committed and still in git index.
# After correction: file removed from index; trash called; REPORT_APPLIED "(drift corrected)".
# ---------------------------------------------------------------------------
@test "test_drift_d_tracked_unstages_and_trashes" {
  # Commit a file so it's tracked in the index
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  git -C "$CLAUDE_DIR" add -- "tracked.txt"
  git -C "$CLAUDE_DIR" commit -m "add tracked.txt" >/dev/null 2>&1

  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls.txt"

  # Mock trash to record calls
  trash() {
    echo "$1" >> "$TRASH_CALLS_FILE"
    return 0
  }
  export -f trash

  CONF_STATE["tracked.txt"]="d"

  apply_drift_correction "tracked.txt"

  # File removed from git index
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -z "$tracked" ]

  # trash was called with absolute path
  [ -f "$TRASH_CALLS_FILE" ]
  local trash_arg
  trash_arg=$(cat "$TRASH_CALLS_FILE")
  [ "$trash_arg" = "$CLAUDE_DIR/tracked.txt" ]

  # REPORT_APPLIED contains "(drift corrected)"
  local found=false
  local entry
  for entry in "${REPORT_APPLIED[@]}"; do
    [[ "$entry" == *"(drift corrected)"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_drift_skips_path_in_skip_paths (C1-T-3)
# Path in SKIP_PATHS; assert no ops, REPORT_APPLIED empty.
# ---------------------------------------------------------------------------
@test "test_drift_skips_path_in_skip_paths" {
  echo "content" > "$CLAUDE_DIR/skipme.txt"
  CONF_STATE["skipme.txt"]="r"
  SKIP_PATHS=("skipme.txt")

  apply_drift_correction "skipme.txt"

  # REPORT_APPLIED should be empty (skipped)
  [ "${#REPORT_APPLIED[@]}" -eq 0 ]

  # File should NOT be tracked (no git ops ran)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "skipme.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_drift_dry_run_r_untracked_no_ops (C1-T-4)
# CONF='r', file on disk but not tracked, DRY_RUN=true.
# Assert: no git ops, REPORT_DRY_RUN has "dry-run".
# ---------------------------------------------------------------------------
@test "test_drift_dry_run_r_untracked_no_ops" {
  echo "content" > "$CLAUDE_DIR/untracked.txt"
  CONF_STATE["untracked.txt"]="r"
  DRY_RUN=true

  apply_drift_correction "untracked.txt"

  # File should NOT be tracked (no git ops)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "untracked.txt")
  [ -z "$tracked" ]

  # REPORT_DRY_RUN has "dry-run"
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}
