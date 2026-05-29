#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-commit-src"
mkdir -p "$CLAUDE_DIR" && git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

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
  TMPDIR_TEST="$BATS_TMPDIR/test-commit-$$-$BATS_TEST_NUMBER"
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
  DRY_RUN=""
}

teardown() { [[ -d "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST"; }

# ---------------------------------------------------------------------------
# Helper: stage a file so there are staged changes
# ---------------------------------------------------------------------------
_stage_file() {
  local filename="${1:-staged.txt}"
  echo "content" > "$CLAUDE_DIR/$filename"
  git -C "$CLAUDE_DIR" add -- "$filename"
}

# ---------------------------------------------------------------------------
# test_nothing_to_commit_when_no_staged_changes
# No staged changes; assert "Nothing to commit" printed; no commit created.
# ---------------------------------------------------------------------------
@test "test_nothing_to_commit_when_no_staged_changes" {
  local log_before
  log_before=$(git -C "$CLAUDE_DIR" log --oneline | wc -l)

  # Pipe empty string to avoid blocking on read
  run bash -c "source '$SCRIPT'; CLAUDE_DIR='$CLAUDE_DIR'; commit_and_push" <<< ""

  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to commit"* ]]

  local log_after
  log_after=$(git -C "$CLAUDE_DIR" log --oneline | wc -l)
  [ "$log_before" -eq "$log_after" ]
}

# ---------------------------------------------------------------------------
# test_empty_message_aborts
# Provide empty commit message; assert "Aborted" printed; no commit created.
# ---------------------------------------------------------------------------
@test "test_empty_message_aborts" {
  _stage_file "new.txt"

  local log_before
  log_before=$(git -C "$CLAUDE_DIR" log --oneline | wc -l)

  # First read (commit message) = empty; function should abort before push prompt
  run bash -c "source '$SCRIPT'; CLAUDE_DIR='$CLAUDE_DIR'; CONF_FILE='$CONF_FILE'; commit_and_push" <<< ""

  [ "$status" -eq 0 ]
  [[ "$output" == *"Aborted"* ]]

  local log_after
  log_after=$(git -C "$CLAUDE_DIR" log --oneline | wc -l)
  [ "$log_before" -eq "$log_after" ]
}

# ---------------------------------------------------------------------------
# test_commit_created_with_message
# Provide message + decline push; assert git log shows commit with that message.
# ---------------------------------------------------------------------------
@test "test_commit_created_with_message" {
  _stage_file "committed.txt"

  # Input: commit message "my test commit", then "n" to decline push
  run bash -c "source '$SCRIPT'; CLAUDE_DIR='$CLAUDE_DIR'; CONF_FILE='$CONF_FILE'; commit_and_push" <<< $'my test commit\nn'

  [ "$status" -eq 0 ]

  local last_msg
  last_msg=$(git -C "$CLAUDE_DIR" log --oneline -1)
  [[ "$last_msg" == *"my test commit"* ]]
  [[ "$output" == *"Commit created"* ]]
}

# ---------------------------------------------------------------------------
# test_d_tombstones_removed_from_conf_after_commit
# Set up CONF='d' for a file that was trashed + git rm --cached'd.
# Commit. Assert tombstone removed from CONF_STATE (live check, not ACTUAL_STATE).
# ---------------------------------------------------------------------------
@test "test_d_tombstones_removed_from_conf_after_commit" {
  # Stage an unrelated file so there's something to commit
  _stage_file "other.txt"

  # Simulate: file was deleted (not on disk, not in git index)
  # CONF_STATE still has 'd' tombstone
  CONF_STATE["deleted.txt"]="d"
  CONF_ORDER_TYPES=("entry" "entry")
  CONF_ORDER_PATHS=("other.txt" "deleted.txt")
  CONF_ORDER_PATH_INDEX["other.txt"]="1"
  CONF_ORDER_PATH_INDEX["deleted.txt"]="1"
  # ACTUAL_STATE deliberately says 'tracked' to prove we DON'T use it
  ACTUAL_STATE["deleted.txt"]="tracked"

  # Input: commit message + decline push
  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    CONF_FILE='$CONF_FILE'
    $(declare -p CONF_STATE)
    $(declare -p CONF_ORDER_TYPES)
    $(declare -p CONF_ORDER_PATHS)
    $(declare -p CONF_ORDER_PATH_INDEX)
    $(declare -p ACTUAL_STATE)
    commit_and_push
    # Print CONF_STATE contents for assertion
    echo "CONF_STATE_deleted_txt=\${CONF_STATE[deleted.txt]:-REMOVED}"
  " <<< $'remove tombstone test\nn'

  [ "$status" -eq 0 ]
  # Tombstone should be removed — file not on disk and not in index
  [[ "$output" == *"CONF_STATE_deleted_txt=REMOVED"* ]]

  # Verify tombstone was also removed from the conf file on disk
  ! grep -q "deleted.txt" "$CONF_FILE" 2>/dev/null || [ ! -f "$CONF_FILE" ]
}

# ---------------------------------------------------------------------------
# test_d_tombstone_kept_when_file_on_disk
# CONF='d' tombstone, file still exists on disk → tombstone must NOT be removed.
# ---------------------------------------------------------------------------
@test "test_d_tombstone_kept_when_file_on_disk" {
  _stage_file "other.txt"

  # File exists on disk (not deleted)
  echo "still here" > "$CLAUDE_DIR/keepme.txt"

  CONF_STATE["keepme.txt"]="d"
  CONF_ORDER_TYPES=("entry" "entry")
  CONF_ORDER_PATHS=("other.txt" "keepme.txt")
  CONF_ORDER_PATH_INDEX["other.txt"]="1"
  CONF_ORDER_PATH_INDEX["keepme.txt"]="1"

  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    CONF_FILE='$CONF_FILE'
    $(declare -p CONF_STATE)
    $(declare -p CONF_ORDER_TYPES)
    $(declare -p CONF_ORDER_PATHS)
    $(declare -p CONF_ORDER_PATH_INDEX)
    commit_and_push
    echo \"CONF_STATE_keepme=\${CONF_STATE[keepme.txt]:-REMOVED}\"
  " <<< $'keep tombstone test\nn'

  [ "$status" -eq 0 ]
  # Tombstone must still be 'd' — file is still on disk
  [[ "$output" == *"CONF_STATE_keepme=d"* ]]
}

# ---------------------------------------------------------------------------
# test_d_tombstone_kept_when_file_in_index
# CONF='d' tombstone, file not on disk but still in git index → tombstone kept.
# ---------------------------------------------------------------------------
@test "test_d_tombstone_kept_when_file_in_index" {
  # Stage the "other" file for the commit
  _stage_file "other.txt"

  # Add a file to git index but don't create it on disk (simulate: deleted from disk but not yet git rm --cached'd)
  echo "indexed" > "$CLAUDE_DIR/indexed.txt"
  git -C "$CLAUDE_DIR" add -- "indexed.txt"
  rm "$CLAUDE_DIR/indexed.txt"  # remove from disk but leave in index

  CONF_STATE["indexed.txt"]="d"
  CONF_ORDER_TYPES=("entry" "entry")
  CONF_ORDER_PATHS=("other.txt" "indexed.txt")
  CONF_ORDER_PATH_INDEX["other.txt"]="1"
  CONF_ORDER_PATH_INDEX["indexed.txt"]="1"

  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    CONF_FILE='$CONF_FILE'
    $(declare -p CONF_STATE)
    $(declare -p CONF_ORDER_TYPES)
    $(declare -p CONF_ORDER_PATHS)
    $(declare -p CONF_ORDER_PATH_INDEX)
    commit_and_push
    echo \"CONF_STATE_indexed=\${CONF_STATE[indexed.txt]:-REMOVED}\"
  " <<< $'keep in-index tombstone\nn'

  [ "$status" -eq 0 ]
  # Tombstone must still be 'd' — file is still in the git index
  [[ "$output" == *"CONF_STATE_indexed=d"* ]]
}

# ---------------------------------------------------------------------------
# test_push_failure_does_not_error
# Mock git push to return 1; assert exit status is 0.
# ---------------------------------------------------------------------------
@test "test_push_failure_does_not_error" {
  _stage_file "pushed.txt"

  # Override git to fail only on push
  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    CONF_FILE='$CONF_FILE'
    git() {
      local arg; for arg in \"\$@\"; do [[ \"\$arg\" == push ]] && return 1; done
      command git \"\$@\"
    }
    export -f git
    commit_and_push
  " <<< $'commit message here\ny'

  [ "$status" -eq 0 ]
  [[ "$output" == *"Push failed"* ]]
}

# ---------------------------------------------------------------------------
# test_dry_run_skips_commit
# DRY_RUN=true; assert no commit created.
# ---------------------------------------------------------------------------
@test "test_dry_run_skips_commit" {
  _stage_file "dryfile.txt"

  local log_before
  log_before=$(git -C "$CLAUDE_DIR" log --oneline | wc -l)

  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    DRY_RUN=true
    commit_and_push
  " <<< ""

  [ "$status" -eq 0 ]

  local log_after
  log_after=$(git -C "$CLAUDE_DIR" log --oneline | wc -l)
  [ "$log_before" -eq "$log_after" ]
}

# ---------------------------------------------------------------------------
# test_d_tombstone_persists_when_no_commit
# CONF_STATE['file']='d', file gone. First write_conf (pre-commit) keeps tombstone.
# User aborts (empty message). parse_conf on conf file → 'd' still present.
# ---------------------------------------------------------------------------
@test "test_d_tombstone_persists_when_no_commit" {
  # Write a conf file with a tombstone
  printf 'deleted.txt=d\n' > "$CONF_FILE"
  parse_conf

  # Verify 'd' is in CONF_STATE
  [ "${CONF_STATE[deleted.txt]}" = "d" ]

  # Stage something, then abort commit with empty message
  _stage_file "staged.txt"

  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    CONF_FILE='$CONF_FILE'
    parse_conf
    commit_and_push
  " <<< ""

  [ "$status" -eq 0 ]
  # Parse conf file again — tombstone must still be there
  reset_globals
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$TMPDIR_TEST/sync-answers.conf"
  parse_conf

  [ "${CONF_STATE[deleted.txt]}" = "d" ]
}

# ---------------------------------------------------------------------------
# test_multiple_tombstones_mixed_outcomes
# Three tombstones: one truly gone (remove), one on disk (keep), one in index (keep).
# After commit, assert only the truly-gone one is removed.
# ---------------------------------------------------------------------------
@test "test_multiple_tombstones_mixed_outcomes" {
  # Stage an unrelated file for the commit
  _stage_file "other.txt"

  # gone.txt — not on disk, not in index → should be REMOVED
  # ondisk.txt — exists on disk → tombstone kept
  echo "still here" > "$CLAUDE_DIR/ondisk.txt"
  # inindex.txt — not on disk, but in git index → tombstone kept
  echo "indexed" > "$CLAUDE_DIR/inindex.txt"
  git -C "$CLAUDE_DIR" add -- "inindex.txt"
  rm "$CLAUDE_DIR/inindex.txt"

  CONF_STATE["gone.txt"]="d"
  CONF_STATE["ondisk.txt"]="d"
  CONF_STATE["inindex.txt"]="d"
  CONF_ORDER_TYPES=("entry" "entry" "entry" "entry")
  CONF_ORDER_PATHS=("other.txt" "gone.txt" "ondisk.txt" "inindex.txt")
  CONF_ORDER_PATH_INDEX["other.txt"]="1"
  CONF_ORDER_PATH_INDEX["gone.txt"]="1"
  CONF_ORDER_PATH_INDEX["ondisk.txt"]="1"
  CONF_ORDER_PATH_INDEX["inindex.txt"]="1"

  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    CONF_FILE='$CONF_FILE'
    $(declare -p CONF_STATE)
    $(declare -p CONF_ORDER_TYPES)
    $(declare -p CONF_ORDER_PATHS)
    $(declare -p CONF_ORDER_PATH_INDEX)
    commit_and_push
    echo \"gone=\${CONF_STATE[gone.txt]:-REMOVED}\"
    echo \"ondisk=\${CONF_STATE[ondisk.txt]:-REMOVED}\"
    echo \"inindex=\${CONF_STATE[inindex.txt]:-REMOVED}\"
  " <<< $'multi tombstone test\nn'

  [ "$status" -eq 0 ]
  [[ "$output" == *"gone=REMOVED"* ]]
  [[ "$output" == *"ondisk=d"* ]]
  [[ "$output" == *"inindex=d"* ]]
}
