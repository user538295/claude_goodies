#!/usr/bin/env bash
# Golden test for the progress-header script behind the /implement skill
# (skills/implement/scripts/plan-progress.sh + its sibling templates and
# task_section.awk). This script is now the sole copy, so its output contract
# is pinned here.
#
# Contract under test (see plan-progress.sh header):
#   Exit 0  — a task remains: the header is printed, then a blank line and the
#             machine-readable trailer NEXT_TASK_NAME / NEXT_TASK_PHASE /
#             NEXT_TASK_NUMBER.
#   Exit 1  — every task done: stdout is exactly "All tasks complete."
#   Exit 2  — usage error / plan file not found.
#   Exit 3  — no recognized task-section heading (## Tasks / ## Task /
#             ## Task breakdown), OR a task section with no tasks; a message is
#             printed to stderr.
#
# The header text comes from progress-header-flat.template (no phases) or
# progress-header-phased.template (### headings under the task section). fill of
# the 12-cell bar is int(completed/total*12); pct is int(completed/total*100+0.5).
# Every expected number below is hand-computed from those two formulas.
#
# Run: bash skills/implement/tests/test_plan_progress.sh
set -u

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
SCRIPT="$SCRIPTS/plan-progress.sh"
FLAT_TPL="$SCRIPTS/progress-header-flat.template"
PHASED_TPL="$SCRIPTS/progress-header-phased.template"

WORKROOT="$(mktemp -d)"
ERRFILE="$WORKROOT/stderr"
trap 'cd /; rm -rf "$WORKROOT"' EXIT

# Assertions run inside ( … ) subshells, so results are collected via a file
# (see test_locator.sh) rather than shell counters, which a subshell can't export.
RESULTS="$WORKROOT/results"
: > "$RESULTS"
CURRENT=""
t()   { CURRENT="$1"; }
ok()  { echo "PASS" >> "$RESULTS"; }
bad() { echo "FAIL: $CURRENT — $1" >> "$RESULTS"; echo "FAIL: $CURRENT — $1" >&2; }

assert_eq() { # expected actual
  if [ "$1" = "$2" ]; then ok; else bad "expected [$1], got [$2]"; fi
}

# Run the script on a plan file; capture stdout, stderr and exit code.
run_plan() { OUT="$(bash "$SCRIPT" "$1" 2>"$ERRFILE")"; RC=$?; ERR="$(cat "$ERRFILE")"; }

# One line of $OUT by its literal prefix (the machine trailer / header rows).
line() { printf '%s\n' "$OUT" | grep "$1" | head -1; }

# Build the expected 12-cell bar: $1 filled █ (U+2588) then ░ (U+2591) to fill 12.
FULL="$(printf '\342\226\210')"
LIGHT="$(printf '\342\226\221')"
bar() {
  local filled="$1" i s=""
  for ((i = 1; i <= 12; i++)); do
    if [ "$i" -le "$filled" ]; then s+="$FULL"; else s+="$LIGHT"; fi
  done
  printf '%s' "$s"
}

# ---------------------------------------------------------------- 1. FLAT plan
# 2 done / 5 total -> remaining 3, next is task #3 ("Task three").
# fill = int(2/5*12) = int(4.8) = 4 ;  pct = int(2/5*100+0.5) = int(40.5) = 40.
FLAT="$WORKROOT/flat.md"
cat > "$FLAT" <<'EOF'
## Tasks
- [x] Task one
- [x] Task two
- [ ] Task three
- [ ] Task four
- [ ] Task five
EOF
run_plan "$FLAT"
( t "flat: exits 0 while a task remains"; assert_eq "0" "$RC" )
( t "flat: Progress row — 12-cell bar, pct, completed/total"
  assert_eq "Progress   : [$(bar 4)] 40%  (2/5 tasks)" "$(line '^Progress')" )
( t "flat: Next task row — number and name"
  assert_eq "Next task  : 3  Task three" "$(line '^Next task')" )
( t "flat: Completed label";  assert_eq "Completed  : 2 tasks" "$(line '^Completed')" )
( t "flat: Remaining label";  assert_eq "Remaining  : 3 tasks" "$(line '^Remaining')" )
( t "flat: NEXT_TASK_NUMBER trailer"; assert_eq "NEXT_TASK_NUMBER=3" "$(line '^NEXT_TASK_NUMBER=')" )
( t "flat: NEXT_TASK_NAME trailer";   assert_eq "NEXT_TASK_NAME=Task three" "$(line '^NEXT_TASK_NAME=')" )
( t "flat: NEXT_TASK_PHASE trailer is empty (no phases)"
  assert_eq "NEXT_TASK_PHASE=" "$(line '^NEXT_TASK_PHASE=')" )

# ---------------------------------------------------------------- 2. PHASED plan
# ### headings begin with a digit so the phase number is explicit. Layout:
#   Phase 1: 2 done  (complete)          Phase 2: 1 done, 2 remaining
#   Phase 3: 1 remaining
# totals: 3 done / 6 tasks ; 1 complete / 3 phases.
# next uncompleted is "Wire it up" — 2nd task of phase 2 -> PHASE 2, NUM 2.
# fill = int(3/6*12) = 6 ; pct = int(3/6*100+0.5) = int(50.5) = 50.
PHASED="$WORKROOT/phased.md"
cat > "$PHASED" <<'EOF'
## Tasks

