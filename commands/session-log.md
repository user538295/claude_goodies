---
description: Manage session prompt logging (on / off / status)
---

Enable, disable, or check the status of prompt logging.

**Usage:** `/session-log [on|off|status]`

Read `$ARGUMENTS` and act:

### on — Enable logging

1. Run: `mkdir -p "$HOME/.claude/prompt-logs" && touch "$HOME/.claude/prompt-logs/.enabled"`
2. Print:
   ```
   ✓ Session logging enabled.
   Logs: ~/.claude/prompt-logs/
   ```

### off — Disable logging

1. Run: `rm -f "$HOME/.claude/prompt-logs/.enabled"`
2. Print:
   ```
   ✓ Session logging disabled.
   ```

### status — Show current state (default when no argument given)

1. Run: `[ -f "$HOME/.claude/prompt-logs/.enabled" ] && echo on || echo off`
2. Print:
   - If on: `Session logging: on\nLog directory: ~/.claude/prompt-logs/`
   - If off: `Session logging: off\nRun /session-log on to enable.`
