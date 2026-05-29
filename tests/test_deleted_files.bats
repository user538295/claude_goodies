#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-deleted-src"
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
  TMPDIR_TEST="$BATS_TMPDIR/test-deleted-$$-$BATS_TEST_NUMBER"
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
# Helper: commit a file so it exists in HEAD
# ---------------------------------------------------------------------------
_commit_file() {
  local filename="$1"
  echo "content" > "$CLAUDE_DIR/$filename"
  git -C "$CLAUDE_DIR" add -- "$filename"
  git -C "$CLAUDE_DIR" commit -m "add $filename" >/dev/null 2>&1
}

# Helper: set up standard CONF_ORDER arrays for a single path
_set_conf_order() {
  local path="$1"
  CONF_ORDER_TYPES=("entry")
  CONF_ORDER_PATHS=("$path")
  CONF_ORDER_PATH_INDEX["$path"]="1"
}

# ---------------------------------------------------------------------------
# test_deleted_r_file_restored
# CONF='r', file missing from disk, file was committed → assert git restore
# called; CONF_STATE still 'r'; ACTUAL_STATE[path]='tracked'; NOT in SKIP_PATHS
# ---------------------------------------------------------------------------
@test "test_deleted_r_file_restored" {
  _commit_file "restore-me.txt"
  rm "$CLAUDE_DIR/restore-me.txt"

  CONF_STATE["restore-me.txt"]="r"
  ACTUAL_STATE["restore-me.txt"]="missing"
  _set_conf_order "restore-me.txt"

  handle_deleted_files

  # File should be back on disk (git restore ran)
  [ -f "$CLAUDE_DIR/restore-me.txt" ]

  # CONF_STATE still 'r'
  [ "${CONF_STATE[restore-me.txt]}" = "r" ]

  # ACTUAL_STATE updated to 'tracked'
  [ "${ACTUAL_STATE[restore-me.txt]}" = "tracked" ]

  # NOT in SKIP_PATHS
  local found=false
  local p
  for p in "${SKIP_PATHS[@]+"${SKIP_PATHS[@]}"}"; do
    [[ "$p" == "restore-me.txt" ]] && found=true && break
  done
  [ "$found" = "false" ]
}

