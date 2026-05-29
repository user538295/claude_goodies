#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-r-src"
mkdir -p "$CLAUDE_DIR" && git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

# ---------------------------------------------------------------------------
# Helper: create a fresh git repo with a committed file
# ---------------------------------------------------------------------------
_setup_repo() {
  local dir="$1"
  local file="$2"
  mkdir -p "$dir"
  git -C "$dir" init >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  # Create and commit the file so it's tracked
  mkdir -p "$(dirname "$dir/$file")"
  echo "content" > "$dir/$file"
  git -C "$dir" add -- "$file"
  git -C "$dir" commit -m "init" >/dev/null 2>&1
}

setup() {
  TMPDIR_TEST="$BATS_TMPDIR/test-r-$$-$BATS_TEST_NUMBER"
  mkdir -p "$TMPDIR_TEST"
  _setup_repo "$TMPDIR_TEST" "tracked.txt"
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  reset_globals
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  # Initialise report arrays (in case reset_globals doesn't)
  REPORT_APPLIED=()
  REPORT_DRY_RUN=()
  REPORT_ERRORS=()
  REPORT_PENDING=()
  SKIP_PATHS=()
}

teardown() {
  [[ -d "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST"
}

# ---------------------------------------------------------------------------
# test_r_to_i_unstages_file
# r→i: after call, git ls-files shows path is no longer tracked; CONF_STATE='i'
# ---------------------------------------------------------------------------
@test "test_r_to_i_unstages_file" {
  CONF_STATE["tracked.txt"]="r"

  apply_from_r "tracked.txt" "i"

  # File should no longer be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -z "$tracked" ]

  # CONF_STATE updated
  [ "${CONF_STATE[tracked.txt]}" = "i" ]

  # File still exists on disk (--cached was used)
  [ -f "$CLAUDE_DIR/tracked.txt" ]
}

# ---------------------------------------------------------------------------
# test_r_to_d_unstages_and_trashes
# r→d: mock trash called with correct absolute path; git unstaged; CONF_STATE='d'
# ---------------------------------------------------------------------------
@test "test_r_to_d_unstages_and_trashes" {
  CONF_STATE["tracked.txt"]="r"
  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls.txt"

  # Mock trash to record calls
  trash() {
    echo "$1" >> "$TRASH_CALLS_FILE"
    return 0
  }
  export -f trash

  apply_from_r "tracked.txt" "d"

  # File should no longer be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -z "$tracked" ]

  # trash was called with absolute path
  [ -f "$TRASH_CALLS_FILE" ]
  local trash_arg
  trash_arg=$(cat "$TRASH_CALLS_FILE")
  [ "$trash_arg" = "$CLAUDE_DIR/tracked.txt" ]

  # CONF_STATE is tombstone 'd'
  [ "${CONF_STATE[tracked.txt]}" = "d" ]

  # File still exists on disk (--cached was used, not a working-tree delete)
  [ -f "$CLAUDE_DIR/tracked.txt" ]
}

# ---------------------------------------------------------------------------
# test_r_to_d_trash_failure_leaves_tombstone
# mock trash returns 1; CONF_STATE still 'd'; error logged to REPORT_ERRORS
# ---------------------------------------------------------------------------
@test "test_r_to_d_trash_failure_leaves_tombstone" {
  CONF_STATE["tracked.txt"]="r"

  # Mock trash to fail
  trash() {
    return 1
  }
  export -f trash

  apply_from_r "tracked.txt" "d"

  # CONF_STATE is tombstone 'd' even after trash failure
  [ "${CONF_STATE[tracked.txt]}" = "d" ]

  # Error logged
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# test_r_to_empty_stages_deletion_with_warning
# r→empty: CONF_STATE=''; warning present in REPORT_ERRORS
# ---------------------------------------------------------------------------
@test "test_r_to_empty_stages_deletion_with_warning" {
  CONF_STATE["tracked.txt"]="r"

  apply_from_r "tracked.txt" ""

  # File should no longer be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -z "$tracked" ]

  # CONF_STATE is empty string
  [ "${CONF_STATE[tracked.txt]}" = "" ]

  # Warning logged to REPORT_ERRORS
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_ERRORS[@]}"; do
    [[ "$entry" == *"tracked.txt"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_r_transitions_dir_uses_recursive_flag
# path ending /: assert git rm used -r flag (whole dir unstaged)
# ---------------------------------------------------------------------------
@test "test_r_transitions_dir_uses_recursive_flag" {
  # Add a directory with files
  mkdir -p "$CLAUDE_DIR/mydir"
  echo "a" > "$CLAUDE_DIR/mydir/a.txt"
  echo "b" > "$CLAUDE_DIR/mydir/b.txt"
  git -C "$CLAUDE_DIR" add "mydir/"
  git -C "$CLAUDE_DIR" commit -m "add dir" >/dev/null 2>&1

  CONF_STATE["mydir/"]="r"

  apply_from_r "mydir/" "i"

  # All files in dir should no longer be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "mydir/")
  [ -z "$tracked" ]

  # CONF_STATE updated
  [ "${CONF_STATE[mydir/]}" = "i" ]
}

# ---------------------------------------------------------------------------
# test_r_transitions_dry_run_no_git_ops
# DRY_RUN=true: git repo unchanged; CONF_STATE still 'r'; intended action in REPORT_DRY_RUN
# ---------------------------------------------------------------------------
@test "test_r_transitions_dry_run_no_git_ops" {
  DRY_RUN=true
  CONF_STATE["tracked.txt"]="r"

  apply_from_r "tracked.txt" "i"

  # File should STILL be tracked (no git ops performed)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -n "$tracked" ]

  # CONF_STATE unchanged (still 'r')
  [ "${CONF_STATE[tracked.txt]}" = "r" ]

  # Dry-run action logged
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* || "$entry" == *"(dry-run)"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_r_to_i_path_with_space
# path contains a space; git rm --cached succeeds; CONF_STATE='i'
# ---------------------------------------------------------------------------
@test "test_r_to_i_path_with_space" {
  # Create and commit a file with a space in its name
  echo "spaced" > "$CLAUDE_DIR/my file.txt"
  git -C "$CLAUDE_DIR" add -- "my file.txt"
  git -C "$CLAUDE_DIR" commit -m "add spaced file" >/dev/null 2>&1

  CONF_STATE["my file.txt"]="r"

  apply_from_r "my file.txt" "i"

  # File should no longer be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "my file.txt")
  [ -z "$tracked" ]

  # CONF_STATE updated
  [ "${CONF_STATE[my file.txt]}" = "i" ]
}

# ---------------------------------------------------------------------------
# test_r_unknown_state_rejected_before_git_rm
# unknown new_state: error logged, git rm NOT run, CONF_STATE unchanged
# ---------------------------------------------------------------------------
@test "test_r_unknown_state_rejected_before_git_rm" {
  CONF_STATE["tracked.txt"]="r"

  apply_from_r "tracked.txt" "x"

  # File must STILL be tracked (git rm was never called)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -n "$tracked" ]

  # CONF_STATE unchanged (still 'r')
  [ "${CONF_STATE[tracked.txt]}" = "r" ]

  # Error logged with "unknown target state" message
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
  [[ "${REPORT_ERRORS[0]}" == *"unknown target state"* ]]
}

# ---------------------------------------------------------------------------
# test_r_git_rm_failure_leaves_conf_state_unchanged (C1-C-1)
# git rm fails on a non-tracked file; CONF_STATE stays 'r'; REPORT_ERRORS non-empty
# ---------------------------------------------------------------------------
@test "test_r_git_rm_failure_leaves_conf_state_unchanged" {
  CONF_STATE["nonexistent.txt"]="r"

  apply_from_r "nonexistent.txt" "i"

  # CONF_STATE must remain 'r' (unchanged)
  [ "${CONF_STATE[nonexistent.txt]}" = "r" ]

  # An error must have been logged
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# test_r_to_d_dir_unstages_and_trashes (C1-C-3)
# r→d for a directory: git unstages recursively; trash called without trailing slash
# ---------------------------------------------------------------------------
@test "test_r_to_d_dir_unstages_and_trashes" {
  # Create a directory with two files and commit them
  mkdir -p "$CLAUDE_DIR/mydir"
  echo "a" > "$CLAUDE_DIR/mydir/a.txt"
  echo "b" > "$CLAUDE_DIR/mydir/b.txt"
  git -C "$CLAUDE_DIR" add "mydir/"
  git -C "$CLAUDE_DIR" commit -m "add mydir" >/dev/null 2>&1

  CONF_STATE["mydir/"]="r"
  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls_dir.txt"

  # Mock trash to record calls
  trash() {
    echo "$1" >> "$TRASH_CALLS_FILE"
    return 0
  }
  export -f trash

  apply_from_r "mydir/" "d"

  # Directory should be removed from the index
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "mydir/")
  [ -z "$tracked" ]

  # trash was called with the absolute path WITHOUT a trailing slash
  [ -f "$TRASH_CALLS_FILE" ]
  local trash_arg
  trash_arg=$(cat "$TRASH_CALLS_FILE")
  [ "$trash_arg" = "$CLAUDE_DIR/mydir" ]

  # CONF_STATE updated
  [ "${CONF_STATE[mydir/]}" = "d" ]
}

# ---------------------------------------------------------------------------
# test_r_to_d_dry_run_no_ops (C1-C-5)
# DRY_RUN=true, r→d: no git ops, CONF_STATE unchanged, REPORT_DRY_RUN contains "dry-run"
# ---------------------------------------------------------------------------
@test "test_r_to_d_dry_run_no_ops" {
  DRY_RUN=true
  CONF_STATE["tracked.txt"]="r"

  apply_from_r "tracked.txt" "d"

  # File should STILL be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -n "$tracked" ]

  # CONF_STATE unchanged
  [ "${CONF_STATE[tracked.txt]}" = "r" ]

  # Dry-run action logged
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_r_to_empty_dry_run_no_ops (C1-C-5)
# DRY_RUN=true, r→'': no git ops, CONF_STATE unchanged, REPORT_DRY_RUN contains "dry-run"
# ---------------------------------------------------------------------------
@test "test_r_to_empty_dry_run_no_ops" {
  DRY_RUN=true
  CONF_STATE["tracked.txt"]="r"

  apply_from_r "tracked.txt" ""

  # File should STILL be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "tracked.txt")
  [ -n "$tracked" ]

  # CONF_STATE unchanged
  [ "${CONF_STATE[tracked.txt]}" = "r" ]

  # Dry-run action logged
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}
