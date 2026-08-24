#!/usr/bin/env bash
# Tests for scripts/collect.sh — run: bash tests/test_collect.sh
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/collect.sh"
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

( t "FILTER_EXEMPT check (clarity-16) reports even when its evidence lines are unchanged"
  newrepo
  { for i in $(seq 1 12); do printf 'if (x) { y(); }\n'; done; } > Complex.cs
  git add Complex.cs; git commit -qm init
  { for i in $(seq 1 12); do printf 'if (x) { y(); }\n'; done; printf '// unrelated comment\n'; } > Complex.cs
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/addedlines.txt" "Complex.cs:13"
  assert_file_lacks "$OUT/addedlines.txt" "Complex.cs:1$"
  assert_file_has   "$OUT/hits.txt" "clarity-16${TAB}Complex.cs:"
)

( t "FILTER_EXEMPT check (clarity-17) reports even when its evidence (line count) predates the diff"
  newrepo
  { for i in $(seq 1 151); do printf 'const l%d = 1;\n' "$i"; done; } > Long.ts
  git add Long.ts; git commit -qm init
  { for i in $(seq 1 151); do printf 'const l%d = 1;\n' "$i"; done; printf 'const extra = 1;\n'; } > Long.ts
  run
  assert_exit_ok "$RC"
  assert_file_has   "$OUT/addedlines.txt" "Long.ts:152"
  assert_file_lacks "$OUT/addedlines.txt" "Long.ts:1$"
  assert_file_has   "$OUT/hits.txt" "clarity-17${TAB}.*Long.ts"
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

# ----------------------------------------------------------------

PASS="$(grep -c '^PASS$' "$RESULTS")"
FAIL="$(grep -c '^FAIL' "$RESULTS")"
rm -rf "$WORKROOT"
echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
