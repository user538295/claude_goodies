#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-orch-src"
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
  TMPDIR_TEST="$BATS_TMPDIR/test-orch-$$-$BATS_TEST_NUMBER"
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
# test_new_file_added_as_pending
# Untracked file in ACTUAL_STATE but not in CONF_STATE.
# After apply_transitions: REPORT_PENDING contains filename; CONF_STATE[file]=''.
# ---------------------------------------------------------------------------
@test "test_new_file_added_as_pending" {
  echo "content" > "$CLAUDE_DIR/newfile.txt"
  ACTUAL_STATE["newfile.txt"]="untracked"

  apply_transitions

  # REPORT_PENDING contains the filename
  local found=false
  local entry
  for entry in "${REPORT_PENDING[@]}"; do
    [[ "$entry" == *"newfile.txt"* ]] && found=true && break
  done
  [ "$found" = "true" ]

  # CONF_STATE[newfile.txt]=''
  [ "${CONF_STATE[newfile.txt]}" = "" ]

  # File NOT tracked in git (no dispatch happened)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "newfile.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_transition_r_to_i_full_cycle
# File committed (actual='tracked'), conf says 'i'.
# After apply_transitions: file NOT in git index; CONF_STATE='i'.
# ---------------------------------------------------------------------------
@test "test_transition_r_to_i_full_cycle" {
  # Commit a file so it's tracked
  echo "content" > "$CLAUDE_DIR/file.txt"
  git -C "$CLAUDE_DIR" add -- "file.txt"
  git -C "$CLAUDE_DIR" commit -m "add file.txt" >/dev/null 2>&1

  ACTUAL_STATE["file.txt"]="tracked"
  CONF_STATE["file.txt"]="i"
  CONF_ORDER_TYPES=("entry")
  CONF_ORDER_PATHS=("file.txt")
  CONF_ORDER_PATH_INDEX["file.txt"]="1"

  apply_transitions

  # File should NOT be in git index after r→i
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "file.txt")
  [ -z "$tracked" ]

  # CONF_STATE updated to 'i'
  [ "${CONF_STATE[file.txt]}" = "i" ]
}

