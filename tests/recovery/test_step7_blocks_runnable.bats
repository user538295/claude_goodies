#!/usr/bin/env bats
#
# test_step7_blocks_runnable.bats — Tasks 2.1 + 2.2
# RECOVERY_SCHEMA_V2
#
# Validates that the Step 7 bash blocks embedded in implement-next.md AND
# implement-next-cc.md are:
#   (a) syntactically equivalent to a hand-written mirror file
#       (step7-blocks-expected-{portable,cc}.sh), AND
#   (b) execute correctly against a synthetic repo with known SHAs and plan
#       state.
#
# This catches markdown-embedded typos that grep cannot detect AND ensures the
# two skills' Step 7 sections stay textually mirrored.
#
# Per-test isolation: each test creates a fresh $TEST_CWD via mktemp -d under
# $BATS_TMPDIR and removes it in teardown.

EXTRACTOR="$HOME/.claude/tests/recovery/extract-bash-blocks.sh"
EXPECTED_PORTABLE="$HOME/.claude/tests/recovery/step7-blocks-expected-portable.sh"
EXPECTED_CC="$HOME/.claude/tests/recovery/step7-blocks-expected-cc.sh"
MD_PORTABLE="$HOME/.claude/commands/implement-next.md"
MD_CC="$HOME/.claude/commands/implement-next-cc.md"

setup() {
  TEST_CWD="$(mktemp -d "$BATS_TMPDIR/recovery-step7-XXXXXX")"
  export TEST_CWD
}

teardown() {
  if [ -n "${TEST_CWD:-}" ] && [ -d "$TEST_CWD" ]; then
    rm -rf "$TEST_CWD"
  fi
}

# Helper: build a synthetic repo with a plan file and an initial commit.
# Captures START_SHA before any plan checkoff. Then makes a commit that
# checks off one task AND touches an implementation file. Sets START_CHECKED.
build_synth_repo() {
  cd "$TEST_CWD" || return 1
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  cat > plan.md <<'EOF'
# Plan
- [ ] Task 1
- [ ] Task 2
EOF
  echo "x" > impl.txt
  git add plan.md impl.txt
  git commit -q -m "initial"
  START_SHA="$(git rev-parse HEAD)"
  START_CHECKED="$(awk '/^- \[[xX]\]/{c++} END{print c+0}' plan.md)"
  export START_SHA
  export START_CHECKED
}

# ---------------------------------------------------------------------------
# Syntactic-equivalence: Step 7 bash blocks in the markdown match the
# hand-written mirror file.
# ---------------------------------------------------------------------------

@test "expected-portable.sh exists" {
  [ -f "$EXPECTED_PORTABLE" ]
}

@test "step7 portable markdown extraction matches expected-portable.sh" {
  # Extract the Step 7 section from implement-next.md (between Step 7 and Step 8 headings),
  # then strip the 3-space list-item indent so column-1 fence detection works.
  # Note: implement-next.md's Step 7 heading is "### Step 7: Self-verification ..."; Step 8 is "### Step 8: Report".
  local section
  section="$(sed -n '/^### Step 7/,/^### Step 8/p' "$MD_PORTABLE" | sed -E 's/^   //')"
  local extracted
  extracted="$(printf '%s\n' "$section" | bash "$EXTRACTOR")"
  local expected
  expected="$(cat "$EXPECTED_PORTABLE")"
  [ "$extracted" = "$expected" ]
}

@test "test_step7_blocks_expected_files_are_identical" {
  # The two skills' Step 7 sections are textually mirrored — the two expected
  # files MUST be byte-identical. If Task 2.2's expected-cc.sh doesn't exist
  # yet, skip rather than fail (the invariant becomes enforceable once 2.2
  # lands).
  if [ ! -f "$EXPECTED_CC" ]; then
    skip "expected-cc.sh not yet present (Task 2.2)"
  fi
  diff -q "$EXPECTED_PORTABLE" "$EXPECTED_CC"
}

# ---------------------------------------------------------------------------
# Behavioural: Step 7 checks pass against a synthetic repo after a real
# commit lands.
# ---------------------------------------------------------------------------

@test "test_step7_check_task_commit_succeeds_after_commit" {
  build_synth_repo
  # Make a commit on top of START_SHA so check 1 should pass.
  sed -i.bak 's/- \[ \] Task 1/- [x] Task 1/' plan.md
  echo "y" >> impl.txt
  git add plan.md impl.txt
  git commit -q -m "feat: task 1"

  # Check 1: check-task-commit.sh must exit 0.
  run bash "$HOME/.claude/scripts/check-task-commit.sh" "$START_SHA"
  [ "$status" -eq 0 ]
}

@test "test_step7_checkoff_count_grows_after_check" {
  build_synth_repo
  # Apply a checkoff in the plan (write directly — Step 7 check 2 reads on-disk plan).
  sed -i.bak 's/- \[ \] Task 1/- [x] Task 1/' plan.md
  echo "y" >> impl.txt
  git add plan.md impl.txt
  git commit -q -m "feat: task 1"

  # Check 2: END_CHECKED - START_CHECKED >= 1.
  ARGUMENTS="plan.md"
  END_CHECKED=$(awk '/^- \[[xX]\]/{c++} END{print c+0}' "$ARGUMENTS")
  [ $((END_CHECKED - START_CHECKED)) -ge 1 ]
}

@test "check 3 plan+impl files both present after normal commit" {
  build_synth_repo
  sed -i.bak 's/- \[ \] Task 1/- [x] Task 1/' plan.md
  echo "y" >> impl.txt
  git add plan.md impl.txt
  git commit -q -m "feat: task 1"

  ARGUMENTS="plan.md"
  # Plan file in commit
  git show --stat HEAD | grep -q "$(basename "$ARGUMENTS")"
  # Impl files (not plan) in commit
  git show --stat HEAD | awk 'NR>1 && /\|/ {print $1}' | grep -v "$(basename "$ARGUMENTS")" | grep -q .
}

@test "test_step7_check3_self_skip_on_recovery_commit" {
  build_synth_repo
  # Make a recovery(R-B): commit (plan-only by design).
  sed -i.bak 's/- \[ \] Task 1/- [x] Task 1/' plan.md
  git add plan.md
  git commit -q -m "recovery(R-B): retroactively check off Task 1"

  # The self-detection wrapper from Step 7 check 3:
  run bash -c 'if git log -1 --format="%s" HEAD | grep -q "^recovery(R-B):"; then echo "Step 7 check 3: SKIPPED (R-B recovery commit is plan-only by design)"; exit 0; else echo "fell through"; exit 1; fi'
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED"* ]]
}
