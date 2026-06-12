#!/usr/bin/env bats
#
# test_hook_gate.bats — Task 1.6 coverage for implement-next-stop-gate.sh
# under the v2 state ecosystem (empty expected_agent_id, breadcrumb absence,
# mid-turn clear, TTL expiry).
#
# The hook gate's source is UNCHANGED — these tests lock in its existing
# behavior so future regressions in fail-open semantics are caught at test time.
#
# Per-test isolation: each test creates a fresh $TEST_CWD via mktemp -d under
# $BATS_TMPDIR and removes it in teardown.

SCRIPT="$HOME/.claude/scripts/implement-next-stop-gate.sh"
WRITER="$HOME/.claude/scripts/implement-next-state-write.sh"

setup() {
  TEST_CWD="$(mktemp -d "$BATS_TMPDIR/recovery-hookgate-XXXXXX")"
  export TEST_CWD
  git init -q "$TEST_CWD"
  (
    cd "$TEST_CWD"
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit --allow-empty -q -m "init"
  )
  HEAD_SHA=$(git -C "$TEST_CWD" rev-parse HEAD)
  export HEAD_SHA
}

teardown() {
  if [ -n "${TEST_CWD:-}" ] && [ -d "$TEST_CWD" ]; then
    rm -rf "$TEST_CWD"
  fi
}

# Helper: build a hook input JSON payload on stdin.
# $1 = agent_id, $2 = cwd
hook_input() {
  local agent_id="$1" cwd="$2"
  jq -nc --arg aid "$agent_id" --arg cwd "$cwd" '{agent_id: $aid, cwd: $cwd}'
}

# Helper: pipe a JSON payload into the gate script via a tempfile to avoid
# any shell-quoting hazards with the payload contents.
# $1 = payload (JSON string)
# Sets bats `$status` and `$output` via `run`.
run_gate() {
  local payload="$1"
  local payload_file="$BATS_TEST_TMPDIR/gate-payload.json"
  printf '%s' "$payload" > "$payload_file"
  run bash -c "bash \"$SCRIPT\" < \"$payload_file\""
}

# ---------------------------------------------------------------------------
# fixture s: breadcrumb present + agent matches + no new commit since sha_before
# Expected: hook BLOCKS — exit 0 + JSON {decision:"block", reason:...} on stdout.
# ---------------------------------------------------------------------------
@test "test_hook_blocks_when_breadcrumb_present_agent_matches_no_commit" {
  # Write a v2 breadcrumb with expected_agent_id="X" and sha_before=HEAD.
  run bash "$WRITER" "$TEST_CWD" "$HEAD_SHA" "plan.md" "Task 1" "X" "cc"
  [ "$status" -eq 0 ]
  [ -f "$TEST_CWD/.claude/implement-next-state.json" ]

  # Send hook payload with matching agent_id and the same cwd.
  payload=$(hook_input "X" "$TEST_CWD")
  run_gate "$payload"

  [ "$status" -eq 0 ]
  # stdout must be JSON with decision: block.
  decision=$(printf '%s' "$output" | jq -r '.decision // empty' 2>/dev/null || true)
  [ "$decision" = "block" ]
  reason=$(printf '%s' "$output" | jq -r '.reason // empty' 2>/dev/null || true)
  [ -n "$reason" ]
  # Stronger: the gate's reason MUST name the missing-commit failure.
  # Catches regressions that empty or mangle the reason text.
  [[ "$reason" == *"without producing a commit"* ]]
  # Sentinel must still exist (block path does NOT remove it).
  [ -f "$TEST_CWD/.claude/implement-next-state.json" ]
}

# ---------------------------------------------------------------------------
# fixture t: breadcrumb present + agent_id mismatch
# Expected: hook passes through — exit 0, empty stdout.
# ---------------------------------------------------------------------------
@test "test_hook_passes_through_when_agent_mismatch" {
  run bash "$WRITER" "$TEST_CWD" "$HEAD_SHA" "plan.md" "Task 1" "X" "cc"
  [ "$status" -eq 0 ]

  # Hook payload has a DIFFERENT agent_id than what's in the breadcrumb.
  payload=$(hook_input "Y" "$TEST_CWD")
  run_gate "$payload"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Sentinel preserved — mismatching agents do not clear it.
  [ -f "$TEST_CWD/.claude/implement-next-state.json" ]
}

