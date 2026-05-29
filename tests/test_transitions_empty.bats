#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-empty-src"
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
  TMPDIR_TEST="$BATS_TMPDIR/test-empty-$$-$BATS_TEST_NUMBER"
  _setup_repo "$TMPDIR_TEST"
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  reset_globals
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
}

teardown() { [[ -d "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST"; }

# ---------------------------------------------------------------------------
# test_empty_to_r_adds_to_git
# Untracked file on disk, CONF_STATE['']=''. After empty→r:
# git ls-files shows it, CONF_STATE='r', file still on disk.
# ---------------------------------------------------------------------------
@test "test_empty_to_r_adds_to_git" {
  echo "content" > "$CLAUDE_DIR/newfile.txt"
  CONF_STATE["newfile.txt"]=""

  apply_from_empty "newfile.txt" "r"

  # File should now be tracked in git
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "newfile.txt")
  [ -n "$tracked" ]

  # CONF_STATE updated to 'r'
  [ "${CONF_STATE[newfile.txt]}" = "r" ]

  # File still exists on disk
  [ -f "$CLAUDE_DIR/newfile.txt" ]
}

# ---------------------------------------------------------------------------
# test_empty_to_i_updates_conf_file_stays
# File on disk, empty→i: CONF_STATE='i', file still on disk, no git tracking.
# ---------------------------------------------------------------------------
@test "test_empty_to_i_updates_conf_file_stays" {
  echo "content" > "$CLAUDE_DIR/localfile.txt"
  CONF_STATE["localfile.txt"]=""

  apply_from_empty "localfile.txt" "i"

  # CONF_STATE updated to 'i'
  [ "${CONF_STATE[localfile.txt]}" = "i" ]

  # File still exists on disk
  [ -f "$CLAUDE_DIR/localfile.txt" ]

  # File NOT tracked in git (no git ops performed)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "localfile.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_empty_to_d_untracked_trashes
# Untracked file on disk; mock trash; after empty→d:
# CONF_STATE='d', trash called with abs path (no trailing slash).
# ---------------------------------------------------------------------------
@test "test_empty_to_d_untracked_trashes" {
  echo "content" > "$CLAUDE_DIR/deleteme.txt"
  CONF_STATE["deleteme.txt"]=""

  # Mock trash
  TRASH_CALLED=""
  trash() { TRASH_CALLED="$1"; }

  apply_from_empty "deleteme.txt" "d"

  # CONF_STATE updated to 'd' (tombstone)
  [ "${CONF_STATE[deleteme.txt]}" = "d" ]

  # trash was called with abs path (no trailing slash)
  [ "$TRASH_CALLED" = "$CLAUDE_DIR/deleteme.txt" ]
}

# ---------------------------------------------------------------------------
# test_empty_to_d_tracked_unstages_then_trashes
# Commit file first, then call empty→d:
# git rm --cached ran (ls-files empty), trash called; CONF_STATE='d'.
# ---------------------------------------------------------------------------
@test "test_empty_to_d_tracked_unstages_then_trashes" {
  echo "content" > "$CLAUDE_DIR/committed.txt"
  git -C "$CLAUDE_DIR" add -- "committed.txt"
  git -C "$CLAUDE_DIR" commit -m "add committed.txt" >/dev/null 2>&1

  CONF_STATE["committed.txt"]=""

  # Mock trash
  TRASH_CALLED=""
  trash() { TRASH_CALLED="$1"; }

  apply_from_empty "committed.txt" "d"

  # git rm --cached ran: file no longer tracked in git index
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "committed.txt")
  [ -z "$tracked" ]

  # trash was called
  [ "$TRASH_CALLED" = "$CLAUDE_DIR/committed.txt" ]

  # CONF_STATE updated to 'd'
  [ "${CONF_STATE[committed.txt]}" = "d" ]
}

# ---------------------------------------------------------------------------
# test_empty_to_r_git_add_failure_leaves_empty
# File missing (git add fails); CONF_STATE stays ''.
# ---------------------------------------------------------------------------
@test "test_empty_to_r_git_add_failure_leaves_empty" {
  # Do NOT create the file — git add will fail
  CONF_STATE["missing.txt"]=""

  apply_from_empty "missing.txt" "r"

  # CONF_STATE stays ''
  [ "${CONF_STATE[missing.txt]}" = "" ]

  # REPORT_ERRORS non-empty
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# test_empty_transitions_dry_run
# DRY_RUN=true, empty→r: file NOT added to git, CONF_STATE stays '',
# REPORT_DRY_RUN has "dry-run".
# ---------------------------------------------------------------------------
@test "test_empty_transitions_dry_run" {
  echo "content" > "$CLAUDE_DIR/newfile.txt"
  CONF_STATE["newfile.txt"]=""
  DRY_RUN=true

  apply_from_empty "newfile.txt" "r"

  # File should NOT be tracked (no git ops)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "newfile.txt")
  [ -z "$tracked" ]

  # CONF_STATE unchanged (still '')
  [ "${CONF_STATE[newfile.txt]}" = "" ]

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
# test_empty_unknown_state_rejected (C1-C-1)
# CONF_STATE='', target state 'x': REPORT_ERRORS non-empty, CONF_STATE stays '',
# file NOT tracked in git.
# ---------------------------------------------------------------------------
@test "test_empty_unknown_state_rejected" {
  echo "content" > "$CLAUDE_DIR/file.txt"
  CONF_STATE["file.txt"]=""

  apply_from_empty "file.txt" "x"

  # CONF_STATE stays ''
  [ "${CONF_STATE[file.txt]}" = "" ]

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
# test_empty_to_i_dry_run_no_ops (C1-C-2)
# DRY_RUN=true, empty→i: CONF_STATE stays '', no git tracking, REPORT_DRY_RUN has "dry-run".
# ---------------------------------------------------------------------------
@test "test_empty_to_i_dry_run_no_ops" {
  echo "content" > "$CLAUDE_DIR/file.txt"
  CONF_STATE["file.txt"]=""
  DRY_RUN=true

  apply_from_empty "file.txt" "i"

  # CONF_STATE stays ''
  [ "${CONF_STATE[file.txt]}" = "" ]

  # File NOT tracked in git
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "file.txt")
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

# ---------------------------------------------------------------------------
# test_empty_to_d_dry_run_no_ops (C1-C-2)
# DRY_RUN=true, empty→d: CONF_STATE stays '', file not removed from disk, REPORT_DRY_RUN has "dry-run".
# ---------------------------------------------------------------------------
@test "test_empty_to_d_dry_run_no_ops" {
  echo "content" > "$CLAUDE_DIR/file.txt"
  CONF_STATE["file.txt"]=""
  DRY_RUN=true

  apply_from_empty "file.txt" "d"

  # CONF_STATE stays ''
  [ "${CONF_STATE[file.txt]}" = "" ]

  # File still on disk (no trash)
  [ -f "$CLAUDE_DIR/file.txt" ]

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
# test_empty_to_d_git_rm_failure_leaves_empty (C1-C-3)
# Commit a file, mock git rm --cached to fail; CONF_STATE stays '', REPORT_ERRORS non-empty.
# ---------------------------------------------------------------------------
@test "test_empty_to_d_git_rm_failure_leaves_empty" {
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  git -C "$CLAUDE_DIR" add -- "tracked.txt"
  git -C "$CLAUDE_DIR" commit -m "add tracked.txt" >/dev/null 2>&1

  CONF_STATE["tracked.txt"]=""

  # Mock git to fail on rm --cached, pass through everything else
  git() {
    if [[ "$*" == *"rm --cached"* ]]; then
      return 1
    fi
    command git "$@"
  }

  apply_from_empty "tracked.txt" "d"

  # CONF_STATE stays '' (tombstone not set when git rm fails)
  [ "${CONF_STATE[tracked.txt]}" = "" ]

  # REPORT_ERRORS non-empty
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# test_empty_to_d_trash_failure_tombstone_persists (C1-C-5)
# File on disk, mock trash to fail; CONF_STATE becomes 'd', REPORT_ERRORS non-empty.
# ---------------------------------------------------------------------------
@test "test_empty_to_d_trash_failure_tombstone_persists" {
  echo "content" > "$CLAUDE_DIR/file.txt"
  CONF_STATE["file.txt"]=""

  # Mock trash to fail
  trash() { return 1; }

  apply_from_empty "file.txt" "d"

  # CONF_STATE is 'd' (tombstone persists even when trash fails)
  [ "${CONF_STATE[file.txt]}" = "d" ]

  # REPORT_ERRORS non-empty
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}
