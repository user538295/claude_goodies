#!/usr/bin/env bats
#
# test_audit_marker.bats — Task 1.5 coverage for audit-plan-run.sh
# `recovery(R-B):` and `recovery(R-AB):` marker recognition + anomalies-log surfacing.
#
# Per-test isolation: each test creates a fresh $TEST_CWD via mktemp -d under
# $BATS_TMPDIR and removes it in teardown.

SCRIPT="$HOME/.claude/scripts/audit-plan-run.sh"

# Helper: build a plan with N tasks; first <checked_count> are checked off.
# Usage: make_plan <plan_path> <total> <checked_count>
make_plan() {
  local plan="$1"
  local total="$2"
  local checked_count="${3:-0}"
  {
    echo "# Test plan"
    echo ""
    echo "## Tasks"
    echo ""
    local i=1
    while [ "$i" -le "$total" ]; do
      if [ "$i" -le "$checked_count" ]; then
        echo "- [x] Task $i"
      else
        echo "- [ ] Task $i"
      fi
      i=$((i + 1))
    done
  } > "$plan"
}

setup() {
  TEST_CWD="$(mktemp -d "$BATS_TMPDIR/recovery-audit-XXXXXX")"
  export TEST_CWD
  git init -q "$TEST_CWD"
  (
    cd "$TEST_CWD"
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    git commit --allow-empty -q -m "init"
  )
}

teardown() {
  if [ -n "${TEST_CWD:-}" ] && [ -d "$TEST_CWD" ]; then
    rm -rf "$TEST_CWD"
  fi
}

# ---------------------------------------------------------------------------
# test_recovery_marker_downgrades_violation_to_warning (R-B)
# ---------------------------------------------------------------------------
@test "test_recovery_marker_downgrades_violation_to_warning_rb" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 3 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  # Task 1 done: impl + checkoff in one commit (1 commit per task).
  echo "impl1" > f1.txt
  make_plan "$plan" 3 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  # Task 2 done with recovery: orphan impl (without checkoff) +
  # recovery commit (just the checkoff). 2 commits for 1 task.
  echo "impl2" > f2.txt
  git add f2.txt
  git commit -q -m "feat: task 2"
  make_plan "$plan" 3 2
  git add plan.md
  git commit -q -m "recovery(R-B): check off task 2"

  # 3 non-merge commits since sha_start; 2 tasks completed; 1 recovery marker.
  # (3 - 1) == 2 → WARNING + PASS.
  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: Recovery commit(s) detected (count=1"* ]]
  [[ "$output" == *"R-B"* ]]
}

# ---------------------------------------------------------------------------
# test_recovery_marker_downgrades_violation_to_warning (R-AB)
# ---------------------------------------------------------------------------
@test "test_recovery_marker_downgrades_violation_to_warning_rab" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 3 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  echo "impl1" > f1.txt
  make_plan "$plan" 3 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  echo "impl2" > f2.txt
  git add f2.txt
  git commit -q -m "feat: task 2"
  make_plan "$plan" 3 2
  git add plan.md
  git commit -q -m "recovery(R-AB): finalize task 2"

  # 3 non-merge commits; 2 tasks completed; 1 R-AB marker → (3-1)=2 → WARNING+PASS.
  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: Recovery commit(s) detected (count=1"* ]]
  [[ "$output" == *"R-AB"* ]]
}

# ---------------------------------------------------------------------------
# test_typo_marker_not_matched
# ---------------------------------------------------------------------------
@test "test_typo_marker_not_matched" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 2 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  echo "impl1" > f1.txt
  git add f1.txt
  git commit -q -m "feat: task 1"
  make_plan "$plan" 2 1
  git add plan.md
  git commit -q -m "chore: check off task 1"

  # Extra orphan-style commit with a TYPO marker — should NOT downgrade.
  echo "impl2" > f2.txt
  git add f2.txt
  git commit -q -m "recovery(R-X): foo"

  # 3 non-merge commits, 1 task done → VIOLATION.
  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION"* ]]
}

# ---------------------------------------------------------------------------
# test_substring_match_not_counted
# ---------------------------------------------------------------------------
@test "test_substring_match_not_counted" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 2 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  echo "impl1" > f1.txt
  git add f1.txt
  git commit -q -m "feat: task 1"
  make_plan "$plan" 2 1
  git add plan.md
  git commit -q -m "chore: check off task 1"

  # Substring at non-zero column — must NOT count.
  echo "impl2" > f2.txt
  git add f2.txt
  git commit -q -m "This reverts recovery(R-B): foo"

  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION"* ]]
}

