#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# test_install_dry_run.bats — TDD tests for install.sh --dry-run feature
# Written first (TDD); all tests WILL FAIL until Phase 2 implementation.
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
# Phase 1 Tests: Task 1.1 / 2.1 — Flag parsing and usage
# ---------------------------------------------------------------------------

# test_dry_run_flag_is_recognized
# parse_flags --dry-run must exit 0 (recognized flag)
@test "test_dry_run_flag_is_recognized" {
  run bash -c "source '$SCRIPT'; parse_flags --dry-run; echo \"DRY_RUN=\$DRY_RUN\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN=1"* ]]
}

# test_dry_run_with_overwrite_is_valid
# --dry-run combined with --overwrite must be accepted
@test "test_dry_run_with_overwrite_is_valid" {
  run bash -c "source '$SCRIPT'; parse_flags --dry-run --overwrite; echo \"DRY_RUN=\$DRY_RUN OVERWRITE=\$OVERWRITE\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN=1"* ]]
  [[ "$output" == *"OVERWRITE=1"* ]]
}

# test_dry_run_with_keep_claude_md_is_valid
# --dry-run combined with --keep-claude-md must be accepted
@test "test_dry_run_with_keep_claude_md_is_valid" {
  run bash -c "source '$SCRIPT'; parse_flags --dry-run --keep-claude-md; echo \"DRY_RUN=\$DRY_RUN KEEP_CLAUDE_MD=\$KEEP_CLAUDE_MD\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN=1"* ]]
  [[ "$output" == *"KEEP_CLAUDE_MD=1"* ]]
}

# test_dryrun_no_hyphen_exits_1
# --dryrun (no hyphen) must exit 1 with "Unknown flag" error
@test "test_dryrun_no_hyphen_exits_1" {
  run bash "$SCRIPT" --dryrun 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown flag"* ]]
}

# test_dry_run_overwrite_keep_combo_exits_1
# --dry-run --overwrite --keep-claude-md must exit 1 (mutual-exclusion)
@test "test_dry_run_overwrite_keep_combo_exits_1" {
  run bash "$SCRIPT" --dry-run --overwrite --keep-claude-md 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# test_help_includes_dry_run
# --help output must include --dry-run
@test "test_help_includes_dry_run" {
  run bash "$SCRIPT" --help 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run"* ]]
}

# ---------------------------------------------------------------------------
# Phase 2 Tests: Task 2.2 — Wrapper function unit tests
# ---------------------------------------------------------------------------

# test_dry_mv_in_dry_run_prints_and_does_not_write
# dry_mv with DRY_RUN=1 must print and not create the destination file
@test "test_dry_mv_in_dry_run_prints_and_does_not_write" {
  local src="$BATS_TMPDIR/src_file-$$-$BATS_TEST_NUMBER"
  local dst="$BATS_TMPDIR/dst_file-$$-$BATS_TEST_NUMBER"
  echo "content" > "$src"
  run bash -c "
    source '$SCRIPT'
    DRY_RUN=1
    WRITE_COUNT=0
    dry_mv '$src' '$dst'
    echo \"status=\$?\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN] Would install"* ]]
  [[ "$output" == *"$(basename "$dst")"* ]]
  [ ! -f "$dst" ]
}

# test_dry_mv_in_dry_run_increments_write_count
# dry_mv with DRY_RUN=1 must increment WRITE_COUNT
@test "test_dry_mv_in_dry_run_increments_write_count" {
  local src="$BATS_TMPDIR/src_file2-$$-$BATS_TEST_NUMBER"
  local dst="$BATS_TMPDIR/dst_file2-$$-$BATS_TEST_NUMBER"
  echo "content" > "$src"
  run bash -c "
    source '$SCRIPT'
    DRY_RUN=1
    WRITE_COUNT=0
    dry_mv '$src' '$dst'
    echo \"WRITE_COUNT=\$WRITE_COUNT\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"WRITE_COUNT=1"* ]]
}

# test_dry_cp_in_dry_run_prints_and_does_not_write
# dry_cp with DRY_RUN=1 must print and not create the destination file
@test "test_dry_cp_in_dry_run_prints_and_does_not_write" {
  local src="$BATS_TMPDIR/src_file3-$$-$BATS_TEST_NUMBER"
  local dst="$BATS_TMPDIR/dst_file3-$$-$BATS_TEST_NUMBER"
  echo "content" > "$src"
  run bash -c "
    source '$SCRIPT'
    DRY_RUN=1
    WRITE_COUNT=0
    dry_cp '$src' '$dst'
    echo \"status=\$?\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN] Would install"* ]]
  [[ "$output" == *"$(basename "$dst")"* ]]
  [ ! -f "$dst" ]
}

