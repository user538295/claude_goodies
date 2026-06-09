#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# test_install_copy.bats — TDD tests for install.sh clone, stage, and move
# ---------------------------------------------------------------------------

SCRIPT="$HOME/.claude/install.sh"

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# create_fixture_dir — plain directory (for INSTALL_SKIP_CLONE=1 tests)
create_fixture_dir() {
  local dir="$1"
  mkdir -p "$dir/scripts"
  echo "#!/bin/sh" > "$dir/scripts/plan-progress.sh"
  echo "#!/usr/bin/awk -f" > "$dir/scripts/task_section.awk"
  echo "# template" > "$dir/scripts/progress-header-flat.template"
  echo "# CLAUDE.md content" > "$dir/CLAUDE.md"
  echo "#!/usr/bin/env bash" > "$dir/install.sh"
}

setup() {
  export INSTALL_DEST="$BATS_TMPDIR/test_dest-$$-$BATS_TEST_NUMBER"
  export INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo-$$-$BATS_TEST_NUMBER"
  export _INSTALL_IS_TTY=0
  mkdir -p "$INSTALL_DEST"

  # Create fixture dir (plain directory for INSTALL_SKIP_CLONE=1)
  FIXTURE_DIR="$BATS_TMPDIR/fixture_dir-$$-$BATS_TEST_NUMBER"
  create_fixture_dir "$FIXTURE_DIR"
  export INSTALL_FIXTURE_DIR="$FIXTURE_DIR"

  export INSTALL_SKIP_CLONE=1
}

teardown() {
  rm -rf "$INSTALL_DEST" "$FIXTURE_DIR" \
    "$BATS_TMPDIR/fixture_repo-$$-$BATS_TEST_NUMBER" \
    "$BATS_TMPDIR/mock_bin-$$-$BATS_TEST_NUMBER" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# test_all_manifest_files_copied_to_dest
# Run against fixture; assert scripts/* and install.sh are at dest;
# assert CLAUDE.md is NOT yet at dest (Task 1.3 handles it);
# assert agents/, commands/, skills/ are NOT created at dest.
# ---------------------------------------------------------------------------
@test "test_all_manifest_files_copied_to_dest" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [ -f "$INSTALL_DEST/scripts/plan-progress.sh" ]
  [ -f "$INSTALL_DEST/install.sh" ]
  # CLAUDE.md is now installed via handle_claude_md() (Task 1.3)
  [ -f "$INSTALL_DEST/CLAUDE.md" ]
  [ ! -d "$INSTALL_DEST/agents" ]
  [ ! -d "$INSTALL_DEST/commands" ]
  [ ! -d "$INSTALL_DEST/skills" ]
}

# ---------------------------------------------------------------------------
# test_scripts_are_executable
# Assert chmod +x applied to .sh files; .awk and .template do NOT have it.
# ---------------------------------------------------------------------------
@test "test_scripts_are_executable" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [ -x "$INSTALL_DEST/scripts/plan-progress.sh" ]
  [ -x "$INSTALL_DEST/install.sh" ]
  # .awk and .template should NOT be executable
  [ ! -x "$INSTALL_DEST/scripts/task_section.awk" ]
  [ ! -x "$INSTALL_DEST/scripts/progress-header-flat.template" ]
}

# ---------------------------------------------------------------------------
# test_dest_dir_created_if_missing
# Run with no dest dir; assert $DEST_DIR/scripts/ created.
# ---------------------------------------------------------------------------
@test "test_dest_dir_created_if_missing" {
  rm -rf "$INSTALL_DEST"
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [ -d "$INSTALL_DEST/scripts" ]
}

# ---------------------------------------------------------------------------
# test_non_sh_files_copied_to_dest
# Assert .awk and .template files are present at dest.
# ---------------------------------------------------------------------------
@test "test_non_sh_files_copied_to_dest" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [ -f "$INSTALL_DEST/scripts/task_section.awk" ]
  [ -f "$INSTALL_DEST/scripts/progress-header-flat.template" ]
}

# ---------------------------------------------------------------------------
# test_non_sh_files_not_executable
# Assert .awk and .template files at dest do NOT have the executable bit.
# ---------------------------------------------------------------------------
@test "test_non_sh_files_not_executable" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [ ! -x "$INSTALL_DEST/scripts/task_section.awk" ]
  [ ! -x "$INSTALL_DEST/scripts/progress-header-flat.template" ]
}

