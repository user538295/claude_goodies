#!/usr/bin/env bash
# Golden test for the shared usage/price engine (scripts/prompt_log_usage.jq)
# and the aggregator CLI (scripts/prompt_log_usage.sh), over a synthetic
# session tree: one main transcript + four sub-agent transcripts (cascaded
# spawnDepth 0/1/2 plus one under workflows/**).
#
# Every expected number below is hand-computed from the price table in
# scripts/prompt_log_prices.json using
#   cents = (in*r_in + out*r_out + cache_read*r_in/10
#            + cache_5m*r_in*1.25 + cache_1h*r_in*2) / 10000
# (r_* are $/MTok, so tokens*rate = dollars*1e6 = cents*1e4).
#
# Run: bash scripts/tests/test_prompt_log_usage.sh
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO/scripts"
ENGINE="$SCRIPTS/prompt_log_usage.jq"
PRICES="$SCRIPTS/prompt_log_prices.json"
AGG="$SCRIPTS/prompt_log_usage.sh"
FAIL=0

# Local time appears in aggregator output; pin it so goldens are stable.
export TZ=UTC

WORKROOT="$(mktemp -d)"
trap 'cd /; rm -rf "$WORKROOT"' EXIT

fail() { echo "FAIL: $1"; FAIL=1; }

assert_eq() { # label expected actual
  if [ "$2" != "$3" ]; then
    fail "$1"
    echo "  expected: $2"
    echo "  actual:   $3"
  fi
}

assert_match() { # label regex actual
  if ! printf '%s' "$3" | grep -Eq "$2"; then
    fail "$1"
    echo "  regex:  $2"
    echo "  actual: $3"
  fi
}

engine() { # mode file... -> engine stdout
  local mode="$1"; shift
  cat "$@" | jq -n -R -r -f "$ENGINE" --arg mode "$mode" --slurpfile P "$PRICES"
}

# ---------------------------------------------------------------- fixtures --
# asst <ts> <id> <model> <effort> <in> <out> <cache_read> <c5m> <c1h> <speed>
asst() {
  printf '{"type":"assistant","timestamp":"%s","effort":"%s","requestId":"req_%s","isSidechain":false,"message":{"id":"%s","model":"%s","role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"answer"}],"usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s},"service_tier":"standard","speed":"%s"}}}\n' \
    "$1" "$4" "$2" "$2" "$3" "$5" "$6" "$7" "$8" "$9" "${10}"
}

# usr <ts> <promptSource-as-json> <isMeta> <content-as-json>
usr() {
  printf '{"type":"user","timestamp":"%s","promptSource":%s,"isMeta":%s,"message":{"role":"user","content":%s}}\n' \
    "$1" "$2" "$3" "$4"
}

PROJ_CWD="$WORKROOT/proj"
mkdir -p "$PROJ_CWD"
PKEY="$(printf '%s' "$PROJ_CWD" | sed 's|[/._]|-|g')"
PDIR="$WORKROOT/.claude/projects/$PKEY"
SID="11111111-2222-3333-4444-555555555555"
mkdir -p "$PDIR/$SID/subagents/workflows/wf_x"
MAIN="$PDIR/$SID.jsonl"

