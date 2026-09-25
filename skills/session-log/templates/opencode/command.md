---
description: Manage session prompt logging and usage totals (on / off / status / usage)
---
<!-- universal-session-log: managed -->

Read `$ARGUMENTS` and run the shared session-log CLI through OpenCode's native command entrypoint. Do not infer a harness from files, directories, or environment variables.

```bash
session_log_root="$HOME/.config/opencode/skills/session-log"
if [[ -f "$session_log_root/install.sh" ]]; then
  exec bash "$session_log_root/install.sh" --harness opencode --arguments "${ARGUMENTS:-status}"
fi
printf 'session-log: complete package is missing at %s\n' "$session_log_root" >&2
exit 1
```

No argument means `status`. `usage` passes OpenCode's native report through unchanged after the one-line harness label. `on` may report `on — restart required`; restart OpenCode before relying on logging.
