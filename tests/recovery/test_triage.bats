#!/usr/bin/env bats
#
# test_triage.bats — Task 1.4 coverage for implement-next-triage.sh classifier.
#
# Per-test isolation: each test creates a fresh $TEST_CWD via mktemp -d under
# $BATS_TMPDIR and removes it in teardown. All paths passed to the triage
# script are absolute and rooted in $TEST_CWD.

SCRIPT="$HOME/.claude/scripts/implement-next-triage.sh"
WRITER="$HOME/.claude/scripts/implement-next-state-write.sh"

# Helper: build a synthetic plan file with one or more tasks.
# Usage: make_plan <plan_path> <task_name_1> [<task_name_2> ...]
# Writes a minimal plan with a "## Tasks" section so plan-progress.sh recognises it.
make_plan() {
  local plan="$1"
  shift
  {
    echo "# Test plan"
    echo ""
    echo "## Tasks"
    echo ""
    while [ $# -gt 0 ]; do
      echo "- [ ] $1"
      shift
    done
  } > "$plan"
}

# Helper: build a synthetic plan file with one task already checked off.
make_plan_checked() {
  local plan="$1"
  shift
  local checked="$1"
  shift
  {
    echo "# Test plan"
    echo ""
    echo "## Tasks"
    echo ""
    echo "- [x] $checked"
    while [ $# -gt 0 ]; do
      echo "- [ ] $1"
      shift
    done
  } > "$plan"
}

# Helper: write a synthetic v2 breadcrumb with all fields. Override via env.
# Used directly to craft specific dispatch fixtures without going through the writer.
write_breadcrumb_v2() {
  local cwd="$1"
  local sha_before="${2:-}"
  local plan_path="${3:-}"
  local task_name="${4:-}"
  local expected_agent_id="${5:-}"
  local branch_name="${6:-}"
  local skill_variant="${7:-cc}"
  local review_abort_count="${8:-0}"
  mkdir -p "$cwd/.claude"
  jq -n \
    --arg sha_before "$sha_before" \
    --arg plan_path "$plan_path" \
    --arg task_name "$task_name" \
    --arg expected_agent_id "$expected_agent_id" \
    --arg branch_name "$branch_name" \
    --arg skill_variant "$skill_variant" \
    --argjson review_abort_count "$review_abort_count" \
    '{
      schema_version: 2,
      sha_before: $sha_before,
      plan_path: $plan_path,
      task_name: $task_name,
      expected_agent_id: $expected_agent_id,
      started_at: "2026-06-12T00:00:00Z",
      branch_name: $branch_name,
      skill_variant: $skill_variant,
      review_abort_count: $review_abort_count
    }' > "$cwd/.claude/implement-next-state.json"
}

# Helper: commit the plan file so HEAD has it.
commit_plan() {
  local cwd="$1"
  local plan="$2"
  (
    cd "$cwd"
    git add "$plan"
    git commit -q -m "add plan"
  )
}

setup() {
  TEST_CWD="$(mktemp -d "$BATS_TMPDIR/recovery-triage-XXXXXX")"
  export TEST_CWD
  git init -q "$TEST_CWD"
  (
    cd "$TEST_CWD"
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit --allow-empty -q -m "init"
  )
}

teardown() {
  if [ -n "${TEST_CWD:-}" ] && [ -d "$TEST_CWD" ]; then
    rm -rf "$TEST_CWD"
  fi
}

# ---------------------------------------------------------------------------
# Row 1: no breadcrumb → R-Fresh
# ---------------------------------------------------------------------------
@test "test_no_breadcrumb_dispatches_r_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"RECOVERY: R-Fresh"* ]]
}

# ---------------------------------------------------------------------------
# Row 2: legacy breadcrumb (no schema_version, no v2 fields) → R-Fresh
# ---------------------------------------------------------------------------
@test "test_legacy_breadcrumb_dispatches_r_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  mkdir -p "$TEST_CWD/.claude"
  # Legacy v1 breadcrumb: no schema_version, no branch_name, no skill_variant, no review_abort_count.
  jq -n '{
    sha_before: "abc1234",
    plan_path: "old.md",
    task_name: "Legacy Task",
    expected_agent_id: "agent-x",
    started_at: "2025-12-01T00:00:00Z"
  }' > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"legacy"* || "$output" == *"Legacy"* ]]
}

