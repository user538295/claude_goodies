#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# test_install_recovery.bats — TDD tests for install.sh recovery-feature
# additions (Task 4.1 of RECOVERY-001-implement-next-recovery-flow):
#   - scripts/implement-next-triage.sh in both files arrays
#   - check_cc_variant_integrity() lists scripts/implement-next-triage.sh
#   - new check_portable_variant_integrity() function
#   - both integrity checks invoked from the same call site
# ---------------------------------------------------------------------------

SCRIPT="$HOME/.claude/install.sh"

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# create_full_manifest_fixture — populate $1 with EVERY file listed in
# install.sh's stage_files() manifest plus CLAUDE.md and install.sh, so the
# install.sh `set -euo pipefail`-guarded stage step does not abort on a
# missing file. Comment lines inside the `files=(...)` block (e.g. the
# RECOVERY_SCHEMA_V2 marker) are filtered out — without filtering, word
# splitting would turn the comment text into spurious filename tokens.
create_full_manifest_fixture() {
  local dir="$1"
  local f
  local files
  files=$(awk '
    /^  local files=\(/ { flag=1; next }
    flag && /^  \)/    { flag=0 }
    flag {
      # strip any in-line trailing comment + skip lines whose first
      # non-whitespace char is "#" (full-line comments)
      sub(/[ \t]*#.*$/, "")
      if ($0 ~ /[^[:space:]]/) print
    }
  ' "$SCRIPT" | tr -d '\n' | tr -s ' ')
  for f in $files; do
    local dst="$dir/$f"
    mkdir -p "$(dirname "$dst")"
    case "$f" in
      *.sh) echo "#!/bin/sh" > "$dst" ;;
      *.py) echo "#!/usr/bin/env python3" > "$dst" ;;
      *.awk) echo "#!/usr/bin/awk -f" > "$dst" ;;
      *) echo "# stub for $f" > "$dst" ;;
    esac
  done
  echo "# CLAUDE.md content" > "$dir/CLAUDE.md"
  echo "#!/usr/bin/env bash" > "$dir/install.sh"
}

setup() {
  export INSTALL_DEST="$BATS_TMPDIR/test_dest-$$-$BATS_TEST_NUMBER"
  export INSTALL_REPO_URL="file://$BATS_TMPDIR/fixture_repo-$$-$BATS_TEST_NUMBER"
  export _INSTALL_IS_TTY=0
  mkdir -p "$INSTALL_DEST"

  FIXTURE_DIR="$BATS_TMPDIR/fixture_dir-$$-$BATS_TEST_NUMBER"
  create_full_manifest_fixture "$FIXTURE_DIR"
  export INSTALL_FIXTURE_DIR="$FIXTURE_DIR"
  export INSTALL_SKIP_CLONE=1
}

teardown() {
  rm -rf "$INSTALL_DEST" "$FIXTURE_DIR" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# test_install_copies_triage_script
# Dry-run install must include implement-next-triage.sh in its output.
# ---------------------------------------------------------------------------
@test "test_install_copies_triage_script" {
  run bash "$SCRIPT" --dry-run 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"implement-next-triage.sh"* ]]
}

# ---------------------------------------------------------------------------
# test_install_real_copies_triage_script_to_dest
# After a real install, scripts/implement-next-triage.sh must exist at DEST.
# ---------------------------------------------------------------------------
@test "test_install_real_copies_triage_script_to_dest" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  [ -f "$INSTALL_DEST/scripts/implement-next-triage.sh" ]
}

# ---------------------------------------------------------------------------
# test_install_integrity_check_includes_triage
# Source install.sh into a sub-shell, remove triage script from DEST,
# call check_cc_variant_integrity, assert stderr names the triage file.
# ---------------------------------------------------------------------------
@test "test_install_integrity_check_includes_triage" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  rm -f "$INSTALL_DEST/scripts/implement-next-triage.sh"

  run bash -c "DEST_DIR='$INSTALL_DEST'; source '$SCRIPT'; DEST_DIR='$INSTALL_DEST'; check_cc_variant_integrity" 2>&1
  [[ "$output" == *"implement-next-triage.sh"* ]]
}

