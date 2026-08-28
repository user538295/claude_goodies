---
name: session-log
description: Manage session prompt logging and usage totals (on / off / status / usage)
---

Enable, disable, or check prompt logging, and total the current session's usage.

**Usage:** `/session-log [on|off|status|usage]`

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
   - If on: `Session logging: on\nLog directory: ~/.claude/prompt-logs/\nRun /session-log usage for the session's working-time and token/price totals.`
   - If off: `Session logging: off\nRun /session-log on to enable.`

### usage — Total the current session (main agent + every sub-agent)

1. Resolve and run the aggregator and print its stdout verbatim inside a ```text fence — do NOT reformat, realign, summarize, or drop fields. When the user supplied extra arguments (a session id, a transcript path, `--check`), pass them through in place of `--latest`:
   ```
   p="${CLAUDE_PLUGIN_ROOT:-}"; [ -n "$p" ] || p=$(jq -r 'first(.plugins | to_entries[] | select(.key | startswith("claude-goodies@")) | .value[0].installPath) // empty' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null); [ -f "$p/skills/session-log/scripts/prompt_log_usage.sh" ] || p="$HOME/.claude"; bash "$p/skills/session-log/scripts/prompt_log_usage.sh" --latest
   ```
2. It prints one block per request (`N. HH:MM:SS (working time HH:MM:SS) "prompt head"` plus an `est. used token:` line), one line per sub-agent transcript (with the sub-agent's own working time, then its est-line), an `internal helpers:` line when helper agents ran (informational only), and a `TOTAL` block: request/sub-agent counts, `working time:` — the sum of the request durations; sub-agents run in parallel, so their time is not added — and the merged `est. used token:` line covering main + all sub-agents. `--check` compares that total against `ccusage session` when ccusage is installed. If the resolution finds no script — no plugin install and no synced copy — skip this step silently; do not report an error.

## What a logged request looks like

`prompt_log_save.sh` (UserPromptSubmit) writes the prompt; `prompt_log_stop.sh` (Stop) appends the response and the measurements; `prompt_log_subagent.sh` (SubagentStop) appends one line per finished sub-agent:

```
## 14:02:11

<prompt>

---

14:03:05 sub-agent finished: general-purpose (agent-9f3c2a1b), working time: 00:02:05, est. used token: input: 9, output: 10259, cache_create: 53763, cache_read: 276799, total_tokens: 340830, price: $0.56, model: claude-sonnet-4-6, effort: medium, jsonl: /Users/…/<sid>/subagents/agent-9f3c2a1b.jsonl

### 14:05:53 response

<last_assistant_message verbatim>

working time: 00:03:42
est. used token: input: 2000, output: 1000, cache_create: 150000, cache_read: 0, total_tokens: 153000, price: $2.32, model: claude-fable-5, effort: max
switched: model claude-sonnet-4-6 → claude-fable-5, effort high → max

---
```

- The response block's `working time:` and `est. used token:` are **cumulative for the current request** and cover the **main agent only**: background-task notifications restart the turn, so one prompt can produce several response blocks whose numbers grow until the next prompt resets them. Sub-agent usage is on the sub-agent lines, not in the response block.
- A sub-agent line carries the sub-agent's own working time and usage, computed from its transcript. A typed sub-agent whose transcript is missing keeps a short line with a ` (not found)` marker.
- Internal helper agents (no transcript anywhere) are not logged but are counted: `/session-log usage` prints one `internal helpers:` line with their count, cumulative run time, and tool calls. Their token usage is not recorded client-side, so they are never priced, and their runtime is never added to the TOTAL — they run concurrently inside the requests' wall time.
- The time rule: a request's `working time:` runs from the prompt to the last assistant output; the TOTAL `working time:` is the sum of the request times. Parallel runtimes (sub-agents, helpers) are shown for information only and never summed into it.
- `total_tokens` = input + output + cache_create + cache_read; `cache_create` = 5m + 1h cache writes.
- Prices come from the static table `skills/session-log/scripts/prompt_log_prices.json`, so they are estimates — hence `est.`. An unknown model contributes $0 and gets a `?` suffix.
- `switched:` appears only when the model or effort differs from the previous request.
- Grep anchors: `^### .* response$`, `^est\. used token:` and `^working time:` (response lines only — on sub-agent lines both sit mid-line by design), `^switched:`, `sub-agent finished:`, `^internal helpers:` (aggregator output only).
