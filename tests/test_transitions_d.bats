#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-d-src"
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
  TMPDIR_TEST="$BATS_TMPDIR/test-d-$$-$BATS_TEST_NUMBER"
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
# test_d_to_r_file_exists_adds_to_git
# file on disk (never removed from disk), CONF_STATE='d'.
# After d→r: git ls-files shows path; CONF_STATE='r'. File still on disk.
# ---------------------------------------------------------------------------
@test "test_d_to_r_file_exists_adds_to_git" {
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  CONF_STATE["tracked.txt"]="d"

  apply_from_d "tracked.txt" "r"

  # File should now be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -n "$tracked" ]

  # CONF_STATE updated to 'r'
  [ "${CONF_STATE[tracked.txt]}" = "r" ]

  # File still exists on disk
  [ -f "$CLAUDE_DIR/tracked.txt" ]
}

# ---------------------------------------------------------------------------
# test_d_to_r_file_missing_but_committed_restores_and_adds
# commit file to git, then delete from disk (NOT from index — use rm not git rm).
# After d→r: file restored to disk AND tracked in git; CONF_STATE='r'.
# ---------------------------------------------------------------------------
@test "test_d_to_r_file_missing_but_committed_restores_and_adds" {
  # Commit the file
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  git -C "$CLAUDE_DIR" add -- "tracked.txt"
  git -C "$CLAUDE_DIR" commit -m "add tracked.txt" >/dev/null 2>&1

  # Delete from disk only (file still in git index / HEAD)
  rm "$CLAUDE_DIR/tracked.txt"

  CONF_STATE["tracked.txt"]="d"

  apply_from_d "tracked.txt" "r"

  # File restored to disk
  [ -f "$CLAUDE_DIR/tracked.txt" ]

  # File is tracked in git
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -n "$tracked" ]

  # CONF_STATE updated to 'r'
  [ "${CONF_STATE[tracked.txt]}" = "r" ]
}

