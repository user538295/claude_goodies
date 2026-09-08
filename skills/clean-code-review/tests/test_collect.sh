#!/usr/bin/env bash
# Tests for scripts/collect.sh — run: bash tests/test_collect.sh
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/collect.sh"
# slice_group_md lives in lib.sh so both collect.sh and these tests exercise the
# exact same slicer — the release guards below call it directly on every catalog.
. "$SKILL_DIR/scripts/lib.sh"
# All temp artifacts (fixture repos, collect.sh outdirs) live under one root,
# removed at the end — no litter in the system temp dir.
WORKROOT="$(mktemp -d)"
export TMPDIR="$WORKROOT"
RESULTS="$(mktemp)"
CURRENT=""
TAB="$(printf '\t')"

t()   { CURRENT="$1"; }
ok()  { echo "PASS" >> "$RESULTS"; }
bad() { echo "FAIL: $CURRENT — $1" >> "$RESULTS"; echo "FAIL: $CURRENT — $1" >&2; }

assert_exit_ok()   { [ "$1" -eq 0 ] && ok || bad "expected exit 0, got $1"; }
assert_exit_fail() { [ "$1" -ne 0 ] && ok || bad "expected non-zero exit"; }
assert_file_has()  { grep -q -- "$2" "$1" 2>/dev/null && ok || bad "$(basename "$1") should contain [$2]"; }
assert_file_lacks(){ grep -q -- "$2" "$1" 2>/dev/null && bad "$(basename "$1") should NOT contain [$2]" || ok; }
assert_eq()        { [ "$1" = "$2" ] && ok || bad "expected [$2], got [$1]"; }

newrepo() {
  local d; d="$(mktemp -d)"; cd "$d" || exit 1
  git init -q
  git config user.email t@t.t; git config user.name t
}

run() { OUT="$("$SCRIPT" "$@" 2>"$WORKROOT"/collect_stderr)"; RC=$?; ERR="$(cat "$WORKROOT"/collect_stderr)"; }

# ---------------------------------------------------------------- non-git mode

( t "non-git dir, no args -> error"
  cd "$(mktemp -d)"
  run
  assert_exit_fail "$RC"
  echo "$ERR" | grep -qi "git" && ok || bad "error should mention git; got: $ERR"
)

( t "non-git dir, file args -> file mode, all lines added"
  cd "$(mktemp -d)"
  printf 'const a = 1;\nconst b = 2;\nconst c = 3;\n' > code.ts
  run code.ts
  assert_exit_ok "$RC"
  assert_file_has "$OUT/files.txt" "code.ts"
  assert_file_has "$OUT/addedlines.txt" "code.ts:1"
  assert_file_has "$OUT/addedlines.txt" "code.ts:3"
  assert_file_has "$OUT/languages.txt" "typescript"
  [ -s "$OUT/diff.patch" ] && ok || bad "diff.patch should be non-empty"
)

( t "non-git dir, missing file -> error"
  cd "$(mktemp -d)"
  run nope.ts
  assert_exit_fail "$RC"
)

# ---------------------------------------------------------------- git default mode

( t "default mode reviews staged + unstaged + untracked"
  newrepo
  printf 'let a = 1;\n' > staged.ts
  printf 'let c = 1;\n' > tracked.ts
  git add staged.ts tracked.ts; git commit -qm init
  printf 'let a = 1;\nlet b = 2;\n' > staged.ts; git add staged.ts   # staged
  printf 'let c = 1;\nlet d = 2;\n' > tracked.ts                     # unstaged
  printf 'let e = 1;\n' > untracked.ts                               # untracked
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/files.txt" "staged.ts"
  assert_file_has "$OUT/files.txt" "^tracked.ts"
  assert_file_has "$OUT/files.txt" "untracked.ts"
  assert_file_has "$OUT/addedlines.txt" "staged.ts:2"
  assert_file_has "$OUT/addedlines.txt" "^tracked.ts:2"
  assert_file_has "$OUT/addedlines.txt" "untracked.ts:1"
  assert_file_lacks "$OUT/addedlines.txt" "^tracked.ts:1"
)

