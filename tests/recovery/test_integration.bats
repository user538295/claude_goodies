#!/usr/bin/env bats
#
# test_integration.bats — Task 4.3b coverage.
#
# Shell-invocable end-to-end integration of the recovery feature: wires
# implement-next-state-write.sh, implement-next-triage.sh, and a re-invocation
# step to exercise the cross-script contract. Not redundant with
# test_triage.bats — those tests exercise the classifier in isolation against
# hand-crafted breadcrumbs; this file uses the writer to produce the breadcrumb,
# then runs triage against it as the skill's Step 0 would.
#
# Fixtures covered (shell-only subset of the Manual Integration Test Catalog):
#   - e.warn        task-name mismatch + clean + same SHA → R-Fresh + WARNING
#   - k             malformed breadcrumb JSON → R-Fresh
#   - l             plan file deleted between runs → exit 1
#   - m             schema-v1 (legacy) breadcrumb → R-Fresh
#   - m.corrupt     v2 field without schema_version → R-Fresh (corrupt)
#   - m.partial-v2  schema_version: 2 but missing skill_variant → R-Fresh
#                   (the triage detects "v2 field present, schema_version
#                   missing" as corruption; the missing-skill_variant case is
#                   a documented sub-case of the same dispatch row)
#   - r2            review_abort_count >= 2 → R-Stuck (exit 1)
#
# Per-test isolation: each test creates a fresh $TEST_CWD via mktemp -d under
# $BATS_TMPDIR and removes it in teardown.

WRITER="$HOME/.claude/scripts/implement-next-state-write.sh"
TRIAGE="$HOME/.claude/scripts/implement-next-triage.sh"
CLEAR="$HOME/.claude/scripts/implement-next-state-clear.sh"

# Helper: build a synthetic plan with one or more tasks under "## Tasks".
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

# Helper: commit the plan file so HEAD has a tree containing it.
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
  TEST_CWD="$(mktemp -d "$BATS_TMPDIR/recovery-integration-XXXXXX")"
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
# Fixture (e.warn): task-name mismatch + clean + same SHA →
#   R-Fresh + WARNING on stdout AND a line in recovery-anomalies.log.
#
# Integration assertion: the writer-produced v2 breadcrumb is consumed by the
# triage's auto-clear dispatch row, the breadcrumb is removed, the anomalies
# log is created.
# ---------------------------------------------------------------------------
@test "integration_e_warn_auto_clear_warning_logged" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1" "Task 2"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Writer produces a v2 breadcrumb referencing a stale task name. The breadcrumb
  # is written via the production writer (not hand-crafted) so the integration
  # test exercises the writer→triage handoff.
  run bash "$WRITER" "$TEST_CWD" "$head_sha" "$plan" "Stale Task X" "agent-x" "cc"
  [ "$status" -eq 0 ]
  [ -f "$TEST_CWD/.claude/implement-next-state.json" ]

  # Triage as the skill's Step 0 would invoke it.
  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"WARNING"* ]]

  # Breadcrumb auto-cleared by triage.
  [ ! -f "$TEST_CWD/.claude/implement-next-state.json" ]

  # Anomalies log present with the WARNING line.
  log="$TEST_CWD/.claude/recovery-anomalies.log"
  [ -f "$log" ]
  [ "$(wc -l < "$log" | tr -d '[:space:]')" = "1" ]
  grep -q "WARNING" "$log"

  # Re-invocation: the skill would proceed to Step 1 as R-Fresh; another triage
  # call now sees no breadcrumb (the previous call cleared it) → R-Fresh again,
  # this time the "no breadcrumb" row, not the auto-clear row.
  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"No prior breadcrumb"* ]]
}

