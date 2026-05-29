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