( t "staged keyword -> staged only"
  newrepo
  printf 'let a = 1;\n' > f.ts; git add f.ts; git commit -qm init
  printf 'let s = 1;\n' > staged.ts; git add staged.ts
  printf 'let a = 1;\nlet u = 2;\n' > f.ts                  # unstaged
  printf 'let n = 1;\n' > untracked.ts
  run staged
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/files.txt" "staged.ts"
  assert_file_lacks "$OUT/files.txt" "untracked.ts"
  assert_file_lacks "$OUT/addedlines.txt" "f.ts:2"
)

( t "unstaged keyword -> unstaged only"
  newrepo
  printf 'let a = 1;\n' > f.ts; git add f.ts; git commit -qm init
  printf 'let s = 1;\n' > staged.ts; git add staged.ts
  printf 'let a = 1;\nlet u = 2;\n' > f.ts
  run unstaged
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/files.txt" "f.ts"
  assert_file_lacks "$OUT/files.txt" "staged.ts"
)

( t "untracked keyword -> untracked only, gitignore respected"
  newrepo
  printf 'ignored.ts\n' > .gitignore
  printf 'let a = 1;\n' > f.ts; git add f.ts .gitignore; git commit -qm init
  printf 'let a = 1;\nlet u = 2;\n' > f.ts
  printf 'let n = 1;\n' > untracked.ts
  printf 'let i = 1;\n' > ignored.ts
  run untracked
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/files.txt" "untracked.ts"
  assert_file_lacks "$OUT/files.txt" "ignored.ts"
  assert_file_lacks "$OUT/files.txt" "f.ts"
)

( t "combined keywords: staged untracked"
  newrepo
  printf 'let a = 1;\n' > f.ts; git add f.ts; git commit -qm init
  printf 'let s = 1;\n' > staged.ts; git add staged.ts
  printf 'let a = 1;\nlet u = 2;\n' > f.ts
  printf 'let n = 1;\n' > untracked.ts
  run staged untracked
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/files.txt" "staged.ts"
  assert_file_has   "$OUT/files.txt" "untracked.ts"
  assert_file_lacks "$OUT/addedlines.txt" "f.ts:2"
)

# ---------------------------------------------------------------- refs and ranges

( t "range A..B reviews commits only, ignores worktree"
  newrepo
  printf 'let a = 1;\n' > f.ts; git add f.ts; git commit -qm one
  printf 'let a = 1;\nlet b = 2;\n' > f.ts; git add f.ts; git commit -qm two
  printf 'let a = 1;\nlet b = 2;\nlet w = 3;\n' > f.ts      # worktree noise
  run 'HEAD~1..HEAD'
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/addedlines.txt" "f.ts:2"
  assert_file_lacks "$OUT/addedlines.txt" "f.ts:3"
)

( t "single ref diffs against worktree"
  newrepo
  printf 'let a = 1;\n' > f.ts; git add f.ts; git commit -qm one
  printf 'let a = 1;\nlet b = 2;\n' > f.ts; git add f.ts; git commit -qm two
  printf 'let a = 1;\nlet b = 2;\nlet w = 3;\n' > f.ts
  run 'HEAD~1'
  assert_exit_ok "$RC"
  assert_file_has "$OUT/addedlines.txt" "f.ts:2"
  assert_file_has "$OUT/addedlines.txt" "f.ts:3"
)

( t "bogus token -> error naming valid targets"
  newrepo
  printf 'x\n' > f.ts; git add f.ts; git commit -qm init
  run definitely-not-a-thing
  assert_exit_fail "$RC"
  echo "$ERR" | grep -q "staged" && ok || bad "error should list valid targets; got: $ERR"
)

( t "ref combined with keyword -> error"
  newrepo
  printf 'x\n' > f.ts; git add f.ts; git commit -qm init
  run HEAD staged
  assert_exit_fail "$RC"
)

# ---------------------------------------------------------------- filtering & languages