# ---------------------------------------------------------------------------
# Row 3: v2 field present but no schema_version → R-Fresh (corrupt)
# ---------------------------------------------------------------------------
@test "test_corrupt_v2_field_without_version_dispatches_r_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  mkdir -p "$TEST_CWD/.claude"
  # Has skill_variant (a v2 field) but no schema_version → corrupt.
  jq -n '{
    sha_before: "abc1234",
    plan_path: "old.md",
    task_name: "Some Task",
    expected_agent_id: "agent-x",
    started_at: "2025-12-01T00:00:00Z",
    skill_variant: "cc"
  }' > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"inconsisten"* || "$output" == *"corrupt"* ]]
}

# ---------------------------------------------------------------------------
# Row 4: breadcrumb's task_name already committed-checked → clears, R-Fresh
# ---------------------------------------------------------------------------
@test "test_committed_checked_breadcrumb_clears_and_r_fresh" {
  plan="$TEST_CWD/plan.md"
  # Plan with one task already checked and one remaining.
  make_plan_checked "$plan" "Task A" "Task B"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Breadcrumb references Task A — already checked in HEAD's plan.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task A" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [ ! -f "$TEST_CWD/.claude/implement-next-state.json" ]
}

# ---------------------------------------------------------------------------
# Row 5a: task_name mismatch + clean + same SHA → R-Fresh + WARNING
# ---------------------------------------------------------------------------
@test "test_task_name_mismatch_clean_same_sha_r_fresh_with_warning" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1" "Task 2"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Breadcrumb references "Some Old Task" — not in plan; tree clean; HEAD == sha_before.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Some Old Task" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"WARNING"* ]]
  # Breadcrumb auto-cleared.
  [ ! -f "$TEST_CWD/.claude/implement-next-state.json" ]
  # Anomalies log present.
  [ -f "$TEST_CWD/.claude/recovery-anomalies.log" ]
  [ "$(wc -l < "$TEST_CWD/.claude/recovery-anomalies.log" | tr -d '[:space:]')" = "1" ]
}

# ---------------------------------------------------------------------------
# Row 5b: task_name mismatch + dirty OR moved → halt (exit 1)
# ---------------------------------------------------------------------------
@test "test_task_name_mismatch_dirty_or_moved_halt" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Make working tree dirty.
  echo "dirty" >> "$plan"

  # Breadcrumb references a task that doesn't match NEXT_TASK_NAME.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Stale Task" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Row 6: matched + HEAD == sha_before + clean → R-C
# ---------------------------------------------------------------------------
@test "test_matched_clean_same_sha_r_c" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Breadcrumb matches next task; HEAD == sha_before; tree clean.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-C"* ]]
  [[ "$output" == *"STEP_2_RESUME=true"* ]]
}

# ---------------------------------------------------------------------------
# Row 7: matched + HEAD == sha_before + dirty → R-A
# ---------------------------------------------------------------------------
@test "test_matched_dirty_same_sha_r_a" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Make tree dirty (uncommitted edit).
  echo "uncommitted impl" > "$TEST_CWD/impl.txt"

  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-A"* ]]
  [[ "$output" == *"REVIEW_RANGE=HEAD+worktree"* ]]
  [[ "$output" == *"STEP_2_RESUME=false"* ]]
}

# ---------------------------------------------------------------------------
# Row 8: matched + HEAD != sha_before + clean → R-B
# ---------------------------------------------------------------------------
@test "test_matched_clean_moved_r_b" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  sha_before=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Advance HEAD to simulate "impl committed but plan not checked".
  (
    cd "$TEST_CWD"
    echo "impl" > impl.txt
    git add impl.txt
    git commit -q -m "impl"
  )
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)
  [ "$sha_before" != "$head_sha" ]

  write_breadcrumb_v2 "$TEST_CWD" "$sha_before" "$plan" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-B"* ]]
  [[ "$output" == *"REVIEW_RANGE=${sha_before}..HEAD"* ]]
  [[ "$output" == *"STEP_2_RESUME=false"* ]]
  [[ "$output" == *"START_SHA=${sha_before}"* ]]
}

# ---------------------------------------------------------------------------
# Row 9: matched + HEAD != sha_before + dirty → R-AB
# ---------------------------------------------------------------------------
@test "test_matched_dirty_moved_r_ab" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  sha_before=$(git -C "$TEST_CWD" rev-parse HEAD)

  (
    cd "$TEST_CWD"
    echo "impl" > impl.txt
    git add impl.txt
    git commit -q -m "impl"
  )
  # Dirty tree on top of new commit.
  echo "extra" >> "$TEST_CWD/impl.txt"

  write_breadcrumb_v2 "$TEST_CWD" "$sha_before" "$plan" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-AB"* ]]
  [[ "$output" == *"REVIEW_RANGE=${sha_before}..HEAD+worktree"* ]]
}

