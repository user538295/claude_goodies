#!/bin/bash
set -euo pipefail
[ "${CLAUDE_GOODIES_PROMPT_LOG:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
# SessionStart hooks: non-zero exit is non-blocking (unlike UserPromptSubmit exit 2 which erases prompt), so no trap needed.
source "$(dirname "${BASH_SOURCE[0]}")/prompt_log_lib.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // ""')
cwd=$(echo "$input" | jq -r '.cwd // ""')

[ -z "$session_id" ] && exit 0
[ -z "$cwd" ] && exit 0

create_session_file "$session_id" "$cwd"
