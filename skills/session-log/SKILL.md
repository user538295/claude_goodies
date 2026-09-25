---
name: session-log
description: Manage session prompt logging and usage totals (on / off / status / usage)
---
<!-- universal-session-log: managed -->

Run the shared session-log CLI through Claude Code's native skill entrypoint. Do not infer a harness from files, directories, or environment variables.

```bash
session_log_root="$HOME/.claude/skills/session-log"
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "$CLAUDE_PLUGIN_ROOT/skills/session-log/install.sh" ]]; then
  session_log_root="$CLAUDE_PLUGIN_ROOT/skills/session-log"
fi
if [[ -f "$session_log_root/install.sh" ]]; then
  exec bash "$session_log_root/install.sh" --harness claude --arguments "${ARGUMENTS:-status}"
fi
printf 'session-log: complete package is missing at %s\n' "$session_log_root" >&2
exit 1
```

No argument means `status`. `usage` prints Claude Code's native report without changing its fields. `on` may report `on — restart required`; restart Claude Code before relying on logging.
