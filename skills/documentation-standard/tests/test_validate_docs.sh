#!/usr/bin/env bash
# Tests for scripts/validate_docs.py — run: bash tests/test_validate_docs.sh
#
# The documentation-standard skill invokes this validator via $BASE. These tests
# build temporary fixture docs trees and assert the validator's ACTUAL, observed
# behaviour (exit code + printed output), not its docstring. Where the real
# behaviour differs from what the CLI help implies, the assertion pins the real
# behaviour and the case name records the discrepancy. Requires python3.
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/validate_docs.py"
RESULTS="$(mktemp)"
# A sandbox cwd+HOME with no readme.md/contributing.md, so the validator's
# root-file check (which inspects the CURRENT directory, not the docs tree)
# behaves deterministically across machines.
SANDBOX="$(mktemp -d)"
CURRENT=""

t()   { CURRENT="$1"; }
ok()  { echo "PASS" >> "$RESULTS"; }
bad() { echo "FAIL: $CURRENT — $1" >> "$RESULTS"; echo "FAIL: $CURRENT — $1" >&2; }

assert_eq()      { [ "$1" = "$2" ] && ok || bad "expected [$2], got [$1]"; }
assert_match()   { printf '%s' "$1" | grep -qF -- "$2" && ok || bad "output should contain [$2]"; }
assert_nomatch() { printf '%s' "$1" | grep -qF -- "$2" && bad "output should NOT contain [$2]" || ok; }

# Run the validator from the sandbox cwd. Args are passed through. Sets RC, OUT.
run() {
  OUT="$(cd "$SANDBOX" && HOME="$SANDBOX" python3 "$SCRIPT" "$@" 2>&1)"; RC=$?
}

# Build a well-formed docs tree at $1: all required dirs, a correctly named
# Architecture file with a valid metadata header + fresh (future) review date,
# and a correctly named ADR with all required sections.
mk_well() {
  local d="$1"
  mkdir -p "$d/Architecture" "$d/ADRs" "$d/Backlog" "$d/Completed" "$d/UserManual"
  printf '# Overview\n\n**Purpose**: Describe the system\n**Audience**: Engineers\n**Status**: Active\n**Last reviewed**: 2026-01-01\n**Next review**: 2999-01-01\n\nBody text here.\n' \
    > "$d/Architecture/001_overview.md"
  printf '# Use Postgres\n\nStatus: Accepted\nDate: 2026-01-01\n\n## Context\nSome context.\n\n## Decision\nWe use Postgres.\n\n## Consequences\nFine.\n' \
    > "$d/ADRs/01_use_postgres.md"
}

# ---------------------------------------------------------------- happy path

( t "well-formed tree (valid dirs + metadata + fresh dates) passes: exit 0, no errors"
  D="$(mktemp -d)/docs"; mk_well "$D"
  run --path "$D"
  assert_eq "$RC" "0"
  assert_match "$OUT" "Validation PASSED"
  assert_nomatch "$OUT" "Missing or invalid metadata header"
  assert_nomatch "$OUT" "Validation FAILED" )

# ---------------------------------------------------------------- missing directory
# DISCREPANCY: a missing required directory is a WARNING, not an error, so the
# non-strict run still exits 0 ("PASSED with warnings") — it is not a hard failure.

( t "missing required directory is a WARNING, non-strict exit 0 (discrepancy: not a hard fail)"
  D="$(mktemp -d)/docs"; mk_well "$D"; rmdir "$D/Backlog"
  run --path "$D"
  assert_eq "$RC" "0"
  assert_match "$OUT" "Missing expected directories: Backlog"
  assert_match "$OUT" "Validation PASSED with warnings" )

# ---------------------------------------------------------------- missing metadata header
# Metadata headers are validated only for files under Architecture/ (verified in
# validate_architecture_files -> validate_markdown_file); this is where the check fires.

( t "Architecture doc missing metadata header is an ERROR: exit 1, reported"
  D="$(mktemp -d)/docs"; mk_well "$D"
  printf '# No Meta\n\nJust a body, no metadata block.\n' > "$D/Architecture/002_nometa.md"
  run --path "$D"
  assert_eq "$RC" "1"
  assert_match "$OUT" "Missing or invalid metadata header"
  assert_match "$OUT" "Validation FAILED" )

# ---------------------------------------------------------------- --strict escalation

( t "--strict escalates a warning-only tree to failure: non-strict exit 0, strict exit 1"
  D="$(mktemp -d)/docs"; mk_well "$D"; rmdir "$D/Completed"   # produces a warning, no error
  run --path "$D"
  assert_eq "$RC" "0"
  run --path "$D" --strict
  assert_eq "$RC" "1"
  assert_match "$OUT" "strict mode" )

# ---------------------------------------------------------------- stale review date

( t "stale (past) Next review date is flagged as an overdue WARNING, non-strict exit 0"
  D="$(mktemp -d)/docs"; mk_well "$D"
  printf '# Old\n\n**Purpose**: x\n**Audience**: x\n**Status**: x\n**Last reviewed**: 2020-01-01\n**Next review**: 2020-06-01\n\nBody.\n' \
    > "$D/Architecture/003_old.md"
  run --path "$D"
  assert_eq "$RC" "0"
  assert_match "$OUT" "Documentation review overdue" )

# ---------------------------------------------------------------- --path vs default
# DISCREPANCY: when the docs dir is absent the validator exits 1 but prints NO
# error text (validate() returns before print_results), so we assert on exit code.

( t "--path targets the fixture; default 'Documentation' is used when --path is omitted"
  D="$(mktemp -d)/docs"; mk_well "$D"
  run --path "$D"
  assert_eq "$RC" "0"                       # fixture found via --path
  run                                        # no --path, sandbox cwd has no Documentation/
  assert_eq "$RC" "1"                        # default path used, not the fixture
  assert_nomatch "$OUT" "Validation PASSED" )

# ----------------------------------------------------------------

PASS="$(grep -c '^PASS$' "$RESULTS")"
FAIL="$(grep -c '^FAIL' "$RESULTS")"
rm -rf "$RESULTS" "$SANDBOX"
echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
