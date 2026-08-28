#!/usr/bin/env bash
# End-to-end test for the session-log hook scripts and the lib helpers.
# The scripts only ever touch "$HOME/.claude/...", so overriding HOME gives a
# complete sandbox — nothing here reads or writes the real prompt logs.
#
# Run: bash scripts/tests/test_prompt_log_hooks.sh
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/scripts"
FAIL=0

export TZ=UTC
WORKROOT="$(mktemp -d)"
trap 'cd /; rm -rf "$WORKROOT"' EXIT
export HOME="$WORKROOT"
mkdir -p "$HOME/.claude/prompt-logs" "$HOME/.claude/session-maps" "$WORKROOT/logs"
touch "$HOME/.claude/prompt-logs/.enabled"

fail() { echo "FAIL: $1"; FAIL=1; }

assert_eq() { # label expected actual
  if [ "$2" != "$3" ]; then
    fail "$1"
    echo "  expected: [$2]"
    echo "  actual:   [$3]"
  fi
}

assert_grep() { # label regex file
  grep -Eq "$2" "$3" || { fail "$1"; echo "  regex: $2"; echo "  file:  $(cat "$3")"; }
}

refute_grep() { # label regex file
  if grep -Eq "$2" "$3"; then fail "$1"; echo "  unexpected match: $2"; fi
}

mk_log() { # sid -> creates the session map + an empty log, echoes the log path
  local sid="$1"
  local log="$WORKROOT/logs/session_$sid.md"
  : > "$log"
  printf '%s\n' "$log" > "$HOME/.claude/session-maps/$sid"
  printf '%s' "$log"
}

# Canonical fixture turn: fable-5 / max, cache-reset shape.
#   2000*10 + 1000*50 + 100000*10*1.25 + 50000*10*2
#   = 20000 + 50000 + 1250000 + 1000000 = 2320000 -> 232 cents = $2.32
#   tokens 2000+1000+150000+0 = 153000
EST='est\. used token: input: 2000, output: 1000, cache_create: 150000, cache_read: 0, total_tokens: 153000, price: \$2\.32, model: claude-fable-5, effort: max'
TRANSCRIPT="$WORKROOT/transcript.jsonl"
{
  printf '{"type":"user","timestamp":"2026-08-28T10:00:00.000Z","promptSource":"typed","isMeta":false,"message":{"role":"user","content":"do the thing"}}\n'
  printf '{"type":"assistant","timestamp":"2026-08-28T10:00:20.000Z","effort":"max","requestId":"req_1","message":{"id":"msg_1","model":"claude-fable-5","role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":2000,"output_tokens":1000,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":100000,"ephemeral_1h_input_tokens":50000},"speed":"standard"}}}\n'
} > "$TRANSCRIPT"

stop_payload() { # sid transcript_path [agent_id]
  printf '{"session_id":"%s","transcript_path":"%s","last_assistant_message":"Done: **all good**\\nsecond line","effort":{"level":"max"}%s}\n' \
    "$1" "$2" "${3:+,\"agent_id\":\"$3\"}"
}

# ------------------------------------------------- prompt_log_save.sh --------
sid_save="aaaaaaaa-0000-0000-0000-000000000001"
mkdir -p "$WORKROOT/proj"
printf '{"session_id":"%s","prompt":"hello world","cwd":"%s"}\n' "$sid_save" "$WORKROOT/proj" \
  | bash "$SCRIPTS/prompt_log_save.sh" > "$WORKROOT/save.out" 2>"$WORKROOT/save.err"
assert_eq "save.sh writes nothing to stdout" "" "$(cat "$WORKROOT/save.out")"
save_log="$(cat "$HOME/.claude/session-maps/$sid_save" 2>/dev/null || true)"
if [ -z "$save_log" ] || [ ! -f "$save_log" ]; then
  fail "save.sh did not create a session log (stderr: $(cat "$WORKROOT/save.err"))"
else
  assert_grep "save.sh appends the prompt heading" '^## [0-9]{2}:[0-9]{2}:[0-9]{2}$' "$save_log"
  assert_grep "save.sh appends the prompt text" '^hello world$' "$save_log"
fi
pstart_file="$HOME/.claude/session-maps/$sid_save.pstart"
if [ ! -f "$pstart_file" ]; then
  fail "save.sh did not write <sid>.pstart"
else
  pstart="$(cat "$pstart_file")"
  case "$pstart" in
    ''|*[!0-9]*) fail "<sid>.pstart is not an epoch: [$pstart]" ;;
    *) [ "$pstart" -gt 1700000000 ] || fail "<sid>.pstart looks wrong: [$pstart]" ;;
  esac
