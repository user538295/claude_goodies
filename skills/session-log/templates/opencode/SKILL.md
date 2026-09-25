---
name: session-log
description: Manage session prompt logging and usage totals (on / off / status / usage)
---
<!-- universal-session-log: managed -->

Run the shared session-log CLI through OpenCode's native skill entrypoint. Do not infer a harness from files, directories, or environment variables.

```bash
session_log_root="$HOME/.config/opencode/skills/session-log"
if [[ -f "$session_log_root/install.sh" ]]; then
  exec bash "$session_log_root/install.sh" --harness opencode --arguments "${ARGUMENTS:-status}"
fi
printf 'session-log: complete package is missing at %s\n' "$session_log_root" >&2
exit 1
```

No argument means `status`. `usage` prints OpenCode's native report without changing its fields. `on` may report `on — restart required`; restart OpenCode before relying on logging.
