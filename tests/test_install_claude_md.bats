#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# test_install_claude_md.bats — TDD tests for install.sh CLAUDE.md handling
# ---------------------------------------------------------------------------

SCRIPT="$HOME/.claude/install.sh"

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

create_fixture_dir() {
  local dir="$1"
  mkdir -p "$dir/scripts"
  echo "#!/bin/sh" > "$dir/scripts/plan-progress.sh"
  echo "#!/usr/bin/awk -f" > "$dir/scripts/task_section.awk"
  echo "# template" > "$dir/scripts/progress-header-flat.template"
  echo "# CLAUDE.md content from repo" > "$dir/CLAUDE.md"
  echo "#!/usr/bin/env bash" > "$dir/install.sh"
}

setup() {
  export INSTALL_DEST="$BATS_TMPDIR/test_dest-$$-$BATS_TEST_NUMBER"
  export INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo-$$-$BATS_TEST_NUMBER"
  export _INSTALL_IS_TTY=0
  mkdir -p "$INSTALL_DEST"

  FIXTURE_DIR="$BATS_TMPDIR/fixture_dir-$$-$BATS_TEST_NUMBER"
  create_fixture_dir "$FIXTURE_DIR"
  export INSTALL_FIXTURE_DIR="$FIXTURE_DIR"
  export INSTALL_SKIP_CLONE=1
}

teardown() {
  rm -rf "$INSTALL_DEST" "$FIXTURE_DIR" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# test_fresh_install_copies_claude_md
# No existing CLAUDE.md at dest; assert it is copied regardless of flags.
# ---------------------------------------------------------------------------
@test "test_fresh_install_copies_claude_md" {
  [ ! -f "$INSTALL_DEST/CLAUDE.md" ]
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [ -f "$INSTALL_DEST/CLAUDE.md" ]
  grep -q "CLAUDE.md content from repo" "$INSTALL_DEST/CLAUDE.md"
}

# ---------------------------------------------------------------------------
# test_default_skips_existing_claude_md
# Existing CLAUDE.md at dest; no flag; assert file unchanged and hint printed.
# ---------------------------------------------------------------------------
@test "test_default_skips_existing_claude_md" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  grep -q "existing-content" "$INSTALL_DEST/CLAUDE.md"
  [[ "$output" == *"--overwrite"* ]]
}

# ---------------------------------------------------------------------------
# test_keep_claude_md_skips_silently
# Existing CLAUDE.md at dest; --keep-claude-md; assert unchanged, no CLAUDE.md output.
# ---------------------------------------------------------------------------
@test "test_keep_claude_md_skips_silently" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run bash "$SCRIPT" --keep-claude-md 2>&1
  [ "$status" -eq 0 ]
  grep -q "existing-content" "$INSTALL_DEST/CLAUDE.md"
  # No output about CLAUDE.md should appear
  [[ "$output" != *"CLAUDE.md already exists"* ]]
  [[ "$output" != *"--overwrite"* ]]
}

# ---------------------------------------------------------------------------
# test_overwrite_noninteractive_overwrites
# Existing CLAUDE.md; --overwrite; _INSTALL_IS_TTY=0; assert overwritten.
# ---------------------------------------------------------------------------
@test "test_overwrite_noninteractive_overwrites" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$FIXTURE_DIR" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" --overwrite 2>&1
  [ "$status" -eq 0 ]
  grep -q "CLAUDE.md content from repo" "$INSTALL_DEST/CLAUDE.md"
  [[ "$output" == *"Non-interactive"* ]]
}

# ---------------------------------------------------------------------------
# test_overwrite_interactive_yes_overwrites
# Existing CLAUDE.md; --overwrite; _INSTALL_IS_TTY=1; y input via pipe; assert overwritten.
# ---------------------------------------------------------------------------
@test "test_overwrite_interactive_yes_overwrites" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$FIXTURE_DIR" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=1 \
    _INSTALL_PAGER=cat \
    bash "$SCRIPT" --overwrite <<< "y"
  [ "$status" -eq 0 ]
  grep -q "CLAUDE.md content from repo" "$INSTALL_DEST/CLAUDE.md"
}

# ---------------------------------------------------------------------------
# test_overwrite_interactive_no_leaves_unchanged
# Existing CLAUDE.md; --overwrite; _INSTALL_IS_TTY=1; n input via pipe; assert unchanged + message.
# ---------------------------------------------------------------------------
@test "test_overwrite_interactive_no_leaves_unchanged" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$FIXTURE_DIR" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=1 \
    _INSTALL_PAGER=cat \
    bash "$SCRIPT" --overwrite <<< "n"
  [ "$status" -eq 0 ]
  grep -q "existing-content" "$INSTALL_DEST/CLAUDE.md"
  [[ "$output" == *"unchanged"* ]]
}
