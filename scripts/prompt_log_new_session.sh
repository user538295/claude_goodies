#!/bin/bash
set -euo pipefail
source "$HOME/.claude/scripts/prompt_log_lib.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // ""')
cwd=$(echo "$input" | jq -r '.cwd // ""')

[ -z "$session_id" ] && exit 0
[ -z "$cwd" ] && exit 0

create_session_file "$session_id" "$cwd"
