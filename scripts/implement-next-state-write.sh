#!/usr/bin/env bash
# RECOVERY_SCHEMA_V2
#
# implement-next-state-write.sh <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> [<skill_variant>]
#
# Writes the SubagentStop-hook sentinel that armed the /implement-next gate.
# Called by /implement-all-cc before each per-task subagent spawn (default mode).
#
# Default mode signature:
#   <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> [<skill_variant>]
#
# Behavior:
#   - schema_version: 2 (integer) written.
#   - branch_name captured via `git -C "$cwd" symbolic-ref --short HEAD`; empty
#     on detached HEAD.
#   - skill_variant defaults to "cc" when the 6th arg is omitted (back-compat
#     with the existing 5-arg caller at implement-all-cc.md). Valid values:
#     "portable" | "cc". Any other value → exit 2.
#   - review_abort_count: 0 (integer) written.
#   - Atomic write: render to "$state_file.tmp" (sibling of $state_file, same
#     filesystem), then `mv` (POSIX-atomic on same filesystem).
#   - Default mode keeps the empty-expected_agent_id guard (exit 2 if arg 5
#     is empty).
#
# Test-only hook:
#   _RECOVERY_TEST_DELAY_BEFORE_MV — if set to a number, sleep that many
#   seconds between writing the .tmp and the mv. Undocumented in user-facing
#   usage; defaults to no delay.
#
# Exit codes:
#   0 = sentinel written.
#   2 = usage error.

set -euo pipefail

if [ $# -lt 5 ] || [ $# -gt 6 ]; then
    echo "Usage: implement-next-state-write.sh <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> [<skill_variant>]" >&2
    exit 2
fi

cwd="$1"
sha_before="$2"
plan_path="$3"
task_name="$4"
expected_agent_id="$5"
skill_variant="${6:-cc}"

if [ -z "$expected_agent_id" ]; then
    echo "ERROR: expected_agent_id (arg 5) may not be empty in default mode" >&2
    exit 2
fi

case "$skill_variant" in
    portable|cc) ;;
    *)
        echo "ERROR: invalid skill_variant '$skill_variant'; must be 'portable' or 'cc'" >&2
        exit 2
        ;;
esac

if [ ! -d "$cwd" ]; then
    echo "ERROR: cwd does not exist: $cwd" >&2
    exit 2
fi

mkdir -p "$cwd/.claude"
state_file="$cwd/.claude/implement-next-state.json"
tmp_file="$state_file.tmp"

# branch_name: empty string on detached HEAD or non-git dir.
branch_name=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo "")

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
    --arg sha_before "$sha_before" \
    --arg plan_path "$plan_path" \
    --arg task_name "$task_name" \
    --arg expected_agent_id "$expected_agent_id" \
    --arg started_at "$now" \
    --arg branch_name "$branch_name" \
    --arg skill_variant "$skill_variant" \
    '{
        schema_version: 2,
        sha_before: $sha_before,
        plan_path: $plan_path,
        task_name: $task_name,
        expected_agent_id: $expected_agent_id,
        started_at: $started_at,
        branch_name: $branch_name,
        skill_variant: $skill_variant,
        review_abort_count: 0
    }' > "$tmp_file"

# Test-only hook: simulate a slow write so a kill -9 can interrupt before mv.
if [ -n "${_RECOVERY_TEST_DELAY_BEFORE_MV:-}" ]; then
    sleep "$_RECOVERY_TEST_DELAY_BEFORE_MV"
fi

mv "$tmp_file" "$state_file"

echo "Sentinel written: $state_file"