{
  # -- req1: dedupe (msg_a has 3 content blocks with ONE id), a <synthetic>
  #    entry, and a tool_result user entry that must not open a segment.
  #    counted: msg_a 100000/50000/cr 300000/5m 20000  +  msg_b 10000/5000
  #    => in 110000, out 55000, cc 20000, cr 300000, total 485000
  #    sonnet-4-6 = 3/15:
  #      110000*3 + 55000*15 + 300000*3/10 + 20000*3*1.25
  #      = 330000 + 825000 + 90000 + 75000 = 1320000 -> 132 cents = $1.32
  usr '2026-08-28T10:00:00.123Z' '"typed"' 'false' '"first prompt\nwith newline"'
  asst '2026-08-28T10:00:01.001Z' msg_a claude-sonnet-4-6 high 100000 50000 300000 20000 0 standard
  asst '2026-08-28T10:00:02.500Z' msg_a claude-sonnet-4-6 high 100000 50000 300000 20000 0 standard
  asst '2026-08-28T10:00:03.750Z' msg_a claude-sonnet-4-6 high 100000 50000 300000 20000 0 standard
  asst '2026-08-28T10:00:04.000Z' msg_syn '<synthetic>' high 0 0 0 0 0 standard
  usr '2026-08-28T10:00:05.000Z' 'null' 'false' '[{"type":"tool_result","content":"ok"}]'
  asst '2026-08-28T10:00:10.000Z' msg_b claude-sonnet-4-6 high 10000 5000 0 0 0 standard
  asst '2026-08-28T10:00:11.000Z' msg_b claude-sonnet-4-6 high 10000 5000 0 0 0 standard

  # -- req2: opened by a "queued" prompt; the meta entry before it must not
  #    open a segment. Model switch + cache reset shape (cr 0, big writes).
  #    fable-5 = 10/50: 2000*10 + 1000*50 + 100000*10*1.25 + 50000*10*2
  #      = 20000 + 50000 + 1250000 + 1000000 = 2320000 -> 232 cents = $2.32
  #    tokens 2000+1000+150000+0 = 153000
  usr '2026-08-28T10:00:50.000Z' 'null' 'true' '"<command-name>/model</command-name>"'
  usr '2026-08-28T10:01:00.500Z' '"queued"' 'false' '"second prompt (queued)"'
  asst '2026-08-28T10:01:20.000Z' msg_c claude-fable-5 max 2000 1000 0 100000 50000 standard
  asst '2026-08-28T10:01:21.000Z' msg_c claude-fable-5 max 2000 1000 0 100000 50000 standard

  # -- req3: interrupted turn (stop_reason null) is still totaled; its long
  #    prompt exercises the 60-char head truncation.
  #    sonnet-5 = 3/15: 20000*3 + 10000*15 = 60000 + 150000 = 210000
  #      -> 21 cents = $0.21, tokens 30000
  usr '2026-08-28T10:02:00.000Z' '"typed"' 'false' '"third prompt interrupted with a very long text that must be truncated"'
  printf '{"type":"assistant","timestamp":"2026-08-28T10:02:30.000Z","effort":"low","requestId":"req_msg_d","message":{"id":"msg_d","model":"claude-sonnet-5","role":"assistant","stop_reason":null,"content":[{"type":"text","text":"partial"}],"usage":{"input_tokens":20000,"output_tokens":10000,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"speed":"standard"}}}\n'

  # -- req4: fast row (10/50) + standard row (5/25) inside one request.
  #    fast: 40000*10 + 20000*50 = 400000 + 1000000 = 1400000 -> 140 cents
  #    std : 40000*5  + 20000*25 = 200000 +  500000 =  700000 ->  70 cents
  #    => 210 cents = $2.10, in 80000, out 40000, tokens 120000
  usr '2026-08-28T10:03:00.000Z' '"typed"' 'false' '"fourth prompt fast"'
  asst '2026-08-28T10:03:10.000Z' msg_e claude-opus-5 high 40000 20000 0 0 0 fast
  asst '2026-08-28T10:03:20.000Z' msg_f claude-opus-5 high 40000 20000 0 0 0 standard

  # -- req5: no assistant entry at all -> all-zero est-line.
  usr '2026-08-28T10:04:00.000Z' '"typed"' 'false' '"fifth prompt no answer"'

  # -- req6: unknown model (=> $0 + "?"), legacy cache_creation_input_tokens
  #    (counts as 5m), missing cache_read (defaults to 0), and a trailing
  #    assistant entry with no usage object at all (must be skipped entirely,
  #    so claude-opus-4-8 must NOT appear in the model list).
  usr '2026-08-28T10:05:00.000Z' '"typed"' 'false' '"sixth prompt unknown model"'
  printf '{"type":"assistant","timestamp":"2026-08-28T10:05:30.000Z","effort":"high","requestId":"req_msg_g","message":{"id":"msg_g","model":"claude-test-9","role":"assistant","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":10000,"output_tokens":5000,"cache_creation_input_tokens":30000}}}\n'
  printf '{"type":"assistant","timestamp":"2026-08-28T10:05:40.000Z","effort":"high","message":{"id":"msg_h","model":"claude-opus-4-8","role":"assistant","content":[{"type":"text","text":"no usage"}]}}\n'
} > "$MAIN"