# test_dry_mkdir_in_dry_run_prints_and_does_not_create
# dry_mkdir with DRY_RUN=1 must print and not create the directory
@test "test_dry_mkdir_in_dry_run_prints_and_does_not_create" {
  local newdir="$BATS_TMPDIR/newdir-$$-$BATS_TEST_NUMBER"
  run bash -c "
    source '$SCRIPT'
    DRY_RUN=1
    WRITE_COUNT=0
    dry_mkdir '$newdir'
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN] Would create directory"* ]]
  [[ "$output" == *"$newdir"* ]]
  [ ! -d "$newdir" ]
}

# test_dry_mkdir_does_not_increment_write_count
# dry_mkdir must NOT increment WRITE_COUNT
@test "test_dry_mkdir_does_not_increment_write_count" {
  local newdir="$BATS_TMPDIR/newdir2-$$-$BATS_TEST_NUMBER"
  run bash -c "
    source '$SCRIPT'
    DRY_RUN=1
    WRITE_COUNT=0
    dry_mkdir '$newdir'
    echo \"WRITE_COUNT=\$WRITE_COUNT\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"WRITE_COUNT=0"* ]]
}

# test_dry_mv_in_real_mode_moves_file
# dry_mv with DRY_RUN=0 must actually move the file to the destination
@test "test_dry_mv_in_real_mode_moves_file" {
  local src="$BATS_TMPDIR/src_real-$$-$BATS_TEST_NUMBER"
  local dst="$BATS_TMPDIR/dst_real-$$-$BATS_TEST_NUMBER"
  echo "real-content" > "$src"
  bash -c "
    source '$SCRIPT'
    DRY_RUN=0
    WRITE_COUNT=0
    dry_mv '$src' '$dst'
  "
  [ -f "$dst" ]
  grep -q "real-content" "$dst"
}

# test_dry_cp_in_real_mode_copies_file
# dry_cp with DRY_RUN=0 must actually copy the file to the destination
@test "test_dry_cp_in_real_mode_copies_file" {
  local src="$BATS_TMPDIR/src_cp_real-$$-$BATS_TEST_NUMBER"
  local dst="$BATS_TMPDIR/dst_cp_real-$$-$BATS_TEST_NUMBER"
  echo "cp-content" > "$src"
  bash -c "
    source '$SCRIPT'
    DRY_RUN=0
    WRITE_COUNT=0
    dry_cp '$src' '$dst'
  "
  [ -f "$dst" ]
  grep -q "cp-content" "$dst"
  # src still exists (cp, not mv)
  [ -f "$src" ]
}

# ---------------------------------------------------------------------------
# Phase 2 Tests: Task 2.3 — move_files() integration tests
# ---------------------------------------------------------------------------

# test_dry_run_scripts_not_written_to_dest
# Full --dry-run: scripts/ dir must NOT be created at dest
@test "test_dry_run_scripts_not_written_to_dest" {
  # Touch marker AFTER setup() has created fixture files, BEFORE run
  local marker="$BATS_TMPDIR/marker-$$-$BATS_TEST_NUMBER"
  touch "$marker"

  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]

  # No files under INSTALL_DEST should be newer than marker
  local new_files
  new_files="$(find "$INSTALL_DEST" -newer "$marker" 2>/dev/null)"
  [ -z "$new_files" ]

  rm -f "$marker"
}

# test_dry_run_install_sh_not_written
# Full --dry-run: install.sh must NOT be written at dest
@test "test_dry_run_install_sh_not_written" {
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  [ ! -f "$INSTALL_DEST/install.sh" ]
}

# test_dry_run_each_script_file_logged
# Full --dry-run: output must contain [DRY RUN] Would install line for each fixture script
@test "test_dry_run_each_script_file_logged" {
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]

  # Check each file in fixture scripts/
  for f in "$FIXTURE_DIR/scripts/"*; do
    [[ -e "$f" ]] || continue
    local fname
    fname="$(basename "$f")"
    [[ "$output" == *"[DRY RUN] Would install $fname"* ]]
  done

  # install.sh itself
  [[ "$output" == *"[DRY RUN] Would install install.sh"* ]]
}

# test_real_mode_scripts_written_correctly
# Regression: without --dry-run, files must be written to dest (move_files refactor)
@test "test_real_mode_scripts_written_correctly" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [ -f "$INSTALL_DEST/scripts/plan-progress.sh" ]
  [ -f "$INSTALL_DEST/scripts/task_section.awk" ]
  [ -f "$INSTALL_DEST/scripts/progress-header-flat.template" ]
  [ -f "$INSTALL_DEST/install.sh" ]
}

