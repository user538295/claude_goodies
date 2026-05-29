#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-claude-src-scanner"
mkdir -p "$CLAUDE_DIR"
git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

setup() {
  CLAUDE_DIR="$BATS_TMPDIR/test-claude-$$"
  mkdir -p "$CLAUDE_DIR"
  git init "$CLAUDE_DIR" >/dev/null 2>&1
  reset_globals
}

teardown() {
  [[ -d "${CLAUDE_DIR:-}" ]] && rm -rf "$CLAUDE_DIR"
}

# ---------------------------------------------------------------------------
# test_scan_excludes_git_dir
# ---------------------------------------------------------------------------
@test "test_scan_excludes_git_dir" {
  touch "$CLAUDE_DIR/README.md"

  output=$(scan_files)

  # .git itself should not appear
  ! echo "$output" | grep -qxF ".git"
  # .git/ (with slash) should not appear
  ! echo "$output" | grep -qxF ".git/"
  # No path starting with .git/ should appear
  ! echo "$output" | grep -q "^\.git/"
  [[ "$output" == *"README.md"* ]]
}

# ---------------------------------------------------------------------------
# test_scan_excludes_conf_file
# ---------------------------------------------------------------------------
@test "test_scan_excludes_conf_file" {
  touch "$CLAUDE_DIR/sync-answers.conf"
  touch "$CLAUDE_DIR/CLAUDE.md"

  output=$(scan_files)

  [[ "$output" != *"sync-answers.conf"* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
}

# ---------------------------------------------------------------------------
# test_scan_directory_entry_suppresses_contents
# ---------------------------------------------------------------------------
@test "test_scan_directory_entry_suppresses_contents" {
  mkdir -p "$CLAUDE_DIR/scripts"
  touch "$CLAUDE_DIR/scripts/foo.sh"
  CONF_STATE["scripts/"]="i"

  output=$(scan_files)

  [[ "$output" == *"scripts/"* ]]
  [[ "$output" != *"scripts/foo.sh"* ]]
}

# ---------------------------------------------------------------------------
# test_scan_emits_files_as_plain_paths
# ---------------------------------------------------------------------------
@test "test_scan_emits_files_as_plain_paths" {
  touch "$CLAUDE_DIR/CLAUDE.md"

  output=$(scan_files)

  # Must appear exactly as "CLAUDE.md" — not "CLAUDE.md/"
  echo "$output" | grep -qxF "CLAUDE.md"
}

# ---------------------------------------------------------------------------
# test_scan_emits_dirs_with_slash
# ---------------------------------------------------------------------------
@test "test_scan_emits_dirs_with_slash" {
  mkdir -p "$CLAUDE_DIR/projects"
  touch "$CLAUDE_DIR/projects/file.txt"
  CONF_STATE["projects/"]="r"

  output=$(scan_files)

  echo "$output" | grep -qxF "projects/"
  [[ "$output" != *"projects/file.txt"* ]]
}

# ---------------------------------------------------------------------------
# test_scan_symlink_treated_as_file
# ---------------------------------------------------------------------------
@test "test_scan_symlink_treated_as_file" {
  local target_file="$BATS_TMPDIR/real_target_file_$$"
  touch "$target_file"
  ln -s "$target_file" "$CLAUDE_DIR/mylink"

  output=$(scan_files)

  echo "$output" | grep -qxF "mylink"
  [[ "$output" != *"mylink/"* ]]
}

# ---------------------------------------------------------------------------
# test_scan_symlink_to_dir_not_descended
# ---------------------------------------------------------------------------
@test "test_scan_symlink_to_dir_not_descended" {
  ln -s /tmp "$CLAUDE_DIR/dirlink"

  output=$(scan_files)

  # dirlink appears in output
  echo "$output" | grep -qxF "dirlink"

  # The contents of /tmp must not appear (find does not follow symlinks)
  [[ "$output" != *"dirlink/"* ]]

  # dirlink appears exactly once (no descending into symlink target)
  local count
  count=$(echo "$output" | grep -c "dirlink" || true)
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# test_scan_file_with_space_in_name
# ---------------------------------------------------------------------------
@test "test_scan_file_with_space_in_name" {
  touch "$CLAUDE_DIR/my file.md"

  output=$(scan_files)

  echo "$output" | grep -qxF "my file.md"
}

# ---------------------------------------------------------------------------
# test_scan_excludes_gitignore
# ---------------------------------------------------------------------------
@test "test_scan_excludes_gitignore" {
  touch "$CLAUDE_DIR/.gitignore"
  touch "$CLAUDE_DIR/CLAUDE.md"

  output=$(scan_files)

  [[ "$output" != *".gitignore"* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
}

# ---------------------------------------------------------------------------
# test_scan_broken_symlink
# ---------------------------------------------------------------------------
@test "test_scan_broken_symlink" {
  ln -s /tmp/nonexistent_path_xyz "$CLAUDE_DIR/deadlink"

  output=$(scan_files)

  echo "$output" | grep -qxF "deadlink"
}

# ---------------------------------------------------------------------------
# test_scan_nested_conf_dirs
# ---------------------------------------------------------------------------
@test "test_scan_nested_conf_dirs" {
  # CONF_STATE has a/ but NOT a/b/
  # Create deep nested structure
  mkdir -p "$CLAUDE_DIR/a/b/c"
  touch "$CLAUDE_DIR/a/b/c/file.txt"
  CONF_STATE["a/"]="i"

  output=$(scan_files)

  # Only a/ appears; its contents do not
  echo "$output" | grep -qxF "a/"
  [[ "$output" != *"a/b"* ]]
  [[ "$output" != *"a/b/c"* ]]
  [[ "$output" != *"a/b/c/file.txt"* ]]
}

# ---------------------------------------------------------------------------
# test_scan_two_hierarchical_conf_dirs
# ---------------------------------------------------------------------------
@test "test_scan_two_hierarchical_conf_dirs" {
  # CONF_STATE has both a/=i AND a/b/=r
  # Parent prune should take precedence: only a/ in output, not a/b/
  mkdir -p "$CLAUDE_DIR/a/b"
  touch "$CLAUDE_DIR/a/b/file.txt"
  CONF_STATE["a/"]="i"
  CONF_STATE["a/b/"]="r"

  output=$(scan_files)

  echo "$output" | grep -qxF "a/"
  [[ "$output" != *"a/b"* ]]
}

# ---------------------------------------------------------------------------
# Task 2.3 — build_actual_state tests
# ---------------------------------------------------------------------------

_setup_git_repo() {
  # Configure git identity and create an initial commit
  git -C "$CLAUDE_DIR" config user.email "test@test.com"
  git -C "$CLAUDE_DIR" config user.name "Test"
  echo "content" > "$CLAUDE_DIR/tracked.txt"
  git -C "$CLAUDE_DIR" add tracked.txt
  git -C "$CLAUDE_DIR" commit -m "init" >/dev/null 2>&1
  # Add .gitignore that ignores ignored.txt
  echo "ignored.txt" > "$CLAUDE_DIR/.gitignore"
  git -C "$CLAUDE_DIR" add .gitignore
  git -C "$CLAUDE_DIR" commit -m "gitignore" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# test_actual_state_tracked
# ---------------------------------------------------------------------------
@test "test_actual_state_tracked" {
  _setup_git_repo
  # tracked.txt is committed — should resolve to 'tracked'
  CONF_STATE=()

  build_actual_state

  [ "${ACTUAL_STATE[tracked.txt]}" = "tracked" ]
}

# ---------------------------------------------------------------------------
# test_actual_state_ignored
# ---------------------------------------------------------------------------
@test "test_actual_state_ignored" {
  _setup_git_repo
  # Create file matching the ignored pattern in .gitignore
  echo "secret" > "$CLAUDE_DIR/ignored.txt"
  CONF_STATE=()

  build_actual_state

  [ "${ACTUAL_STATE[ignored.txt]}" = "ignored" ]
}

# ---------------------------------------------------------------------------
# test_actual_state_untracked
# ---------------------------------------------------------------------------
@test "test_actual_state_untracked" {
  _setup_git_repo
  # Create a new file that is neither committed nor ignored
  echo "new" > "$CLAUDE_DIR/untracked.txt"
  CONF_STATE=()

  build_actual_state

  [ "${ACTUAL_STATE[untracked.txt]}" = "untracked" ]
}

# ---------------------------------------------------------------------------
# test_actual_state_missing
# ---------------------------------------------------------------------------
@test "test_actual_state_missing" {
  _setup_git_repo
  # CONF_STATE references a file that does not exist on disk
  CONF_STATE["ghost.txt"]="track"

  build_actual_state

  [ "${ACTUAL_STATE[ghost.txt]}" = "missing" ]
}

# ---------------------------------------------------------------------------
# test_build_actual_state_aborts_on_git_error
# ---------------------------------------------------------------------------
@test "test_build_actual_state_aborts_on_git_error" {
  _setup_git_repo
  # Create an untracked file so it will reach git_is_ignored
  echo "new" > "$CLAUDE_DIR/untracked.txt"
  CONF_STATE=()

  # Locate the real git binary before modifying PATH
  local real_git
  real_git="$(command -v git)"

  # Create a fake git that returns 128 for check-ignore, delegates rest to real git
  local fake_git_dir="$BATS_TMPDIR/fake-git-$$"
  mkdir -p "$fake_git_dir"
  cat > "$fake_git_dir/git" << GITEOF
#!/bin/bash
if [[ "\$*" == *"check-ignore"* ]]; then
  echo "fatal: fake git error" >&2
  exit 128
fi
exec "$real_git" "\$@"
GITEOF
  chmod +x "$fake_git_dir/git"

  # Run in subshell with fake git prepended to PATH.
  # Pass ORIG_PATH so the subshell can construct PATH correctly without quoting issues.
  local orig_path="$PATH"
  run env PATH="$fake_git_dir:$orig_path" bash -c "
    source '$SCRIPT'
    CLAUDE_DIR='$CLAUDE_DIR'
    reset_globals
    build_actual_state
  "

  [ "$status" -eq 1 ]
  [[ "$output" == *"untracked.txt"* ]]
}

# ---------------------------------------------------------------------------
# test_actual_state_tracked_directory
# ---------------------------------------------------------------------------
@test "test_actual_state_tracked_directory" {
  # Set up: create a directory with a file, commit it, add to CONF_STATE
  git -C "$CLAUDE_DIR" config user.email "test@test.com" 2>/dev/null || true
  git -C "$CLAUDE_DIR" config user.name "Test" 2>/dev/null || true

  mkdir -p "$CLAUDE_DIR/mydir"
  echo "content" > "$CLAUDE_DIR/mydir/file.txt"
  git -C "$CLAUDE_DIR" add mydir/file.txt
  git -C "$CLAUDE_DIR" commit -m "add dir" >/dev/null 2>&1

  CONF_STATE["mydir/"]="r"

  build_actual_state

  [ "${ACTUAL_STATE["mydir/"]}" = "tracked" ]
}