SUB="$PDIR/$SID/subagents"
# a1: spawnDepth 0, duplicate ids. haiku-4-5 = 1/5:
#   10000*1 + 2000*5 = 10000 + 10000 = 20000 -> 2 cents = $0.02, tokens 12000
{
  asst '2026-08-28T10:00:20.000Z' msg_s1 claude-haiku-4-5 high 10000 2000 0 0 0 standard
  asst '2026-08-28T10:00:21.000Z' msg_s1 claude-haiku-4-5 high 10000 2000 0 0 0 standard
} > "$SUB/agent-a1.jsonl"
printf '{"agentType":"general-purpose","description":"d","spawnDepth":0}\n' > "$SUB/agent-a1.meta.json"

# a2: spawnDepth 1, child of a1. sonnet-4-6 = 3/15:
#   50000*3 + 10000*15 + 100000*3/10 + 16000*3*1.25
#   = 150000 + 150000 + 30000 + 60000 = 390000 -> 39 cents = $0.39
#   tokens 50000+10000+16000+100000 = 176000
asst '2026-08-28T10:00:30.000Z' msg_s2 claude-sonnet-4-6 high 50000 10000 100000 16000 0 standard > "$SUB/agent-a2.jsonl"
printf '{"agentType":"Explore","description":"d","spawnDepth":1,"parentAgentId":"a1"}\n' > "$SUB/agent-a2.meta.json"

# a3: spawnDepth 2, child of a2. opus-5 = 5/25:
#   20000*5 + 4000*25 + 200000*5/10 + 10000*5*2
#   = 100000 + 100000 + 100000 + 100000 = 400000 -> 40 cents = $0.40
#   tokens 20000+4000+10000+200000 = 234000
asst '2026-08-28T10:00:40.000Z' msg_s3 claude-opus-5 max 20000 4000 200000 0 10000 standard > "$SUB/agent-a3.jsonl"
printf '{"agentType":"general-purpose","description":"d","spawnDepth":2,"parentAgentId":"a2"}\n' > "$SUB/agent-a3.meta.json"

# w1: under workflows/**, only reachable by recursion. sonnet-5 = 3/15:
#   30000*3 + 6000*15 = 90000 + 90000 = 180000 -> 18 cents = $0.18, tokens 36000
asst '2026-08-28T10:01:40.000Z' msg_w1 claude-sonnet-5 high 30000 6000 0 0 0 standard \
  > "$SUB/workflows/wf_x/agent-w1.jsonl"
printf '{"agentType":"workflow-step","description":"d","spawnDepth":1}\n' \
  > "$SUB/workflows/wf_x/agent-w1.meta.json"

# A second, older transcript so --latest has something to reject.
cp "$MAIN" "$PDIR/00000000-0000-0000-0000-000000000000.jsonl"
touch -t 202001010000 "$PDIR/00000000-0000-0000-0000-000000000000.jsonl"

# ------------------------------------------------------------ engine modes --
# Main-file total: in 110000+2000+20000+80000+10000 = 222000
#                  out 55000+1000+10000+40000+5000  = 111000
#                  cc  20000+150000+30000            = 200000
#                  cr  300000
#                  tokens 833000, cents 132+232+21+210+0 = 595 = $5.95
MAIN_TOTAL='est. used token: input: 222000, output: 111000, cache_create: 200000, cache_read: 300000, total_tokens: 833000, price: $5.95, model: claude-fable-5+claude-opus-5+claude-opus-5:fast+claude-sonnet-4-6+claude-sonnet-5+claude-test-9?, effort: high+low+max'
assert_eq "engine mode=total on main transcript" "$MAIN_TOTAL" "$(engine total "$MAIN")"