fi

# ------------------------------------------------- prompt_log_stop.sh --------
# Normal turn: response block, working time from .pstart, est-line, switch line.
sid1="bbbbbbbb-0000-0000-0000-000000000001"
log1="$(mk_log "$sid1")"
# 13262s = 3h41m02s -> 03:41:02 (the clock may tick once mid-run, hence 0[0-9]).
printf '%s\n' "$(( $(date +%s) - 13262 ))" > "$HOME/.claude/session-maps/$sid1.pstart"
printf '%s\n' "claude-sonnet-4-6 high" > "$HOME/.claude/session-maps/$sid1.last"
stop_payload "$sid1" "$TRANSCRIPT" | bash "$SCRIPTS/prompt_log_stop.sh" > "$WORKROOT/stop.out" 2>/dev/null
rc=$?
assert_eq "stop.sh exits 0" "0" "$rc"
assert_eq "stop.sh writes nothing to stdout" "" "$(cat "$WORKROOT/stop.out")"
assert_grep "stop.sh writes the response heading" '^### [0-9]{2}:[0-9]{2}:[0-9]{2} response$' "$log1"
assert_grep "stop.sh writes the response verbatim" '^Done: \*\*all good\*\*$' "$log1"
assert_grep "stop.sh keeps multi-line responses" '^second line$' "$log1"
assert_grep "stop.sh computes working time from .pstart" '^working time: 03:41:0[0-9]$' "$log1"
assert_grep "stop.sh writes the est-line" "^$EST\$" "$log1"
assert_grep "stop.sh writes the switch line" \
  '^switched: model claude-sonnet-4-6 → claude-fable-5, effort high → max$' "$log1"
assert_grep "stop.sh closes the block" '^---$' "$log1"
# Consumed by emptying, not deleting: these scripts never call rm.
assert_eq "stop.sh consumes <sid>.pstart" "0" \
  "$(wc -c < "$HOME/.claude/session-maps/$sid1.pstart" | tr -d ' ')"
assert_eq "stop.sh rewrites <sid>.last" "claude-fable-5 max" \
  "$(cat "$HOME/.claude/session-maps/$sid1.last")"

# Unchanged model+effort -> no switch line.
sid2="bbbbbbbb-0000-0000-0000-000000000002"
log2="$(mk_log "$sid2")"
printf '%s\n' "claude-fable-5 max" > "$HOME/.claude/session-maps/$sid2.last"
stop_payload "$sid2" "$TRANSCRIPT" | bash "$SCRIPTS/prompt_log_stop.sh" >/dev/null 2>&1
refute_grep "no switch line when model and effort are unchanged" '^switched:' "$log2"
assert_grep "est-line still written when nothing switched" "^$EST\$" "$log2"

# No .pstart (session-log enabled mid-session) -> working time from transcript:
# 10:00:00Z -> 10:00:20Z = 00:00:20.
sid3="bbbbbbbb-0000-0000-0000-000000000003"
log3="$(mk_log "$sid3")"
stop_payload "$sid3" "$TRANSCRIPT" | bash "$SCRIPTS/prompt_log_stop.sh" >/dev/null 2>&1
assert_grep "working time falls back to transcript timestamps" '^working time: 00:00:20$' "$log3"
refute_grep "no switch line without a previous .last" '^switched:' "$log3"

# Sub-agent Stop payload (agent_id present) -> the main hook must stay silent.
sid4="bbbbbbbb-0000-0000-0000-000000000004"
log4="$(mk_log "$sid4")"
stop_payload "$sid4" "$TRANSCRIPT" "9f3c2a1b" | bash "$SCRIPTS/prompt_log_stop.sh" > "$WORKROOT/sub.out" 2>&1
rc=$?
assert_eq "stop.sh exits 0 for a sub-agent payload" "0" "$rc"
assert_eq "stop.sh stays silent for a sub-agent payload" "" "$(cat "$WORKROOT/sub.out")"
assert_eq "stop.sh writes nothing for a sub-agent payload" "0" "$(wc -c < "$log4" | tr -d ' ')"

