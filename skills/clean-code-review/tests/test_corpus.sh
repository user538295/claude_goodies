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
  cmd="$(grep -h "^$check$(printf '\t')$lang$(printf '\t')" "$SKILL_DIR"/scripts/checks/*.tsv | cut -f3-)"
  if [ -z "$cmd" ]; then
    echo "FAIL: no command found for $key" >&2; FAIL=$((FAIL+1)); continue
  fi
  eval "$cmd" < ../filelist > "../out/$key" 2>"../out/$key.err"
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

# ---- file-level threshold checks (clarity-16, clarity-17, smells-01)
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
for ext in ts js cs swift kt java; do
  for i in $(seq 1 12); do echo 'if (x) { y(); }'; done > "thr/complex.$ext"
  printf 'if (a) { b(); }\nvalue = 1;\n' > "thr/simple.$ext"
done
for i in $(seq 1 12); do echo "if x$i: pass"; done > thr/complex.py
printf 'if a: pass\nb = 1\n' > thr/simple.py
for i in $(seq 1 160); do echo "const l$i = 1;"; done > thr/long.ts
printf 'const s = 1;\n' > thr/short.ts
for i in $(seq 1 1010); do echo "const g$i = 1;"; done > thr/huge.ts
find thr -type f | sort > ../thrlist

run_thr clarity-16 typescript "thr/complex.ts"    "thr/simple.ts"
run_thr clarity-16 javascript "thr/complex.js"    "thr/simple.js"
run_thr clarity-16 python     "thr/complex.py"    "thr/simple.py"
run_thr clarity-16 csharp     "thr/complex.cs"    "thr/simple.cs"
run_thr clarity-16 swift      "thr/complex.swift" "thr/simple.swift"
run_thr clarity-16 kotlin     "thr/complex.kt"    "thr/simple.kt"
run_thr clarity-16 java       "thr/complex.java"  "thr/simple.java"
run_thr clarity-17 all        "thr/long.ts"    "thr/short.ts"
run_thr smells-01  all        "thr/huge.ts"    "thr/long.ts"

echo ""
echo "corpus assertions passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