# mode=last -> req6 (unknown model). Fields: start, end, model, effort, line.
LAST_LINE='est. used token: input: 10000, output: 5000, cache_create: 30000, cache_read: 0, total_tokens: 45000, price: $0.00, model: claude-test-9?, effort: high'
last_rec="$(engine last "$MAIN")"
# US (\037), not tab: tab is IFS whitespace, so an empty model/effort field
# between two tabs would silently shift the est-line into the wrong variable.
IFS=$'\037' read -r l_start l_end l_model l_effort l_line <<EOF
$last_rec
EOF
# 2026-08-28T10:05:00Z = 1787911500, 10:05:40Z = 1787911540
assert_eq "mode=last segment start epoch" "1787911500" "$l_start"
assert_eq "mode=last segment end epoch" "1787911540" "$l_end"
assert_eq "mode=last model of last counted entry" "claude-test-9" "$l_model"
assert_eq "mode=last effort of last counted entry" "high" "$l_effort"
assert_eq "mode=last est-line" "$LAST_LINE" "$l_line"

# One record per typed/queued prompt — meta and tool_result users excluded.
assert_eq "mode=segments emits one record per prompt" "6" "$(engine segments "$MAIN" | wc -l | tr -d ' ')"

# TOTAL over every file = merge; must equal the arithmetic sum of the parts:
#   595 + 2 + 39 + 40 + 18 = 694 cents = $6.94
#   in  222000+10000+50000+20000+30000 = 332000
#   out 111000+2000+10000+4000+6000    = 133000
#   cc  200000+0+16000+10000+0         = 226000
#   cr  300000+0+100000+200000+0       = 600000  => tokens 1291000
TOTAL_LINE='est. used token: input: 332000, output: 133000, cache_create: 226000, cache_read: 600000, total_tokens: 1291000, price: $6.94, model: claude-fable-5+claude-haiku-4-5+claude-opus-5+claude-opus-5:fast+claude-sonnet-4-6+claude-sonnet-5+claude-test-9?, effort: high+low+max'
assert_eq "engine mode=merge over main + 4 sub-agents" "$TOTAL_LINE" \
  "$(engine merge "$MAIN" "$SUB/agent-a1.jsonl" "$SUB/agent-a2.jsonl" "$SUB/agent-a3.jsonl" "$SUB/workflows/wf_x/agent-w1.jsonl")"

# A corrupt line must be skipped, not abort the run.
cp "$MAIN" "$WORKROOT/corrupt.jsonl"
printf 'this is not json\n' >> "$WORKROOT/corrupt.jsonl"
assert_eq "corrupt line is skipped" "$MAIN_TOTAL" "$(engine total "$WORKROOT/corrupt.jsonl")"

# ------------------------------------------------------- headless / SDK mode --
# Headless runs (claude -p, the SDK, cron) mark prompts promptSource "sdk", and
# they carry no effort anywhere — hence "effort: unknown". CC also injects
# <task-notification> back into the session as a user entry that is shaped
# EXACTLY like a real sdk prompt (promptSource "sdk", isMeta unset), so only the
# opening tag tells them apart. Real prompts do sometimes start with "<" (six
# "<Role…" prompts exist in this machine's transcripts), so the guard is
# anchored on the exact tag and never on a bare "<".
#
# haiku-4-5 = 1/5:
#   req1 = 10000+20000 in, 2000+4000 out -> 30000*1 + 6000*5 = 60000 -> $0.06
#   req2 = 5000 in, 1000 out             ->  5000*1 + 1000*5 = 10000 -> $0.01
#   file total                           -> 35000*1 + 7000*5 = 70000 -> $0.07
HEADLESS="$WORKROOT/headless.jsonl"
hasst() { # ts id in out — headless entries carry no effort field at all
  printf '{"type":"assistant","timestamp":"%s","requestId":"req_%s","message":{"id":"%s","model":"claude-haiku-4-5","role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"a"}],"usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"speed":"standard"}}}\n' \
    "$1" "$2" "$2" "$3" "$4"
}
{
  usr '2026-08-28T10:00:00.000Z' '"sdk"' 'false' '"headless one"'
  hasst '2026-08-28T10:00:10.000Z' msg_h1 10000 2000
  usr '2026-08-28T10:00:20.000Z' 'null' 'false' '[{"type":"tool_result","content":"ok"}]'
  usr '2026-08-28T10:00:30.000Z' '"sdk"' 'false' '"<task-notification>\n<task-id>a164</task-id>\n<status>completed</status>\n</task-notification>"'
  hasst '2026-08-28T10:00:40.000Z' msg_h2 20000 4000
  usr '2026-08-28T10:01:00.000Z' '"sdk"' 'false' '"headless two"'
  hasst '2026-08-28T10:01:10.000Z' msg_h3 5000 1000
} > "$HEADLESS"

