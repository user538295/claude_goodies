#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-claude-src-git"
mkdir -p "$CLAUDE_DIR"
git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

setup() {
  CLAUDE_DIR="$BATS_TMPDIR/test-git-$$"
  mkdir -p "$CLAUDE_DIR"
  git -C "$CLAUDE_DIR" init >/dev/null 2>&1
  git -C "$CLAUDE_DIR" config user.email "test@test.com"
  git -C "$CLAUDE_DIR" config user.name "Test"
  # Create and commit a tracked file
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  git -C "$CLAUDE_DIR" add tracked.txt
  git -C "$CLAUDE_DIR" commit -m "init" >/dev/null 2>&1
  # Create .gitignore to ignore a pattern
  echo "ignored.txt" > "$CLAUDE_DIR/.gitignore"
  git -C "$CLAUDE_DIR" add .gitignore
  git -C "$CLAUDE_DIR" commit -m "gitignore" >/dev/null 2>&1
  # Create an ignored file
  echo "secret" > "$CLAUDE_DIR/ignored.txt"
  # Create an untracked file (not committed, not ignored)
  echo "new" > "$CLAUDE_DIR/untracked.txt"
  reset_globals
}

teardown() {
  [[ -d "${CLAUDE_DIR:-}" ]] && rm -rf "$CLAUDE_DIR"
}

# ---------------------------------------------------------------------------
# test_tracked_file_returns_0
# ---------------------------------------------------------------------------
@test "test_tracked_file_returns_0" {
  git_is_tracked "tracked.txt" && rc=0 || rc=$?
  [ "$rc" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_untracked_file_returns_1
# ---------------------------------------------------------------------------
@test "test_untracked_file_returns_1" {
  git_is_tracked "untracked.txt" && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
}

# ---------------------------------------------------------------------------
# test_ignored_file_returns_0_for_git_is_ignored
# ---------------------------------------------------------------------------
@test "test_ignored_file_returns_0_for_git_is_ignored" {
  git_is_ignored "ignored.txt" && rc=0 || rc=$?
  [ "$rc" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_non_ignored_file_returns_1
# ---------------------------------------------------------------------------
@test "test_non_ignored_file_returns_1" {
  git_is_ignored "tracked.txt" && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
}

# ---------------------------------------------------------------------------
# test_git_is_ignored_distinguishes_error_from_not_ignored
# ---------------------------------------------------------------------------
@test "test_git_is_ignored_distinguishes_error_from_not_ignored" {
  # Run outside git repo: set CLAUDE_DIR to a non-repo directory
  local saved_dir="$CLAUDE_DIR"
  CLAUDE_DIR="$BATS_TMPDIR/not-a-repo-$$"
  mkdir -p "$CLAUDE_DIR"
  git_is_ignored "somefile.txt" && rc=0 || rc=$?
  CLAUDE_DIR="$saved_dir"
  rm -rf "$BATS_TMPDIR/not-a-repo-$$"
  [ "$rc" -eq 2 ]
  # GIT_CHECK_ERR should contain the error message from git
  [ -n "$GIT_CHECK_ERR" ]
}

# ---------------------------------------------------------------------------
# test_script_survives_untracked_file_scan
# ---------------------------------------------------------------------------
@test "test_script_survives_untracked_file_scan" {
  # Create 5 tracked + 5 untracked files and verify git_is_tracked works for each
  for i in 1 2 3 4 5; do
    echo "content$i" > "$CLAUDE_DIR/tracked$i.txt"
    git -C "$CLAUDE_DIR" add "tracked$i.txt"
  done
  git -C "$CLAUDE_DIR" commit -m "add files" >/dev/null 2>&1
  for i in 1 2 3 4 5; do
    echo "new$i" > "$CLAUDE_DIR/untracked$i.txt"
  done
  # Verify all tracked files return 0 and all untracked return 1
  for i in 1 2 3 4 5; do
    git_is_tracked "tracked$i.txt" && rc=0 || rc=$?
    [ "$rc" -eq 0 ]
    git_is_tracked "untracked$i.txt" && rc=0 || rc=$?
    [ "$rc" -eq 1 ]
  done
}

# ---------------------------------------------------------------------------
# test_tracked_directory_returns_0
# ---------------------------------------------------------------------------
@test "test_tracked_directory_returns_0" {
  mkdir -p "$CLAUDE_DIR/somedir"
  echo "file" > "$CLAUDE_DIR/somedir/file.txt"
  git -C "$CLAUDE_DIR" add "somedir/file.txt"
  git -C "$CLAUDE_DIR" commit -m "add somedir" >/dev/null 2>&1
  git_is_tracked "somedir/" && rc=0 || rc=$?
  [ "$rc" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_partially_tracked_directory_returns_0
# ---------------------------------------------------------------------------
@test "test_partially_tracked_directory_returns_0" {
  mkdir -p "$CLAUDE_DIR/somedir"
  echo "file1" > "$CLAUDE_DIR/somedir/file1.txt"
  echo "file2" > "$CLAUDE_DIR/somedir/file2.txt"
  echo "file3" > "$CLAUDE_DIR/somedir/file3.txt"
  git -C "$CLAUDE_DIR" add "somedir/file1.txt"
  git -C "$CLAUDE_DIR" commit -m "add one file" >/dev/null 2>&1
  # file2 and file3 are untracked
  git_is_tracked "somedir/" && rc=0 || rc=$?
  [ "$rc" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_empty_directory_returns_1
# ---------------------------------------------------------------------------
@test "test_empty_directory_returns_1" {
  mkdir -p "$CLAUDE_DIR/emptydir"
  # git doesn't track empty dirs — no files to add
  git_is_tracked "emptydir/" && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
}

# ---------------------------------------------------------------------------
# test_untracked_directory_returns_1_without_crashing
# ---------------------------------------------------------------------------
@test "test_untracked_directory_returns_1_without_crashing" {
  mkdir -p "$CLAUDE_DIR/untrackeddir"
  echo "untracked" > "$CLAUDE_DIR/untrackeddir/file.txt"
  # No git add — all files are untracked
  git_is_tracked "untrackeddir/" && rc=0 || rc=$?
  [ "$rc" -eq 1 ]
}

@test "test_git_is_tracked_file_returns_2_on_git_error" {
  # Use a non-git directory to trigger exit 128
  local old_claude_dir="$CLAUDE_DIR"
  CLAUDE_DIR="$BATS_TMPDIR/not-a-git-repo-$$"
  mkdir -p "$CLAUDE_DIR"
  touch "$CLAUDE_DIR/somefile.txt"

  git_is_tracked "somefile.txt" && rc=0 || rc=$?
  [ "$rc" -eq 2 ]

  CLAUDE_DIR="$old_claude_dir"
  rm -rf "$BATS_TMPDIR/not-a-git-repo-$$"
}

@test "test_git_is_tracked_dir_returns_2_on_git_error" {
  # Use a non-git directory to trigger exit 128
  local old_claude_dir="$CLAUDE_DIR"
  CLAUDE_DIR="$BATS_TMPDIR/not-a-git-repo-dir-$$"
  mkdir -p "$CLAUDE_DIR/somedir"

  git_is_tracked "somedir/" && rc=0 || rc=$?
  [ "$rc" -eq 2 ]

  CLAUDE_DIR="$old_claude_dir"
  rm -rf "$BATS_TMPDIR/not-a-git-repo-dir-$$"
}
