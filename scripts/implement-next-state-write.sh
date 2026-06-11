#!/usr/bin/env bash
# implement-next-state-write.sh <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id>
#
# Writes the SubagentStop-hook sentinel that armed the /implement-next gate.
# Called by /implement-all-cc before each per-task subagent spawn.
#
# Exit 0 = sentinel written.
# Exit 2 = usage error.

set -euo pipefail

if [ $# -ne 5 ]; then
    echo "Usage: implement-next-state-write.sh <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id>" >&2
    exit 2
fi

if [ -z "$5" ]; then
    echo "ERROR: expected_agent_id (arg 5) may not be empty" >&2
    exit 2
fi

cwd="$1"
sha_before="$2"
plan_path="$3"
task_name="$4"
expected_agent_id="$5"

if [ ! -d "$cwd" ]; then
    echo "ERROR: cwd does not exist: $cwd" >&2
    exit 2
fi

mkdir -p "$cwd/.claude"
state_file="$cwd/.claude/implement-next-state.json"

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
    --arg sha_before "$sha_before" \
    --arg plan_path "$plan_path" \
    --arg task_name "$task_name" \
    --arg expected_agent_id "$expected_agent_id" \
    --arg started_at "$now" \
    '{
        sha_before: $sha_before,
        plan_path: $plan_path,
        task_name: $task_name,
        expected_agent_id: $expected_agent_id,
        started_at: $started_at
    }' > "$state_file"

echo "Sentinel written: $state_file"
