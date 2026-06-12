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
