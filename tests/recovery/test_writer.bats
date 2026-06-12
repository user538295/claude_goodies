#!/usr/bin/env bats
#
# test_writer.bats — Task 1.1 coverage for implement-next-state-write.sh
# default mode: atomic write + v2 schema + 6th positional arg.
#
# Per-test isolation: each test creates a fresh $TEST_CWD via mktemp -d under
# $BATS_TMPDIR and removes it in teardown.

SCRIPT="$HOME/.claude/scripts/implement-next-state-write.sh"

setup() {
  TEST_CWD="$(mktemp -d "$BATS_TMPDIR/recovery-writer-XXXXXX")"
  export TEST_CWD
  # Initialize a git repo so branch_name capture has something to talk to.
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
# test_default_mode_writes_v2_schema
# ---------------------------------------------------------------------------
@test "test_default_mode_writes_v2_schema" {
  run bash "$SCRIPT" "$TEST_CWD" "abc1234" "plan.md" "Task 1" "agent-xyz" "portable"
  [ "$status" -eq 0 ]

  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ -f "$state_file" ]

  # schema_version must be the INTEGER 2 (not the string "2").
  run jq -r '.schema_version | tostring + " " + (. | type)' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "2 number" ]

  # All existing fields preserved.
  [ "$(jq -r '.sha_before' "$state_file")" = "abc1234" ]
  [ "$(jq -r '.plan_path' "$state_file")" = "plan.md" ]
  [ "$(jq -r '.task_name' "$state_file")" = "Task 1" ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "agent-xyz" ]
  [ -n "$(jq -r '.started_at' "$state_file")" ]

  # New v2 fields.
  [ -n "$(jq -r '.branch_name' "$state_file")" ]   # default branch from `git init`
  [ "$(jq -r '.skill_variant' "$state_file")" = "portable" ]

  # review_abort_count must be integer 0.
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "0 number" ]
}

# ---------------------------------------------------------------------------
# test_default_mode_accepts_six_or_five_args
# ---------------------------------------------------------------------------
@test "test_default_mode_accepts_six_or_five_args" {
  # 5-arg invocation succeeds; skill_variant defaults to "cc".
  run bash "$SCRIPT" "$TEST_CWD" "sha1" "plan.md" "T1" "agent-5"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ -f "$state_file" ]
  [ "$(jq -r '.skill_variant' "$state_file")" = "cc" ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "agent-5" ]

  # 6-arg invocation succeeds with the supplied variant.
  rm -f "$state_file"
  run bash "$SCRIPT" "$TEST_CWD" "sha2" "plan.md" "T1" "agent-6" "portable"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.skill_variant' "$state_file")" = "portable" ]

  # 4 args or fewer → exit 2 with usage diagnostic.
  rm -f "$state_file"
  run bash "$SCRIPT" "$TEST_CWD" "sha3" "plan.md" "T1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

# ---------------------------------------------------------------------------
# test_default_mode_rejects_invalid_skill_variant
# ---------------------------------------------------------------------------
@test "test_default_mode_rejects_invalid_skill_variant" {
  run bash "$SCRIPT" "$TEST_CWD" "sha1" "plan.md" "T1" "agent-x" "bogus"
  [ "$status" -eq 2 ]
  [[ "$output" == *"skill_variant"* ]]
}

# ---------------------------------------------------------------------------
# test_default_mode_empty_expected_agent_id_rejected
# ---------------------------------------------------------------------------
@test "test_default_mode_empty_expected_agent_id_rejected" {
  # Empty arg 5 in default mode → exit 2 (guard preserved from prior behavior).
  run bash "$SCRIPT" "$TEST_CWD" "sha1" "plan.md" "T1" "" "cc"
  [ "$status" -eq 2 ]
  [[ "$output" == *"expected_agent_id"* ]]
}

# ---------------------------------------------------------------------------
# test_branch_name_captured_on_feature_branch
# ---------------------------------------------------------------------------
@test "test_branch_name_captured_on_feature_branch" {
  (
    cd "$TEST_CWD"
    git checkout -q -b feature/foo
  )
  run bash "$SCRIPT" "$TEST_CWD" "sha1" "plan.md" "T1" "agent-x" "cc"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ "$(jq -r '.branch_name' "$state_file")" = "feature/foo" ]
}

