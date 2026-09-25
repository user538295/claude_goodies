---
name: session-log
description: Manage session prompt logging and usage totals (on / off / status / usage)
user-invocable: true
---
<!-- universal-session-log: managed -->

Run the shared session-log CLI through OMP's native skill entrypoint. Do not infer a harness from files, directories, or environment variables.

```bash
session_log_root="$HOME/.omp/agent/skills/session-log"
if [[ -f "$session_log_root/install.sh" ]]; then
  exec bash "$session_log_root/install.sh" --harness omp --arguments "${ARGUMENTS:-status}"
fi
printf 'session-log: complete package is missing at %s\n' "$session_log_root" >&2
exit 1
```

No argument means `status`. `usage` prints OMP's native report without changing its fields. `on` may report `on — restart required`; restart OMP before relying on logging. A run started with `--no-session` has no reconstructable native usage report.
