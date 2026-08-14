---
description: Manage session prompt logging (on / off / status)
---

Enable, disable, or check the status of prompt logging.

**Usage:** `/session-log [on|off|status]`

Read `$ARGUMENTS` and act:

### on — Enable logging

1. Run `echo "$CLAUDE_PLUGIN_ROOT"` to get the plugin directory. If empty or unset, print an error: "Cannot locate plugin scripts. Please reinstall the plugin from the marketplace." and stop.
2. The scripts directory is `$CLAUDE_PLUGIN_ROOT/scripts`.
3. Read `~/.claude/settings.json`. If the file does not exist, treat it as `{}`.
4. Under the top-level `"hooks"` key, add these two entries (preserve everything else):
   - `SessionStart` / matcher `"startup"`: command `bash "$CLAUDE_PLUGIN_ROOT/scripts/prompt_log_new_session.sh"` (substitute the actual resolved path)
   - `UserPromptSubmit` (no matcher): command `bash "$CLAUDE_PLUGIN_ROOT/scripts/prompt_log_save.sh"` (substitute the actual resolved path)
   Skip any entry already present (check by looking for `prompt_log_new_session.sh` / `prompt_log_save.sh` in existing hook commands).
5. Write the updated JSON back to `~/.claude/settings.json` atomically (write to a temp file, then move).
6. Print:
   ```
   ✓ Session logging enabled.
   Logs: ~/.claude/prompt-logs/
   Restart Claude Code for hooks to take effect.
   ```

### off — Disable logging

1. Read `~/.claude/settings.json`. If it does not exist, print "Session logging was not enabled." and stop.
2. Remove any hook entries whose `command` contains `prompt_log_new_session.sh` or `prompt_log_save.sh`.
3. Clean up: remove empty hook arrays and empty hook group objects.
4. Write the updated JSON back atomically.
5. Print:
   ```
   ✓ Session logging disabled.
   Restart Claude Code for the change to take effect.
   ```

### status — Show current state (default)

1. Read `~/.claude/settings.json`. If it does not exist, logging is off.
2. Check if any hook command contains `prompt_log_new_session.sh` or `prompt_log_save.sh`.
3. Print:
   - If on: `Session logging: on\nLog directory: ~/.claude/prompt-logs/`
   - If off: `Session logging: off\nRun /session-log on to enable.`