( t "vendor/generated/artifact paths are skipped"
  newrepo
  mkdir -p node_modules/lib src log
  printf 'let a = 1;\n' > src/f.ts
  printf 'let v = 1;\n' > node_modules/lib/v.ts
  printf '{}\n' > package-lock.json
  printf 'boom\n' > log/exit.log
  printf 'old\n' > data.bak
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/files.txt"   "src/f.ts"
  assert_file_lacks "$OUT/files.txt"   "node_modules"
  assert_file_lacks "$OUT/files.txt"   "exit.log"
  assert_file_has   "$OUT/skipped.txt" "node_modules/lib/v.ts"
  assert_file_has   "$OUT/skipped.txt" "package-lock.json"
  assert_file_has   "$OUT/skipped.txt" "log/exit.log"
  assert_file_has   "$OUT/skipped.txt" "data.bak"
  assert_file_lacks "$OUT/unanalysed.txt" ".log"
)

( t "language detection and unanalysed extensions"
  newrepo
  printf 'let a = 1;\n' > f.ts
  printf 'x = 1\n' > g.py
  printf 'package main\n' > h.go
  printf '# doc\n' > readme.md
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/languages.txt" "typescript"
  assert_file_has   "$OUT/languages.txt" "python"
  assert_file_has   "$OUT/unanalysed.txt" ".go"
  assert_file_lacks "$OUT/unanalysed.txt" ".md"
)

( t "clean repo with no changes -> error 'nothing to review'"
  newrepo
  printf 'x\n' > f.ts; git add f.ts; git commit -qm init
  run
  assert_exit_fail "$RC"
  echo "$ERR" | grep -qi "no changes" && ok || bad "should say no changes; got: $ERR"
)

( t "unborn HEAD with staged file works"
  newrepo
  printf 'let a = 1;\n' > f.ts; git add f.ts
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/files.txt" "f.ts"
  assert_file_has "$OUT/addedlines.txt" "f.ts:1"
)

( t "unresolved merge conflict -> error"
  newrepo
  printf 'base\n' > f.ts; git add f.ts; git commit -qm base
  git checkout -qb side; printf 'side\n' > f.ts; git commit -qam side
  git checkout -q -; printf 'main\n' > f.ts; git commit -qam main
  git merge side >/dev/null 2>&1 || true
  run
  assert_exit_fail "$RC"
  echo "$ERR" | grep -qi "conflict" && ok || bad "should mention conflicts; got: $ERR"
)

# ---------------------------------------------------------------- hits

( t "detection hits appear for added lines only"
  newrepo
  printf '// TODO old debt\n' > f.ts; git add f.ts; git commit -qm init
  printf '// TODO old debt\n// TODO fresh debt\n' > f.ts
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
  assert_file_lacks "$OUT/hits.txt" "smells-07${TAB}f.ts:1:"
)

( t "FILTER_EXEMPT check (smells-20) reports even when its evidence line is unchanged"
  newrepo
  printf 'public class NoHash {\n    public override bool Equals(object other) { return true; }\n}\n' > NoHash.cs
  git add NoHash.cs; git commit -qm init
  printf 'public class NoHash {\n    public override bool Equals(object other) { return true; }\n    // unrelated comment\n}\n' > NoHash.cs
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/addedlines.txt" "NoHash.cs:3"
  assert_file_lacks "$OUT/addedlines.txt" "NoHash.cs:2"
  assert_file_has   "$OUT/hits.txt" "smells-20${TAB}NoHash.cs:2:"
)

( t "FILTER_EXEMPT check (clarity-16) reports even when its evidence (the branchy function) predates the diff"
  newrepo
  branchyfn() { printf 'public void Branchy()\n{\n'; for i in $(seq 1 12); do printf '  if (x) { y(); }\n'; done; printf '}\n'; }
  branchyfn > Complex.cs
  git add Complex.cs; git commit -qm init
  { branchyfn; printf '// unrelated comment\n'; } > Complex.cs
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/addedlines.txt" "Complex.cs:16"
  assert_file_lacks "$OUT/addedlines.txt" "Complex.cs:1$"
  assert_file_has   "$OUT/hits.txt" "clarity-16${TAB}Complex.cs:1:"
)

( t "FILTER_EXEMPT check (clarity-17) reports even when its evidence (the long function) predates the diff"
  newrepo
  longfn() { printf 'function longOne() {\n'; for i in $(seq 1 151); do printf '  const l%d = 1;\n' "$i"; done; printf '}\n'; }
  longfn > Long.ts
  git add Long.ts; git commit -qm init
  { longfn; printf 'const extra = 1;\n'; } > Long.ts
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/addedlines.txt" "Long.ts:154"
  assert_file_lacks "$OUT/addedlines.txt" "Long.ts:1$"
  assert_file_has   "$OUT/hits.txt" "clarity-17${TAB}Long.ts:1:"
)