# ---------------------------------------------------------------------------
# test_branch_name_empty_on_detached_head
# ---------------------------------------------------------------------------
@test "test_branch_name_empty_on_detached_head" {
  (
    cd "$TEST_CWD"
    # Detach HEAD onto the current commit's SHA.
    sha=$(git rev-parse HEAD)
    git checkout -q --detach "$sha"
  )
  run bash "$SCRIPT" "$TEST_CWD" "sha1" "plan.md" "T1" "agent-x" "cc"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ "$(jq -r '.branch_name' "$state_file")" = "" ]
}

# ---------------------------------------------------------------------------
# test_atomic_write_no_partial_file_visible
# ---------------------------------------------------------------------------
@test "test_atomic_write_no_partial_file_visible" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-populate the state_file with a known-good marker so we can verify the
  # half-finished write never replaces it.
  printf '{"marker":"prior"}' > "$state_file"

  # Invoke writer with a test-only delay between .tmp creation and the mv.
  # Background it, then kill -9 mid-flight before the mv lands.
  _RECOVERY_TEST_DELAY_BEFORE_MV=2 bash "$SCRIPT" \
    "$TEST_CWD" "sha1" "plan.md" "T1" "agent-x" "cc" &
  writer_pid=$!

  # Give the writer enough time to render the .tmp but NOT enough to mv it.
  sleep 0.5
  kill -9 "$writer_pid" 2>/dev/null || true
  wait "$writer_pid" 2>/dev/null || true

  # The final state_file must still contain the prior marker — never
  # half-written. The .tmp may or may not exist; that's fine.
  [ -f "$state_file" ]
  run jq -r '.marker' "$state_file"
  [ "$status" -eq 0 ]
  [ "$output" = "prior" ]
}

# ---------------------------------------------------------------------------
# test_atomic_write_overwrites_cleanly
# ---------------------------------------------------------------------------
@test "test_atomic_write_overwrites_cleanly" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"

  run bash "$SCRIPT" "$TEST_CWD" "sha1" "plan.md" "T1" "agent-1" "cc"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "agent-1" ]

  run bash "$SCRIPT" "$TEST_CWD" "sha2" "plan.md" "T2" "agent-2" "portable"
  [ "$status" -eq 0 ]

  # Second call fully replaced first.
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "agent-2" ]
  [ "$(jq -r '.task_name' "$state_file")" = "T2" ]
  [ "$(jq -r '.skill_variant' "$state_file")" = "portable" ]

  # No .tmp orphan should remain after a clean run.
  [ ! -f "$state_file.tmp" ]
}

# ===========================================================================
# Task 1.2 — --upsert mode tests
# ===========================================================================

# ---------------------------------------------------------------------------
# test_upsert_allows_empty_expected_agent_id
# ---------------------------------------------------------------------------
@test "test_upsert_allows_empty_expected_agent_id" {
  # --upsert + empty arg 5 → exit 0, JSON written.
  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1" "" "cc"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ -f "$state_file" ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "" ]
}

# ---------------------------------------------------------------------------
# test_upsert_creates_new_breadcrumb_when_absent
# ---------------------------------------------------------------------------
@test "test_upsert_creates_new_breadcrumb_when_absent" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ ! -f "$state_file" ]

  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1" "" "portable"
  [ "$status" -eq 0 ]
  [ -f "$state_file" ]

  # Fresh v2 breadcrumb.
  run jq -r '.schema_version | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "2 number" ]
  [ "$(jq -r '.sha_before' "$state_file")" = "sha1" ]
  [ "$(jq -r '.plan_path' "$state_file")" = "plan.md" ]
  [ "$(jq -r '.task_name' "$state_file")" = "T1" ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "" ]
  [ "$(jq -r '.skill_variant' "$state_file")" = "portable" ]
  [ -n "$(jq -r '.started_at' "$state_file")" ]
  [ -n "$(jq -r '.branch_name' "$state_file")" ]
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "0 number" ]
}

