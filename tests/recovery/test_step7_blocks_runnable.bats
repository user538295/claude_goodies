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

@test "expected-cc.sh exists" {
  [ -f "$EXPECTED_CC" ]
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

@test "step7 cc markdown extraction matches expected-cc.sh" {
  # Extract the Step 7 section from implement-next-cc.md (between Step 7 and Step 8 headings),
  # then strip the 3-space list-item indent so column-1 fence detection works.
  local section
  section="$(sed -n '/^### Step 7/,/^### Step 8/p' "$MD_CC" | sed -E 's/^   //')"
  local extracted
  extracted="$(printf '%s\n' "$section" | bash "$EXTRACTOR")"
  local expected
  expected="$(cat "$EXPECTED_CC")"
  [ "$extracted" = "$expected" ]
}

@test "test_step7_blocks_expected_files_share_check_blocks" {
  # The two skills' Step 7 check blocks (checks 1, 2, 3) are textually mirrored.
  # The cc variant legitimately diverges by appending a final breadcrumb-clear
  # bash block ("On success, clear the breadcrumb"); this is required by
  # Task 2.2 because cc Step 7 owns the breadcrumb-clear that portable Step 7
  # does not need (portable parents already cleared on halt paths).
  #
  # Invariant: every line of expected-portable.sh appears verbatim in
  # expected-cc.sh, and cc has EXACTLY ONE extra line at the end
  # (the implement-next-state-clear.sh invocation).
  local portable_lines cc_lines
  portable_lines="$(wc -l < "$EXPECTED_PORTABLE" | tr -d ' ')"
  cc_lines="$(wc -l < "$EXPECTED_CC" | tr -d ' ')"
  # cc has exactly one more line than portable.
  [ $((cc_lines - portable_lines)) -eq 1 ]
  # The first $portable_lines lines of cc are byte-identical to portable.
  diff -q <(head -n "$portable_lines" "$EXPECTED_CC") "$EXPECTED_PORTABLE"
  # The final line of cc is the breadcrumb-clear invocation.
  tail -n 1 "$EXPECTED_CC" | grep -qF 'implement-next-state-clear.sh "$(pwd)"'
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