( t "FILTER_EXEMPT check (smells-01) reports even when its evidence (line count) predates the diff"
  newrepo
  { for i in $(seq 1 1001); do printf 'const l%d = 1;\n' "$i"; done; } > Huge.ts
  git add Huge.ts; git commit -qm init
  { for i in $(seq 1 1001); do printf 'const l%d = 1;\n' "$i"; done; printf 'const extra = 1;\n'; } > Huge.ts
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/addedlines.txt" "Huge.ts:1002"
  assert_file_lacks "$OUT/addedlines.txt" "Huge.ts:1$"
  assert_file_has   "$OUT/hits.txt" "smells-01${TAB}.*Huge.ts"
)

( t "FILTER_EXEMPT check (tests-13) reports even when its evidence (no assertions) predates the diff"
  newrepo
  mkdir -p tests
  printf 'def test_creates_order():\n    service.create_order(payload)\n' > tests/test_flow.py
  git add tests/test_flow.py; git commit -qm init
  printf 'def test_creates_order():\n    service.create_order(payload)\n    # unrelated comment\n' > tests/test_flow.py
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/addedlines.txt" "tests/test_flow.py:3"
  assert_file_lacks "$OUT/addedlines.txt" "tests/test_flow.py:1"
  assert_file_has   "$OUT/hits.txt" "tests-13${TAB}tests/test_flow.py:0"
)

( t "FILTER_EXEMPT set matches groups/*.md Scope:files declarations, except the documented tests-01 exception"
  file_scoped="$(perl -ne 'if (/^### (\S+)/) { $id = $1 } if (/\*\*Scope\*\*: `files`/) { print "$id\n" }' "$SKILL_DIR"/groups/*.md | sort -u)"
  exempt="$(grep '^FILTER_EXEMPT=' "$SKILL_DIR/scripts/collect.sh" | sed -E 's/^FILTER_EXEMPT="//; s/"$//' | tr -s ' ' '\n' | sed '/^$/d' | sort -u)"
  expected_exempt="$(printf '%s\n' "$file_scoped" | grep -vx 'tests-01' | sort -u)"
  assert_eq "$exempt" "$expected_exempt"
  printf '%s\n' "$file_scoped" | grep -qx 'tests-01' && ok || bad "tests-01 should be declared Scope: files in groups/tests.md"
  printf '%s\n' "$exempt" | grep -qx 'tests-01' && bad "tests-01 must NOT be in FILTER_EXEMPT — it still needs added-line filtering" || ok
)

( t "SKIP_TESTS set matches the checks whose groups/*.md NOTE says to dismiss test files"
  documented="$(perl -ne 'if (/^### (\S+)/) { $id = $1 } if (/NOTE for agent:/ && /[Dd]ismiss[^.]{0,40}test file/) { print "$id\n" }' "$SKILL_DIR"/groups/*.md | sort -u)"
  skipped="$(grep '^SKIP_TESTS=' "$SKILL_DIR/scripts/collect.sh" | sed -E 's/^SKIP_TESTS="//; s/"$//' | tr -s ' ' '\n' | sed '/^$/d' | sort -u)"
  assert_eq "$skipped" "$documented"
)

( t "SKIP_TESTS check (solid-06) skips test files but still reports in production files"
  newrepo
  mkdir -p src src/__tests__
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  printf 'export class Cart {\n  public total = 0;\n}\n' > src/cart.ts
  printf 'export class CartFixture {\n  public sut = 0;\n}\n' > src/__tests__/cart.test.ts
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/hits.txt" "solid-06${TAB}src/cart.ts:2:"
  assert_file_lacks "$OUT/hits.txt" "solid-06${TAB}src/__tests__/cart.test.ts"
)

( t "a check NOT in SKIP_TESTS (smells-07) still reports inside test files"
  newrepo
  mkdir -p src/__tests__
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  printf '// TODO fix this fixture\n' > src/__tests__/thing.test.ts
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}src/__tests__/thing.test.ts:1:"
)

