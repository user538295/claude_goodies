#!/usr/bin/env bash
# Semantic tests for the detection patterns in scripts/checks/*.tsv.
# tests/corpus.tsv defines, per check+lang, code lines that MUST match and
# near-misses that must NOT. Run: bash tests/test_corpus.sh
#
# corpus.tsv columns (tab-separated):
#   check_id  lang  filename  expect  code
# expect: MATCH        - this exact line must be flagged (file:line hit)
#         NOMATCH      - this exact line must NOT be flagged
#         FILE_MATCH   - the file must appear in the command output (file-level checks)
#         FILE_NOMATCH - the file must NOT appear in the command output
#         FILL         - content only, no assertion (padding for file-level checks)
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORPUS="$SKILL_DIR/tests/corpus.tsv"
. "$SKILL_DIR/scripts/lib.sh"

WORKROOT="$(mktemp -d)"
trap 'cd /; rm -rf "$WORKROOT"' EXIT
cd "$WORKROOT" || exit 1
mkdir corpus out
cd corpus || exit 1

PASS=0; FAIL=0
ROWS=()

# ---- build corpus files, remember each row's line number
while IFS="$(printf '\t')" read -r check lang fname expect code; do
  case "$check" in ''|'#'*) continue ;; esac
  mkdir -p "$(dirname "$fname")" 2>/dev/null
  printf '%s\n' "$code" >> "$fname"
  n="$(wc -l < "$fname" | tr -d ' ')"
  [ "$expect" = "FILL" ] && continue
  ROWS+=("$check|$lang|$fname|$expect|$n")
done < "$CORPUS"

find . -type f | sed 's|^\./||' | sort > ../filelist

# ---- run each referenced check command exactly once
ran=""
for row in "${ROWS[@]}"; do
  check="${row%%|*}"; rest="${row#*|}"; lang="${rest%%|*}"
  key="$check.$lang"
  case " $ran " in *" $key "*) continue ;; esac
  ran="$ran $key"
  # A check may declare several rows for one language (collect.sh runs each and
  # appends every row's hits), so union the rows here instead of eval'ing them as
  # one blob — the first would swallow the shared stdin and starve the rest.
  : > "../out/$key"; : > "../out/$key.err"
  found=0
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    found=1
    eval "$cmd" < ../filelist >> "../out/$key" 2>>"../out/$key.err"
  done <<EOF