# ---------------------------------------------------------------------------
# test_deleted_r_file_never_committed_logs_warning
# CONF='r', file never committed, not on disk → git restore fails; CONF_STATE
# stays 'r'; warning in REPORT_ERRORS; path added to SKIP_PATHS
# ---------------------------------------------------------------------------
@test "test_deleted_r_file_never_committed_logs_warning" {
  # File never committed (not in HEAD), not on disk

  CONF_STATE["ghost.txt"]="r"
  ACTUAL_STATE["ghost.txt"]="missing"
  _set_conf_order "ghost.txt"

  handle_deleted_files

  # CONF_STATE still 'r'
  [ "${CONF_STATE[ghost.txt]}" = "r" ]

  # Path IS in SKIP_PATHS
  local found=false
  local p
  for p in "${SKIP_PATHS[@]+"${SKIP_PATHS[@]}"}"; do
    [[ "$p" == "ghost.txt" ]] && found=true && break
  done
  [ "$found" = "true" ]

  # Warning logged to REPORT_ERRORS
  [ "${#REPORT_ERRORS[@]}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# test_deleted_i_file_removed_from_conf
# CONF='i', file gone from disk, NOT in git index → remove from CONF_STATE
# and CONF_ORDER_PATH_INDEX; no git op needed
# ---------------------------------------------------------------------------
@test "test_deleted_i_file_removed_from_conf" {
  # File never committed and not on disk

  CONF_STATE["gone-i.txt"]="i"
  ACTUAL_STATE["gone-i.txt"]="missing"
  _set_conf_order "gone-i.txt"

  handle_deleted_files

  # CONF_STATE key removed
  [ "${CONF_STATE[gone-i.txt]+set}" != "set" ]

  # CONF_ORDER_PATH_INDEX entry unset
  [ "${CONF_ORDER_PATH_INDEX[gone-i.txt]+set}" != "set" ]

  # No errors
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]

  # ACTUAL_STATE entry also cleared
  [ "${ACTUAL_STATE[gone-i.txt]+set}" != "set" ]
}

# ---------------------------------------------------------------------------
# test_deleted_i_file_tracked_runs_git_rm_cached
# CONF='i', file missing from disk but committed and tracked in git index →
# git rm --cached; CONF_STATE key removed; file not in git index; path index unset
# ---------------------------------------------------------------------------
@test "test_deleted_i_file_tracked_runs_git_rm_cached" {
  _commit_file "tracked-i.txt"
  rm "$CLAUDE_DIR/tracked-i.txt"
  # File is gone from disk but still in git index

  CONF_STATE["tracked-i.txt"]="i"
  ACTUAL_STATE["tracked-i.txt"]="missing"
  _set_conf_order "tracked-i.txt"

  handle_deleted_files

  # CONF_STATE key removed
  [ "${CONF_STATE[tracked-i.txt]+set}" != "set" ]

  # File no longer in git index
  local in_index
  in_index=$(git -C "$CLAUDE_DIR" ls-files -- "tracked-i.txt")
  [ -z "$in_index" ]

  # CONF_ORDER_PATH_INDEX unset
  [ "${CONF_ORDER_PATH_INDEX[tracked-i.txt]+set}" != "set" ]

  # No errors
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_deleted_d_tombstone_cleared
# CONF='d', file gone from disk, NOT in git index → tombstone removed from
# CONF_STATE and CONF_ORDER_PATH_INDEX; no git op needed
# ---------------------------------------------------------------------------
@test "test_deleted_d_tombstone_cleared" {
  # File never committed, not on disk, not in git index

  CONF_STATE["dead.txt"]="d"
  ACTUAL_STATE["dead.txt"]="missing"
  _set_conf_order "dead.txt"

  handle_deleted_files

  # CONF_STATE key removed
  [ "${CONF_STATE[dead.txt]+set}" != "set" ]

  # CONF_ORDER_PATH_INDEX unset
  [ "${CONF_ORDER_PATH_INDEX[dead.txt]+set}" != "set" ]

  # No errors
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]

  # ACTUAL_STATE entry also cleared
  [ "${ACTUAL_STATE[dead.txt]+set}" != "set" ]
}

# ---------------------------------------------------------------------------
# test_deleted_d_file_in_index_runs_git_rm_cached
# CONF='d', file missing from disk but still in git index → git rm --cached;
# tombstone removed from CONF_STATE and CONF_ORDER_PATH_INDEX
# ---------------------------------------------------------------------------
@test "test_deleted_d_file_in_index_runs_git_rm_cached" {
  _commit_file "indexed-d.txt"
  rm "$CLAUDE_DIR/indexed-d.txt"
  # File is gone from disk but still in git index

  CONF_STATE["indexed-d.txt"]="d"
  ACTUAL_STATE["indexed-d.txt"]="missing"
  _set_conf_order "indexed-d.txt"

  handle_deleted_files

  # CONF_STATE key removed
  [ "${CONF_STATE[indexed-d.txt]+set}" != "set" ]

  # File no longer in git index
  local in_index
  in_index=$(git -C "$CLAUDE_DIR" ls-files -- "indexed-d.txt")
  [ -z "$in_index" ]

  # CONF_ORDER_PATH_INDEX unset
  [ "${CONF_ORDER_PATH_INDEX[indexed-d.txt]+set}" != "set" ]

  # No errors
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_deleted_pending_removed_from_conf
# CONF='', file gone → remove from CONF_STATE and CONF_ORDER_PATH_INDEX
# ---------------------------------------------------------------------------
@test "test_deleted_pending_removed_from_conf" {
  CONF_STATE["pending.txt"]=""
  ACTUAL_STATE["pending.txt"]="missing"
  _set_conf_order "pending.txt"

  handle_deleted_files

  # CONF_STATE key removed
  [ "${CONF_STATE[pending.txt]+set}" != "set" ]

  # CONF_ORDER_PATH_INDEX unset
  [ "${CONF_ORDER_PATH_INDEX[pending.txt]+set}" != "set" ]

  # No errors
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]

  # ACTUAL_STATE entry also cleared
  [ "${ACTUAL_STATE[pending.txt]+set}" != "set" ]
}

# ---------------------------------------------------------------------------
# test_conf_order_arrays_rebuilt_correctly_after_removal
# 3 entries: remove the middle one. Verify CONF_ORDER_PATHS and CONF_ORDER_TYPES
# contain only the 2 remaining entries in correct order.
# ---------------------------------------------------------------------------
@test "test_conf_order_arrays_rebuilt_correctly_after_removal" {
  # Set up 3 entries
  CONF_STATE["alpha.txt"]="r"
  CONF_STATE["gone-i.txt"]="i"
  CONF_STATE["zeta.txt"]="d"
  CONF_ORDER_TYPES=("entry" "entry" "entry")
  CONF_ORDER_PATHS=("alpha.txt" "gone-i.txt" "zeta.txt")
  CONF_ORDER_PATH_INDEX["alpha.txt"]="1"
  CONF_ORDER_PATH_INDEX["gone-i.txt"]="1"
  CONF_ORDER_PATH_INDEX["zeta.txt"]="1"

  # Only gone-i.txt is missing from disk (alpha and zeta have files)
  echo "content" > "$CLAUDE_DIR/alpha.txt"
  echo "content" > "$CLAUDE_DIR/zeta.txt"
  # gone-i.txt not on disk, not in git index

  handle_deleted_files

  # gone-i.txt removed from CONF_STATE
  [ "${CONF_STATE[gone-i.txt]+set}" != "set" ]

  # CONF_ORDER_PATHS must NOT contain gone-i.txt
  local p; local found=false
  for p in "${CONF_ORDER_PATHS[@]+"${CONF_ORDER_PATHS[@]}"}"; do
    [[ "$p" == "gone-i.txt" ]] && found=true && break
  done
  [ "$found" = "false" ]

  # CONF_ORDER_PATHS must still contain alpha.txt and zeta.txt
  local has_alpha=false has_zeta=false
  for p in "${CONF_ORDER_PATHS[@]+"${CONF_ORDER_PATHS[@]}"}"; do
    [[ "$p" == "alpha.txt" ]] && has_alpha=true
    [[ "$p" == "zeta.txt" ]] && has_zeta=true
  done
  [ "$has_alpha" = "true" ]
  [ "$has_zeta" = "true" ]

  # CONF_ORDER_PATHS should have exactly 2 entries
  [ "${#CONF_ORDER_PATHS[@]}" -eq 2 ]

  # CONF_ORDER_TYPES must NOT contain the removed entry's type
  # (CONF_ORDER_TYPES and CONF_ORDER_PATHS must be same length)
  [ "${#CONF_ORDER_TYPES[@]}" -eq 2 ]

  # Remaining state untouched
  [ "${CONF_STATE[alpha.txt]}" = "r" ]
  [ "${CONF_STATE[zeta.txt]}" = "d" ]
}

# ---------------------------------------------------------------------------
# test_deleted_i_git_rm_failure_logs_error_and_keeps_conf
# CONF='i', file tracked in git index, but git rm --cached fails → REPORT_ERRORS
# populated; CONF_STATE key NOT removed; CONF_ORDER_PATH_INDEX still set.
# ---------------------------------------------------------------------------
@test "test_deleted_i_git_rm_failure_logs_error_and_keeps_conf" {
  _commit_file "tracked-fail.txt"
  rm "$CLAUDE_DIR/tracked-fail.txt"

  CONF_STATE["tracked-fail.txt"]="i"
  ACTUAL_STATE["tracked-fail.txt"]="missing"
  _set_conf_order "tracked-fail.txt"

  # Override git to fail only on rm --cached
  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    CONF_FILE='$CONF_FILE'
    $(declare -p CONF_STATE)
    $(declare -p CONF_ORDER_TYPES)
    $(declare -p CONF_ORDER_PATHS)
    $(declare -p CONF_ORDER_PATH_INDEX)
    $(declare -p ACTUAL_STATE)
    git() {
      local arg; for arg in \"\$@\"; do
        if [[ \"\$arg\" == rm ]]; then return 1; fi
      done
      command git \"\$@\"
    }
    export -f git
    handle_deleted_files
    echo \"CONF_STATE_key=\${CONF_STATE[tracked-fail.txt]:-REMOVED}\"
    echo \"ERRORS_count=\${#REPORT_ERRORS[@]}\"
  " <<< ""

  [ "$status" -eq 0 ]
  # Key must NOT be removed
  [[ "$output" == *"CONF_STATE_key=i"* ]]
  # Error must be logged
  [[ "$output" == *"ERRORS_count=1"* ]]
}

# ---------------------------------------------------------------------------
# test_deleted_d_git_rm_failure_logs_error_and_keeps_tombstone
# CONF='d', file in git index, git rm --cached fails → REPORT_ERRORS populated;
# tombstone NOT removed.
# ---------------------------------------------------------------------------
@test "test_deleted_d_git_rm_failure_logs_error_and_keeps_tombstone" {
  _commit_file "d-fail.txt"
  rm "$CLAUDE_DIR/d-fail.txt"

  CONF_STATE["d-fail.txt"]="d"
  ACTUAL_STATE["d-fail.txt"]="missing"
  _set_conf_order "d-fail.txt"

  run bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    CONF_FILE='$CONF_FILE'
    $(declare -p CONF_STATE)
    $(declare -p CONF_ORDER_TYPES)
    $(declare -p CONF_ORDER_PATHS)
    $(declare -p CONF_ORDER_PATH_INDEX)
    $(declare -p ACTUAL_STATE)
    git() {
      local arg; for arg in \"\$@\"; do
        if [[ \"\$arg\" == rm ]]; then return 1; fi
      done
      command git \"\$@\"
    }
    export -f git
    handle_deleted_files
    echo \"CONF_STATE_key=\${CONF_STATE[d-fail.txt]:-REMOVED}\"
    echo \"ERRORS_count=\${#REPORT_ERRORS[@]}\"
  " <<< ""

  [ "$status" -eq 0 ]
  # Tombstone must NOT be removed
  [[ "$output" == *"CONF_STATE_key=d"* ]]
  # Error must be logged
  [[ "$output" == *"ERRORS_count=1"* ]]
}

# ---------------------------------------------------------------------------
# test_ordering_deleted_files_before_transitions (integration)
# Deleted 'i' file that is tracked in git: handle_deleted_files removes it
# from CONF_STATE so apply_transitions never sees it.
# ---------------------------------------------------------------------------
@test "test_ordering_deleted_files_before_transitions" {
  _commit_file "foo.sh"
  rm "$CLAUDE_DIR/foo.sh"

  CONF_STATE["foo.sh"]="i"
  ACTUAL_STATE["foo.sh"]="missing"
  _set_conf_order "foo.sh"

  handle_deleted_files

  # After handle_deleted_files: foo.sh removed from CONF_STATE
  [ "${CONF_STATE[foo.sh]+set}" != "set" ]

  # Not in git index
  local in_index
  in_index=$(git -C "$CLAUDE_DIR" ls-files -- "foo.sh")
  [ -z "$in_index" ]

  # Now run apply_transitions — foo.sh is not in CONF_STATE so not processed
  apply_transitions

  # Still not in CONF_STATE after transitions
  [ "${CONF_STATE[foo.sh]+set}" != "set" ]

  # Still not in git index
  in_index=$(git -C "$CLAUDE_DIR" ls-files -- "foo.sh")
  [ -z "$in_index" ]

  # Not on disk
  [ ! -f "$CLAUDE_DIR/foo.sh" ]
}

# ---------------------------------------------------------------------------
# test_skip_paths_r_restore_success_stays_in_conf
# CONF='r', file missing, git restore succeeds → CONF_STATE still 'r',
# path NOT in SKIP_PATHS, ACTUAL_STATE[path]='tracked'
# ---------------------------------------------------------------------------
@test "test_skip_paths_r_restore_success_stays_in_conf" {
  _commit_file "revive.txt"
  rm "$CLAUDE_DIR/revive.txt"

  CONF_STATE["revive.txt"]="r"
  ACTUAL_STATE["revive.txt"]="missing"
  _set_conf_order "revive.txt"

  handle_deleted_files

  # CONF_STATE still 'r'
  [ "${CONF_STATE[revive.txt]}" = "r" ]

  # NOT in SKIP_PATHS
  local found=false
  local p
  for p in "${SKIP_PATHS[@]+"${SKIP_PATHS[@]}"}"; do
    [[ "$p" == "revive.txt" ]] && found=true && break
  done
  [ "$found" = "false" ]

  # ACTUAL_STATE updated
  [ "${ACTUAL_STATE[revive.txt]}" = "tracked" ]
}

# ---------------------------------------------------------------------------
# test_skip_paths_r_restore_failure_path_in_skip_list
# CONF='r', file missing, git restore fails (never committed) → CONF_STATE
# still 'r', path IS in SKIP_PATHS
# ---------------------------------------------------------------------------
@test "test_skip_paths_r_restore_failure_path_in_skip_list" {
  # File never committed — git restore will fail

  CONF_STATE["never-was.txt"]="r"
  ACTUAL_STATE["never-was.txt"]="missing"
  _set_conf_order "never-was.txt"

  handle_deleted_files

  # CONF_STATE still 'r'
  [ "${CONF_STATE[never-was.txt]}" = "r" ]

  # Path IS in SKIP_PATHS
  local found=false
  local p
  for p in "${SKIP_PATHS[@]+"${SKIP_PATHS[@]}"}"; do
    [[ "$p" == "never-was.txt" ]] && found=true && break
  done
  [ "$found" = "true" ]
}

# ---------------------------------------------------------------------------
# test_file_on_disk_skipped
# File IS on disk with CONF='i' — handle_deleted_files must NOT touch it
# ---------------------------------------------------------------------------
@test "test_file_on_disk_skipped" {
  echo "here" > "$CLAUDE_DIR/present.txt"

  CONF_STATE["present.txt"]="i"
  ACTUAL_STATE["present.txt"]="untracked"
  _set_conf_order "present.txt"

  handle_deleted_files

  # CONF_STATE unchanged
  [ "${CONF_STATE[present.txt]}" = "i" ]

  # CONF_ORDER_PATH_INDEX unchanged
  [ "${CONF_ORDER_PATH_INDEX[present.txt]+set}" = "set" ]

  # No errors
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]
}