( t "hits work in untracked files and in paths with spaces"
  newrepo
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  mkdir -p "my dir"
  printf '// TODO handle errors\n' > "my dir/new file.ts"
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}my dir/new file.ts:1:"
)

( t "magic numbers are judgment-only: no clarity-08 in hits"
  newrepo
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  printf 'const magic = 86400;\n' > nums.ts
  run
  assert_exit_ok "$RC"
  assert_file_lacks "$OUT/hits.txt" "clarity-08"
)

( t "per-check hit cap at 200 with WARN-CAP"
  newrepo
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  for i in $(seq 1 250); do printf '// TODO item %d\n' "$i"; done > big.ts
  run
  assert_exit_ok "$RC"
  n="$(grep -c "^smells-07${TAB}big.ts" "$OUT/hits.txt")"
  assert_eq "$n" "200"
  assert_file_has "$OUT/warnings.txt" "WARN-CAP: smells-07"
)

( t "large diff notice above 100 files"
  newrepo
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  for i in $(seq 1 105); do printf 'let a = 1;\n' > "f$i.ts"; done
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/warnings.txt" "NOTICE-LARGE-DIFF"
)

( t "numbered diff: added and context lines carry file line numbers"
  newrepo
  printf 'let a = 1;\n' > f.ts; git add f.ts; git commit -qm init
  printf 'let a = 1;\nlet b = 2;\n' > f.ts
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/numbered.patch" "2|+let b = 2;"
  assert_file_has "$OUT/numbered.patch" "1| let a = 1;"
)

( t "numbered diff covers untracked pseudo-diffs"
  newrepo
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  printf 'let e = 1;\nlet f = 2;\n' > u.ts
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/numbered.patch" "1|+let e = 1;"
  assert_file_has "$OUT/numbered.patch" "2|+let f = 2;"
)

# ---------------------------------------------------------------- deny-list config

# Fixture: two added lines that trip smells-07 (TODO comment), so a denied check
# leaves no hit while an undenied run does.
todo_fixture() {
  printf '// TODO old debt\n' > f.ts; git add f.ts; git commit -qm init
  printf '// TODO old debt\n// TODO fresh debt\n' > f.ts
}