# ---------------------------------------------------------------------------
# test_upsert_preserves_existing_agent_id
# ---------------------------------------------------------------------------
@test "test_upsert_preserves_existing_agent_id" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"

  # Pre-write breadcrumb with a real expected_agent_id.
  run bash "$SCRIPT" "$TEST_CWD" "sha1" "plan.md" "T1" "REAL_ID" "cc"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "REAL_ID" ]

  # --upsert with empty arg 5 must preserve REAL_ID.
  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1" "" "cc"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "REAL_ID" ]
}

# ---------------------------------------------------------------------------
# test_upsert_preserves_existing_non_empty_fields
# ---------------------------------------------------------------------------
@test "test_upsert_preserves_existing_non_empty_fields" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"

  # Pre-write breadcrumb with task_name="X", branch derived from repo (main or
  # master from `git init`). We assert task_name preservation, and we set up a
  # known branch_name explicitly to test that preservation as well.
  (
    cd "$TEST_CWD"
    git checkout -q -b main 2>/dev/null || git checkout -q main 2>/dev/null || true
  )
  run bash "$SCRIPT" "$TEST_CWD" "sha1" "plan.md" "X" "agent-1" "cc"
  [ "$status" -eq 0 ]
  existing_branch=$(jq -r '.branch_name' "$state_file")
  [ -n "$existing_branch" ]
  [ "$(jq -r '.task_name' "$state_file")" = "X" ]

  # Now invoke --upsert with a DIFFERENT task_name and an empty-string proxy
  # for branch_name. We cannot pass branch_name directly through positional
  # args (it's derived from `git -C $cwd symbolic-ref`), so we use a detached
  # HEAD scenario to simulate a "would write empty branch_name" caller and
  # verify the merge preserves the pre-existing non-empty branch_name.
  (
    cd "$TEST_CWD"
    sha=$(git rev-parse HEAD)
    git checkout -q --detach "$sha"
  )

  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha2" "plan.md" "Y" "agent-2" "cc"
  [ "$status" -eq 0 ]

  # Pre-existing task_name "X" is preserved (existing non-empty wins).
  [ "$(jq -r '.task_name' "$state_file")" = "X" ]
  # Pre-existing branch_name is preserved (the new args would have written ""
  # in detached HEAD but merge kept the prior value).
  [ "$(jq -r '.branch_name' "$state_file")" = "$existing_branch" ]
}

# ---------------------------------------------------------------------------
# test_upsert_overwrites_empty_fields_with_new_args
# ---------------------------------------------------------------------------
@test "test_upsert_overwrites_empty_fields_with_new_args" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-write a breadcrumb with branch_name="" (use jq to fabricate the file
  # directly so we can control individual field values).
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n \
    --arg started_at "$now" \
    '{
      schema_version: 2,
      sha_before: "sha1",
      plan_path: "plan.md",
      task_name: "T1",
      expected_agent_id: "agent-1",
      started_at: $started_at,
      branch_name: "",
      skill_variant: "cc",
      review_abort_count: 0
    }' > "$state_file"

  # Create a feature branch so the new args' derived branch_name is non-empty.
  (
    cd "$TEST_CWD"
    git checkout -q -b feature/y
  )

  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1" "agent-1" "cc"
  [ "$status" -eq 0 ]

  # Empty branch_name was overwritten by the new args' value.
  [ "$(jq -r '.branch_name' "$state_file")" = "feature/y" ]
}

# ---------------------------------------------------------------------------
# test_upsert_preserves_review_abort_count
# ---------------------------------------------------------------------------
@test "test_upsert_preserves_review_abort_count" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-write a breadcrumb with review_abort_count=1.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n \
    --arg started_at "$now" \
    '{
      schema_version: 2,
      sha_before: "sha1",
      plan_path: "plan.md",
      task_name: "T1",
      expected_agent_id: "agent-1",
      started_at: $started_at,
      branch_name: "main",
      skill_variant: "cc",
      review_abort_count: 1
    }' > "$state_file"

  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1" "" "cc"
  [ "$status" -eq 0 ]

  # Counter preserved as integer 1.
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "1 number" ]
}