# ---------------------------------------------------------------------------
# test_d_to_r_never_committed_logs_error
# file never committed, not on disk.
# After d→r: CONF_STATE stays 'd'; REPORT_ERRORS contains "Cannot restore".
# ---------------------------------------------------------------------------
@test "test_d_to_r_never_committed_logs_error" {
  # Do NOT create or commit the file
  CONF_STATE["ghost.txt"]="d"

  apply_from_d "ghost.txt" "r"

  # CONF_STATE stays 'd'
  [ "${CONF_STATE[ghost.txt]}" = "d" ]

  # REPORT_ERRORS contains "Cannot restore"
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_ERRORS[@]}"; do
    [[ "$entry" == *"Cannot restore"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_d_to_i_file_exists_updates_conf
# file exists on disk.
# After d→i: CONF_STATE='i'. File still on disk. Git state unchanged.
# ---------------------------------------------------------------------------
@test "test_d_to_i_file_exists_updates_conf" {
  echo "content" > "$CLAUDE_DIR/local.txt"
  CONF_STATE["local.txt"]="d"

  apply_from_d "local.txt" "i"

  # CONF_STATE updated to 'i'
  [ "${CONF_STATE[local.txt]}" = "i" ]

  # File still exists on disk
  [ -f "$CLAUDE_DIR/local.txt" ]

  # Git state unchanged (file not tracked — no git add was done)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "local.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_d_to_i_missing_file_is_blocked
# file not on disk.
# After d→i: CONF_STATE stays 'd'. REPORT_ERRORS contains "file is gone".
# ---------------------------------------------------------------------------
@test "test_d_to_i_missing_file_is_blocked" {
  # Do NOT create the file
  CONF_STATE["gone.txt"]="d"

  apply_from_d "gone.txt" "i"

  # CONF_STATE stays 'd'
  [ "${CONF_STATE[gone.txt]}" = "d" ]

  # REPORT_ERRORS contains "file is gone"
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_ERRORS[@]}"; do
    [[ "$entry" == *"file is gone"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_d_to_empty_file_missing_committed_restores
# commit file, then remove from disk.
# After d→empty: file restored to disk; CONF_STATE=''.
# ---------------------------------------------------------------------------
@test "test_d_to_empty_file_missing_committed_restores" {
  # Commit the file
  echo "content" > "$CLAUDE_DIR/restore_me.txt"
  git -C "$CLAUDE_DIR" add -- "restore_me.txt"
  git -C "$CLAUDE_DIR" commit -m "add restore_me.txt" >/dev/null 2>&1

  # Delete from disk only
  rm "$CLAUDE_DIR/restore_me.txt"

  CONF_STATE["restore_me.txt"]="d"

  apply_from_d "restore_me.txt" ""

  # File restored to disk
  [ -f "$CLAUDE_DIR/restore_me.txt" ]

  # CONF_STATE updated to ''
  [ "${CONF_STATE[restore_me.txt]}" = "" ]
}

# ---------------------------------------------------------------------------
# test_d_transitions_dry_run
# DRY_RUN=true; call apply_from_d("tracked.txt","r");
# assert git unchanged, CONF_STATE stays 'd', REPORT_DRY_RUN has "dry-run".
# ---------------------------------------------------------------------------
@test "test_d_transitions_dry_run" {
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  CONF_STATE["tracked.txt"]="d"
  DRY_RUN=true

  apply_from_d "tracked.txt" "r"

  # File should NOT be tracked (no git ops)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -z "$tracked" ]

  # CONF_STATE unchanged (still 'd')
  [ "${CONF_STATE[tracked.txt]}" = "d" ]

  # REPORT_DRY_RUN has "dry-run"
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_d_unknown_state_rejected (C1-C-3 Major)
# CONF_STATE='d', call apply_from_d with unknown target state 'x'.
# Assert: CONF_STATE stays 'd'; file NOT tracked; REPORT_ERRORS non-empty.
# ---------------------------------------------------------------------------
@test "test_d_unknown_state_rejected" {
  echo "content" > "$CLAUDE_DIR/file.txt"
  CONF_STATE["file.txt"]="d"

  apply_from_d "file.txt" "x"

  # CONF_STATE stays 'd'
  [ "${CONF_STATE[file.txt]}" = "d" ]

  # File NOT tracked in git
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "file.txt")
  [ -z "$tracked" ]

  # REPORT_ERRORS non-empty and contains "unknown target state"
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_ERRORS[@]}"; do
    [[ "$entry" == *"unknown target state"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_d_to_empty_file_exists_clears_conf (C1-C-1 Major)
# File exists on disk, CONF_STATE='d', transition to ''.
# Assert: file still on disk; CONF_STATE=''; file NOT tracked in git.
# ---------------------------------------------------------------------------
@test "test_d_to_empty_file_exists_clears_conf" {
  echo "x" > "$CLAUDE_DIR/local.txt"
  CONF_STATE["local.txt"]="d"

  apply_from_d "local.txt" ""

  # File still on disk
  [ -f "$CLAUDE_DIR/local.txt" ]

  # CONF_STATE updated to ''
  [ "${CONF_STATE[local.txt]}" = "" ]

  # File NOT tracked in git (no git add done)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "local.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_d_to_empty_never_committed_logs_error (C1-C-2 Major)
# File never created or committed, CONF_STATE='d', transition to ''.
# Assert: CONF_STATE stays 'd'; REPORT_ERRORS non-empty, contains "Cannot restore".
# ---------------------------------------------------------------------------
@test "test_d_to_empty_never_committed_logs_error" {
  # Do NOT create or commit "ghost.txt"
  CONF_STATE["ghost.txt"]="d"

  apply_from_d "ghost.txt" ""

  # CONF_STATE stays 'd'
  [ "${CONF_STATE[ghost.txt]}" = "d" ]

  # REPORT_ERRORS non-empty and contains "Cannot restore"
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_ERRORS[@]}"; do
    [[ "$entry" == *"Cannot restore"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_d_to_i_dry_run_no_ops (C1-C-4 Moderate)
# DRY_RUN=true, file on disk, CONF_STATE='d', transition to 'i'.
# Assert: CONF_STATE stays 'd'; REPORT_DRY_RUN has "dry-run".
# ---------------------------------------------------------------------------
@test "test_d_to_i_dry_run_no_ops" {
  echo "content" > "$CLAUDE_DIR/local.txt"
  CONF_STATE["local.txt"]="d"
  DRY_RUN=true

  apply_from_d "local.txt" "i"

  # CONF_STATE unchanged (still 'd')
  [ "${CONF_STATE[local.txt]}" = "d" ]

  # REPORT_DRY_RUN has "dry-run"
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_d_to_empty_dry_run_no_ops (C1-C-4 Moderate)
# DRY_RUN=true, file on disk, CONF_STATE='d', transition to ''.
# Assert: CONF_STATE stays 'd'; REPORT_DRY_RUN has "dry-run".
# ---------------------------------------------------------------------------
@test "test_d_to_empty_dry_run_no_ops" {
  echo "content" > "$CLAUDE_DIR/local.txt"
  CONF_STATE["local.txt"]="d"
  DRY_RUN=true

  apply_from_d "local.txt" ""

  # CONF_STATE unchanged (still 'd')
  [ "${CONF_STATE[local.txt]}" = "d" ]

  # REPORT_DRY_RUN has "dry-run"
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_d_to_r_git_add_failure_leaves_state (C1-C-5 Moderate)
# File is gitignored so `git add` (without -f) returns non-zero.
# Assert: CONF_STATE stays 'd'; REPORT_ERRORS non-empty.
# ---------------------------------------------------------------------------
@test "test_d_to_r_git_add_failure_leaves_state" {
  # Add the file to .gitignore so git add fails
  echo "reject_me.txt" >> "$CLAUDE_DIR/.gitignore"
  git -C "$CLAUDE_DIR" add -- ".gitignore"
  git -C "$CLAUDE_DIR" commit -m "add gitignore" >/dev/null 2>&1

  # Create the file on disk
  echo "x" > "$CLAUDE_DIR/reject_me.txt"
  CONF_STATE["reject_me.txt"]="d"

  apply_from_d "reject_me.txt" "r"

  # CONF_STATE stays 'd' (git add failed)
  [ "${CONF_STATE[reject_me.txt]}" = "d" ]

  # REPORT_ERRORS non-empty
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}