( t "no config -> denied.txt empty, scriptable hit still present"
  newrepo
  todo_fixture
  run
  assert_exit_ok "$RC"
  [ -f "$OUT/denied.txt" ] && [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt should exist and be empty"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "deny a check id -> that check silenced, group not expanded"
  newrepo
  todo_fixture
  printf '{"deny":["smells-07"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has  "$OUT/denied.txt" "^smells-07$"
  assert_file_lacks "$OUT/denied.txt" "smells-01"
  assert_file_lacks "$OUT/hits.txt" "smells-07${TAB}"
)

( t "deny a group name -> expands to all its check ids"
  newrepo
  todo_fixture
  printf '{"deny":["smells"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has  "$OUT/denied.txt" "^smells-07$"
  assert_file_has  "$OUT/denied.txt" "^smells-01$"
  assert_file_lacks "$OUT/hits.txt" "smells-07${TAB}"
)

( t "unknown deny entry -> WARN-CONFIG, exit ok, nothing denied"
  newrepo
  todo_fixture
  printf '{"deny":["clarty-08"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has  "$OUT/warnings.txt" "WARN-CONFIG:"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt should be empty for an unknown entry"
  assert_file_has  "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "malformed config JSON -> warns and continues (no abort)"
  newrepo
  todo_fixture
  printf '{ this is not json' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/warnings.txt" "not valid JSON or not a JSON object"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt should be empty on broken JSON"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "config at repo root applies when invoked from a subdirectory"
  newrepo
  mkdir sub
  printf '// TODO old debt\n' > sub/f.ts; git add sub/f.ts; git commit -qm init
  printf '// TODO old debt\n// TODO fresh debt\n' > sub/f.ts
  printf '{"deny":["smells-07"]}' > .clean-code-review-config.json
  cd sub
  run
  assert_exit_ok "$RC"
  assert_file_has  "$OUT/denied.txt" "^smells-07$"
  assert_file_lacks "$OUT/hits.txt" "smells-07${TAB}"
)

( t "deny is scoped: denied check silenced, sibling check still fires"
  newrepo
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  mkdir -p src
  printf 'export class Cart {\n  public total = 0; // TODO wire up\n}\n' > src/cart.ts
  printf '{"deny":["smells-07"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_lacks "$OUT/hits.txt" "smells-07${TAB}"
  assert_file_has   "$OUT/hits.txt" "solid-06${TAB}src/cart.ts:2:"
)

( t "regex metacharacter entry is treated literally -> warns, denies nothing"
  newrepo
  todo_fixture
  printf '{"deny":[".*"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has  "$OUT/warnings.txt" "WARN-CONFIG:"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "'.*' must not expand — denied.txt must be empty"
  assert_file_has  "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "non-array deny value -> warns and continues (no abort)"
  newrepo
  todo_fixture
  printf '{"deny":"smells"}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/warnings.txt" "is not an array"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt should be empty on non-array deny"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "mixed valid + unknown entries -> valid denied, unknown warned"
  newrepo
  todo_fixture
  printf '{"deny":["smells-07","bogus-99"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/denied.txt" "^smells-07$"
  assert_file_lacks "$OUT/hits.txt" "smells-07${TAB}"
  assert_file_has   "$OUT/warnings.txt" "WARN-CONFIG:"
)

( t "group + overlapping id -> denied.txt deduped"
  newrepo
  todo_fixture
  printf '{"deny":["smells","smells-07"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_eq "$(grep -c "^smells-07$" "$OUT/denied.txt")" "1"
)

( t "config present but deny empty -> denied.txt empty, hit present"
  newrepo
  todo_fixture
  printf '{"deny":[]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt should be empty"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "config file itself is excluded from the reviewed file set"
  newrepo
  todo_fixture
  printf '{"deny":[]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_lacks "$OUT/files.txt" "clean-code-review-config"
  assert_file_has   "$OUT/skipped.txt" "clean-code-review-config"
)

( t "deny one id -> a sibling check in the SAME group still fires"
  newrepo
  printf 'x\n' > seed.ts; git add seed.ts; git commit -qm init
  # Untracked file: every line is an added line. Line 2 trips smells-07 (TODO),
  # line 3 trips smells-08 (return null) — both in the smells group.
  printf 'export function f() {\n  // TODO wire up\n  return null;\n}\n' > f.ts
  printf '{"deny":["smells-07"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_lacks "$OUT/hits.txt" "smells-07${TAB}"
  assert_file_has   "$OUT/hits.txt" "smells-08${TAB}f.ts:3:"
)

( t "non-git file mode, no config -> smells-07 fires (deny baseline)"
  cd "$(mktemp -d)"
  printf '// TODO old debt\n// TODO fresh debt\n' > f.ts
  run f.ts
  assert_exit_ok "$RC"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:"
)

( t "deny in non-git file mode -> config at \$PWD applies"
  cd "$(mktemp -d)"
  printf '// TODO old debt\n// TODO fresh debt\n' > f.ts
  printf '{"deny":["smells-07"]}' > .clean-code-review-config.json
  run f.ts
  assert_exit_ok "$RC"
  assert_file_has  "$OUT/denied.txt" "^smells-07$"
  assert_file_lacks "$OUT/hits.txt" "smells-07${TAB}"
)

( t "top-level-array config -> exit 3 wording, nothing denied"
  newrepo
  todo_fixture
  printf '["smells-07"]' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/warnings.txt" "not valid JSON or not a JSON object"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt should be empty for a top-level array"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "deny entry with embedded newline -> dropped, no group silently denied"
  newrepo
  todo_fixture
  # JSON string "x\nsmells": valid JSON whose decoded value contains a newline.
  # Line-based resolution would otherwise split it into 'x' + 'smells' and deny
  # the entire smells group — the perl \n guard must drop it instead.
  printf '{"deny":["x\\nsmells"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt must be empty — newline entry must not deny smells"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "boolean/null deny entries -> dropped silently, no WARN-CONFIG"
  newrepo
  todo_fixture
  printf '{"deny":[true,null]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt should be empty for boolean/null entries"
  assert_file_lacks "$OUT/warnings.txt" "WARN-CONFIG:"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

( t "numeric deny entry -> WARN-CONFIG, nothing denied"
  newrepo
  todo_fixture
  printf '{"deny":[5]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_has "$OUT/warnings.txt" "WARN-CONFIG:"
  [ ! -s "$OUT/denied.txt" ] && ok || bad "denied.txt should be empty for a numeric entry"
  assert_file_has "$OUT/hits.txt" "smells-07${TAB}f.ts:2:"
)

# ---------------------------------------------------------------- deny-list MD slicing
# The deny feature slices denied checks out of the per-group MD copies agents
# read ($OUT/groups/{group}.md), so a denied check's definition never reaches the
# model. These assert the copies are written correctly end-to-end, and the
# release guards below assert every catalog slices cleanly.

hdrcount() { grep -cE "^### ${2}-[0-9]" "$1" 2>/dev/null | tr -d ' '; }

( t "no config -> every group MD copied verbatim to groups/ (single source of truth)"
  newrepo
  todo_fixture
  run
  assert_exit_ok "$RC"
  [ -d "$OUT/groups" ] && ok || bad "groups/ dir should always exist"
  for g in clarity smells solid arch tests safety ddd; do
    if diff -q "$SKILL_DIR/groups/$g.md" "$OUT/groups/$g.md" >/dev/null; then ok; else bad "$g.md copy should be verbatim when nothing is denied"; fi
  done
)

( t "deny one id -> group MD sliced: denied header gone, sibling kept, count base-1, frame intact"
  newrepo
  todo_fixture
  printf '{"deny":["smells-07"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  base="$(hdrcount "$SKILL_DIR/groups/smells.md" smells)"
  [ -f "$OUT/groups/smells.md" ] && ok || bad "groups/smells.md should be written"
  assert_file_lacks "$OUT/groups/smells.md" "^### smells-07 "
  assert_file_has   "$OUT/groups/smells.md" "^### smells-08 "
  assert_eq "$(hdrcount "$OUT/groups/smells.md" smells)" "$((base - 1))"
  assert_file_has   "$OUT/groups/smells.md" "^# Group:"
  assert_file_has   "$OUT/groups/smells.md" "^## Output instruction"
)

( t "deny whole group -> sliced copy has zero headers (fully denied) but keeps frame"
  newrepo
  todo_fixture
  printf '{"deny":["ddd"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  [ -f "$OUT/groups/ddd.md" ] && ok || bad "groups/ddd.md should be written"
  assert_eq "$(hdrcount "$OUT/groups/ddd.md" ddd)" "0"
  assert_file_has "$OUT/groups/ddd.md" "^## Output instruction"
)

( t "deny one id -> touched group sliced, untouched sibling copied verbatim"
  newrepo
  todo_fixture
  printf '{"deny":["smells-07"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  assert_file_lacks "$OUT/groups/smells.md" "^### smells-07 "
  if diff -q "$SKILL_DIR/groups/clarity.md" "$OUT/groups/clarity.md" >/dev/null; then ok; else bad "untouched clarity.md should be a verbatim copy"; fi
)

( t "duplicated deny id -> sliced once, count base-1 (dedup must not double-cut)"
  newrepo
  todo_fixture
  printf '{"deny":["clarity-08","clarity-08"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  base="$(hdrcount "$SKILL_DIR/groups/clarity.md" clarity)"
  assert_eq "$(hdrcount "$OUT/groups/clarity.md" clarity)" "$((base - 1))"
  assert_file_lacks "$OUT/groups/clarity.md" "^### clarity-08 "
)

( t "mixed valid + unknown deny -> valid group sliced, no file for the unknown entry"
  newrepo
  todo_fixture
  printf '{"deny":["smells-07","bogus-99"]}' > .clean-code-review-config.json
  run
  assert_exit_ok "$RC"
  [ -f "$OUT/groups/smells.md" ] && ok || bad "valid group should be sliced"
  [ ! -f "$OUT/groups/bogus.md" ] && ok || bad "unknown entry must not produce a slice file"
)

# Release guards: run the real slicer over every shipped catalog so a malformed
# or restructured group MD is caught before release, not at review time.
( t "release: empty deny slices every catalog byte-for-byte identical to the original"
  for g in clarity smells solid arch tests safety ddd; do
    src="$SKILL_DIR/groups/$g.md"
    if diff -q "$src" <(slice_group_md "$src" " ") >/dev/null; then ok; else bad "$g.md changes under an empty deny set — not cleanly sliceable"; fi
  done
)

( t "release: denying one check removes exactly its block from every catalog"
  for g in clarity smells solid arch tests safety ddd; do
    src="$SKILL_DIR/groups/$g.md"
    base="$(hdrcount "$src" "$g")"
    first="$(grep -oE "^### ${g}-[0-9]+" "$src" | head -1 | awk '{print $2}')"
    last="$(grep -oE "^### ${g}-[0-9]+" "$src" | tail -1 | awk '{print $2}')"
    sliced="$(slice_group_md "$src" " $first ")"
    got="$(printf '%s\n' "$sliced" | grep -cE "^### ${g}-[0-9]" | tr -d ' ')"
    assert_eq "$got" "$((base - 1))"
    printf '%s\n' "$sliced" | grep -qE "^### ${first} " && bad "$g: denied $first still present" || ok
    printf '%s\n' "$sliced" | grep -qE "^### ${last} "  && ok || bad "$g: sibling $last was dropped"
    printf '%s\n' "$sliced" | grep -qE "^## " && ok || bad "$g: footer/section frame lost after slicing"
  done
)

# Guard against count-table drift: the per-group counts hardcoded in SKILL.md
# (Step 4 spawn table + the "Expected check counts" line) must equal the real
# number of `### {group}-NN` headers in each group MD file, and the grand total
# must stay in sync. synthesizer.md no longer restates base counts — it uses the
# effective counts the orchestrator passes — so it is not guarded here.
( t "SKILL.md count tables match groups/*.md header counts"
  total=0
  for g in clarity smells solid arch tests safety ddd; do
    n="$(grep -cE "^### ${g}-[0-9]" "$SKILL_DIR/groups/$g.md")"
    total=$((total + n))
    grep -qE "^\| ${g} \|.*\| ${n} \|" "$SKILL_DIR/SKILL.md" && ok || bad "Step4 table: $g should be $n"
    grep -qE "${g}=${n}[ ,]" "$SKILL_DIR/SKILL.md" && ok || bad "Expected-counts line: $g should be $n"
  done
  grep -qF "(${total} total)" "$SKILL_DIR/SKILL.md" && ok || bad "SKILL.md grand total should be ${total}"
  # The same grand total is restated in the frontmatter description and the
  # benchmark note; guard both so a group-count change can't leave them stale.
  grep -qF "${total} checks across" "$SKILL_DIR/SKILL.md" && ok || bad "frontmatter should say ${total} checks across"
  grep -qF "of the ${total} checks"  "$SKILL_DIR/SKILL.md" && ok || bad "benchmark note should reference ${total} checks"
)

# Guard the SKIP_TESTS doc: the id list on SKILL.md's files_prod.txt table row
# must match the SKIP_TESTS variable in collect.sh, or the doc silently drifts.
( t "SKILL.md SKIP_TESTS doc matches the collect.sh SKIP_TESTS variable"
  vars="$(grep -E '^SKIP_TESTS=' "$SKILL_DIR/scripts/collect.sh" | grep -oE '[a-z]+-[0-9]+' | sort)"
  docrow="$(grep -F 'files_prod.txt' "$SKILL_DIR/SKILL.md" | grep -F 'SKIP_TESTS')"
  for id in $vars; do
    printf '%s' "$docrow" | grep -qF "$id" && ok || bad "SKILL.md files_prod row should document $id"
  done
  assert_eq "$(printf '%s' "$docrow" | grep -oE '[a-z]+-[0-9]+' | sort | wc -l | tr -d ' ')" \
            "$(printf '%s\n' "$vars" | wc -l | tr -d ' ')"
)

# ----------------------------------------------------------------

PASS="$(grep -c '^PASS$' "$RESULTS")"
FAIL="$(grep -c '^FAIL' "$RESULTS")"
rm -rf "$WORKROOT"
echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