# ---------------------------------------------------------------------------
# fixture u: no breadcrumb on disk
# Expected: hook passes through — exit 0, empty stdout.
# ---------------------------------------------------------------------------
@test "test_hook_passes_through_when_breadcrumb_absent" {
  [ ! -f "$TEST_CWD/.claude/implement-next-state.json" ]

  payload=$(hook_input "any" "$TEST_CWD")
  run_gate "$payload"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Breadcrumb has empty expected_agent_id (standalone child / portable parent).
# Hook MUST fail open per implement-next-stop-gate.sh:62-64 — exit 0, no block.
# ---------------------------------------------------------------------------
@test "test_hook_passes_through_when_expected_agent_id_empty" {
  # --upsert allows empty expected_agent_id (arg 5).
  run bash "$WRITER" --upsert "$TEST_CWD" "$HEAD_SHA" "plan.md" "Task 1" "" "portable"
  [ "$status" -eq 0 ]
  # Confirm the breadcrumb truly has an empty expected_agent_id.
  [ "$(jq -r '.expected_agent_id' "$TEST_CWD/.claude/implement-next-state.json")" = "" ]

  # Any agent_id in the payload should pass through.
  payload=$(hook_input "anything" "$TEST_CWD")
  run_gate "$payload"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # Sentinel preserved — fail-open does NOT clear.
  [ -f "$TEST_CWD/.claude/implement-next-state.json" ]
}

# ---------------------------------------------------------------------------
# Breadcrumb present + agent matches + a NEW commit exists since sha_before.
# Expected: hook removes the breadcrumb AND exits 0 with no block JSON.
# ---------------------------------------------------------------------------
@test "test_hook_passes_through_when_new_commit_exists" {
  # Capture sha_before, then create a new commit so HEAD != sha_before.
  SHA_BEFORE="$HEAD_SHA"
  run bash "$WRITER" "$TEST_CWD" "$SHA_BEFORE" "plan.md" "Task 1" "X" "cc"
  [ "$status" -eq 0 ]
  [ -f "$TEST_CWD/.claude/implement-next-state.json" ]

  # Add a new commit after the breadcrumb was written.
  (
    cd "$TEST_CWD"
    git commit --allow-empty -q -m "follow-up commit"
  )

  payload=$(hook_input "X" "$TEST_CWD")
  run_gate "$payload"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # The hook MUST remove the sentinel after detecting a new commit.
  [ ! -f "$TEST_CWD/.claude/implement-next-state.json" ]
}

# ---------------------------------------------------------------------------
# Breadcrumb's started_at is older than the 4h TTL (14400s) — stale sentinel.
# Expected: hook removes the breadcrumb and fails open — exit 0, no block.
# ---------------------------------------------------------------------------
@test "test_hook_ttl_expired_removes_and_fails_open" {
  # Write a valid breadcrumb, then rewrite started_at to 5 hours ago.
  run bash "$WRITER" "$TEST_CWD" "$HEAD_SHA" "plan.md" "Task 1" "X" "cc"
  [ "$status" -eq 0 ]
  state_file="$TEST_CWD/.claude/implement-next-state.json"
  [ -f "$state_file" ]

  # 5 hours ago in the same ISO 8601 UTC format the writer emits.
  five_hours_ago=$(TZ=UTC date -u -v-5H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || TZ=UTC date -u -d "5 hours ago" +%Y-%m-%dT%H:%M:%SZ)
  jq --arg t "$five_hours_ago" '.started_at = $t' "$state_file" > "$state_file.tmp"
  mv "$state_file.tmp" "$state_file"
  [ "$(jq -r '.started_at' "$state_file")" = "$five_hours_ago" ]

  # Even with a matching agent_id, the TTL check fires before the new-commit
  # check, so the sentinel is removed and the hook exits with no block JSON.
  payload=$(hook_input "X" "$TEST_CWD")
  run_gate "$payload"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$state_file" ]
}