# ---------------------------------------------------------------------------
# test_install_portable_integrity_check_includes_triage
# Symmetric to cc test — check_portable_variant_integrity warns about the
# missing triage script.
# ---------------------------------------------------------------------------
@test "test_install_portable_integrity_check_includes_triage" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  rm -f "$INSTALL_DEST/scripts/implement-next-triage.sh"

  run bash -c "DEST_DIR='$INSTALL_DEST'; source '$SCRIPT'; DEST_DIR='$INSTALL_DEST'; check_portable_variant_integrity" 2>&1
  [[ "$output" == *"implement-next-triage.sh"* ]]
}

# ---------------------------------------------------------------------------
# test_install_portable_integrity_check_function_exists
# check_portable_variant_integrity must be defined as a function. Use
# declare -F (locale-independent) rather than `type` whose message is
# localised.
# ---------------------------------------------------------------------------
@test "test_install_portable_integrity_check_function_exists" {
  run bash -c "source '$SCRIPT'; declare -F check_portable_variant_integrity"
  [ "$status" -eq 0 ]
  [[ "$output" == *"check_portable_variant_integrity"* ]]
}

# ---------------------------------------------------------------------------
# test_install_calls_both_integrity_checks_end_to_end
# Per plan: install in tmp DEST_DIR, remove triage script, source install.sh
# functions and invoke both checks against the modified DEST_DIR. The plan
# explicitly allows sourcing either ${DEST_DIR}/install.sh or ${SRC}/install.sh
# — we use ${SRC} because the stub install.sh in the fixture lacks the
# function definitions.
# ---------------------------------------------------------------------------
@test "test_install_calls_both_integrity_checks_end_to_end" {
  run bash "$SCRIPT" 2>&1
  [ "$status" -eq 0 ]
  rm -f "$INSTALL_DEST/scripts/implement-next-triage.sh"

  run bash -c "DEST_DIR='$INSTALL_DEST'; source '$SCRIPT'; DEST_DIR='$INSTALL_DEST'; check_cc_variant_integrity" 2>&1
  [[ "$output" == *"implement-next-triage.sh"* ]]

  run bash -c "DEST_DIR='$INSTALL_DEST'; source '$SCRIPT'; DEST_DIR='$INSTALL_DEST'; check_portable_variant_integrity" 2>&1
  [[ "$output" == *"implement-next-triage.sh"* ]]
}

# ---------------------------------------------------------------------------
# test_install_sh_lists_triage_at_least_four_times
# Inline syntactic check: grep -c "implement-next-triage" install.sh >= 4
# (two files arrays + two integrity checks).
# ---------------------------------------------------------------------------
@test "test_install_sh_lists_triage_at_least_four_times" {
  local count
  count=$(grep -c "implement-next-triage" "$SCRIPT")
  [ "$count" -ge 4 ]
}

# ---------------------------------------------------------------------------
# test_install_invokes_portable_integrity_check_in_move_files
# move_files (the post-install block that calls check_cc_variant_integrity)
# must also call check_portable_variant_integrity (>= 2 occurrences: def + call).
# ---------------------------------------------------------------------------
@test "test_install_invokes_portable_integrity_check_in_move_files" {
  local count
  count=$(grep -c "check_portable_variant_integrity" "$SCRIPT")
  [ "$count" -ge 2 ]
}

# ---------------------------------------------------------------------------
# test_install_recovery_schema_v2_marker_present
# The RECOVERY_SCHEMA_V2 marker comment must appear near triage-script
# insertion points so future grep-based version checks succeed.
# ---------------------------------------------------------------------------
@test "test_install_recovery_schema_v2_marker_present" {
  local count
  count=$(grep -c "RECOVERY_SCHEMA_V2" "$SCRIPT")
  [ "$count" -ge 1 ]
}