# ---------------------------------------------------------------------------
# test_upsert_keeps_existing_started_at
# ---------------------------------------------------------------------------
@test "test_upsert_keeps_existing_started_at" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  fixed_started_at="2025-01-01T00:00:00Z"
  jq -n \
    --arg started_at "$fixed_started_at" \
    '{
      schema_version: 2,
      sha_before: "sha1",
      plan_path: "plan.md",
      task_name: "T1",
      expected_agent_id: "agent-1",
      started_at: $started_at,
      branch_name: "main",
      skill_variant: "cc",
      review_abort_count: 0
    }' > "$state_file"

  # Wait at least 1 second so a fresh now() would differ from the fixed value.
  sleep 1

  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1" "" "cc"
  [ "$status" -eq 0 ]

  # started_at preserved unchanged.
  [ "$(jq -r '.started_at' "$state_file")" = "$fixed_started_at" ]
}

# ---------------------------------------------------------------------------
# test_upsert_on_malformed_existing_breadcrumb_creates_fresh
# ---------------------------------------------------------------------------
@test "test_upsert_on_malformed_existing_breadcrumb_creates_fresh" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Write garbage to the state file.
  printf 'this is not json {{{' > "$state_file"

  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1" "agent-x" "cc"
  [ "$status" -eq 0 ]

  # Writer succeeded with a fresh v2 breadcrumb (treating malformed as absent).
  run jq -r '.schema_version | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "2 number" ]
  [ "$(jq -r '.sha_before' "$state_file")" = "sha1" ]
  [ "$(jq -r '.task_name' "$state_file")" = "T1" ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "agent-x" ]
  [ "$(jq -r '.skill_variant' "$state_file")" = "cc" ]
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "0 number" ]
}

# ---------------------------------------------------------------------------
# test_upsert_legacy_v1_breadcrumb_upgraded_to_v2 (C1-T-1 regression catcher)
# ---------------------------------------------------------------------------
@test "test_upsert_legacy_v1_breadcrumb_upgraded_to_v2" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-write a legacy v1 breadcrumb (no schema_version, no v2 fields).
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n \
    --arg started_at "$now" \
    '{
      sha_before: "sha-legacy",
      plan_path: "plan.md",
      task_name: "Legacy task",
      expected_agent_id: "legacy-agent",
      started_at: $started_at
    }' > "$state_file"

  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha-new" "plan.md" "T-new" "" "portable"
  [ "$status" -eq 0 ]

  # schema_version forced to INTEGER 2 regardless of legacy input.
  run jq -r '.schema_version | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "2 number" ]

  # Pre-existing non-empty fields preserved (existing-wins precedence).
  [ "$(jq -r '.sha_before' "$state_file")" = "sha-legacy" ]
  [ "$(jq -r '.task_name' "$state_file")" = "Legacy task" ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "legacy-agent" ]

  # Absent v2 fields filled from new args / defaults.
  [ "$(jq -r '.skill_variant' "$state_file")" = "portable" ]
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "0 number" ]
}

# ---------------------------------------------------------------------------
# test_upsert_null_expected_agent_id_treated_as_absent (C1-T-3)
# ---------------------------------------------------------------------------
@test "test_upsert_null_expected_agent_id_treated_as_absent" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-write a breadcrumb where expected_agent_id is JSON null.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n \
    --arg started_at "$now" \
    '{
      schema_version: 2,
      sha_before: "sha1",
      plan_path: "plan.md",
      task_name: "T1",
      expected_agent_id: null,
      started_at: $started_at,
      branch_name: "main",
      skill_variant: "cc",
      review_abort_count: 0
    }' > "$state_file"

  # --upsert with a non-empty new arg 5 should fill in the null.
  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1" "agent-real" "cc"
  [ "$status" -eq 0 ]

  # null was treated as "not present"; new arg wins.
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "agent-real" ]
}

# ---------------------------------------------------------------------------
# test_upsert_existing_wins_when_both_non_empty (C1-T-4)
# ---------------------------------------------------------------------------
@test "test_upsert_existing_wins_when_both_non_empty" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"

  # Pre-write a breadcrumb with a real expected_agent_id and task_name.
  run bash "$SCRIPT" "$TEST_CWD" "sha-old" "plan.md" "Old task" "AGENT_OLD" "cc"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "AGENT_OLD" ]
  [ "$(jq -r '.task_name' "$state_file")" = "Old task" ]
  [ "$(jq -r '.sha_before' "$state_file")" = "sha-old" ]

  # --upsert with DIFFERENT non-empty new args must NOT clobber existing values.
  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha-new" "plan.md" "New task" "AGENT_NEW" "cc"
  [ "$status" -eq 0 ]

  # Existing non-empty values win across all merge-eligible string fields.
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "AGENT_OLD" ]
  [ "$(jq -r '.task_name' "$state_file")" = "Old task" ]
  [ "$(jq -r '.sha_before' "$state_file")" = "sha-old" ]
}

