#!/bin/bash
set -euo pipefail
source "$HOME/.claude/scripts/prompt_log_lib.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // ""')
prompt=$(echo "$input" | jq -r '.prompt // ""')
cwd=$(echo "$input" | jq -r '.cwd // ""')

[ -z "$session_id" ] && exit 0
[ -z "$prompt" ] && exit 0

session_map="$_CLAUDE_SESSION_MAP_DIR/${session_id}"
[ ! -f "$session_map" ] && create_session_file "$session_id" "$cwd"

session_file=$(cat "$session_map") || { echo "ERROR: failed to read session map for ${session_id}" >&2; exit 1; }
[ -z "$session_file" ] && { echo "ERROR: session map is empty for ${session_id}" >&2; exit 1; }

timestamp=$(date '+%H:%M:%S')

{
  printf '## %s\n\n' "$timestamp"
  printf '%s\n' "$prompt"
  printf '\n%s\n\n' '---'
} >> "$session_file"
