#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# test_install_prereqs.bats — TDD tests for install.sh prereq checks and flags
# ---------------------------------------------------------------------------

SCRIPT="$HOME/.claude/install.sh"

setup() {
  export INSTALL_DEST="$BATS_TMPDIR/test_dest"
  export INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo"
  export _INSTALL_IS_TTY=0
  mkdir -p "$BATS_TMPDIR/test_dest"

  # Create a stub directory for PATH manipulation
  STUB_DIR="$BATS_TMPDIR/stubs-$$-$BATS_TEST_NUMBER"
  mkdir -p "$STUB_DIR"
}

teardown() {
  [[ -d "${STUB_DIR:-}" ]] && rm -rf "$STUB_DIR"
  [[ -d "$BATS_TMPDIR/test_dest" ]] && rm -rf "$BATS_TMPDIR/test_dest"
}

# ---------------------------------------------------------------------------
# test_missing_git_exits_1
# Mock command -v git to fail via PATH stub; assert exit code 1 and
# error message contains "git".
# ---------------------------------------------------------------------------
@test "test_missing_git_exits_1" {
  # Create a stub curl that works (so we isolate the git failure)
  cat > "$STUB_DIR/curl" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$STUB_DIR/curl"

  # Do NOT create git in stub dir — prepend stub dir to PATH so curl is found
  # but git is NOT (no git stub, and real git is shadowed by stub dir being first).
  # However, we need the real system binaries (bash, env, etc.) to still work,
  # so we prepend rather than replace PATH. We shadow git by omitting it from
  # the stub dir AND wrapping the git binary to fail.
  # Simplest: create a wrapper that makes `command -v git` fail by using a
  # function override approach — source a helper that exports a no-op.
  # Best approach for bash: create stub that exits non-zero when invoked as git.
  # `command -v git` finds git in PATH, but we want it NOT found.
  # Solution: create a directory with only curl (no git), prepend it, and also
  # create a symlink/stub that shadows the real git with a non-found sentinel.

  # Build a PATH that excludes ALL directories containing git
  # (there may be multiple: e.g. /opt/homebrew/bin/git and /usr/bin/git)
  local git_dirs
  git_dirs="$(which -a git 2>/dev/null | xargs -I{} dirname {} | sort -u | tr '\n' ':')"

  local new_path="$STUB_DIR"
  local IFS_save="$IFS"
  IFS=":"
  for dir in $PATH; do
    IFS="$IFS_save"
    # Skip this dir if it contains git
    local skip=0
    local gd
    for gd in $(echo "$git_dirs" | tr ':' '\n'); do
      if [[ "$dir" == "$gd" ]]; then
        skip=1
        break
      fi
    done
    if [[ "$skip" -eq 0 ]]; then
      new_path="$new_path:$dir"
    fi
  done
  IFS="$IFS_save"

  run env PATH="$new_path" \
    INSTALL_DEST="$BATS_TMPDIR/test_dest" \
    INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"git"* ]]
}

# ---------------------------------------------------------------------------
# test_missing_curl_exits_1
# Mock command -v curl to fail; assert exit code 1 and message contains "curl".
# ---------------------------------------------------------------------------
@test "test_missing_curl_exits_1" {
  # Stub git (works), but no curl in PATH
  cat > "$STUB_DIR/git" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$STUB_DIR/git"

  # Build a PATH that excludes the directory containing curl
  local real_curl_dir
  real_curl_dir="$(dirname "$(command -v curl)")"

  local new_path="$STUB_DIR"
  local IFS_save="$IFS"
  IFS=":"
  for dir in $PATH; do
    IFS="$IFS_save"
    if [[ "$dir" != "$real_curl_dir" ]]; then
      new_path="$new_path:$dir"
    fi
  done
  IFS="$IFS_save"

  run env PATH="$new_path" \
    INSTALL_DEST="$BATS_TMPDIR/test_dest" \
    INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl"* ]]
}

# ---------------------------------------------------------------------------
# test_unknown_flag_exits_1
# Call with --foo; assert exit 1 + usage output.
# ---------------------------------------------------------------------------
@test "test_unknown_flag_exits_1" {
  run env INSTALL_DEST="$BATS_TMPDIR/test_dest" \
    INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" --foo 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"Unknown"* ]]
}

# ---------------------------------------------------------------------------
# test_help_flag_prints_usage_exits_0
# Call with --help; assert exit code 0 and output contains usage text.
# ---------------------------------------------------------------------------
@test "test_help_flag_prints_usage_exits_0" {
  run env INSTALL_DEST="$BATS_TMPDIR/test_dest" \
    INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" --help 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

# ---------------------------------------------------------------------------
# test_conflicting_flags_exits_1
# Call with --overwrite --keep-claude-md; assert exit 1.
# ---------------------------------------------------------------------------
@test "test_conflicting_flags_exits_1" {
  run env INSTALL_DEST="$BATS_TMPDIR/test_dest" \
    INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" --overwrite --keep-claude-md 2>&1
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# test_valid_flags_accepted
# Source install.sh to load functions; call parse_flags directly;
# assert OVERWRITE=1 and KEEP_CLAUDE_MD=0 (for --overwrite).
# Also test --keep-claude-md sets KEEP_CLAUDE_MD=1.
# ---------------------------------------------------------------------------
@test "test_valid_flags_accepted" {
  # Source install.sh to load functions without executing main
  # shellcheck disable=SC1090
  source "$SCRIPT"

  # Test --overwrite
  OVERWRITE=0
  KEEP_CLAUDE_MD=0
  parse_flags --overwrite
  [ "$OVERWRITE" -eq 1 ]
  [ "$KEEP_CLAUDE_MD" -eq 0 ]

  # Test --keep-claude-md
  OVERWRITE=0
  KEEP_CLAUDE_MD=0
  parse_flags --keep-claude-md
  [ "$OVERWRITE" -eq 0 ]
  [ "$KEEP_CLAUDE_MD" -eq 1 ]
}