# ---------------------------------------------------------------------------
# Row 11: malformed JSON → R-Fresh
# ---------------------------------------------------------------------------
@test "test_malformed_json_r_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  mkdir -p "$TEST_CWD/.claude"
  echo "not valid json {{{" > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"Malformed JSON"* ]]
}

# ---------------------------------------------------------------------------
# Row 12: branch_name non-empty + differs from current branch → warn + continue
# ---------------------------------------------------------------------------
@test "test_branch_mismatch_warns_continues" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  current_branch=$(git -C "$TEST_CWD" symbolic-ref --short HEAD)

  # Breadcrumb says "main" but current is whatever git init defaulted to;
  # craft a deliberately different branch name.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "feature/other" "cc" 0

  # Sanity: pre-condition is "branch differs".
  [ "feature/other" != "$current_branch" ]

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  # Triage continues to dispatch (R-C here since clean + same sha) and emits a warning.
  [[ "$output" == *"CASE=R-C"* ]]
  [[ "$output" == *"branch"* ]]
}

# ---------------------------------------------------------------------------
# Row 13: skill_variant differs from current → warn + continue
# ---------------------------------------------------------------------------
@test "test_variant_mismatch_warns_continues" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Breadcrumb says skill_variant=cc; invocation passes "portable".
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "portable"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-C"* ]]
  [[ "$output" == *"variant"* ]]
}

# ---------------------------------------------------------------------------
# Row 14: plan_path mismatch → R-Fresh (stale-plan)
# ---------------------------------------------------------------------------
@test "test_plan_path_mismatch_r_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Breadcrumb references different plan path.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "/other/plan.md" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"stale"* || "$output" == *"plan"* ]]
}

# ---------------------------------------------------------------------------
# Row 15: review_abort_count >= 2 → R-Stuck (exit 1)
# ---------------------------------------------------------------------------
@test "test_review_abort_count_two_r_stuck" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 2

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CASE=R-Stuck"* ]]
}

# ---------------------------------------------------------------------------
# Additional: plan file deleted between runs → exit 1
# ---------------------------------------------------------------------------
@test "test_plan_file_deleted_exit_1" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Reference a plan path that doesn't exist anywhere.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$TEST_CWD/missing.md" "Task 1" "agent-x" "" "cc" 0

  # And invoke with the missing plan path.
  run bash "$SCRIPT" "$TEST_CWD" "$TEST_CWD/missing.md" "cc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan"* || "$stderr" == *"plan"* ]]
}

# ---------------------------------------------------------------------------
# Additional: RECOVERY: line format regex check (R-A path)
# ---------------------------------------------------------------------------
@test "test_recovery_line_format_regex" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  echo "uncommitted" > "$TEST_CWD/impl.txt"
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  # Format: RECOVERY: R-A detected. sha_before=<hex>, head=<hex>, dirty=true. <action>.
  echo "$output" | grep -qE '^RECOVERY: R-A detected\. sha_before=[a-f0-9]+, head=[a-f0-9]+, dirty=true\. .*\.$'
}

# ---------------------------------------------------------------------------
# Additional: anomalies log appended on auto-clear
# ---------------------------------------------------------------------------
@test "test_anomalies_log_appended_on_auto_clear" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Stale" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  log="$TEST_CWD/.claude/recovery-anomalies.log"
  [ -f "$log" ]
  [ "$(wc -l < "$log" | tr -d '[:space:]')" = "1" ]
  grep -q "WARNING" "$log"
}

# ---------------------------------------------------------------------------
# Additional: anomalies log truncated when exceeds 10000 lines
# ---------------------------------------------------------------------------
@test "test_anomalies_log_capped_at_10000_lines" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Pre-populate with 10001 lines.
  mkdir -p "$TEST_CWD/.claude"
  log="$TEST_CWD/.claude/recovery-anomalies.log"
  for i in $(seq 1 10001); do
    echo "PADDING $i" >> "$log"
  done

  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Stale" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  # Expected: tail -n 5000 + 1 new = 5001.
  line_count=$(wc -l < "$log" | tr -d '[:space:]')
  [ "$line_count" = "5001" ]
}