$(grep -h "^$check$(printf '\t')$lang$(printf '\t')" "$SKILL_DIR"/scripts/checks/*.tsv | cut -f3-)
EOF
  if [ "$found" = 0 ]; then
    echo "FAIL: no command found for $key" >&2; FAIL=$((FAIL+1)); continue
  fi
  if [ -s "../out/$key.err" ]; then
    echo "FAIL: $key errored: $(head -n 1 "../out/$key.err")" >&2; FAIL=$((FAIL+1))
  fi
done

# ---- assertions
for row in "${ROWS[@]}"; do
  check="${row%%|*}"; rest="${row#*|}"
  lang="${rest%%|*}"; rest="${rest#*|}"
  fname="${rest%%|*}"; rest="${rest#*|}"
  expect="${rest%%|*}"; lineno="${rest#*|}"
  outf="../out/$check.$lang"
  case "$expect" in
    MATCH)
      grep -q "^$fname:$lineno:" "$outf" 2>/dev/null \
        && PASS=$((PASS+1)) \
        || { FAIL=$((FAIL+1)); echo "FAIL: $check/$lang MATCH missed: $fname:$lineno ($(sed -n "${lineno}p" "$fname"))" >&2; } ;;
    NOMATCH)
      grep -q "^$fname:$lineno:" "$outf" 2>/dev/null \
        && { FAIL=$((FAIL+1)); echo "FAIL: $check/$lang NOMATCH hit: $fname:$lineno ($(sed -n "${lineno}p" "$fname"))" >&2; } \
        || PASS=$((PASS+1)) ;;
    FILE_MATCH)
      grep -q "$fname" "$outf" 2>/dev/null \
        && PASS=$((PASS+1)) \
        || { FAIL=$((FAIL+1)); echo "FAIL: $check/$lang FILE_MATCH missed: $fname" >&2; } ;;
    FILE_NOMATCH)
      grep -q "$fname" "$outf" 2>/dev/null \
        && { FAIL=$((FAIL+1)); echo "FAIL: $check/$lang FILE_NOMATCH hit: $fname" >&2; } \
        || PASS=$((PASS+1)) ;;
    *) FAIL=$((FAIL+1)); echo "FAIL: unknown expect '$expect' for $check/$lang" >&2 ;;
  esac
done

# ---- threshold checks: per-file (smells-01) and per-function (clarity-16, clarity-17)
run_thr() {  # $1=check $2=lang $3=file-that-must-appear $4=file-that-must-not
  local cmd out
  cmd="$(grep -h "^$1$(printf '\t')$2$(printf '\t')" "$SKILL_DIR"/scripts/checks/*.tsv | cut -f3-)"
  out="$(eval "$cmd" < ../thrlist 2>&1)"
  if printf '%s\n' "$out" | grep -q "$3"; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); echo "FAIL: $1/$2 should flag $3; got: $out" >&2; fi
  if printf '%s\n' "$out" | grep -q "$4"; then
    FAIL=$((FAIL+1)); echo "FAIL: $1/$2 should NOT flag $4; got: $out" >&2
  else PASS=$((PASS+1)); fi
}

mkdir -p thr
# clarity-16 is per-function: one function with 12 branch lines must flag, and a
# file whose 24 branch lines are spread over 12 two-branch functions must not —
# that spread file is exactly what the old per-file keyword count flagged.
gen_br() {  # $1=ext $2=long-function-header $3=two-branch-function-template ($N substituted)
  { printf '%s\n' "$2"; for i in $(seq 1 12); do echo '  if (x) { y(); }'; done; printf '}\n'; } > "thr/branchy.$1"
  for i in $(seq 1 12); do printf '%s\n' "${3//\$N/$i}"; done > "thr/spread.$1"
}
gen_br ts   'function branchy() {'      'function f$N() {
  if (a) { b(); }
  if (c) { d(); }
}'
cp thr/branchy.ts thr/branchy.js; cp thr/spread.ts thr/spread.js
gen_br cs   'public void Branchy()
{'                                      'public void F$N()
{
  if (a) { b(); }
  if (c) { d(); }
}'
gen_br kt   'fun branchy() {'           'fun f$N() {
  if (a) { b() }
  if (c) { d() }
}'
gen_br java 'public void branchy() {'   'public void f$N() {
  if (a) { b(); }
  if (c) { d(); }
}'
gen_br cpp  'void branchy() {'          'void f$N() {
  if (a) { b(); }
  if (c) { d(); }
}'
{ printf 'func branchy() {\n'; for i in $(seq 1 12); do echo '  if x { y() }'; done; printf '}\n'; } > thr/branchy.swift
for i in $(seq 1 12); do printf 'func f%d() {\n  if a { b() }\n  if c { d() }\n}\n' "$i"; done > thr/spread.swift
{ printf 'def branchy():\n'; for i in $(seq 1 12); do echo "    if x$i: pass"; done; } > thr/branchy.py
for i in $(seq 1 12); do printf 'def f%d():\n    if a: pass\n    if c: pass\n\n' "$i"; done > thr/spread.py

# Must-not fixtures for the counting rules mbranch adds on top of the old keyword
# count: prose in comments/docstrings is not branching, a `describe` suite is not
# a function, and a swift `for:` argument label is not a loop.
{ printf 'def documented():\n    """\n'
  for i in $(seq 1 12); do echo "    Retries if the cache is cold, for each stale key."; done
  printf '    """\n    return 1\n'; } > thr/docprose.py
{ printf "describe('suite', () => {\n"; for i in $(seq 1 12); do echo '  if (x) { y(); }'; done
  printf '});\n'; } > thr/suite.ts
{ printf 'func labelled() {\n'
  for i in $(seq 1 12); do echo '  button.setTitle(t, for: .normal)'; done
  printf '}\n'; } > thr/labels.swift
for i in $(seq 1 160); do echo "const l$i = 1;"; done > thr/long.ts
printf 'const s = 1;\n' > thr/short.ts
for i in $(seq 1 1010); do echo "const g$i = 1;"; done > thr/huge.ts

# clarity-17 is per-function: one 160-line function must flag, 40 four-line
# functions in a 160-line file must not. `thr/long.ts` above (160 statements,
# no function) stays the smells-01 negative.
gen_fn() {  # $1=ext $2=header-of-the-long-function $3=short-function-template ($N substituted)
  { printf '%s\n' "$2"; for i in $(seq 1 157); do echo "  const l$i = 1;"; done; printf '}\n'; } > "thr/longfn.$1"
  for i in $(seq 1 40); do printf '%s\n' "${3//\$N/$i}"; done > "thr/manyfns.$1"
}
gen_fn ts    'function longOne() {'                'function f$N() {
  const x = 1;
  return x;
}'
cp thr/longfn.ts thr/longfn.js; cp thr/manyfns.ts thr/manyfns.js
gen_fn cs    'public void LongOne()
{'                                                 'public int F$N()
{
  return 1;
}'
gen_fn swift 'func longOne() {'                    'func f$N() {
  let x = 1
  _ = x
}'
gen_fn kt    'fun longOne() {'                     'fun f$N() {
  val x = 1
  println(x)
}'
gen_fn java  'public void longOne() {'             'public int f$N() {
  int x = 1;
  return x;
}'
gen_fn cpp   'void longOne() {'                    'int f$N() {
  int x = 1;
  return x;
}'
{ printf 'def long_one():\n'; for i in $(seq 1 157); do echo "    l$i = 1"; done; } > thr/longfn.py
for i in $(seq 1 40); do printf 'def f%d():\n    x = 1\n    return x\n\n' "$i"; done > thr/manyfns.py

find thr -type f | sort > ../thrlist

run_thr clarity-16 typescript "thr/branchy.ts"    "thr/spread.ts"
run_thr clarity-16 javascript "thr/branchy.js"    "thr/spread.js"
run_thr clarity-16 python     "thr/branchy.py"    "thr/spread.py"
run_thr clarity-16 csharp     "thr/branchy.cs"    "thr/spread.cs"
run_thr clarity-16 swift      "thr/branchy.swift" "thr/spread.swift"
run_thr clarity-16 kotlin     "thr/branchy.kt"    "thr/spread.kt"
run_thr clarity-16 java       "thr/branchy.java"  "thr/spread.java"
run_thr clarity-16 cpp        "thr/branchy.cpp"   "thr/spread.cpp"
run_thr clarity-16 python     "thr/branchy.py"    "thr/docprose.py"
run_thr clarity-16 typescript "thr/branchy.ts"    "thr/suite.ts"
run_thr clarity-16 swift      "thr/branchy.swift" "thr/labels.swift"
run_thr clarity-17 typescript "thr/longfn.ts"    "thr/manyfns.ts"
run_thr clarity-17 javascript "thr/longfn.js"    "thr/manyfns.js"
run_thr clarity-17 python     "thr/longfn.py"    "thr/manyfns.py"
run_thr clarity-17 csharp     "thr/longfn.cs"    "thr/manyfns.cs"
run_thr clarity-17 swift      "thr/longfn.swift" "thr/manyfns.swift"
run_thr clarity-17 kotlin     "thr/longfn.kt"    "thr/manyfns.kt"
run_thr clarity-17 java       "thr/longfn.java"  "thr/manyfns.java"
run_thr clarity-17 cpp        "thr/longfn.cpp"   "thr/manyfns.cpp"
run_thr smells-01  all        "thr/huge.ts"    "thr/long.ts"

echo ""
echo "corpus assertions passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
