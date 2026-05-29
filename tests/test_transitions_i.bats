#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-i-src"
mkdir -p "$CLAUDE_DIR" && git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

# ---------------------------------------------------------------------------
# Helper: create a fresh git repo with a committed file
# ---------------------------------------------------------------------------
_setup_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  # Make an initial commit so the repo has a HEAD
  touch "$dir/.gitkeep"
  git -C "$dir" add -- ".gitkeep"
  git -C "$dir" commit -m "init" >/dev/null 2>&1
}

setup() {
  TMPDIR_TEST="$BATS_TMPDIR/test-i-$$-$BATS_TEST_NUMBER"
  mkdir -p "$TMPDIR_TEST"
  _setup_repo "$TMPDIR_TEST"
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  reset_globals
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  # Ensure report arrays are initialized
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
# test_i_to_r_adds_to_git
# gitignored file; after i→r: git ls-files shows path tracked; CONF_STATE='r'; file on disk
# ---------------------------------------------------------------------------
@test "test_i_to_r_adds_to_git" {
  # Add to .gitignore so git treats it as ignored
  echo "secret.txt" >> "$CLAUDE_DIR/.gitignore"
  echo "secret content" > "$CLAUDE_DIR/secret.txt"

  CONF_STATE["secret.txt"]="i"

  apply_from_i "secret.txt" "r"

  # File should now be tracked
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "secret.txt")
  [ -n "$tracked" ]

  # CONF_STATE updated to 'r'
  [ "${CONF_STATE[secret.txt]}" = "r" ]

  # File still exists on disk
  [ -f "$CLAUDE_DIR/secret.txt" ]
}

# ---------------------------------------------------------------------------
# test_i_to_r_uses_force_add
# File is in .gitignore; plain git add would fail; verify -f was used (file IS tracked after)
# ---------------------------------------------------------------------------
@test "test_i_to_r_uses_force_add" {
  # Add to .gitignore so plain git add would reject it
  echo "ignored_file.txt" >> "$CLAUDE_DIR/.gitignore"
  echo "content" > "$CLAUDE_DIR/ignored_file.txt"

  # Verify plain git add WOULD fail (without -f)
  run git -C "$CLAUDE_DIR" add -- "ignored_file.txt"
  [ "$status" -ne 0 ]

  CONF_STATE["ignored_file.txt"]="i"

  # apply_from_i uses git add -f, so it should succeed
  apply_from_i "ignored_file.txt" "r"

  # File IS now tracked (proving -f was used)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "ignored_file.txt")
  [ -n "$tracked" ]

  [ "${CONF_STATE[ignored_file.txt]}" = "r" ]
}

# ---------------------------------------------------------------------------
# test_i_to_d_trashes_file
# mock trash; after i→d: CONF_STATE='d'; mock trash called with correct abs path (no trailing slash)
# ---------------------------------------------------------------------------
@test "test_i_to_d_trashes_file" {
  echo "to delete" > "$CLAUDE_DIR/delete_me.txt"
  CONF_STATE["delete_me.txt"]="i"

  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls.txt"

  # Mock trash to record calls
  trash() {
    echo "$1" >> "$TRASH_CALLS_FILE"
    return 0
  }
  export -f trash

  apply_from_i "delete_me.txt" "d"

  # CONF_STATE is tombstone 'd'
  [ "${CONF_STATE[delete_me.txt]}" = "d" ]

  # trash was called with absolute path (no trailing slash)
  [ -f "$TRASH_CALLS_FILE" ]
  local trash_arg
  trash_arg=$(cat "$TRASH_CALLS_FILE")
  [ "$trash_arg" = "$CLAUDE_DIR/delete_me.txt" ]
}

