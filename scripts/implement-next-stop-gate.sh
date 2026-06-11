#!/usr/bin/env bash
# implement-next-stop-gate.sh
#
# SubagentStop hook. Refuses to let an /implement-next subagent end its turn
# unless a new commit has landed since the sentinel was written.
#
# Anthropic prescribes this pattern in code.claude.com/docs/en/best-practices (accessed 2026-06-11) — "As a deterministic gate: a Stop hook ... blocks the turn from ending until it passes." The 8-block override applies to the `Stop` event; the `SubagentStop` event has no documented cap per code.claude.com/docs/en/hooks (accessed 2026-06-11).
#
# Activation contract:
#   /implement-all-cc writes <cwd>/.claude/implement-next-state.json before each
#   per-task subagent spawn. Schema:
#     { "sha_before": "<sha>", "plan_path": "<path>", "task_name": "<name>",
#       "expected_agent_id": "<id>", "started_at": "<iso8601>" }
#
# Behavior:
#   - No sentinel  → exit 0 (not an implement-next subagent, pass through)
#   - Sentinel + new commit since sha_before → remove sentinel, exit 0
#   - Sentinel + no new commit → emit JSON block decision (exit 0)
#   - Any internal error → exit 0 (fail open — never break the user's session)

set -uo pipefail

# Read stdin once. If anything fails parsing, fail open.
INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

# Extract cwd from the hook payload.
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$CWD" ] && exit 0
[ -d "$CWD" ] || exit 0

STATE_FILE="$CWD/.claude/implement-next-state.json"
[ -f "$STATE_FILE" ] || exit 0  # not an implement-next subagent

# Parse the sentinel. Fail open on malformed JSON.
SHA_BEFORE="$(jq -r '.sha_before // empty' "$STATE_FILE" 2>/dev/null || true)"
PLAN_PATH="$(jq -r '.plan_path // empty' "$STATE_FILE" 2>/dev/null || true)"
TASK_NAME="$(jq -r '.task_name // "the current task"' "$STATE_FILE" 2>/dev/null || echo 'the current task')"
EXPECTED_AGENT_ID="$(jq -r '.expected_agent_id // empty' "$STATE_FILE" 2>/dev/null || true)"
[ -z "$SHA_BEFORE" ] && exit 0

# TTL check: if sentinel is older than 4 hours, treat as stale and fail open.
# This guards against orphaned sentinels from killed parent loops, OS reboots, etc.
STARTED_AT="$(jq -r '.started_at // empty' "$STATE_FILE" 2>/dev/null || true)"
if [ -n "$STARTED_AT" ]; then
    # date -j -f is BSD/macOS; date -d is GNU/Linux. Try both.
    # Force UTC on the read side to align with the writer (state-write.sh
    # uses `date -u +%Y-%m-%dT%H:%M:%SZ`). BSD `date -j -f` does NOT honor
    # the literal `Z` suffix — without TZ=UTC, the timestamp would be parsed
    # in the local timezone, causing TTL miscalculation across timezones.
    sentinel_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" "+%s" 2>/dev/null || TZ=UTC date -d "$STARTED_AT" "+%s" 2>/dev/null || echo 0)
    now_epoch=$(date "+%s")
    if [ "$sentinel_epoch" -gt 0 ] && [ $((now_epoch - sentinel_epoch)) -gt 14400 ]; then
        rm -f "$STATE_FILE" 2>/dev/null || true
        exit 0
    fi
fi

# Safety: if expected_agent_id is missing or empty (malformed sentinel),
# fail-open. Without a known target, the hook cannot safely filter and
# would otherwise block every subagent in this cwd.
if [ -z "$EXPECTED_AGENT_ID" ]; then
    exit 0
fi

# Filter: only gate the specific subagent that /implement-all spawned. Nested
# sub-sub-agents (devils-advocate, fix agents, check-off agent) fire their own
# SubagentStop events with different agent_ids; they must NOT be blocked or
# the /implement-next run deadlocks.
FIRING_AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null || true)"
if [ "$FIRING_AGENT_ID" != "$EXPECTED_AGENT_ID" ]; then
    exit 0
fi

# Verify cwd is a git repo. If not, fail open (subagent isn't producing commits here).
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# Verify sha_before resolves. If not, the sentinel is stale — fail open.
if ! git -C "$CWD" rev-parse --verify "$SHA_BEFORE" >/dev/null 2>&1; then
    exit 0
fi

# Count new non-merge commits since sha_before.
NEW_COMMITS=$(git -C "$CWD" rev-list --count --no-merges "${SHA_BEFORE}..HEAD" 2>/dev/null || echo 0)

if [ "${NEW_COMMITS:-0}" -ge 1 ]; then
    # Success: clean up the sentinel so subsequent SubagentStop fires pass through.
    rm -f "$STATE_FILE" 2>/dev/null || true
    exit 0
fi

# Block: tell the subagent exactly what's missing and how to recover.
REASON="implement-next subagent attempted to end its turn without producing a commit. Task '${TASK_NAME}' is incomplete. You MUST:
  1. Run the relevant tests (NEVER use Monitor inside this subagent — Monitor causes silent termination).
  2. Mark the task done in ${PLAN_PATH} by changing '- [ ]' to '- [x]'.
  3. git add the implementation files AND the plan file, then git commit with a message describing the task.
If the test suite cannot finish in this subagent's window (Bash has a 10-minute foreground ceiling, verified via anthropics/claude-code GitHub issue #25881), run only the task-relevant subset here — the parent /implement-all loop will run the full suite at its own level where Monitor works correctly."

# Emit the block decision as JSON on stdout. exit 0 because the JSON itself
# carries the block signal (per Anthropic SubagentStop hook spec).
jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