H1='est. used token: input: 30000, output: 6000, cache_create: 0, cache_read: 0, total_tokens: 36000, price: $0.06, model: claude-haiku-4-5, effort: unknown'
H2='est. used token: input: 5000, output: 1000, cache_create: 0, cache_read: 0, total_tokens: 6000, price: $0.01, model: claude-haiku-4-5, effort: unknown'

# Two sdk prompts -> exactly two requests. Before sdk was accepted this was 0;
# if the injected notification split too it would be 3.
assert_eq "sdk prompts segment the session" "2" \
  "$(engine segments "$HEADLESS" | wc -l | tr -d ' ')"
assert_eq "the injected task-notification does not open a request" "$H1" \
  "$(engine segments "$HEADLESS" | sed -n '1p' | cut -d"$(printf '\037')" -f3)"
assert_eq "second sdk request is totaled on its own" "$H2" \
  "$(engine segments "$HEADLESS" | sed -n '2p' | cut -d"$(printf '\037')" -f3)"
# The Stop hook uses mode=last: it must report the LAST request, not the running
# session total ($0.07) — the defect seen in headless session 6c4e5d92.
assert_eq "mode=last on a headless transcript reports one request, not the total" "$H2" \
  "$(engine last "$HEADLESS" | cut -d"$(printf '\037')" -f5)"
assert_eq "headless file total still counts every entry" \
  'est. used token: input: 35000, output: 7000, cache_create: 0, cache_read: 0, total_tokens: 42000, price: $0.07, model: claude-haiku-4-5, effort: unknown' \
  "$(engine total "$HEADLESS")"

# ---------------------------------------------------------------- aggregator --
cat > "$WORKROOT/expected.txt" <<'EOF'
session: <sid>.jsonl

1. 10:00:00 "first prompt with newline"
est. used token: input: 110000, output: 55000, cache_create: 20000, cache_read: 300000, total_tokens: 485000, price: $1.32, model: claude-sonnet-4-6, effort: high
2. 10:01:00 "second prompt (queued)"
est. used token: input: 2000, output: 1000, cache_create: 150000, cache_read: 0, total_tokens: 153000, price: $2.32, model: claude-fable-5, effort: max
3. 10:02:00 "third prompt interrupted with a very long text that must be"
est. used token: input: 20000, output: 10000, cache_create: 0, cache_read: 0, total_tokens: 30000, price: $0.21, model: claude-sonnet-5, effort: low
4. 10:03:00 "fourth prompt fast"
est. used token: input: 80000, output: 40000, cache_create: 0, cache_read: 0, total_tokens: 120000, price: $2.10, model: claude-opus-5+claude-opus-5:fast, effort: high
5. 10:04:00 "fifth prompt no answer"
est. used token: input: 0, output: 0, cache_create: 0, cache_read: 0, total_tokens: 0, price: $0.00, model: -, effort: -
6. 10:05:00 "sixth prompt unknown model"
est. used token: input: 10000, output: 5000, cache_create: 30000, cache_read: 0, total_tokens: 45000, price: $0.00, model: claude-test-9?, effort: high

