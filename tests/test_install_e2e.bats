#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# test_install_e2e.bats — Integration tests for install.sh full flow
# Uses a local git repo fixture instead of real network clone.
# ---------------------------------------------------------------------------

SCRIPT="$HOME/.claude/install.sh"

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

create_git_fixture_repo() {
  local repo="$1"
  git init "$repo" >/dev/null 2>&1
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config user.name "Test"
  mkdir -p "$repo/scripts"
  printf '#!/bin/sh\necho plan-progress\n' > "$repo/scripts/plan-progress.sh"
  printf '#!/usr/bin/awk -f\n# awk script\n' > "$repo/scripts/task_section.awk"
  printf '# template\n' > "$repo/scripts/progress-header-flat.template"
  printf '# CLAUDE.md content from repo\n' > "$repo/CLAUDE.md"
  printf '#!/usr/bin/env bash\n# install.sh fixture\n' > "$repo/install.sh"
  git -C "$repo" add .
  git -C "$repo" commit -m "fixture" >/dev/null 2>&1
}

setup() {
  FIXTURE_REPO="$BATS_TMPDIR/fixture_repo-e2e-$$-$BATS_TEST_NUMBER"
  create_git_fixture_repo "$FIXTURE_REPO"

  export INSTALL_REPO_URL="file://$FIXTURE_REPO"
  export INSTALL_DEST="$BATS_TMPDIR/test_dest-e2e-$$-$BATS_TEST_NUMBER"
  export _INSTALL_IS_TTY=0
  mkdir -p "$INSTALL_DEST"
}

teardown() {
  rm -rf "$FIXTURE_REPO" "$INSTALL_DEST" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# test_full_install_fresh_dest
# Full clone-based install to a fresh dest; assert all files present,
# .sh files executable, and forbidden dirs absent.
# ---------------------------------------------------------------------------
@test "test_full_install_fresh_dest" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]

  # Core files present
  [ -f "$INSTALL_DEST/scripts/plan-progress.sh" ]
  [ -f "$INSTALL_DEST/scripts/task_section.awk" ]
  [ -f "$INSTALL_DEST/scripts/progress-header-flat.template" ]
  [ -f "$INSTALL_DEST/install.sh" ]
  [ -f "$INSTALL_DEST/CLAUDE.md" ]

  # .sh files executable
  [ -x "$INSTALL_DEST/scripts/plan-progress.sh" ]
  [ -x "$INSTALL_DEST/install.sh" ]

  # Non-.sh files NOT executable
  [ ! -x "$INSTALL_DEST/scripts/task_section.awk" ]
  [ ! -x "$INSTALL_DEST/scripts/progress-header-flat.template" ]

  # Forbidden dirs must NOT exist
  [ ! -d "$INSTALL_DEST/agents" ]
  [ ! -d "$INSTALL_DEST/commands" ]
  [ ! -d "$INSTALL_DEST/skills" ]
}

# ---------------------------------------------------------------------------
# test_idempotent_second_run
# Run full install twice; assert second run exits 0, CLAUDE.md unchanged,
# all scripts present and .sh files executable.
# ---------------------------------------------------------------------------
@test "test_idempotent_second_run" {
  # First run
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]

  # Record CLAUDE.md content after first run
  local first_content
  first_content="$(cat "$INSTALL_DEST/CLAUDE.md")"

  # Second run
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]

  # CLAUDE.md must be unchanged (default mode — no --overwrite)
  local second_content
  second_content="$(cat "$INSTALL_DEST/CLAUDE.md")"
  [ "$first_content" = "$second_content" ]

  # All scripts still present and executable
  [ -f "$INSTALL_DEST/scripts/plan-progress.sh" ]
  [ -x "$INSTALL_DEST/scripts/plan-progress.sh" ]
  [ -f "$INSTALL_DEST/install.sh" ]
  [ -x "$INSTALL_DEST/install.sh" ]

  # Hint message printed on second run (existing CLAUDE.md)
  [[ "$output" == *"--overwrite"* ]]
}
