#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"
# On macOS the system bash is 3.2; simulate bash 4 for happy-path tests
# via the _TEST_BASH_MAJOR override built into the script.
MOCK_BASH4="_TEST_BASH_MAJOR=4"

teardown() {
  [[ -n "${_tmpdir:-}" && -d "$_tmpdir" ]] && rm -rf "$_tmpdir" || true
}

# ---------------------------------------------------------------------------
# test_preflight_fails_without_trash
# ---------------------------------------------------------------------------
@test "test_preflight_fails_without_trash" {
  # Remove trash from PATH by building a PATH without it
  local no_trash_path
  no_trash_path=$(echo "$PATH" | tr ':' '\n' | grep -v "^$" | while IFS= read -r dir; do
    if [[ -x "$dir/trash" ]]; then
      : # skip dirs containing trash
    else
      echo "$dir"
    fi
  done | tr '\n' ':' | sed 's/:$//')

  run env PATH="$no_trash_path" _TEST_BASH_MAJOR=4 bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trash"* ]]
}

# ---------------------------------------------------------------------------
# test_preflight_fails_outside_git_repo
# ---------------------------------------------------------------------------
@test "test_preflight_fails_outside_git_repo" {
  _tmpdir=$(mktemp -d)

  # Override CLAUDE_DIR to a non-git directory
  run env CLAUDE_DIR="$_tmpdir" _TEST_BASH_MAJOR=4 bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git repository"* ]]
}

# ---------------------------------------------------------------------------
# test_preflight_passes_with_trash_and_git
# ---------------------------------------------------------------------------
@test "test_preflight_passes_with_trash_and_git" {
  _tmpdir=$(mktemp -d)
  git init "$_tmpdir"

  run env CLAUDE_DIR="$_tmpdir" _TEST_BASH_MAJOR=4 bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_preflight_runs_in_dry_run_mode
# ---------------------------------------------------------------------------
@test "test_preflight_runs_in_dry_run_mode" {
  _tmpdir=$(mktemp -d)
  git init "$_tmpdir"

  run env CLAUDE_DIR="$_tmpdir" _TEST_BASH_MAJOR=4 bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_preflight_fails_on_bash_3
# ---------------------------------------------------------------------------
@test "test_preflight_fails_on_bash_3" {
  run env _TEST_BASH_MAJOR=3 bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bash 4.0+"* ]]
}
