#!/usr/bin/env bash
# RECOVERY_SCHEMA_V2
#
# implement-next-state-write.sh [--upsert] <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> [<skill_variant>]
#
# Writes the SubagentStop-hook sentinel that armed the /implement-next gate.
# Called by /implement-all-cc before each per-task subagent spawn (default mode).
#
# Default mode signature:
#   <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> [<skill_variant>]
#
# --upsert mode signature:
#   --upsert <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> [<skill_variant>]
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
# --upsert mode:
#   - Skips the empty-expected_agent_id guard (the writer accepts empty arg 5).
#   - Read-merge semantics: if state_file exists AND parses as JSON, for each
#     output field, prefer the existing non-empty value over the new-args
#     value. Specifically:
#       expected_agent_id, task_name, plan_path, sha_before, branch_name,
#       skill_variant: existing non-empty wins.
#       started_at:    keep existing if present; else fresh now().
#       schema_version: always set to 2 (integer).
#       review_abort_count: keep existing if present (integer); else default 0.
#   - If state_file does not exist OR is malformed JSON, behavior matches the
#     default-mode write minus the empty-agentId guard (fresh breadcrumb).
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

# Parse flags (before positional args). --upsert must precede <cwd>.
upsert=0
if [ "${1:-}" = "--upsert" ]; then
    upsert=1
    shift
fi

if [ $# -lt 5 ] || [ $# -gt 6 ]; then
    echo "Usage: implement-next-state-write.sh [--upsert] <cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> [<skill_variant>]" >&2
    exit 2
fi

cwd="$1"
sha_before="$2"
plan_path="$3"
task_name="$4"
expected_agent_id="$5"
skill_variant="${6:-cc}"

if [ "$upsert" -eq 0 ] && [ -z "$expected_agent_id" ]; then
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

# branch_name from new args: derived via `git -C $cwd symbolic-ref`.
# Empty string on detached HEAD or non-git dir.
new_branch_name=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo "")
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Compute final field values.
# In default mode: just use the new-args values as-is.
# In --upsert mode: read-merge with existing breadcrumb (if parseable);
#                   existing non-empty fields win.
final_sha_before="$sha_before"
final_plan_path="$plan_path"
final_task_name="$task_name"
final_expected_agent_id="$expected_agent_id"
final_started_at="$now"
final_branch_name="$new_branch_name"
final_skill_variant="$skill_variant"
final_review_abort_count="0"

if [ "$upsert" -eq 1 ] && [ -f "$state_file" ]; then
    # Treat malformed JSON as absent (create fresh).
    if jq -e . "$state_file" >/dev/null 2>&1; then
        # Helper: return existing field if non-empty, else fall back.
        # "Non-empty" for strings means JSON value !=null and !="".
        merge_str() {
            local field="$1" fallback="$2"
            local existing
            existing=$(jq -r --arg f "$field" '.[$f] // ""' "$state_file" 2>/dev/null || echo "")
            if [ -n "$existing" ]; then
                printf '%s' "$existing"
            else
                printf '%s' "$fallback"
            fi
        }
        final_sha_before=$(merge_str sha_before "$sha_before")
        final_plan_path=$(merge_str plan_path "$plan_path")
        final_task_name=$(merge_str task_name "$task_name")
        final_expected_agent_id=$(merge_str expected_agent_id "$expected_agent_id")
        final_branch_name=$(merge_str branch_name "$new_branch_name")
        final_skill_variant=$(merge_str skill_variant "$skill_variant")
        # started_at: keep existing if present (any non-empty string).
        existing_started_at=$(jq -r '.started_at // ""' "$state_file" 2>/dev/null || echo "")
        if [ -n "$existing_started_at" ]; then
            final_started_at="$existing_started_at"
        fi
        # review_abort_count: keep existing integer if present; else 0.
        existing_count=$(jq -r '.review_abort_count // empty | numbers' "$state_file" 2>/dev/null || echo "")
        if [ -n "$existing_count" ]; then
            final_review_abort_count="$existing_count"
        fi
    fi
fi

jq -n \
    --arg sha_before "$final_sha_before" \
    --arg plan_path "$final_plan_path" \
    --arg task_name "$final_task_name" \
    --arg expected_agent_id "$final_expected_agent_id" \
    --arg started_at "$final_started_at" \
    --arg branch_name "$final_branch_name" \
    --arg skill_variant "$final_skill_variant" \
    --argjson review_abort_count "$final_review_abort_count" \
    '{
        schema_version: 2,
        sha_before: $sha_before,
        plan_path: $plan_path,
        task_name: $task_name,
        expected_agent_id: $expected_agent_id,
        started_at: $started_at,
        branch_name: $branch_name,
        skill_variant: $skill_variant,
        review_abort_count: $review_abort_count
    }' > "$tmp_file"

# Test-only hook: simulate a slow write so a kill -9 can interrupt before mv.
if [ -n "${_RECOVERY_TEST_DELAY_BEFORE_MV:-}" ]; then
    sleep "$_RECOVERY_TEST_DELAY_BEFORE_MV"
fi

mv "$tmp_file" "$state_file"

echo "Sentinel written: $state_file"