# ---------------------------------------------------------------------------
# test_skip_clone_without_fixture_dir_exits_1
# Set INSTALL_SKIP_CLONE=1, unset INSTALL_FIXTURE_DIR; assert exit 1
# and output contains 'INSTALL_FIXTURE_DIR'.
# ---------------------------------------------------------------------------
@test "test_skip_clone_without_fixture_dir_exits_1" {
  # Explicitly set INSTALL_FIXTURE_DIR to empty to override the exported value from setup()
  run env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"INSTALL_FIXTURE_DIR"* ]]
}

# ---------------------------------------------------------------------------
# test_cleanup_on_failure
# Simulate copy failure; assert temp dirs removed.
# ---------------------------------------------------------------------------
@test "test_cleanup_on_failure" {
  # Create a fixture with a scripts dir but make it so copying install.sh fails
  # by making the fixture's install.sh a directory (cp will fail)
  local bad_fixture="$BATS_TMPDIR/bad_fixture-$$-$BATS_TEST_NUMBER"
  mkdir -p "$bad_fixture/scripts"
  echo "#!/bin/sh" > "$bad_fixture/scripts/plan-progress.sh"
  echo "# CLAUDE.md" > "$bad_fixture/CLAUDE.md"
  # Make install.sh a directory — cp will fail trying to copy it as a file
  mkdir -p "$bad_fixture/install.sh"

  # Use a known STAGE_DIR so we can verify it's cleaned up
  local known_stage="$BATS_TMPDIR/known_stage-$$-$BATS_TEST_NUMBER"
  mkdir -p "$known_stage"

  run env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$bad_fixture" \
    INSTALL_STAGE_DIR="$known_stage" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" 2>&1

  # Should exit non-zero
  [ "$status" -ne 0 ]

  # Verify the stage dir was cleaned up by the EXIT trap
  [ ! -d "$known_stage" ]

  rm -rf "$bad_fixture"
}

# ---------------------------------------------------------------------------
# test_existing_install_untouched_on_failure
# Pre-place files at dest; simulate failure; assert originals unchanged.
# ---------------------------------------------------------------------------
@test "test_existing_install_untouched_on_failure" {
  # Pre-place a sentinel file at dest
  mkdir -p "$INSTALL_DEST/scripts"
  echo "sentinel-content" > "$INSTALL_DEST/scripts/old_file.sh"

  local bad_fixture="$BATS_TMPDIR/bad_fixture2-$$-$BATS_TEST_NUMBER"
  mkdir -p "$bad_fixture/scripts"
  echo "#!/bin/sh" > "$bad_fixture/scripts/plan-progress.sh"
  echo "# CLAUDE.md" > "$bad_fixture/CLAUDE.md"
  mkdir -p "$bad_fixture/install.sh"  # directory — will cause cp to fail

  run env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$bad_fixture" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" 2>&1

  [ "$status" -ne 0 ]
  # The old sentinel file must still exist unchanged
  [ -f "$INSTALL_DEST/scripts/old_file.sh" ]
  grep -q "sentinel-content" "$INSTALL_DEST/scripts/old_file.sh"

  rm -rf "$bad_fixture"
}

# ---------------------------------------------------------------------------
# test_cross_device_fallback
# Mock mv to fail (exit 1) for the first call via PATH stub;
# assert cp+rm fallback executes and file arrives at dest.
# ---------------------------------------------------------------------------
@test "test_cross_device_fallback" {
  local mock_bin="$BATS_TMPDIR/mock_bin-$$-$BATS_TEST_NUMBER"
  mkdir -p "$mock_bin"

  # Create a mv stub that always fails
  cat > "$mock_bin/mv" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$mock_bin/mv"

  run env PATH="$mock_bin:$PATH" \
    INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$FIXTURE_DIR" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" 2>&1

  [ "$status" -eq 0 ]
  # All manifest files should be at dest even though mv failed (cp fallback succeeded)
  [ -f "$INSTALL_DEST/scripts/plan-progress.sh" ]
  [ -f "$INSTALL_DEST/scripts/task_section.awk" ]
  [ -f "$INSTALL_DEST/scripts/progress-header-flat.template" ]
  [ -f "$INSTALL_DEST/install.sh" ]
}