# ---------------------------------------------------------------------------
# test_recovery_commits_count_both_markers
# ---------------------------------------------------------------------------
@test "test_recovery_commits_count_both_markers" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 3 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  # Task 1 done in 1 commit (impl + checkoff bundled).
  echo "impl1" > f1.txt
  make_plan "$plan" 3 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  # Three extra recovery commits (2 R-B + 1 R-AB) inflate the commit count
  # without adding completed tasks. Recovery-aware audit:
  #   commits = 4 (1 normal + 3 recovery), completed = 1, recovery_commits = 3.
  #   (4 - 3) == 1 → PASS with WARNING.
  echo "extra1" > e1.txt
  git add e1.txt
  git commit -q -m "recovery(R-B): note 1"
  echo "extra2" > e2.txt
  git add e2.txt
  git commit -q -m "recovery(R-B): note 2"
  echo "extra3" > e3.txt
  git add e3.txt
  git commit -q -m "recovery(R-AB): note 3"

  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 0 ]
  [[ "$output" == *"count=3"* ]]
  [[ "$output" == *"R-B"* ]]
  [[ "$output" == *"R-AB"* ]]
}

# ---------------------------------------------------------------------------
# test_merge_commit_with_recovery_subject_ignored
# ---------------------------------------------------------------------------
@test "test_merge_commit_with_recovery_subject_ignored" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 2 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  # Build a side branch for merge.
  git checkout -q -b feature
  echo "side" > side.txt
  git add side.txt
  git commit -q -m "feat: side work"
  git checkout -q -

  # Task 1 done normally.
  echo "impl1" > f1.txt
  git add f1.txt
  git commit -q -m "feat: task 1"
  make_plan "$plan" 2 1
  git add plan.md
  git commit -q -m "chore: check off task 1"

  # Merge with a recovery-looking subject. --no-ff to force merge commit.
  git merge --no-ff feature -m "recovery(R-B): merge" -q

  # The merge is excluded by --no-merges. The "feat: side work" commit on the
  # merged branch IS counted in `git rev-list --count --no-merges`. So:
  #   non-merge commits since sha_start = 3 (feat: side, feat: task 1, chore: check off)
  #   completed = 1
  #   recovery_commits = 0 (merge subject is excluded by --no-merges; no recovery commits exist)
  #   (3 - 0) != 1 → VIOLATION.
  # Goal of test: prove the recovery-subject MERGE didn't sneak past --no-merges
  # to inflate recovery_commits. If we accidentally counted it, recovery_commits=1,
  # (3-1)=2 != 1 still VIOLATION but with a misleading "count=1" message.
  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION"* ]]
  [[ "$output" != *"WARNING"* ]]
  [[ "$output" != *"count=1"* ]]
}

# ---------------------------------------------------------------------------
# test_anomalies_log_existence_surfaced
# ---------------------------------------------------------------------------
@test "test_anomalies_log_existence_surfaced" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 2 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  # 1 commit (impl + checkoff bundled), 1 completed task → PASS.
  echo "impl1" > f1.txt
  make_plan "$plan" 2 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  mkdir -p "$TEST_CWD/.claude"
  cat > "$TEST_CWD/.claude/recovery-anomalies.log" <<'EOF'
WARNING: line 1
WARNING: line 2
WARNING: line 3
EOF

  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RECOVERY ANOMALIES LOG"* ]]
  [[ "$output" == *"lines=3"* ]]
}

# ---------------------------------------------------------------------------
# test_anomalies_log_absent_no_surface
# ---------------------------------------------------------------------------
@test "test_anomalies_log_absent_no_surface" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 2 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  # 1 commit (impl + checkoff bundled), 1 completed task → PASS.
  echo "impl1" > f1.txt
  make_plan "$plan" 2 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  # No anomalies log on disk.
  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 0 ]
  [[ "$output" != *"RECOVERY ANOMALIES LOG"* ]]
}

# ---------------------------------------------------------------------------
# test_no_recovery_markers_normal_pass
# ---------------------------------------------------------------------------
@test "test_no_recovery_markers_normal_pass" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 3 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  # Task 1 done: 1 normal commit (impl rolled together with checkoff).
  echo "impl1" > f1.txt
  make_plan "$plan" 3 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  # Task 2 done: 1 normal commit.
  echo "impl2" > f2.txt
  make_plan "$plan" 3 2
  git add f2.txt plan.md
  git commit -q -m "feat: task 2"

  # 2 commits == 2 completed tasks → PASS, no WARNING.
  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  [[ "$output" != *"WARNING"* ]]
}

