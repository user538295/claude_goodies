#!/bin/bash
_CLAUDE_SESSION_MAP_DIR="$HOME/.claude/session-maps"

create_session_file() {
  local session_id="$1"
  local cwd="$2"
  local project_slug
  # Include parent dir to avoid collisions between same-named projects
  project_slug=$(echo "$cwd" | sed 's|.*/\([^/]*/[^/]*\)$|\1|' | tr '/' '-')
  local prompts_dir="$HOME/.claude/prompt-logs/$project_slug"
  mkdir -p "$prompts_dir"
  local timestamp
  timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
  local session_file="$prompts_dir/session_${timestamp}.md"

  # Store session map in a private directory, not world-writable /tmp
  mkdir -p "$_CLAUDE_SESSION_MAP_DIR"
  chmod 700 "$_CLAUDE_SESSION_MAP_DIR"
  echo "$session_file" > "$_CLAUDE_SESSION_MAP_DIR/${session_id}"
  chmod 600 "$_CLAUDE_SESSION_MAP_DIR/${session_id}"

  # Derive path to Claude's session JSONL file
  local project_key
  project_key=$(echo "$cwd" | sed 's|^/||; s|/|-|g')
  local session_jsonl="$HOME/.claude/projects/${project_key}/${session_id}.jsonl"

  {
    printf '# Prompts — %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '**Session ID:** %s\n' "$session_id"
    printf '**Resume:** `claude --resume %s`\n' "$session_id"
    printf '**Session file:** `%s`\n\n' "$session_jsonl"
    printf '%s\n\n' '---'
  } > "$session_file"
}