# ---------------------------------------------------------------------------
# Phase 2 Tests: Task 2.4 — handle_claude_md() dry-run branch tests
# ---------------------------------------------------------------------------

# test_dry_run_claude_md_absent_prints_would_copy
# No CLAUDE.md at dest; --dry-run output must say "Would copy CLAUDE.md"
@test "test_dry_run_claude_md_absent_prints_would_copy" {
  [ ! -f "$INSTALL_DEST/CLAUDE.md" ]
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN] Would copy CLAUDE.md"* ]]
  [ ! -f "$INSTALL_DEST/CLAUDE.md" ]
}

# test_dry_run_claude_md_exists_no_flags_prints_skip_hint
# Existing CLAUDE.md at dest; --dry-run (no other flags); output must say "Would skip CLAUDE.md"
@test "test_dry_run_claude_md_exists_no_flags_prints_skip_hint" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN] Would skip CLAUDE.md (use --overwrite to replace)"* ]]
  # File must remain unchanged
  grep -q "existing-content" "$INSTALL_DEST/CLAUDE.md"
}

# test_dry_run_keep_claude_md_existing_is_silent
# --keep-claude-md, CLAUDE.md at dest; no dry-run output for CLAUDE.md
@test "test_dry_run_keep_claude_md_existing_is_silent" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run bash "$SCRIPT" --dry-run --keep-claude-md 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" != *"Would copy CLAUDE.md"* ]]
  [[ "$output" != *"Would skip CLAUDE.md"* ]]
  [[ "$output" != *"Would overwrite CLAUDE.md"* ]]
  # Must not have changed the file
  grep -q "existing-content" "$INSTALL_DEST/CLAUDE.md"
}

# test_dry_run_keep_claude_md_absent_prints_would_copy
# --keep-claude-md, no CLAUDE.md at dest; output must say "Would copy CLAUDE.md"
@test "test_dry_run_keep_claude_md_absent_prints_would_copy" {
  [ ! -f "$INSTALL_DEST/CLAUDE.md" ]
  run bash "$SCRIPT" --dry-run --keep-claude-md 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN] Would copy CLAUDE.md"* ]]
  [ ! -f "$INSTALL_DEST/CLAUDE.md" ]
}

# test_dry_run_overwrite_non_tty_prints_would_overwrite
# --overwrite, _INSTALL_IS_TTY=0, CLAUDE.md at dest; output must say "Would overwrite CLAUDE.md"
@test "test_dry_run_overwrite_non_tty_prints_would_overwrite" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$FIXTURE_DIR" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" --dry-run --overwrite 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY RUN] Would overwrite CLAUDE.md"* ]]
  # File must remain unchanged
  grep -q "existing-content" "$INSTALL_DEST/CLAUDE.md"
}

# test_dry_run_overwrite_tty_shows_diff_and_would_prompt
# --overwrite, _INSTALL_IS_TTY=1, _INSTALL_PAGER=cat; output must include diff AND
# "[DRY RUN] Would prompt: Overwrite CLAUDE.md? [y/N]"
@test "test_dry_run_overwrite_tty_shows_diff_and_would_prompt" {
  echo "existing-content" > "$INSTALL_DEST/CLAUDE.md"
  run timeout 5 env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$FIXTURE_DIR" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=1 \
    _INSTALL_PAGER=cat \
    bash "$SCRIPT" --dry-run --overwrite 2>&1
  [ "$status" -eq 0 ]
  # Diff content must be present (existing-content appears in diff -)
  [[ "$output" == *"existing-content"* ]]
  # Prompt message must be present
  [[ "$output" == *"[DRY RUN] Would prompt: Overwrite CLAUDE.md?"* ]]
  # File must remain unchanged
  grep -q "existing-content" "$INSTALL_DEST/CLAUDE.md"
}