# Logging switched off -> nothing is written.
sid5="bbbbbbbb-0000-0000-0000-000000000005"
log5="$(mk_log "$sid5")"
mv "$HOME/.claude/prompt-logs/.enabled" "$HOME/.claude/prompt-logs/.disabled"
stop_payload "$sid5" "$TRANSCRIPT" | bash "$SCRIPTS/prompt_log_stop.sh" >/dev/null 2>&1
rc=$?
mv "$HOME/.claude/prompt-logs/.disabled" "$HOME/.claude/prompt-logs/.enabled"
assert_eq "stop.sh exits 0 when logging is off" "0" "$rc"
assert_eq "stop.sh writes nothing when logging is off" "0" "$(wc -c < "$log5" | tr -d ' ')"

# Unknown session (no session map) -> nothing written, exit 0.
sid6="bbbbbbbb-0000-0000-0000-000000000006"
stop_payload "$sid6" "$TRANSCRIPT" | bash "$SCRIPTS/prompt_log_stop.sh" > "$WORKROOT/nomap.out" 2>&1
rc=$?
assert_eq "stop.sh exits 0 without a session map" "0" "$rc"
assert_eq "stop.sh stays silent without a session map" "" "$(cat "$WORKROOT/nomap.out")"

# Unreadable transcript -> response and working time still logged, usage skipped.
sid7="bbbbbbbb-0000-0000-0000-000000000007"
log7="$(mk_log "$sid7")"
stop_payload "$sid7" "$WORKROOT/does-not-exist.jsonl" | bash "$SCRIPTS/prompt_log_stop.sh" >/dev/null 2>&1
rc=$?
assert_eq "stop.sh exits 0 with an unreadable transcript" "0" "$rc"
assert_grep "response is logged without a transcript" '^Done: \*\*all good\*\*$' "$log7"
assert_grep "working time is logged without a transcript" '^working time: [0-9]{2}:[0-9]{2}:[0-9]{2}$' "$log7"
refute_grep "no est-line without a transcript" '^est\. used token:' "$log7"

# Garbage stdin (induced jq failure) -> silent, exit 0.
printf 'not json at all\n' | bash "$SCRIPTS/prompt_log_stop.sh" > "$WORKROOT/garbage.out" 2>/dev/null
rc=$?
assert_eq "stop.sh exits 0 on garbage input" "0" "$rc"
assert_eq "stop.sh stays silent on garbage input" "" "$(cat "$WORKROOT/garbage.out")"

# ---------------------------------------------- prompt_log_subagent.sh -------
sid8="cccccccc-0000-0000-0000-000000000001"
log8="$(mk_log "$sid8")"
parent_dir="$WORKROOT/projects/-proj"
mkdir -p "$parent_dir/$sid8/subagents"
printf '{}\n' > "$parent_dir/$sid8/subagents/agent-9f3c2a1b.jsonl"
sub_payload() { # sid agent_id agent_type
  printf '{"session_id":"%s","transcript_path":"%s","agent_id":"%s","agent_type":"%s"}\n' \
    "$1" "$parent_dir/$1.jsonl" "$2" "$3"
}
sub_payload "$sid8" "9f3c2a1b" "general-purpose" | bash "$SCRIPTS/prompt_log_subagent.sh" > "$WORKROOT/sa.out" 2>/dev/null
rc=$?
assert_eq "subagent.sh exits 0" "0" "$rc"
assert_eq "subagent.sh writes nothing to stdout" "" "$(cat "$WORKROOT/sa.out")"
assert_grep "subagent.sh logs the finish line with the jsonl path" \
  "^[0-9]{2}:[0-9]{2}:[0-9]{2} sub-agent finished: general-purpose \(agent-9f3c2a1b\), jsonl: $parent_dir/$sid8/subagents/agent-9f3c2a1b\.jsonl\$" "$log8"

sid9="cccccccc-0000-0000-0000-000000000002"
log9="$(mk_log "$sid9")"
sub_payload "$sid9" "deadbeef" "Explore" | bash "$SCRIPTS/prompt_log_subagent.sh" >/dev/null 2>&1
assert_grep "subagent.sh marks a missing jsonl" ' \(not found\)$' "$log9"

printf 'not json at all\n' | bash "$SCRIPTS/prompt_log_subagent.sh" > "$WORKROOT/sa_garbage.out" 2>/dev/null
rc=$?
assert_eq "subagent.sh exits 0 on garbage input" "0" "$rc"
assert_eq "subagent.sh stays silent on garbage input" "" "$(cat "$WORKROOT/sa_garbage.out")"