# ---------------------------------------------------------------------------
# Additional: anomalies log first creation emits gitignore notice
# ---------------------------------------------------------------------------
@test "test_anomalies_log_first_creation_emits_gitignore_notice" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # First auto-clear: no pre-existing log.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Stale1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  # Stderr should contain the gitignore notice. `run` combines stdout+stderr by default;
  # use stderr explicit fields when available. Bats 1.5+ supports --separate-stderr.
  # Here we accept that the notice appears either in output or stderr.
  [[ "$output" == *"NOTE: Created .claude/recovery-anomalies.log"* ]] || \
    [[ "$stderr" == *"NOTE: Created .claude/recovery-anomalies.log"* ]]
  log="$TEST_CWD/.claude/recovery-anomalies.log"
  [ "$(wc -l < "$log" | tr -d '[:space:]')" = "1" ]

  # Second trigger in same TEST_CWD: no notice; log grows to 2 lines.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Stale2" "agent-x" "" "cc" 0
  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  # Notice should NOT appear in second run.
  if [[ "$output" == *"NOTE: Created .claude/recovery-anomalies.log"* ]]; then
    echo "Notice should NOT fire on second creation"
    return 1
  fi
  [ "$(wc -l < "$log" | tr -d '[:space:]')" = "2" ]
}

# ---------------------------------------------------------------------------
# Additional: legacy breadcrumb without review_abort_count → R-Fresh (not R-Stuck)
# ---------------------------------------------------------------------------
@test "test_legacy_breadcrumb_no_review_abort_count_no_r_stuck" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  mkdir -p "$TEST_CWD/.claude"
  # v1 breadcrumb: no review_abort_count, no schema_version.
  jq -n '{
    sha_before: "abc",
    plan_path: "old.md",
    task_name: "Old",
    expected_agent_id: "a",
    started_at: "2025-01-01T00:00:00Z"
  }' > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" != *"CASE=R-Stuck"* ]]
}

# ---------------------------------------------------------------------------
# Additional: R-Stuck diagnostic includes absolute breadcrumb path
# ---------------------------------------------------------------------------
@test "test_r_stuck_diagnostic_includes_absolute_breadcrumb_path" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 2

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 1 ]
  # Absolute path to breadcrumb in the diagnostic. Combined stderr+stdout from bats run.
  expected_path="$TEST_CWD/.claude/implement-next-state.json"
  [[ "$output" == *"$expected_path"* ]]
}

# Variant: relative cwd → emitted path is still absolute
@test "test_r_stuck_diagnostic_absolute_path_even_with_relative_cwd" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 2

  parent=$(dirname "$TEST_CWD")
  base=$(basename "$TEST_CWD")
  run bash -c "cd '$parent' && bash '$SCRIPT' './$base' '$plan' 'cc'"
  [ "$status" -eq 1 ]
  expected_path="$TEST_CWD/.claude/implement-next-state.json"
  [[ "$output" == *"$expected_path"* ]]
}

# ---------------------------------------------------------------------------
# Additional: detached HEAD skips branch check entirely
# ---------------------------------------------------------------------------
@test "test_detached_head_skips_branch_check" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Detach HEAD.
  (
    cd "$TEST_CWD"
    git checkout -q --detach "$head_sha"
  )

  # Breadcrumb with empty branch_name (writer would have captured empty in detached state).
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  # No branch warning emitted.
  if [[ "$output" == *"branch"* && "$output" == *"warn"* ]]; then
    echo "Should not warn about branch when both are empty/detached"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Additional: task name with special characters (grep -F protection)
# ---------------------------------------------------------------------------
@test "test_task_name_with_special_chars" {
  plan="$TEST_CWD/plan.md"
  task="Task [foo] *bar* (baz)"
  make_plan "$plan" "$task"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Breadcrumb has same task name — must match (no false negative).
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "$task" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  # Should match → R-C (clean + same sha).
  [[ "$output" == *"CASE=R-C"* ]]
}

# ---------------------------------------------------------------------------
# Additional: plan_path absolute vs relative literal mismatch → R-Fresh
# ---------------------------------------------------------------------------
@test "test_plan_path_absolute_vs_relative_mismatch" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Breadcrumb stores absolute path; invocation uses relative path with same target.
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 0

  # Run with relative plan path (must still exist for the relative check)
  parent=$(dirname "$TEST_CWD")
  base=$(basename "$TEST_CWD")
  run bash -c "cd '$parent' && bash '$SCRIPT' './$base' './$base/plan.md' 'cc'"
  [ "$status" -eq 0 ]
  # Literal string comparison → mismatch → R-Fresh.
  [[ "$output" == *"CASE=R-Fresh"* ]]
}

# ---------------------------------------------------------------------------
# Additional: schema_version as string "2" → corrupt → R-Fresh
# ---------------------------------------------------------------------------
@test "test_schema_version_as_string_two_handled" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  mkdir -p "$TEST_CWD/.claude"
  jq -n '{
    schema_version: "2",
    sha_before: "abc",
    plan_path: "p.md",
    task_name: "T",
    expected_agent_id: "a",
    started_at: "2026-01-01T00:00:00Z",
    branch_name: "",
    skill_variant: "cc",
    review_abort_count: 0
  }' > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
}