sub-agent: general-purpose (agent-a1), jsonl: <sid>/subagents/agent-a1.jsonl
est. used token: input: 10000, output: 2000, cache_create: 0, cache_read: 0, total_tokens: 12000, price: $0.02, model: claude-haiku-4-5, effort: high
sub-agent: Explore (agent-a2), jsonl: <sid>/subagents/agent-a2.jsonl
est. used token: input: 50000, output: 10000, cache_create: 16000, cache_read: 100000, total_tokens: 176000, price: $0.39, model: claude-sonnet-4-6, effort: high
sub-agent: general-purpose (agent-a3), jsonl: <sid>/subagents/agent-a3.jsonl
est. used token: input: 20000, output: 4000, cache_create: 10000, cache_read: 200000, total_tokens: 234000, price: $0.40, model: claude-opus-5, effort: max
sub-agent: workflow-step (agent-w1), jsonl: <sid>/subagents/workflows/wf_x/agent-w1.jsonl
est. used token: input: 30000, output: 6000, cache_create: 0, cache_read: 0, total_tokens: 36000, price: $0.18, model: claude-sonnet-5, effort: high

TOTAL (6 requests, 4 sub-agents)
est. used token: input: 332000, output: 133000, cache_create: 226000, cache_read: 600000, total_tokens: 1291000, price: $6.94, model: claude-fable-5+claude-haiku-4-5+claude-opus-5+claude-opus-5:fast+claude-sonnet-4-6+claude-sonnet-5+claude-test-9?, effort: high+low+max
EOF

normalize() { sed -e "s|$PDIR/||g" -e "s|$SID|<sid>|g"; }

HOME="$WORKROOT" bash "$AGG" "$MAIN" > "$WORKROOT/by_path.txt" 2>"$WORKROOT/by_path.err"
if ! normalize < "$WORKROOT/by_path.txt" > "$WORKROOT/by_path.norm"; then :; fi
if ! diff -u "$WORKROOT/expected.txt" "$WORKROOT/by_path.norm"; then
  fail "aggregator output differs from the golden (explicit path)"
  echo "  stderr: $(cat "$WORKROOT/by_path.err")"
fi

HOME="$WORKROOT" bash "$AGG" "$SID" > "$WORKROOT/by_sid.txt" 2>&1
assert_eq "aggregator resolves a bare session id to the same output" \
  "$(cat "$WORKROOT/by_path.txt")" "$(cat "$WORKROOT/by_sid.txt")"

(cd "$PROJ_CWD" && HOME="$WORKROOT" bash "$AGG" --latest) > "$WORKROOT/latest.txt" 2>&1
assert_eq "--latest picks the newest transcript of the current project" \
  "$(cat "$WORKROOT/by_path.txt")" "$(cat "$WORKROOT/latest.txt")"

# TOTAL must equal the arithmetic sum of every est-line printed above it.
sum_cents() { # reads est-lines, prints summed cents
  sed -n 's/.*price: \$\([0-9]*\)\.\([0-9][0-9]\).*/\1 \2/p' | awk '{s += $1 * 100 + $2} END {print s+0}'
}
parts_cents="$(grep '^est\. used token:' "$WORKROOT/by_path.txt" | head -10 | sum_cents)"
total_cents="$(grep '^est\. used token:' "$WORKROOT/by_path.txt" | tail -1 | sum_cents)"
assert_eq "TOTAL equals the sum of the per-part est-lines" "$parts_cents" "$total_cents"

# --check with ccusage absent from PATH: a note, not a failure.
check_out="$(cd "$PROJ_CWD" && PATH=/usr/bin:/bin HOME="$WORKROOT" bash "$AGG" "$MAIN" --check 2>&1)"
check_rc=$?
assert_eq "--check exits 0 when ccusage is missing" "0" "$check_rc"
assert_match "--check prints a skip note when ccusage is missing" \
  '^check: ccusage not installed' "$(printf '%s' "$check_out" | grep '^check:')"

# Unknown argument / missing file must fail loudly (this is a CLI, not a hook).
if (HOME="$WORKROOT" bash "$AGG" "$WORKROOT/nope.jsonl" >/dev/null 2>&1); then
  fail "aggregator should exit non-zero for a missing transcript"
fi

echo "engine+aggregator checks done"
[ "$FAIL" -eq 0 ] && echo "passed" || echo "FAILED"
exit "$FAIL"