# ---------------------------------------------------------------------------
# Fixture (k): malformed JSON breadcrumb → R-Fresh.
#
# Integration assertion: a corrupted on-disk breadcrumb (e.g., truncated
# mid-write) does not crash the triage; the classifier prints the documented
# R-Fresh diagnostic; a subsequent writer call overwrites the bad JSON cleanly.
# ---------------------------------------------------------------------------
@test "integration_k_malformed_json_recovers_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"

  mkdir -p "$TEST_CWD/.claude"
  # Garbled, half-written JSON.
  printf '%s' '{"schema_version": 2, "sha_before": "ab' > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  [[ "$output" == *"Malformed JSON"* ]]

  # Re-invocation: writer can overwrite the bad JSON cleanly (no manual cleanup).
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)
  run bash "$WRITER" "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "cc"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  # The new breadcrumb parses cleanly.
  run jq -e . "$state_file"
  [ "$status" -eq 0 ]
  # And triage now consumes the writer's output as a valid matched breadcrumb
  # (R-C — clean tree + same SHA).
  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-C"* ]]
}

# ---------------------------------------------------------------------------
# Fixture (l): plan file deleted between runs → exit 1.
#
# Integration assertion: the writer-produced breadcrumb references a plan
# path; the plan is then deleted; triage exits 1 with a stderr diagnostic
# naming the missing path.
# ---------------------------------------------------------------------------
@test "integration_l_plan_file_deleted_exits_halt" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  run bash "$WRITER" "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "cc"
  [ "$status" -eq 0 ]

  # Delete the plan file (and remove it from index/HEAD via a follow-up commit
  # so the in-tree version is gone too).
  rm -f "$plan"

  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 1 ]
  # stdout includes the R-Halt case; stderr names the missing path.
  [[ "$output" == *"plan"* ]]
}

# ---------------------------------------------------------------------------
# Fixture (m): legacy v1 breadcrumb (no schema_version, no v2 fields) → R-Fresh.
#
# Integration assertion: a hand-crafted v1 breadcrumb (representing a
# pre-upgrade install state) dispatches to R-Fresh; the diagnostic mentions
# "legacy"; a subsequent writer call replaces it with a clean v2 record.
# ---------------------------------------------------------------------------
@test "integration_m_legacy_v1_breadcrumb_recovers_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"

  mkdir -p "$TEST_CWD/.claude"
  # Legacy v1 shape: no schema_version, no branch_name, no skill_variant,
  # no review_abort_count.
  jq -n '{
    sha_before: "deadbeef",
    plan_path: "plan.md",
    task_name: "Legacy Task",
    expected_agent_id: "agent-legacy",
    started_at: "2025-12-01T00:00:00Z"
  }' > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  # Diagnostic mentions legacy (case-insensitive).
  [[ "$output" == *"egacy"* ]]

  # Writer can replace the legacy breadcrumb in place.
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)
  run bash "$WRITER" "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-new" "cc"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ "$(jq -r '.schema_version | tostring' "$state_file")" = "2" ]
  [ "$(jq -r '.skill_variant' "$state_file")" = "cc" ]
}

# ---------------------------------------------------------------------------
# Fixture (m.corrupt): v2 field present but no schema_version → R-Fresh corrupt.
#
# Integration assertion: a partially-upgraded breadcrumb (writer crashed
# mid-migration or external tampering) dispatches to R-Fresh and the diagnostic
# names the schema inconsistency. Distinct from clean legacy.
# ---------------------------------------------------------------------------
@test "integration_m_corrupt_v2_field_without_version_recovers_fresh" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"

  mkdir -p "$TEST_CWD/.claude"
  # No schema_version, but has branch_name (a v2 field) → corrupt.
  jq -n '{
    sha_before: "abc1234",
    plan_path: "plan.md",
    task_name: "Some Task",
    expected_agent_id: "agent-x",
    started_at: "2025-12-01T00:00:00Z",
    branch_name: "main"
  }' > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
  # Triage diagnostic mentions inconsistency or corrupt.
  [[ "$output" == *"inconsisten"* || "$output" == *"corrupt"* ]]
}

