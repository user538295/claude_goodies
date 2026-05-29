#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-main-src"
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
  TMPDIR_TEST="$BATS_TMPDIR/test-main-$$-$BATS_TEST_NUMBER"
  _setup_repo "$TMPDIR_TEST"
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  reset_globals
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
}

teardown() { [[ -d "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST"; }

# ---------------------------------------------------------------------------
# test_unknown_flag_exits_1
# ---------------------------------------------------------------------------
@test "test_unknown_flag_exits_1" {
  run bash "$SCRIPT" --unknown
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown argument"* ]] || [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# test_dry_run_flag_no_writes
# Run script with --dry-run; assert DRY RUN header appears, output has
# "(dry-run)" and conf state is not modified for state transitions.
# ---------------------------------------------------------------------------
@test "test_dry_run_flag_no_writes" {
  # Create a file and conf with state=r (will attempt a transition if not tracked)
  echo "content" > "$TMPDIR_TEST/file.txt"
  echo "file.txt=r" > "$TMPDIR_TEST/sync-answers.conf"

  local conf_before
  conf_before=$(cat "$TMPDIR_TEST/sync-answers.conf")

  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]

  # The Would Apply section should appear since there's a pending transition
  [[ "$output" == *"Would Apply (dry-run)"* ]]

  # The (dry-run) marker should appear in the transition entry
  [[ "$output" == *"(dry-run)"* ]]

  # Conf should not have had state transitions written (dry-run)
  local conf_after
  conf_after=$(cat "$TMPDIR_TEST/sync-answers.conf")
  # In dry-run the conf is not written (write_conf is no-op)
  [ "$conf_before" = "$conf_after" ]
}

# ---------------------------------------------------------------------------
# test_full_run_idempotent
# Run main() twice with a stable state; second run should show "Nothing to commit".
# ---------------------------------------------------------------------------
@test "test_full_run_idempotent" {
  # First run: empty conf, empty dir (only .gitkeep)
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT"
  [ "$status" -eq 0 ]

  # Second run: still stable
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to commit"* ]]
}

# ---------------------------------------------------------------------------
# test_full_run_new_file_appears_in_pending
# Add untracked file, run main(); assert file appears in pending section.
# ---------------------------------------------------------------------------
@test "test_full_run_new_file_appears_in_pending" {
  echo "hello" > "$TMPDIR_TEST/newfile.txt"

  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"newfile.txt"* ]]
  [[ "$output" == *"Pending"* ]]
}

# ---------------------------------------------------------------------------
# test_no_orphan_tempfiles_after_run
# Run script to completion; assert no .XXXXXX temp files remain in CLAUDE_DIR.
# Also test dry-run mode leaves no orphan temp files.
# ---------------------------------------------------------------------------
@test "test_no_orphan_tempfiles_after_run" {
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT"
  [ "$status" -eq 0 ]

  # Find any leftover temp files — mktemp replaces X's with random chars,
  # so actual orphans look like "sync-answers.conf.Ab3xQ9" (6 random chars).
  # Use ?????? (exactly 6 chars) to match the mktemp suffix pattern.
  local orphans
  orphans=$(find "$TMPDIR_TEST" \( -name "sync-answers.conf.??????" -o -name ".gitignore.??????" \) 2>/dev/null)
  [ -z "$orphans" ]

  # Also test dry-run leaves no orphan temp files
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  local orphans_dry
  orphans_dry=$(find "$TMPDIR_TEST" \( -name "sync-answers.conf.??????" -o -name ".gitignore.??????" \) 2>/dev/null)
  [ -z "$orphans_dry" ]
}

# ---------------------------------------------------------------------------
# test_empty_conf_and_empty_scan_exits_cleanly
# Init empty git repo, empty conf, run main(); assert exit 0 and clean output.
# ---------------------------------------------------------------------------
@test "test_empty_conf_and_empty_scan_exits_cleanly" {
  touch "$TMPDIR_TEST/sync-answers.conf"

  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to commit"* ]]
}

# ---------------------------------------------------------------------------
# test_source_does_not_call_main
# Source the script in a subshell; assert exit 0, no stdout invocation,
# and no new files created in CLAUDE_DIR.
# ---------------------------------------------------------------------------
@test "test_source_does_not_call_main" {
  local file_count_before
  file_count_before=$(find "$TMPDIR_TEST" -type f | wc -l)

  run bash -c "
    export CLAUDE_DIR='$TMPDIR_TEST'
    export CONF_FILE='$TMPDIR_TEST/sync-answers.conf'
    export _TEST_BASH_MAJOR=4
    source '$SCRIPT'
    echo ok
  "
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]

  local file_count_after
  file_count_after=$(find "$TMPDIR_TEST" -type f | wc -l)
  [ "$file_count_before" -eq "$file_count_after" ]
}

# ---------------------------------------------------------------------------
# test_reset_globals_clears_dry_run
# Set DRY_RUN=true, call reset_globals(), assert DRY_RUN is now false.
# ---------------------------------------------------------------------------
@test "test_reset_globals_clears_dry_run" {
  DRY_RUN=true
  reset_globals
  [ "$DRY_RUN" = "false" ]
}