# ---------------------------------------------------------------------------
# test_commit_count_and_recovery_count_use_consistent_filter
# ---------------------------------------------------------------------------
@test "test_commit_count_and_recovery_count_use_consistent_filter" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 3 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  # tmp branch with a recovery-subject commit, to be merged in later.
  git checkout -q -b tmp
  echo "tmp-side" > tmpfile.txt
  git add tmpfile.txt
  git commit -q -m "recovery(R-B): merge-branch"
  git checkout -q -

  # Normal commits on main.
  echo "n1" > n1.txt
  make_plan "$plan" 3 1
  git add n1.txt plan.md
  git commit -q -m "feat: normal 1"

  echo "n2" > n2.txt
  make_plan "$plan" 3 2
  git add n2.txt plan.md
  git commit -q -m "feat: normal 2"

  # Recovery commit on main.
  echo "r1" > r1.txt
  git add r1.txt
  git commit -q -m "recovery(R-B): main-recovery"

  # Merge tmp into main.
  git merge --no-ff tmp -m "Merge tmp" -q

  # Final state with --no-merges (sha_start..HEAD):
  #   - "recovery(R-B): merge-branch" (on tmp; included via merge)
  #   - "feat: normal 1"
  #   - "feat: normal 2"
  #   - "recovery(R-B): main-recovery"
  # Total non-merge commits: 4
  # recovery_commits (both markers, --no-merges): 2
  # completed tasks: 2
  # (4 - 2) == 2 → PASS with WARNING.

  rev_count=$(git rev-list --count --no-merges "${sha_start}..HEAD")
  [ "$rev_count" -eq 4 ]

  rec_count=$(git log --format='%s' --no-merges "${sha_start}..HEAD" | grep -cE '^recovery\((R-B|R-AB)\):' || true)
  [ "$rec_count" -eq 2 ]

  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: Recovery commit(s) detected (count=2"* ]]
}

# ---------------------------------------------------------------------------
# test_recovery_present_but_math_still_wrong_violation
#
# Recovery markers are present but the adjusted math still does not match.
# Audit must still emit VIOLATION + exit 1.
# ---------------------------------------------------------------------------
@test "test_recovery_present_but_math_still_wrong_violation" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 3 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  # 5 non-merge commits, 1 task completed, 1 recovery commit.
  # (5 - 1) = 4 != 1 → VIOLATION (recovery does not rescue this).
  echo "impl1" > f1.txt
  make_plan "$plan" 3 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  echo "x1" > x1.txt; git add x1.txt; git commit -q -m "extra 1"
  echo "x2" > x2.txt; git add x2.txt; git commit -q -m "extra 2"
  echo "x3" > x3.txt; git add x3.txt; git commit -q -m "extra 3"
  echo "x4" > x4.txt; git add x4.txt; git commit -q -m "recovery(R-B): orphan"

  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VIOLATION"* ]]
  [[ "$output" != *"PASS"* ]]
}

# ---------------------------------------------------------------------------
# test_stderr_lists_recovery_commit_subjects
#
# Plan line 476: emit recovery commit subjects to stderr when recovery_commits > 0.
# ---------------------------------------------------------------------------
@test "test_stderr_lists_recovery_commit_subjects" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 3 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  echo "impl1" > f1.txt
  make_plan "$plan" 3 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  echo "impl2" > f2.txt
  git add f2.txt
  git commit -q -m "feat: task 2"
  make_plan "$plan" 3 2
  git add plan.md
  git commit -q -m "recovery(R-B): finalize task 2"

  # Capture stderr separately. `bats` v1.5+ provides --separate-stderr,
  # but a portable shell-level redirect works too.
  stderr_file="$BATS_TMPDIR/audit-stderr-$$.txt"
  run bash -c "bash \"$SCRIPT\" \"$plan\" \"$sha_start\" 2> \"$stderr_file\""
  [ "$status" -eq 0 ]
  stderr_content="$(cat "$stderr_file")"

  [[ "$stderr_content" == *"Recovery commit subjects:"* ]]
  [[ "$stderr_content" == *"recovery(R-B): finalize task 2"* ]]
  rm -f "$stderr_file"
}

# ---------------------------------------------------------------------------
# test_anomalies_log_found_when_audit_invoked_from_subdirectory
#
# The anomalies log lives at <repo_root>/.claude/recovery-anomalies.log.
# Audit must locate it even when invoked from a subdirectory of the repo.
# ---------------------------------------------------------------------------
@test "test_anomalies_log_found_when_audit_invoked_from_subdirectory" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" 2 0
  cd "$TEST_CWD"
  git add plan.md
  git commit -q -m "add plan"
  sha_start=$(git rev-parse HEAD)

  echo "impl1" > f1.txt
  make_plan "$plan" 2 1
  git add f1.txt plan.md
  git commit -q -m "feat: task 1"

  mkdir -p "$TEST_CWD/.claude" "$TEST_CWD/subdir"
  cat > "$TEST_CWD/.claude/recovery-anomalies.log" <<'EOF'
WARNING: line 1
WARNING: line 2
EOF

  # Invoke audit from a SUBDIRECTORY of the repo. The anomalies log lives
  # at $TEST_CWD/.claude/..., not $TEST_CWD/subdir/.claude/...
  cd "$TEST_CWD/subdir"
  run bash "$SCRIPT" "$plan" "$sha_start"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RECOVERY ANOMALIES LOG"* ]]
  [[ "$output" == *"lines=2"* ]]
}
