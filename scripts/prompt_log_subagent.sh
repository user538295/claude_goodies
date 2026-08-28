#!/bin/bash
set -euo pipefail
# Same contract as prompt_log_stop.sh: never write stdout, always exit 0.
trap 'exit 0' EXIT
umask 077
[ -f "$HOME/.claude/prompt-logs/.enabled" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/prompt_log_lib.sh"

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // ""')
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // ""')
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // "sub-agent"')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""')
[ -n "$session_id" ] || exit 0
[ -n "$agent_id" ] || exit 0
[ -n "$transcript" ] || exit 0

session_map="$_CLAUDE_SESSION_MAP_DIR/${session_id}"
[ -f "$session_map" ] || exit 0
session_file=$(cat "$session_map")
[ -n "$session_file" ] || exit 0

# transcript_path is the parent session's; the sub-agent's own transcript sits
# beside it under <session-id>/subagents/.
jsonl="$(dirname "$transcript")/${session_id}/subagents/agent-${agent_id}.jsonl"
missing=""
if [ ! -f "$jsonl" ]; then missing=" (not found)"; fi

printf '%s sub-agent finished: %s (agent-%s), jsonl: %s%s\n\n' \
  "$(date '+%H:%M:%S')" "$agent_type" "$agent_id" "$jsonl" "$missing" >> "$session_file"