### 1. Setup
- [x] Init repo
- [x] Add config

### 2. Build
- [x] Create module
- [ ] Wire it up
- [ ] Add tests

### 3. Ship
- [ ] Deploy
EOF
run_plan "$PHASED"
( t "phased: exits 0 while a task remains"; assert_eq "0" "$RC" )
( t "phased: Progress row — tasks and phases figures"
  assert_eq "Progress   : [$(bar 6)] 50%  (3/6 tasks, 1/3 phases)" "$(line '^Progress')" )
( t "phased: Next task row — phase.number and name"
  assert_eq "Next task  : 2.2  Wire it up" "$(line '^Next task')" )
( t "phased: NEXT_TASK_PHASE trailer";  assert_eq "NEXT_TASK_PHASE=2" "$(line '^NEXT_TASK_PHASE=')" )
( t "phased: NEXT_TASK_NUMBER trailer"; assert_eq "NEXT_TASK_NUMBER=2" "$(line '^NEXT_TASK_NUMBER=')" )

# ---------------------------------------------------------------- 3. eval-safety
# The next task name carries every shell-special char ($ ` ' " *). The script
# extracts the name BEFORE any eval and echoes it directly, so the trailer must
# reproduce it byte-for-byte — a regression to eval'ing it would mangle or
# execute this.
SPECIAL_NAME='pay $5 for `cmd` '\''sq'\'' "dq" *all*'
SPECIAL="$WORKROOT/special.md"
{ printf '## Tasks\n'; printf -- '- [ ] %s\n' "$SPECIAL_NAME"; } > "$SPECIAL"
run_plan "$SPECIAL"
( t "special: exits 0"; assert_eq "0" "$RC" )
( t "special: NEXT_TASK_NAME is reproduced verbatim"
  assert_eq "$SPECIAL_NAME" "$(printf '%s\n' "$OUT" | grep '^NEXT_TASK_NAME=' | head -1 | sed 's/^NEXT_TASK_NAME=//')" )

# ---------------------------------------------------------------- 4. all complete
DONE="$WORKROOT/done.md"
cat > "$DONE" <<'EOF'
## Tasks
- [x] a
- [x] b
EOF
run_plan "$DONE"
( t "all complete: exit 1";                assert_eq "1" "$RC" )
( t "all complete: stdout says so";        assert_eq "All tasks complete." "$OUT" )

# ---------------------------------------------------------------- 5. no task section
NOSEC="$WORKROOT/nosec.md"
cat > "$NOSEC" <<'EOF'
## Overview
- [ ] this bullet is not under a task heading
EOF
run_plan "$NOSEC"
( t "no section: exit 3";                  assert_eq "3" "$RC" )
( t "no section: stderr warns";
  printf '%s' "$ERR" | grep -q "no recognized task section" && ok || bad "stderr: [$ERR]" )

# ---------------------------------------------------------------- 6. missing file
run_plan "$WORKROOT/does-not-exist.md"
( t "missing file: exit 2";                assert_eq "2" "$RC" )
( t "missing file: stderr names it";
  printf '%s' "$ERR" | grep -q "not found" && ok || bad "stderr: [$ERR]" )

# ---------------------------------------------------------------- 7. template integrity
# Every {{TOKEN}} in either template must be substituted by the script's awk
# renderer (an escaped gsub /\{\{TOKEN\}\}/). Grepping the escaped form ties the
# template to the code, so a renamed token would surface as a failure here
# instead of rendering literally in the header.
for tok in $(grep -ohE '\{\{[A-Z_]+\}\}' "$FLAT_TPL" "$PHASED_TPL" | tr -d '{}' | sort -u); do
  t "template token {{$tok}} is substituted by the script"
  needle="\\{\\{${tok}\\}\\}"   # -> literal  \{\{TOKEN\}\}
  grep -Fq -- "$needle" "$SCRIPT" && ok || bad "no gsub for {{$tok}} in plan-progress.sh"
done

# ---------------------------------------------------------------- 8. section, zero checkboxes
# A recognized task section with NO checkbox lines has total==0. This now
# correctly distinguishes an empty section (exit 3, "No tasks found") from a
# genuinely all-done plan (exit 1, "All tasks complete." — case 4): a heading
# with no tasks is nothing to implement, not a finished plan.
EMPTY="$WORKROOT/empty-section.md"
cat > "$EMPTY" <<'EOF'
## Tasks

Some prose, but no checkbox lines yet.
EOF
run_plan "$EMPTY"
( t "empty section: exit 3";                assert_eq "3" "$RC" )
( t "empty section: stderr says no tasks found";
  printf '%s' "$ERR" | grep -q "No tasks found" && ok || bad "stderr: [$ERR]" )

# ----------------------------------------------------------------
PASS="$(grep -c '^PASS$' "$RESULTS")"
FAIL="$(grep -c '^FAIL' "$RESULTS")"
echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