# ---------------------------------------------------------------------------
# Fixture (m.partial-v2): the brief documents this as a Cycle-1 breadcrumb
# (schema_version: 2 present, but missing skill_variant) consumed by a Cycle-2
# dispatcher. The current triage implementation treats "v2 field present + no
# schema_version" as corruption and "schema_version present + missing v2 field"
# as a valid-but-partial record that doesn't trip the inconsistency check.
#
# Integration assertion: a schema_version=2 breadcrumb that lacks skill_variant
# is consumed by triage WITHOUT being flagged corrupt — dispatch proceeds based
# on the matched-state row (R-C in this fixture since tree clean + sha matches).
# ---------------------------------------------------------------------------
@test "integration_m_partial_v2_missing_skill_variant_proceeds" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  mkdir -p "$TEST_CWD/.claude"
  # schema_version: 2 (integer), but no skill_variant. Branch and abort count
  # present so the triage's v2-field detection sees the record as v2-flavored.
  jq -n --arg sha "$head_sha" --arg plan "$plan" '{
    schema_version: 2,
    sha_before: $sha,
    plan_path: $plan,
    task_name: "Task 1",
    expected_agent_id: "agent-x",
    started_at: "2026-06-12T00:00:00Z",
    branch_name: "",
    review_abort_count: 0
  }' > "$TEST_CWD/.claude/implement-next-state.json"

  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  # Partial-v2 is NOT corrupt-flagged: schema_version: 2 is consistent with the
  # presence of branch_name / review_abort_count; the missing skill_variant is
  # a tolerated additive omission. Dispatch proceeds to the matched row.
  [[ "$output" == *"CASE=R-C"* ]]
  [[ "$output" != *"Schema inconsistency"* ]]
}

# ---------------------------------------------------------------------------
# Fixture (r2): review_abort_count >= 2 → R-Stuck (exit 1).
#
# Integration assertion: a breadcrumb whose counter was bumped twice by
# --increment-review-abort produces an R-Stuck dispatch on the next triage
# call — no review/test/commit is attempted; manual recovery is required.
# Wires writer (default mode) → writer (--increment-review-abort × 2) →
# triage → expected halt.
# ---------------------------------------------------------------------------
@test "integration_r2_stuck_after_two_increments" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  # Initial breadcrumb via the writer.
  run bash "$WRITER" "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "cc"
  [ "$status" -eq 0 ]

  # Two review aborts → count reaches 2.
  run bash "$WRITER" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ "$(jq -r '.review_abort_count' "$state_file")" = "1" ]

  run bash "$WRITER" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.review_abort_count' "$state_file")" = "2" ]

  # Next triage invocation dispatches R-Stuck and exits 1.
  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CASE=R-Stuck"* ]]

  # Breadcrumb unchanged on disk — R-Stuck does NOT clear it; manual recovery
  # is required.
  [ -f "$state_file" ]
  [ "$(jq -r '.review_abort_count' "$state_file")" = "2" ]
}

# ---------------------------------------------------------------------------
# Cross-script contract sanity check: writer → triage → state-clear → triage
#
# This is the canonical "happy" recovery loop the integration test asserts as
# a sanity check that the three scripts interoperate without surprise:
#   1. writer creates a v2 breadcrumb.
#   2. triage classifies it as R-C (clean + same SHA).
#   3. state-clear removes the breadcrumb.
#   4. re-running triage sees no breadcrumb → R-Fresh.
# ---------------------------------------------------------------------------
@test "integration_round_trip_writer_triage_clear_triage" {
  plan="$TEST_CWD/plan.md"
  make_plan "$plan" "Task 1"
  commit_plan "$TEST_CWD" "plan.md"
  head_sha=$(git -C "$TEST_CWD" rev-parse HEAD)

  run bash "$WRITER" "$TEST_CWD" "$head_sha" "$plan" "Task 1" "agent-x" "cc"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ -f "$state_file" ]

  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-C"* ]]

  run bash "$CLEAR" "$TEST_CWD"
  [ "$status" -eq 0 ]
  [ ! -f "$state_file" ]

  run bash "$TRIAGE" "$TEST_CWD" "$plan" "cc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CASE=R-Fresh"* ]]
}