# ------------------------------------------------------- hooks.json wiring ---
# The registered command strings must actually resolve ${CLAUDE_PLUGIN_ROOT}
# and run the script. Single-quoting it — the form shipped up to 1.7.2 — leaves
# the path literal, so [ -f ] fails and every hook silently does nothing.
HOOKS_JSON="$REPO/hooks/hooks.json"
hook_cmd() { jq -r --arg ev "$1" '.hooks[$ev][0].hooks[0].command' "$HOOKS_JSON"; }

if jq -r '.hooks | to_entries[] | .value[].hooks[].command' "$HOOKS_JSON" | grep -q "s='"; then
  fail "hooks.json single-quotes \${CLAUDE_PLUGIN_ROOT}, so it never expands"
fi
assert_eq "Stop hook keeps its 30s timeout" "30" \
  "$(jq -r '.hooks.Stop[0].hooks[0].timeout' "$HOOKS_JSON")"
assert_eq "SubagentStop hook keeps its 15s timeout" "15" \
  "$(jq -r '.hooks.SubagentStop[0].hooks[0].timeout' "$HOOKS_JSON")"

sid_wired="dddddddd-0000-0000-0000-000000000001"
log_wired="$(mk_log "$sid_wired")"
printf '{"session_id":"%s","prompt":"wired prompt","cwd":"%s"}\n' "$sid_wired" "$WORKROOT/proj" \
  | CLAUDE_PLUGIN_ROOT="$REPO" bash -c "$(hook_cmd UserPromptSubmit)" >/dev/null 2>&1
assert_grep "UserPromptSubmit command string reaches the script" '^wired prompt$' "$log_wired"

stop_payload "$sid_wired" "$TRANSCRIPT" \
  | CLAUDE_PLUGIN_ROOT="$REPO" bash -c "$(hook_cmd Stop)" > "$WORKROOT/wired.out" 2>/dev/null
assert_eq "Stop command string exits 0" "0" "$?"
assert_eq "Stop command string writes no stdout" "" "$(cat "$WORKROOT/wired.out")"
assert_grep "Stop command string reaches the script" '^### [0-9]{2}:[0-9]{2}:[0-9]{2} response$' "$log_wired"
assert_grep "Stop command string produces the est-line" "^$EST\$" "$log_wired"

sub_payload "$sid_wired" "9f3c2a1b" "general-purpose" \
  | CLAUDE_PLUGIN_ROOT="$REPO" bash -c "$(hook_cmd SubagentStop)" >/dev/null 2>&1
assert_grep "SubagentStop command string reaches the script" 'sub-agent finished: general-purpose' "$log_wired"

# ------------------------------------------------------------ lib helpers ----
# shellcheck source=/dev/null
source "$SCRIPTS/prompt_log_lib.sh"
assert_eq "fmt_hms 13262" "03:41:02" "$(fmt_hms 13262)"   # 3*3600 + 41*60 + 2
assert_eq "fmt_hms 0" "00:00:00" "$(fmt_hms 0)"
assert_eq "fmt_hms clamps negatives" "00:00:00" "$(fmt_hms -5)"
assert_eq "fmt_hms 359999" "99:59:59" "$(fmt_hms 359999)"  # 99*3600 + 59*60 + 59

assert_eq "switch_line model only" "switched: model a → b" "$(switch_line a high b high)"
assert_eq "switch_line effort only" "switched: effort high → max" "$(switch_line a high a max)"
assert_eq "switch_line both" "switched: model a → b, effort high → max" "$(switch_line a high b max)"
assert_eq "switch_line no change" "" "$(switch_line a high a high)"
assert_eq "switch_line no previous state" "" "$(switch_line "" "" b max)"
# A half with no previous value has no transition to render: a stale .last can
# hold "model " (empty effort), which must not print "effort  → high".
assert_eq "switch_line skips effort with no previous effort" "" "$(switch_line a "" a high)"
assert_eq "switch_line skips model with no previous model" "" "$(switch_line "" high b high)"
assert_eq "switch_line still reports the known half" "switched: model a → b" \
  "$(switch_line a "" b high)"

assert_eq "resolve_project_key mangles / . and _" \
  "-Users-x-dev-my-proj-a" "$(resolve_project_key /Users/x/dev/my.proj_a)"
real_key="$(resolve_project_key "$REPO")"
if [ -n "$real_key" ] && [ -d "/Users/$(id -un)/.claude/projects/$real_key" ]; then
  echo "resolve_project_key matches this repo's real transcript dir"
else
  echo "note: no real transcript dir for this repo — slug shape checked only"
fi

echo "hook checks done"
[ "$FAIL" -eq 0 ] && echo "passed" || echo "FAILED"
exit "$FAIL"
