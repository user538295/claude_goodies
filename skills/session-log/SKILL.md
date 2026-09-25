---
name: session-log
description: Manage session prompt logging and usage totals (on / off / status / usage)
---
<!-- universal-session-log: managed -->

Resolve this skill's own package directory (`$BASE`) across every supported harness — without Claude-Code-only artifacts — then hand off to its `install.sh` for the fixed `claude` harness.

```bash
BASE=""; for d in "${SESSION_LOG_HOME:-}" .agents/skills/session-log .claude/skills/session-log .cursor/skills/session-log .opencode/skills/session-log .codex/skills/session-log ~/.agents/skills/session-log ~/.claude/skills/session-log ~/.cursor/skills/session-log ~/.config/opencode/skills/session-log ~/.omp/agent/skills/session-log ~/.codex/skills/session-log "$(ls -d ~/.claude/plugins/cache/*/claude-goodies/*/skills/session-log 2>/dev/null | sort -V | tail -1)"; do [ -n "$d" ] && [ -f "$d/install.sh" ] && { BASE="$d"; break; }; done
if [ -n "$BASE" ]; then
  exec bash "$BASE/install.sh" --harness claude --arguments "${ARGUMENTS:-status}"
fi
printf 'session-log: complete package not found in any known skills root — set SESSION_LOG_HOME=<skill dir>\n' >&2
exit 1
```

No argument means `status`. `usage` prints Claude Code's native report without changing its fields. `on` may report `on — restart required`; restart Claude Code before relying on logging.