# ---------------------------------------------------------------------------
# Additional: R-Fresh emits TASK_NAME derived from plan
# ---------------------------------------------------------------------------
@test "test_r_fresh_emits_task_name_from_plan" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "First Task"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"TASK_NAME=First Task"* ]]
}

# ---------------------------------------------------------------------------
# Additional: usage errors (missing args, invalid variant) → exit 2
# ---------------------------------------------------------------------------
@test "test_usage_error_missing_args" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "test_usage_error_invalid_variant" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  run bash "$SCRIPT" "$TEST_CWD" "$plan" "bogus"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Additional: non-git cwd → exit 1
# ---------------------------------------------------------------------------
@test "test_non_git_cwd_exit_1" {
  not_git="$(mktemp -d "$BATS_TMPDIR/recovery-not-git-XXXXXX")"
  trap "rm -rf '$not_git'" EXIT
  plan="$not_git/plan.md"
  make_plan "$plan" "Task 1"
  run bash "$SCRIPT" "$not_git" "$plan" "cc"
  [ "$status" -eq 1 ]
  rm -rf "$not_git"
}

# ---------------------------------------------------------------------------
# Additional: START_SHA and START_CHECKED emitted on every exit-0 path
# ---------------------------------------------------------------------------
@test "test_emits_start_sha_and_start_checked_on_r_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan_checked "$plan" "Done" "Pending"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"START_SHA="* ]]
  # One [x] in the plan → START_CHECKED=1.
  [[ "$output" == *"START_CHECKED=1"* ]]
}

# ---------------------------------------------------------------------------
# Additional: plan with all tasks checked off (NEXT_TASK_NAME may be empty)
# ---------------------------------------------------------------------------
@test "test_all_tasks_complete_r_fresh_empty_task_name" {
  plan="$TEST_CWD/plan.md"
  {
    echo "# Test plan"
    echo ""
    echo "## Tasks"
    echo ""
    echo "- [x] Done 1"
    echo "- [x] Done 2"
  } > "$plan"

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  # No breadcrumb + plan exists + all tasks complete → R-Fresh; TASK_NAME may be empty.
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  # START_CHECKED=2 (both done).
  [[ "$output" == *"START_CHECKED=2"* ]]
}

# ---------------------------------------------------------------------------
# Additional: R-Stuck does NOT delete the breadcrumb (user must clear manually)
# ---------------------------------------------------------------------------
@test "test_r_stuck_preserves_breadcrumb" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 2

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CASE=R-Stuck"* ]]
  # Breadcrumb MUST remain so a manual recovery can read it.
  [ -f "$TEST_CWD/.claude/implement-next-state.json" ]
}

# ---------------------------------------------------------------------------
# Additional: task_name mismatch + dirty does NOT delete the breadcrumb
# ---------------------------------------------------------------------------
@test "test_row_5b_halt_preserves_breadcrumb" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  echo "dirty" >> "$plan"
  write_breadcrumb_v2 "$TEST_CWD" "$head_sha" "$plan" "Stale Task" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 1 ]
  # Breadcrumb MUST remain (the manual investigator may need it).
  [ -f "$TEST_CWD/.claude/implement-next-state.json" ]
}

# ---------------------------------------------------------------------------
# Additional: paths containing spaces or special chars in $cwd handled safely
# ---------------------------------------------------------------------------
@test "test_cwd_with_spaces_handled" {
  # mktemp -d under a space-containing parent directory.
  parent="$(mktemp -d "$BATS_TMPDIR/Space Test-XXXXXX")"
  cwd="$parent/with space"
  mkdir -p "$cwd"
  git init -q "$cwd"
  (
    cd "$cwd"
    git config user.email t@t
    git config user.name t
    git commit --allow-empty -q -m init
  )
  plan="$cwd/plan.md"
  make_plan "$plan" "Task 1"
  (
    cd "$cwd"
    git add plan.md
    git commit -q -m "p"
  )
  head_sha=$(git -C "$cwd" rev-parse HEAD)
  # Use the matched-clean-same-sha → R-C path so is_dirty is exercised.
  write_breadcrumb_v2 "$cwd" "$head_sha" "$plan" "Task 1" "agent-x" "" "cc" 0

  run bash "$SCRIPT" "$cwd" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-C"* ]]

  rm -rf "$parent"
}