# ---------------------------------------------------------------------------
# test_full_run_r_to_i_transition
# CONF='i' for a previously tracked file; assert file removed from git index
# and appears in .gitignore sentinel block after run.
# ---------------------------------------------------------------------------
@test "test_full_run_r_to_i_transition" {
  # Set up: create and commit file.txt so it is tracked
  echo "content" > "$TMPDIR_TEST/file.txt"
  git -C "$TMPDIR_TEST" add -- "file.txt"
  git -C "$TMPDIR_TEST" commit -m "add file" >/dev/null 2>&1

  # Set conf to 'i' — should trigger r→i transition
  printf 'file.txt=i\n' > "$TMPDIR_TEST/sync-answers.conf"

  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" <<< ""

  [ "$status" -eq 0 ]

  # file should no longer be in the git index
  local tracked
  tracked=$(git -C "$TMPDIR_TEST" ls-files -- "file.txt")
  [ -z "$tracked" ]

  # .gitignore sentinel block should contain file.txt
  [[ -f "$TMPDIR_TEST/.gitignore" ]]
  grep -q "file.txt" "$TMPDIR_TEST/.gitignore"
}

# ---------------------------------------------------------------------------
# test_full_lifecycle_new_to_tracked_to_deleted
# Multi-step E2E: untracked → pending → tracked → idempotent → deleted → restored.
# ---------------------------------------------------------------------------
@test "test_full_lifecycle_new_to_tracked_to_deleted" {
  echo "content" > "$TMPDIR_TEST/newfile.txt"

  # Step 1: new file appears as pending
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" <<< ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pending"* ]]
  [[ "$output" == *"newfile.txt"* ]]

  # Step 2: set conf=r, file gets tracked and committed
  printf 'newfile.txt=r\n' > "$TMPDIR_TEST/sync-answers.conf"
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" <<< $'track newfile\nn'
  [ "$status" -eq 0 ]
  local tracked
  tracked=$(git -C "$TMPDIR_TEST" ls-files -- "newfile.txt")
  [ -n "$tracked" ]

  # Step 3: idempotent — second run has "Nothing to commit"
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" <<< ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to commit"* ]]

  # Step 4: set conf=d, run WITHOUT committing (empty stdin → "Aborted.")
  # This trashes the file and unstages it from git index but does NOT commit,
  # so the file is still present in HEAD. The tombstone stays in conf.
  printf 'newfile.txt=d\n' > "$TMPDIR_TEST/sync-answers.conf"
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" <<< ""
  [ "$status" -eq 0 ]
  # File should be gone from disk (trashed)
  [ ! -f "$TMPDIR_TEST/newfile.txt" ]
  # File should no longer be in the git index (git rm --cached was run)
  local deleted_tracked
  deleted_tracked=$(git -C "$TMPDIR_TEST" ls-files -- "newfile.txt")
  [ -z "$deleted_tracked" ]
  # Tombstone should still be in conf (no commit → no tombstone removal)
  grep -q "newfile.txt=d" "$TMPDIR_TEST/sync-answers.conf"

  # Step 4.5: set conf=r (restore from HEAD), run → handle_deleted_files() sees
  # CONF='r' with file missing → git restore --source=HEAD succeeds (file is in HEAD)
  # → file restored to disk and index. Then commit the restoration.
  printf 'newfile.txt=r\n' > "$TMPDIR_TEST/sync-answers.conf"
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" <<< $'restore newfile\nn'
  [ "$status" -eq 0 ]
  # File should be back on disk
  [ -f "$TMPDIR_TEST/newfile.txt" ]
  # File should be tracked in git
  local restored_tracked
  restored_tracked=$(git -C "$TMPDIR_TEST" ls-files -- "newfile.txt")
  [ -n "$restored_tracked" ]

  # Step 5: run again → "Nothing to commit" (stable state after restore)
  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" <<< ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to commit"* ]]
}

# ---------------------------------------------------------------------------
# test_dry_run_missing_file_not_restored
# DRY_RUN must not restore a missing file tracked in HEAD (conf=r).
# handle_deleted_files() must skip git restore and log to REPORT_DRY_RUN.
# ---------------------------------------------------------------------------
@test "test_dry_run_missing_file_not_restored" {
  # Set up: file tracked in git HEAD, then deleted from disk and index
  echo "content" > "$TMPDIR_TEST/tracked.txt"
  git -C "$TMPDIR_TEST" add -- "tracked.txt"
  git -C "$TMPDIR_TEST" commit -m "add tracked.txt" >/dev/null 2>&1
  rm "$TMPDIR_TEST/tracked.txt"
  git -C "$TMPDIR_TEST" rm --cached -- "tracked.txt" >/dev/null 2>&1

  printf 'tracked.txt=r\n' > "$TMPDIR_TEST/sync-answers.conf"

  run env CLAUDE_DIR="$TMPDIR_TEST" CONF_FILE="$TMPDIR_TEST/sync-answers.conf" \
    _TEST_BASH_MAJOR=4 bash "$SCRIPT" --dry-run

  [ "$status" -eq 0 ]
  # File must NOT be restored (dry-run)
  [ ! -f "$TMPDIR_TEST/tracked.txt" ]
  # Output should mention dry-run action
  [[ "$output" == *"dry-run"* ]]
}