# ---------------------------------------------------------------------------
# test_idempotent_second_run
# Stable state: conf='r', actual='tracked'. Two calls to apply_transitions.
# Second call: REPORT_APPLIED should be empty (no changes needed).
# ---------------------------------------------------------------------------
@test "test_idempotent_second_run" {
  # Commit a file so it's tracked
  echo "content" > "$CLAUDE_DIR/stable.txt"
  git -C "$CLAUDE_DIR" add -- "stable.txt"
  git -C "$CLAUDE_DIR" commit -m "add stable.txt" >/dev/null 2>&1

  ACTUAL_STATE["stable.txt"]="tracked"
  CONF_STATE["stable.txt"]="r"
  CONF_ORDER_TYPES=("entry")
  CONF_ORDER_PATHS=("stable.txt")
  CONF_ORDER_PATH_INDEX["stable.txt"]="1"

  # First run
  apply_transitions
  REPORT_APPLIED=()

  # Rebuild ACTUAL_STATE for second run (file is still tracked)
  ACTUAL_STATE["stable.txt"]="tracked"

  # Second run
  apply_transitions

  # REPORT_APPLIED should be empty (idempotent)
  [ "${#REPORT_APPLIED[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_multi_state_coexistence
# 4 files with different states. Verify all transitions applied correctly.
# ---------------------------------------------------------------------------
@test "test_multi_state_coexistence" {
  # fileA: committed (actual='tracked'), conf='i' → r→i transition
  echo "a" > "$CLAUDE_DIR/fileA.txt"
  git -C "$CLAUDE_DIR" add -- "fileA.txt"
  git -C "$CLAUDE_DIR" commit -m "add fileA.txt" >/dev/null 2>&1

  # fileB: gitignored, conf='r' → i→r transition (git add -f)
  echo "fileB.txt" >> "$CLAUDE_DIR/.gitignore"
  git -C "$CLAUDE_DIR" add -- ".gitignore"
  git -C "$CLAUDE_DIR" commit -m "gitignore fileB" >/dev/null 2>&1
  echo "b" > "$CLAUDE_DIR/fileB.txt"

  # fileC: untracked, NOT in conf → pending
  echo "c" > "$CLAUDE_DIR/fileC.txt"

  # fileD: untracked, conf='d' → trash
  echo "d" > "$CLAUDE_DIR/fileD.txt"

  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls.txt"
  trash() { echo "$1" >> "$TRASH_CALLS_FILE"; return 0; }
  export -f trash

  ACTUAL_STATE["fileA.txt"]="tracked"
  ACTUAL_STATE["fileB.txt"]="ignored"
  ACTUAL_STATE["fileC.txt"]="untracked"
  ACTUAL_STATE["fileD.txt"]="untracked"

  CONF_STATE["fileA.txt"]="i"
  CONF_STATE["fileB.txt"]="r"
  CONF_STATE["fileD.txt"]="d"

  CONF_ORDER_TYPES=("entry" "entry" "entry")
  CONF_ORDER_PATHS=("fileA.txt" "fileB.txt" "fileD.txt")
  CONF_ORDER_PATH_INDEX["fileA.txt"]="1"
  CONF_ORDER_PATH_INDEX["fileB.txt"]="1"
  CONF_ORDER_PATH_INDEX["fileD.txt"]="1"

  apply_transitions

  # fileA: not in git index (r→i: git rm --cached ran)
  local tracked_a
  tracked_a=$(git -C "$CLAUDE_DIR" ls-files -- "fileA.txt")
  [ -z "$tracked_a" ]
  [ "${CONF_STATE[fileA.txt]}" = "i" ]

  # fileB: in git index (i→r: git add -f ran)
  local tracked_b
  tracked_b=$(git -C "$CLAUDE_DIR" ls-files -- "fileB.txt")
  [ -n "$tracked_b" ]
  [ "${CONF_STATE[fileB.txt]}" = "r" ]

  # fileC: in REPORT_PENDING
  local found_c=false
  local entry
  for entry in "${REPORT_PENDING[@]}"; do
    [[ "$entry" == *"fileC.txt"* ]] && found_c=true && break
  done
  [ "$found_c" = "true" ]
  [ "${CONF_STATE[fileC.txt]}" = "" ]

  # fileD: trash was called
  [ -f "$TRASH_CALLS_FILE" ]
  grep -q "fileD.txt" "$TRASH_CALLS_FILE"
  [ "${CONF_STATE[fileD.txt]}" = "d" ]
}

# ---------------------------------------------------------------------------
# test_skip_paths_prevents_all_ops
# Path in SKIP_PATHS with conf='r'. No git ops, no pending, no errors.
# ---------------------------------------------------------------------------
@test "test_skip_paths_prevents_all_ops" {
  echo "content" > "$CLAUDE_DIR/skipme.txt"
  ACTUAL_STATE["skipme.txt"]="untracked"
  CONF_STATE["skipme.txt"]="r"
  CONF_ORDER_TYPES=("entry")
  CONF_ORDER_PATHS=("skipme.txt")
  CONF_ORDER_PATH_INDEX["skipme.txt"]="1"
  SKIP_PATHS=("skipme.txt")

  apply_transitions

  # File NOT in git index (no git add ran)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "skipme.txt")
  [ -z "$tracked" ]

  # REPORT_APPLIED empty
  [ "${#REPORT_APPLIED[@]}" -eq 0 ]

  # REPORT_ERRORS empty
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_dry_run_no_state_mutation (C1-D-1, C1-T-8)
# DRY_RUN=true, new file in ACTUAL_STATE. Assert: REPORT_PENDING populated,
# CONF_STATE NOT mutated, conf file NOT written.
# ---------------------------------------------------------------------------
@test "test_dry_run_no_state_mutation" {
  echo "content" > "$CLAUDE_DIR/newfile.txt"
  ACTUAL_STATE["newfile.txt"]="untracked"
  DRY_RUN=true

  apply_transitions

  # REPORT_PENDING still populated (user sees pending even in dry-run)
  local found=false
  local entry
  for entry in "${REPORT_PENDING[@]}"; do
    [[ "$entry" == *"newfile.txt"* ]] && found=true && break
  done
  [ "$found" = "true" ]

  # CONF_STATE NOT mutated in dry-run
  [ "${CONF_STATE[newfile.txt]+set}" != "set" ]

  # CONF_ORDER_PATH_INDEX NOT mutated
  [ "${CONF_ORDER_PATH_INDEX[newfile.txt]+set}" != "set" ]

  # Conf file NOT written (write_conf is no-op in DRY_RUN)
  [ ! -f "$CONF_FILE" ]
}

# ---------------------------------------------------------------------------
# test_pending_path_on_rerun_is_silent (C1-T-1)
# Path already in CONF_ORDER_PATH_INDEX with conf=''. Second run should NOT
# re-add to REPORT_PENDING, should skip dispatch.
# ---------------------------------------------------------------------------
@test "test_pending_path_on_rerun_is_silent" {
  echo "content" > "$CLAUDE_DIR/pending.txt"
  ACTUAL_STATE["pending.txt"]="untracked"
  CONF_STATE["pending.txt"]=""
  CONF_ORDER_TYPES=("entry")
  CONF_ORDER_PATHS=("pending.txt")
  CONF_ORDER_PATH_INDEX["pending.txt"]="1"

  apply_transitions

  # REPORT_PENDING should NOT contain the file (already known, not re-added)
  local found=false
  local entry
  for entry in "${REPORT_PENDING[@]}"; do
    [[ "$entry" == *"pending.txt"* ]] && found=true && break
  done
  [ "$found" = "false" ]

  # File NOT tracked in git (no dispatch)
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "pending.txt")
  [ -z "$tracked" ]
}

# ---------------------------------------------------------------------------
# test_conf_d_actual_tracked_dispatches_delete (C1-T-2)
# conf='d', file committed and tracked. After apply_transitions:
# file removed from git index; trash called.
# ---------------------------------------------------------------------------
@test "test_conf_d_actual_tracked_dispatches_delete" {
  echo "content" > "$CLAUDE_DIR/todelete.txt"
  git -C "$CLAUDE_DIR" add -- "todelete.txt"
  git -C "$CLAUDE_DIR" commit -m "add todelete.txt" >/dev/null 2>&1

  TRASH_CALLS_FILE="$TMPDIR_TEST/trash_calls.txt"
  trash() { echo "$1" >> "$TRASH_CALLS_FILE"; return 0; }
  export -f trash

  ACTUAL_STATE["todelete.txt"]="tracked"
  CONF_STATE["todelete.txt"]="d"
  CONF_ORDER_TYPES=("entry")
  CONF_ORDER_PATHS=("todelete.txt")
  CONF_ORDER_PATH_INDEX["todelete.txt"]="1"

  apply_transitions

  # File removed from git index
  local tracked
  tracked=$(git -C "$CLAUDE_DIR" ls-files -- "todelete.txt")
  [ -z "$tracked" ]

  # trash was called
  [ -f "$TRASH_CALLS_FILE" ]

  # CONF_STATE is 'd' tombstone
  [ "${CONF_STATE[todelete.txt]}" = "d" ]
}

# ---------------------------------------------------------------------------
# test_write_conf_persists_after_transitions (C1-T-6)
# After a transition, conf file should be written with updated state.
# ---------------------------------------------------------------------------
@test "test_write_conf_persists_after_transitions" {
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  git -C "$CLAUDE_DIR" add -- "tracked.txt"
  git -C "$CLAUDE_DIR" commit -m "add tracked.txt" >/dev/null 2>&1

  ACTUAL_STATE["tracked.txt"]="tracked"
  CONF_STATE["tracked.txt"]="i"
  CONF_ORDER_TYPES=("entry")
  CONF_ORDER_PATHS=("tracked.txt")
  CONF_ORDER_PATH_INDEX["tracked.txt"]="1"

  apply_transitions

  # Conf file should exist
  [ -f "$CONF_FILE" ]

  # Conf file should contain tracked.txt=i
  grep -q "tracked.txt=i" "$CONF_FILE"
}

# ---------------------------------------------------------------------------
# test_conf_d_actual_missing_is_stable_noop (C1-T-4)
# CONF='d', file not on disk and not in index — stable tombstone.
# Assert: no errors, no applied changes.
# ---------------------------------------------------------------------------
@test "test_conf_d_actual_missing_is_stable_noop" {
  # File does not exist on disk or in git index
  ACTUAL_STATE["gone.txt"]="missing"
  CONF_STATE["gone.txt"]="d"
  CONF_ORDER_TYPES=("entry")
  CONF_ORDER_PATHS=("gone.txt")
  CONF_ORDER_PATH_INDEX["gone.txt"]="1"

  apply_transitions

  # No errors
  [ "${#REPORT_ERRORS[@]}" -eq 0 ]

  # No applied changes
  [ "${#REPORT_APPLIED[@]}" -eq 0 ]

  # CONF_STATE stays 'd'
  [ "${CONF_STATE[gone.txt]}" = "d" ]
}