# ---------------------------------------------------------------------------
# test_i_to_empty_removes_from_conf_state
# after i→empty: CONF_STATE=''; file still exists on disk; no git ops
# ---------------------------------------------------------------------------
@test "test_i_to_empty_removes_from_conf_state" {
  echo "keep_me.txt" >> "$CLAUDE_DIR/.gitignore"
  echo "some content" > "$CLAUDE_DIR/keep_me.txt"
  CONF_STATE["keep_me.txt"]="i"

  apply_from_i "keep_me.txt" ""

  # CONF_STATE set to empty string
  [ "${CONF_STATE[keep_me.txt]}" = "" ]

  # File still exists on disk
  [ -f "$CLAUDE_DIR/keep_me.txt" ]

  # File is NOT tracked in git (no git add was done)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "keep_me.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_i_to_r_git_add_failure_reverts_state
# file missing from disk; git add -f fails; CONF_STATE remains 'i'; REPORT_ERRORS non-empty
# ---------------------------------------------------------------------------
@test "test_i_to_r_git_add_failure_reverts_state" {
  # Do NOT create the file — git add -f will fail on missing file
  CONF_STATE["missing_file.txt"]="i"

  apply_from_i "missing_file.txt" "r"

  # CONF_STATE must remain 'i'
  [ "${CONF_STATE[missing_file.txt]}" = "i" ]

  # Error logged
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# test_i_transitions_dry_run
# DRY_RUN=true; call i→r; git unchanged (file not added); CONF_STATE still 'i'; REPORT_DRY_RUN has "dry-run"
# ---------------------------------------------------------------------------
@test "test_i_transitions_dry_run" {
  echo "secret.txt" >> "$CLAUDE_DIR/.gitignore"
  echo "dry content" > "$CLAUDE_DIR/secret.txt"

  DRY_RUN=true
  CONF_STATE["secret.txt"]="i"

  apply_from_i "secret.txt" "r"

  # File should NOT be tracked (no git ops)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "secret.txt")
  [ -z "$tracked" ]

  # CONF_STATE unchanged (still 'i')
  [ "${CONF_STATE[secret.txt]}" = "i" ]

  # Dry-run action logged with "dry-run"
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_i_unknown_state_rejected_before_ops
# unknown target state; file NOT tracked; CONF_STATE remains 'i'; REPORT_ERRORS non-empty
# ---------------------------------------------------------------------------
@test "test_i_unknown_state_rejected_before_ops" {
  echo "some content" > "$CLAUDE_DIR/keep_me.txt"
  CONF_STATE["keep_me.txt"]="i"

  apply_from_i "keep_me.txt" "x"

  # File NOT tracked in git (git add never ran)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "keep_me.txt")
  [ -z "$tracked" ]

  # CONF_STATE remains 'i'
  [ "${CONF_STATE[keep_me.txt]}" = "i" ]

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
# test_i_to_d_trash_failure_leaves_tombstone
# trash returns 1; CONF_STATE='d' (tombstone persists); REPORT_ERRORS non-empty
# ---------------------------------------------------------------------------
@test "test_i_to_d_trash_failure_leaves_tombstone" {
  echo "content" > "$CLAUDE_DIR/fail_trash.txt"
  CONF_STATE["fail_trash.txt"]="i"

  # Mock trash to fail
  trash() { return 1; }
  export -f trash

  apply_from_i "fail_trash.txt" "d"

  # Tombstone 'd' persists even when trash fails
  [ "${CONF_STATE[fail_trash.txt]}" = "d" ]

  # REPORT_ERRORS non-empty
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# test_i_to_d_dir_strips_trailing_slash
# directory with trailing slash; trash called WITHOUT trailing slash
# ---------------------------------------------------------------------------
@test "test_i_to_d_dir_strips_trailing_slash" {
  mkdir -p "$CLAUDE_DIR/subdir"
  echo "x" > "$CLAUDE_DIR/subdir/file.txt"
  CONF_STATE["subdir/"]="i"

  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls_dir.txt"

  # Mock trash to record calls
  trash() {
    echo "$1" >> "$TRASH_CALLS_FILE"
    return 0
  }
  export -f trash

  apply_from_i "subdir/" "d"

  # CONF_STATE updated to 'd'
  [ "${CONF_STATE[subdir/]}" = "d" ]

  # trash called with path WITHOUT trailing slash
  [ -f "$TRASH_CALLS_FILE" ]
  local trash_arg
  trash_arg=$(cat "$TRASH_CALLS_FILE")
  [ "$trash_arg" = "$CLAUDE_DIR/subdir" ]
}

# ---------------------------------------------------------------------------
# test_i_to_r_dir_force_adds_recursively
# directory in .gitignore; after i→r: git ls-files shows files tracked; CONF_STATE='r'
# ---------------------------------------------------------------------------
@test "test_i_to_r_dir_force_adds_recursively" {
  echo "subdir/" >> "$CLAUDE_DIR/.gitignore"
  mkdir -p "$CLAUDE_DIR/subdir"
  echo "x" > "$CLAUDE_DIR/subdir/a.txt"
  echo "y" > "$CLAUDE_DIR/subdir/b.txt"
  CONF_STATE["subdir/"]="i"

  apply_from_i "subdir/" "r"

  # At least one file tracked under subdir/
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "subdir/")
  [ -n "$tracked" ]

  # CONF_STATE updated to 'r'
  [ "${CONF_STATE[subdir/]}" = "r" ]
}

# ---------------------------------------------------------------------------
# test_i_to_d_dry_run_no_ops
# DRY_RUN=true; i→d; CONF_STATE remains 'i'; file not deleted; REPORT_DRY_RUN has "dry-run"
# ---------------------------------------------------------------------------
@test "test_i_to_d_dry_run_no_ops" {
  echo "content" > "$CLAUDE_DIR/dry_delete.txt"
  CONF_STATE["dry_delete.txt"]="i"
  DRY_RUN=true

  apply_from_i "dry_delete.txt" "d"

  # CONF_STATE unchanged
  [ "${CONF_STATE[dry_delete.txt]}" = "i" ]

  # File still exists on disk
  [ -f "$CLAUDE_DIR/dry_delete.txt" ]

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
# test_i_to_empty_dry_run_no_ops
# DRY_RUN=true; i→empty; CONF_STATE remains 'i'; REPORT_DRY_RUN has "dry-run"
# ---------------------------------------------------------------------------
@test "test_i_to_empty_dry_run_no_ops" {
  echo "keep_me.txt" >> "$CLAUDE_DIR/.gitignore"
  echo "content" > "$CLAUDE_DIR/keep_me.txt"
  CONF_STATE["keep_me.txt"]="i"
  DRY_RUN=true

  apply_from_i "keep_me.txt" ""

  # CONF_STATE unchanged (still 'i')
  [ "${CONF_STATE[keep_me.txt]}" = "i" ]

  # REPORT_DRY_RUN has "dry-run"
  [ "${#REPORT_DRY_RUN[@]}" -gt 0 ]
  local found=false
  local entry
  for entry in "${REPORT_DRY_RUN[@]}"; do
    [[ "$entry" == *"dry-run"* ]] && found=true && break
  done
  [ "$found" = "true" ]
}