# test_dry_run_claude_md_not_written_in_any_branch
# All --dry-run branches must not write or modify CLAUDE.md at dest
@test "test_dry_run_claude_md_not_written_in_any_branch" {
  local marker="$BATS_TMPDIR/marker2-$$-$BATS_TEST_NUMBER"

  # Branch 1: absent + no flags
  rm -f "$INSTALL_DEST/CLAUDE.md"
  touch "$marker"
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  new_files="$(find "$INSTALL_DEST" -newer "$marker" 2>/dev/null)"
  [ -z "$new_files" ]

  # Branch 2: present + no flags
  echo "existing" > "$INSTALL_DEST/CLAUDE.md"
  touch "$marker"
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  grep -q "existing" "$INSTALL_DEST/CLAUDE.md"

  # Branch 3: present + --overwrite (non-TTY)
  touch "$marker"
  run env INSTALL_SKIP_CLONE=1 INSTALL_FIXTURE_DIR="$FIXTURE_DIR" \
    INSTALL_DEST="$INSTALL_DEST" INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    _INSTALL_IS_TTY=0 bash "$SCRIPT" --dry-run --overwrite 2>&1
  [ "$status" -eq 0 ]
  grep -q "existing" "$INSTALL_DEST/CLAUDE.md"

  # Branch 4: present + --keep-claude-md
  touch "$marker"
  run bash "$SCRIPT" --dry-run --keep-claude-md 2>&1
  [ "$status" -eq 0 ]
  grep -q "existing" "$INSTALL_DEST/CLAUDE.md"

  rm -f "$marker"
}

# ---------------------------------------------------------------------------
# Phase 2 Tests: Task 2.5 — main() summary and exit code tests
# ---------------------------------------------------------------------------

# test_dry_run_prints_summary_count
# Full --dry-run fresh install (no existing CLAUDE.md): count = scripts/ + install.sh + CLAUDE.md
@test "test_dry_run_prints_summary_count" {
  # No CLAUDE.md at dest → CLAUDE.md is counted too
  local expected_count=0
  for f in "$FIXTURE_DIR/scripts/"*; do
    [[ -e "$f" ]] || continue
    expected_count=$(( expected_count + 1 ))
  done
  expected_count=$(( expected_count + 1 ))  # +1 for install.sh
  expected_count=$(( expected_count + 1 ))  # +1 for CLAUDE.md (absent → counted)

  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"${expected_count} file(s) would be installed."* ]]
}

# test_dry_run_summary_excludes_skipped_claude_md
# --dry-run without --overwrite, CLAUDE.md at dest; count must exclude skipped CLAUDE.md
@test "test_dry_run_summary_excludes_skipped_claude_md" {
  echo "existing" > "$INSTALL_DEST/CLAUDE.md"
  # Count how many scripts/ files + install.sh are in fixture (no CLAUDE.md since it's skipped)
  local expected_count=0
  for f in "$FIXTURE_DIR/scripts/"*; do
    [[ -e "$f" ]] || continue
    expected_count=$(( expected_count + 1 ))
  done
  expected_count=$(( expected_count + 1 ))  # +1 for install.sh; CLAUDE.md excluded

  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"${expected_count} file(s) would be installed."* ]]
}

# test_dry_run_does_not_print_installed_successfully
# --dry-run must NOT print "installed successfully"
@test "test_dry_run_does_not_print_installed_successfully" {
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" != *"installed successfully"* ]]
}

# test_dry_run_exits_0
# --dry-run must exit 0
@test "test_dry_run_exits_0" {
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
}

# test_real_mode_still_prints_success_message
# Regression: without --dry-run, output must contain "installed successfully"
@test "test_real_mode_still_prints_success_message" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"installed successfully"* ]]
}

# ---------------------------------------------------------------------------
# Phase 1 Tests: Task 1.1 special — staging cleanup invariant (case 15)
# ---------------------------------------------------------------------------

# test_dry_run_stage_dir_cleaned_up
# INSTALL_STAGE_DIR injection: stage dir must not exist after dry-run
@test "test_dry_run_stage_dir_cleaned_up" {
  local known_stage="$BATS_TMPDIR/known_stage-$$-$BATS_TEST_NUMBER"
  mkdir -p "$known_stage"

  run env INSTALL_SKIP_CLONE=1 \
    INSTALL_FIXTURE_DIR="$FIXTURE_DIR" \
    INSTALL_DEST="$INSTALL_DEST" \
    INSTALL_REPO_URL="$INSTALL_REPO_URL" \
    INSTALL_STAGE_DIR="$known_stage" \
    _INSTALL_IS_TTY=0 \
    bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  [[ ! -d "$known_stage" ]]
}

# ---------------------------------------------------------------------------
# Phase 1 Tests: Task 1.1 special — regression gate (case 12)
# ---------------------------------------------------------------------------

# test_regression_existing_tests_pass
# Run all existing test suites; assert they all pass (regression gate)
@test "test_regression_existing_tests_pass" {
  run bats "$HOME/.claude/tests/test_install_prereqs.bats" \
    "$HOME/.claude/tests/test_install_copy.bats" \
    "$HOME/.claude/tests/test_install_claude_md.bats" \
    "$HOME/.claude/tests/test_install_e2e.bats"
  if [ "$status" -ne 0 ]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]
}
