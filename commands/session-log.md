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
3. If on, run the aggregator for the current session and show its output verbatim — do NOT reformat it:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}"/scripts/prompt_log_usage.sh --latest
   ```
   It prints one `est. used token:` line per request, one per sub-agent transcript, and a `TOTAL` line. Instead of `--latest` it also takes a session id or a transcript path; add `--check` to compare our total against `ccusage session` when ccusage is installed. If `${CLAUDE_PLUGIN_ROOT}` is unset or the script is missing, skip this step silently — do not report an error.

## What a logged request looks like

`prompt_log_save.sh` (UserPromptSubmit) writes the prompt; `prompt_log_stop.sh` (Stop) appends the response and the measurements; `prompt_log_subagent.sh` (SubagentStop) appends one line per finished sub-agent:

```
## 14:02:11

<prompt>

---

14:03:05 sub-agent finished: general-purpose (agent-9f3c2a1b), jsonl: /Users/…/<sid>/subagents/agent-9f3c2a1b.jsonl

### 14:05:53 response

<last_assistant_message verbatim>

working time: 00:03:42
est. used token: input: 2000, output: 1000, cache_create: 150000, cache_read: 0, total_tokens: 153000, price: $2.32, model: claude-fable-5, effort: max
switched: model claude-sonnet-4-6 → claude-fable-5, effort high → max

---
```

- `total_tokens` = input + output + cache_create + cache_read; `cache_create` = 5m + 1h cache writes.
- Prices come from the static table `scripts/prompt_log_prices.json`, so they are estimates — hence `est.`. An unknown model contributes $0 and gets a `?` suffix.
- `switched:` appears only when the model or effort differs from the previous request.
- Grep anchors: `^### .* response$`, `^est\. used token:`, `^switched:`, `sub-agent finished:`.
