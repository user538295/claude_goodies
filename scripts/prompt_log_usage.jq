# Token/price engine shared by the session-log Stop hook and the aggregator CLI.
#
# Input : Claude transcript JSONL on stdin, read as raw lines (jq -n -R) so a
#         truncated or corrupt line is skipped instead of aborting the run.
# Args  : --arg mode last|segments|total|merge
#         --slurpfile P scripts/prompt_log_prices.json
# Output: fields are separated by US (\u001f), never by tab — an empty field
#         between two tabs is swallowed by the shell's `read`.
#         last     -> "<start_epoch>US<end_epoch>US<model>US<effort>US<est-line>"
#         segments -> one "<HH:MM:SS>US<prompt head>US<est-line>" per request
#         total    -> one "<est-line>" for the whole stream
#         merge    -> same accumulation as total, used when several transcripts
#                     are concatenated: the id dedupe then also collapses an
#                     entry that shows up in more than one file.
#
# One API response is written to the transcript once per content block, each
# copy carrying the same message.usage, so entries are deduped by message.id
# (falling back to requestId, then the line number) before anything is counted.

def US: "\u001f";
def prices: $P[0];

# Longest matching table key wins, so dated ids ("opus-4-8-20260101") and
# Bedrock-style ids ("us.anthropic.claude-opus-5-v1:0") both resolve.
# null = model not in the table -> priced as $0 and marked "?" in the output.
def rate($model; $fast):
  if $fast then prices.fast
  else
    ($model | sub(".*claude-"; "")) as $m
    | ( prices.per_mtok
        | to_entries
        | map(. as $e | select($m | contains($e.key)))
        | sort_by(.key | length)
        | last )
    | if . == null then null else .value end
  end;

# tokens * ($/MTok) = dollars * 1e6 = cents * 1e4.
def bucket_cents:
  rate(.model; .fast) as $r
  | if $r == null then 0
    else ( (.in * $r.in)
           + (.out * $r.out)
           + (.cr * $r.in * prices.mult.cache_read)
           + (.c5m * $r.in * prices.mult.cache_5m)
           + (.c1h * $r.in * prices.mult.cache_1h) ) / 10000
    end;

# Cents are rounded once and the amount is assembled as a string: printf-ing a
# float would surface artifacts like 2.3199999999999998.
def money($c):
  ($c | round) as $r
  | "$" + (($r / 100) | floor | tostring)
        + "." + (($r % 100) | tostring | if length < 2 then "0" + . else . end);

def ts_epoch:
  if . == null then null
  else (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null)
  end;

# A request starts at a prompt the user actually sent. Tool results, slash
# commands and other meta entries are user entries too, and must not split.
def is_start:
  .type == "user"
  and ((.promptSource // "") | . == "typed" or . == "queued")
  and (.isMeta != true);

def is_usage:
  .type == "assistant"
  and (.message.usage != null)
  and (.message.model != "<synthetic>");

def is_fast: (.message.usage.speed // "") == "fast";

def head_text:
  ( .message.content
    | if type == "string" then .
      elif type == "array" then (map(select(.type == "text") | .text) | join(" "))
      else "" end )
  | gsub("[\r\n\t]"; " ") | .[0:60] | sub(" +$"; "");

# cache_creation splits the write into 5m/1h buckets; older entries only carry
# the flat cache_creation_input_tokens, which was always a 5m write.
def usage_of:
  .message.usage as $u
  | ($u.cache_creation // null) as $cc
  | { in:  ($u.input_tokens // 0),
      out: ($u.output_tokens // 0),
      cr:  ($u.cache_read_input_tokens // 0),
      c5m: (if $cc then ($cc.ephemeral_5m_input_tokens // 0)
            else ($u.cache_creation_input_tokens // 0) end),
      c1h: (if $cc then ($cc.ephemeral_1h_input_tokens // 0) else 0 end) };

def render:
  (.buckets | to_entries | sort_by(.key) | map(.value)) as $bs
  | ($bs | map(.in) | add // 0) as $in
  | ($bs | map(.out) | add // 0) as $out
  | ($bs | map(.c5m + .c1h) | add // 0) as $cc
  | ($bs | map(.cr) | add // 0) as $cr
  | ($bs | map(bucket_cents) | add // 0) as $cents
  | ( $bs
      | map(.model
            + (if .fast then ":fast" else "" end)
            + (if rate(.model; .fast) == null then "?" else "" end))
      | join("+") ) as $models
  | (.efforts | keys | join("+")) as $efforts
  | "est. used token: input: \($in), output: \($out), cache_create: \($cc), cache_read: \($cr), total_tokens: \($in + $out + $cc + $cr), price: \(money($cents)), model: \(if $models == "" then "-" else $models end), effort: \(if $efforts == "" then "-" else $efforts end)";

def blank_seg:
  { started: false, start: null, end: null, head: "",
    seen: {}, buckets: {}, efforts: {}, lm: "", le: "" };

($mode == "last" or $mode == "segments") as $split
| reduce (inputs | fromjson? | select(type == "object")) as $e
    ({ n: 0, segs: [], cur: blank_seg };
      .n += 1
      | (if $split and ($e | is_start)
         then .segs += [.cur]
              | .cur = ( blank_seg
                         | .started = true
                         | .start = ($e.timestamp | ts_epoch)
                         | .head = ($e | head_text) )
         else . end)
      | ($e.timestamp | ts_epoch) as $ts
      | (if $ts == null then . else (.cur.start //= $ts) | .cur.end = $ts end)
      | (if ($e | is_usage | not) then .
         else
           ($e.message.id // $e.requestId // ("#" + (.n | tostring))) as $k
           | if (.cur.seen[$k] // false) then .
             else
               ($e.message.model // "") as $model
               | ($model + (if ($e | is_fast) then "|fast" else "" end)) as $bk
               | ($e | usage_of) as $u
               | .cur.seen[$k] = true
               | .cur.buckets[$bk] =
                   ( (.cur.buckets[$bk]
                      // { model: $model, fast: ($e | is_fast),
                           in: 0, out: 0, cr: 0, c5m: 0, c1h: 0 })
                     | .in += $u.in | .out += $u.out | .cr += $u.cr
                     | .c5m += $u.c5m | .c1h += $u.c1h )
               | .cur.efforts[($e.effort // "unknown")] = true
               | .cur.lm = $model
               | .cur.le = ($e.effort // "")
             end
         end)
    )
| .segs += [.cur]
| if $mode == "segments" then
    ( .segs[]
      | select(.started)
      | ((.start // 0) | strflocaltime("%H:%M:%S")) + US + .head + US + render )
  elif $mode == "last" then
    ( ((.segs | map(select(.started)) | last) // .segs[0]) as $s
      | (($s.start // 0) | tostring) + US
        + (($s.end // 0) | tostring) + US
        + $s.lm + US + $s.le + US + ($s | render) )
  else
    (.segs[0] | render)
  end
