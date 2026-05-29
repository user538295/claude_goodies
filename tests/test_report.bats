#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-report-src"
mkdir -p "$CLAUDE_DIR" && git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

setup() {
  TMPDIR_TEST="$BATS_TMPDIR/test-report-$$-$BATS_TEST_NUMBER"
  mkdir -p "$TMPDIR_TEST"
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  reset_globals
  CLAUDE_DIR="$TMPDIR_TEST"
  CONF_FILE="$CLAUDE_DIR/sync-answers.conf"
  REPORT_APPLIED=()
  REPORT_DRY_RUN=()
  REPORT_ERRORS=()
  REPORT_PENDING=()
  DRY_RUN=""
}

teardown() { [[ -d "${TMPDIR_TEST:-}" ]] && rm -rf "$TMPDIR_TEST"; }

# ---------------------------------------------------------------------------
# test_report_shows_applied_transitions
# Populate REPORT_APPLIED; assert output contains path and section header.
# ---------------------------------------------------------------------------
@test "test_report_shows_applied_transitions" {
  REPORT_APPLIED=("CLAUDE.md ('' → r)")

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Applied ==="* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
}

# ---------------------------------------------------------------------------
# test_report_shows_errors
# Populate REPORT_ERRORS; assert error section present in output.
# ---------------------------------------------------------------------------
@test "test_report_shows_errors" {
  REPORT_ERRORS=("broken/file.sh: git rm --cached failed (exit 1)")

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Errors ==="* ]]
  [[ "$output" == *"broken/file.sh"* ]]
}

# ---------------------------------------------------------------------------
# test_report_pending_always_printed
# Empty REPORT_PENDING; assert pending section still printed with "(none)".
# ---------------------------------------------------------------------------
@test "test_report_pending_always_printed" {
  REPORT_PENDING=()

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Pending"* ]]
  [[ "$output" == *"(none)"* ]]
}

# ---------------------------------------------------------------------------
# test_report_pending_lists_files
# Populate REPORT_PENDING; assert files listed in output.
# ---------------------------------------------------------------------------
@test "test_report_pending_lists_files" {
  REPORT_PENDING=("new-file.sh" "new-dir/")

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"new-file.sh"* ]]
  [[ "$output" == *"new-dir/"* ]]
}

# ---------------------------------------------------------------------------
# test_report_dry_run_shows_dry_run_actions
# DRY_RUN=true; populate REPORT_DRY_RUN; assert "Would Apply (dry-run)" header
# present and "=== Applied ===" NOT present.
# ---------------------------------------------------------------------------
@test "test_report_dry_run_shows_dry_run_actions" {
  REPORT_DRY_RUN=("CLAUDE.md: '' → r (dry-run)")
  DRY_RUN=true

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Would Apply (dry-run) ==="* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
  # "=== Applied ===" must NOT appear
  [[ "$output" != *"=== Applied ==="* ]]
}

# ---------------------------------------------------------------------------
# test_report_applied_empty_shows_none (C1-T-1)
# Empty REPORT_APPLIED; assert Applied section shows "(none)".
# ---------------------------------------------------------------------------
@test "test_report_applied_empty_shows_none" {
  REPORT_APPLIED=()
  REPORT_ERRORS=("one error")  # non-empty so only Applied prints "(none)"

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Applied ==="* ]]
  # Applied section none marker appears before Errors section
  [[ "$output" == *"=== Applied ==="*"(none)"*"=== Errors ==="* ]]
}

# ---------------------------------------------------------------------------
# test_report_errors_empty_shows_none (C1-T-2)
# Empty REPORT_ERRORS; assert Errors section shows "(none)".
# ---------------------------------------------------------------------------
@test "test_report_errors_empty_shows_none" {
  REPORT_APPLIED=("some transition")  # non-empty so only Errors prints "(none)"
  REPORT_ERRORS=()

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Errors ==="* ]]
  # Errors section none marker appears before Pending section
  [[ "$output" == *"=== Errors ==="*"(none)"*"=== Pending"* ]]
}

# ---------------------------------------------------------------------------
# test_report_all_sections_present (C1-T-3)
# All three report arrays populated; assert all three section headers present.
# ---------------------------------------------------------------------------
@test "test_report_all_sections_present" {
  REPORT_APPLIED=("file.txt: pending → in repo")
  REPORT_ERRORS=("bad.sh: git add failed")
  REPORT_PENDING=("new.txt")

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Applied ==="* ]]
  [[ "$output" == *"=== Errors ==="* ]]
  [[ "$output" == *"=== Pending"* ]]
}

# ---------------------------------------------------------------------------
# test_report_dry_run_errors_and_pending_still_printed (C1-T-4)
# DRY_RUN=true; assert Errors and Pending sections are still printed.
# ---------------------------------------------------------------------------
@test "test_report_dry_run_errors_and_pending_still_printed" {
  REPORT_DRY_RUN=("file.txt: pending → in repo (dry-run)")
  REPORT_ERRORS=("oops: something failed")
  REPORT_PENDING=("unclassified.txt")
  DRY_RUN=true

  run generate_report

  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Errors ==="* ]]
  [[ "$output" == *"oops"* ]]
  [[ "$output" == *"=== Pending"* ]]
  [[ "$output" == *"unclassified.txt"* ]]
}