# ---------------------------------------------------------------------------
# test_upsert_with_insufficient_args_exits_2 (C1-T-5)
# ---------------------------------------------------------------------------
@test "test_upsert_with_insufficient_args_exits_2" {
  # --upsert + 4 positional args (one short of the 5-arg minimum) → exit 2.
  run bash "$SCRIPT" --upsert "$TEST_CWD" "sha1" "plan.md" "T1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

# ===========================================================================
# Task 1.3 — --increment-review-abort mode tests
# ===========================================================================

# Helper: pre-write a canonical v2 breadcrumb with a specific review_abort_count.
_prewrite_breadcrumb() {
  local count="$1"
  local state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n \
    --arg started_at "$now" \
    --argjson count "$count" \
    '{
      schema_version: 2,
      sha_before: "sha-pre",
      plan_path: "plan-pre.md",
      task_name: "Task-pre",
      expected_agent_id: "agent-pre",
      started_at: $started_at,
      branch_name: "main",
      skill_variant: "cc",
      review_abort_count: $count
    }' > "$state_file"
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_from_zero_to_one
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_from_zero_to_one" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  _prewrite_breadcrumb 0

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]

  # Counter incremented to integer 1.
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "1 number" ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_from_one_to_two
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_from_one_to_two" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  _prewrite_breadcrumb 1

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]

  # Counter incremented to integer 2.
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "2 number" ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_treats_missing_field_as_zero
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_treats_missing_field_as_zero" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-write a breadcrumb WITHOUT review_abort_count field.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n \
    --arg started_at "$now" \
    '{
      schema_version: 2,
      sha_before: "sha-pre",
      plan_path: "plan-pre.md",
      task_name: "Task-pre",
      expected_agent_id: "agent-pre",
      started_at: $started_at,
      branch_name: "main",
      skill_variant: "cc"
    }' > "$state_file"

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]

  # Missing field treated as 0 then incremented to 1.
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "1 number" ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_preserves_other_fields
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_preserves_other_fields" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-write a breadcrumb with very specific values.
  fixed_started_at="2024-12-31T23:59:59Z"
  jq -n \
    --arg started_at "$fixed_started_at" \
    '{
      schema_version: 2,
      sha_before: "deadbeef",
      plan_path: "plans/X.md",
      task_name: "Specific task name",
      expected_agent_id: "agent-special-id",
      started_at: $started_at,
      branch_name: "feature/special",
      skill_variant: "portable",
      review_abort_count: 0
    }' > "$state_file"

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]

  # All non-counter fields preserved byte-identical (schema_version is integer 2).
  run jq -r '.schema_version | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "2 number" ]
  [ "$(jq -r '.sha_before' "$state_file")" = "deadbeef" ]
  [ "$(jq -r '.plan_path' "$state_file")" = "plans/X.md" ]
  [ "$(jq -r '.task_name' "$state_file")" = "Specific task name" ]
  [ "$(jq -r '.expected_agent_id' "$state_file")" = "agent-special-id" ]
  [ "$(jq -r '.started_at' "$state_file")" = "$fixed_started_at" ]
  [ "$(jq -r '.branch_name' "$state_file")" = "feature/special" ]
  [ "$(jq -r '.skill_variant' "$state_file")" = "portable" ]
  # And counter is now 1.
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "1 number" ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_missing_breadcrumb_exits_nonzero
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_missing_breadcrumb_exits_nonzero" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ ! -f "$state_file" ]

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  # Plan specifies "e.g., exit 3"; implementation uses 3.
  [ "$status" -eq 3 ]
  # Stderr / output contains "not found".
  [[ "$output" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_rejects_upsert_combo
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_rejects_upsert_combo" {
  # --increment-review-abort + --upsert (in either order) → exit 2.
  run bash "$SCRIPT" --increment-review-abort --upsert "$TEST_CWD"
  [ "$status" -eq 2 ]

  run bash "$SCRIPT" --upsert --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_rejects_extra_positional_args
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_rejects_extra_positional_args" {
  # --increment-review-abort only takes <cwd> as a positional arg. Extras → exit 2.
  _prewrite_breadcrumb 0
  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD" "extra-arg"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_atomic
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_atomic" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  _prewrite_breadcrumb 1

  # Record the pre-state for the "either pre-existing or fully-incremented"
  # invariant check.
  pre_count=$(jq -r '.review_abort_count' "$state_file")
  [ "$pre_count" = "1" ]

  # Invoke with a delay between .tmp render and mv. Background and kill -9
  # before the mv lands.
  _RECOVERY_TEST_DELAY_BEFORE_MV=2 bash "$SCRIPT" \
    --increment-review-abort "$TEST_CWD" &
  writer_pid=$!

  sleep 0.5
  kill -9 "$writer_pid" 2>/dev/null || true
  wait "$writer_pid" 2>/dev/null || true

  # The final state_file must either be pre-existing content or fully
  # incremented — never partial. Both 1 and 2 are valid; anything else fails.
  [ -f "$state_file" ]
  run jq -r '.review_abort_count' "$state_file"
  [ "$status" -eq 0 ]
  case "$output" in
    1|2) ;;  # Either pre-existing or fully-incremented; both acceptable.
    *) printf 'unexpected review_abort_count: %s\n' "$output" >&2; false ;;
  esac
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_malformed_breadcrumb_exits_nonzero
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_malformed_breadcrumb_exits_nonzero" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-write garbage.
  printf 'this is not json {{{' > "$state_file"

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  # Exit code 3 lock: the script reserves exit 3 for --increment-review-abort
  # data-precondition failures (missing or malformed breadcrumb).
  [ "$status" -eq 3 ]
  # Output names the malformed JSON.
  [[ "$output" == *"malformed"* ]] || [[ "$output" == *"JSON"* ]]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_no_cwd_arg_exits_2
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_no_cwd_arg_exits_2" {
  # --increment-review-abort with NO positional arg → exit 2 (usage error).
  run bash "$SCRIPT" --increment-review-abort
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_nonexistent_cwd_exits_2
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_nonexistent_cwd_exits_2" {
  # cwd pointing at a path that does not exist → exit 2.
  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD/does-not-exist"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cwd"* ]]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_output_is_valid_json
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_output_is_valid_json" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  _prewrite_breadcrumb 0

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]

  # Resulting file must be valid JSON.
  run jq -e . "$state_file"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_coerces_non_integer_counter
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_coerces_non_integer_counter" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Pre-write a breadcrumb whose counter is a JSON string (corruption case).
  # The implementation must coerce this to 0 then increment to 1, NOT crash
  # on a type error from jq arithmetic.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n \
    --arg started_at "$now" \
    '{
      schema_version: 2,
      sha_before: "sha1",
      plan_path: "plan.md",
      task_name: "T1",
      expected_agent_id: "agent-1",
      started_at: $started_at,
      branch_name: "main",
      skill_variant: "cc",
      review_abort_count: "5"
    }' > "$state_file"

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]

  # Counter is now integer 1 (string coerced to 0, then +1).
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "1 number" ]
}

# ---------------------------------------------------------------------------
# test_increment_review_abort_coerces_float_counter
# ---------------------------------------------------------------------------
@test "test_increment_review_abort_coerces_float_counter" {
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  mkdir -p "$TEST_CWD/.claude"

  # Float counter is invalid per spec ("must remain integer in output").
  # Implementation coerces to 0 then increments to 1.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -n \
    --arg started_at "$now" \
    '{
      schema_version: 2,
      sha_before: "sha1",
      plan_path: "plan.md",
      task_name: "T1",
      expected_agent_id: "agent-1",
      started_at: $started_at,
      branch_name: "main",
      skill_variant: "cc",
      review_abort_count: 1.5
    }' > "$state_file"

  run bash "$SCRIPT" --increment-review-abort "$TEST_CWD"
  [ "$status" -eq 0 ]

  # Output must be a clean integer.
  run jq -r '.review_abort_count | tostring + " " + (. | type)' "$state_file"
  [ "$output" = "1 number" ]
}
