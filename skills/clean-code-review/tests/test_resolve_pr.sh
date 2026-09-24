#!/usr/bin/env bash
# Tests for scripts/resolve-pr.sh — run: bash tests/test_resolve_pr.sh
#
# Real-network paths (fetching from a hosting provider) cannot run offline, so
# every test points the repo at LOCAL bare remotes carrying the per-provider
# request ref, and most force the plain-git base path with CCR_NO_GH=1; the two
# gh tests instead put a stub `gh` on PATH (with `env -u CCR_NO_GH`) so the
# gh base-resolution branch is exercised without any network. (`refs/pull/<n>/head`
# for GitHub/Gitea, `refs/merge-requests/<n>/head` for GitLab, `refs/pull-requests/
# <n>/from` for Bitbucket). Bare paths deliberately embed a host/owner/repo tail
# (e.g. .../github.com/o/r.git) so the remote-selection tiers can be exercised
# offline. Every repo sets protocol.file.allow=always so the resolver's own git
# calls fetch from local paths even on hardened configs.
#
# resolve-pr.sh reviews a request in an ISOLATED temp worktree at the request
# head; it never touches the caller's branch or working tree. Its stdout is two
# lines: the worktree path, then the `base...head` range.
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/resolve-pr.sh"
COLLECT="$SKILL_DIR/scripts/collect.sh"
WORKROOT="$(mktemp -d)"
export TMPDIR="$WORKROOT"
RESULTS="$(mktemp)"
CURRENT=""

t()   { CURRENT="$1"; }
ok()  { echo "PASS" >> "$RESULTS"; }
bad() { echo "FAIL: $CURRENT — $1" >> "$RESULTS"; echo "FAIL: $CURRENT — $1" >&2; }

assert_exit_ok()   { [ "$1" -eq 0 ] && ok || bad "expected exit 0, got $1 (stderr: $ERR)"; }
assert_exit_fail() { [ "$1" -ne 0 ] && ok || bad "expected non-zero exit"; }
assert_eq()        { [ "$1" = "$2" ] && ok || bad "expected [$2], got [$1]"; }
assert_match()     { echo "$1" | grep -qE -- "$2" && ok || bad "[$1] should match /$2/"; }
assert_file_has()  { grep -q -- "$2" "$1" 2>/dev/null && ok || bad "$(basename "$1") should contain [$2]"; }
assert_file_lacks(){ grep -q -- "$2" "$1" 2>/dev/null && bad "$(basename "$1") should NOT contain [$2]" || ok; }
assert_head()      { grep -q -- "$2" "$1/f.ts" 2>/dev/null && ok || bad "worktree f.ts should contain [$2]"; }

# stdout: line 1 = worktree dir, line 2 = base...head range.
run() {
  OUT="$(CCR_NO_GH=1 "$SCRIPT" "$@" 2>"$WORKROOT/stderr")"; RC=$?
  ERR="$(cat "$WORKROOT/stderr")"
  WT="$(printf '%s\n' "$OUT" | sed -n 1p)"
  RANGE="$(printf '%s\n' "$OUT" | sed -n 2p)"
}

gitq() { git -c user.email=t@t.t -c user.name=t -c protocol.file.allow=always "$@"; }

# Build a bare remote at an EXACT path (so its URL embeds host/owner/repo for the
# tier tests) with `main` (base) plus a request head that adds <line> on top of
# main, published at <ref>. $1 bare path, $2 added line, $3 ref (default pull/5).
build_bare() {
  local bare="$1" line="$2" ref="${3:-refs/pull/5/head}" default="${4:-main}" seed
  mkdir -p "$(dirname "$bare")"; git init -q --bare "$bare"
  git -C "$bare" symbolic-ref HEAD "refs/heads/$default"
  seed="$(mktemp -d)"
  ( cd "$seed"
    gitq init -q; git symbolic-ref HEAD "refs/heads/$default"
    printf 'let a = 1;\n' > f.ts; gitq add f.ts; gitq commit -qm base
    gitq remote add origin "$bare"; gitq push -q origin "$default"
    gitq checkout -qb pr
    printf 'let a = 1;\n%s\n' "$line" > f.ts; gitq commit -qam feature
    gitq push -q origin "pr:$ref" )
}

# A bare remote at <root>/<repo-path>.git. $1 repo-path (o/r), $2 ref, $3 line.
make_remote() {
  local path="${1:-o/r}" ref="${2:-refs/pull/5/head}" line="${3:-let b = 2;}" bare
  bare="$(mktemp -d)/$path.git"
  build_bare "$bare" "$line" "$ref"
  echo "$bare"
}

# A consumer clone sitting on `main` with a clean worktree, remote = origin.
make_consumer() {
  local remote="$1" dir
  dir="$(mktemp -d)/consumer"
  gitq clone -q "$remote" "$dir" >/dev/null 2>&1
  ( cd "$dir"; git config protocol.file.allow always; gitq checkout -q main >/dev/null 2>&1 )
  echo "$dir"
}

# ---------------------------------------------------------------- URL parsing / guards

( t "missing url arg -> error"
  cd "$(mktemp -d)"; run; assert_exit_fail "$RC" )

( t "url with no pull/merge-request segment -> error"
  cd "$(mktemp -d)"; run "https://gitlab.com/o/r/-/tree/main"
  assert_exit_fail "$RC"; assert_match "$ERR" "pull/merge-request URL" )

( t "github non-pull url (issues) -> error"
  cd "$(mktemp -d)"; run "https://github.com/o/r/issues/5"; assert_exit_fail "$RC" )

( t "valid url but not inside a git repo -> error mentioning repository"
  cd "$(mktemp -d)"; run "https://github.com/o/r/pull/5"
  assert_exit_fail "$RC"; assert_match "$ERR" "repositor" )

( t "no remote configured -> error"
  d="$(mktemp -d)"; cd "$d"; gitq init -q
  printf 'x\n' > f.ts; gitq add f.ts; gitq commit -qm init
  run "https://github.com/o/r/pull/5"
  assert_exit_fail "$RC"; assert_match "$ERR" "remote" )

# ---------------------------------------------------------------- per-provider happy path

( t "github pull url resolves via refs/pull/N/head, isolated worktree, three-dot range"
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"
  assert_match "$RANGE" "^origin/main\.\.\.[0-9a-f]{7,40}$"
  [ -d "$WT" ] && ok || bad "worktree dir should exist"
  assert_head "$WT" "let b = 2;" )

( t "gitlab MR url resolves via refs/merge-requests/N/head"
  remote="$(make_remote o/r refs/merge-requests/7/head)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://gitlab.com/group/subgroup/project/-/merge_requests/7"
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/main\.\.\.[0-9a-f]{7,40}$"; assert_head "$WT" "let b = 2;" )

( t "bitbucket PR url resolves via refs/pull-requests/N/from"
  remote="$(make_remote o/r refs/pull-requests/9/from)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://bitbucket.example.com/scm/proj/repo/pull-requests/9"
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/main\.\.\.[0-9a-f]{7,40}$"; assert_head "$WT" "let b = 2;" )

( t "gitea 'pulls' url kind resolves via refs/pull/N/head"
  remote="$(make_remote o/r refs/pull/5/head)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://gitea.example.com/o/r/pulls/5"
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/main\.\.\.[0-9a-f]{7,40}$"; assert_head "$WT" "let b = 2;" )

( t "gitlab hyphenated 'merge-requests' url kind resolves via refs/merge-requests/N/head"
  remote="$(make_remote o/r refs/merge-requests/7/head)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://gitlab.example.com/o/r/-/merge-requests/7"
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/main\.\.\.[0-9a-f]{7,40}$"; assert_head "$WT" "let b = 2;" )

# ---------------------------------------------------------------- URL variants (parse AND resolve)

( t "trailing .diff, /files, ?query and www. all parse AND resolve to the request head"
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  for u in \
    "https://github.com/o/r/pull/5.diff" \
    "https://github.com/o/r/pull/5/files" \
    "https://github.com/o/r/pull/5?w=1" \
    "https://www.github.com/o/r/pull/5"; do
    run "$u"
    assert_exit_ok "$RC"
    assert_head "$WT" "let b = 2;"
  done )

# ---------------------------------------------------------------- isolation

( t "caller's branch and dirty worktree are untouched (no clean-tree guard, no checkout)"
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  printf 'let a = 1;\nlet dirty = 9;\n' > f.ts     # uncommitted tracked change — must NOT block
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"
  assert_eq "$(git -C "$dir" symbolic-ref --short HEAD)" "main"
  grep -q "let dirty = 9;" "$dir/f.ts" && ok || bad "caller's uncommitted change must survive untouched" )

( t "the created worktree is a real, removable linked worktree"
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"
  git -C "$dir" worktree list | grep -qF "$WT" && ok || bad "resolver worktree should be registered"
  git -C "$dir" worktree remove --force "$WT" >/dev/null 2>&1 && ok || bad "worktree should be cleanly removable" )

# ---------------------------------------------------------------- three-dot correctness (divergent base)

( t "range is three-dot: a commit made on main AFTER the branch point is excluded"
  remote="$(mktemp -d)/o/r.git"; mkdir -p "$(dirname "$remote")"
  git init -q --bare "$remote"; git -C "$remote" symbolic-ref HEAD refs/heads/main
  seed="$(mktemp -d)"
  ( cd "$seed"
    gitq init -q; git symbolic-ref HEAD refs/heads/main
    printf 'let a = 1;\n' > f.ts; gitq add f.ts; gitq commit -qm base
    gitq remote add origin "$remote"; gitq push -q origin main
    gitq checkout -qb pr
    printf 'let a = 1;\nlet b = 2;\n' > f.ts; gitq commit -qam feature
    gitq push -q origin pr:refs/pull/5/head
    gitq checkout -q main
    printf 'let m = 3;\n' > g.ts; gitq add g.ts; gitq commit -qm main-moves-on
    gitq push -q origin main )
  dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"
  names="$(git -C "$WT" diff "$RANGE" --name-only)"
  printf '%s\n' "$names" | grep -qx f.ts && ok || bad "range should include the PR's f.ts change"
  printf '%s\n' "$names" | grep -qx g.ts && bad "three-dot range must EXCLUDE main's later g.ts (two-dot regression)" || ok )

# ---------------------------------------------------------------- base branch resolution

( t "explicit base override diffs against the given branch (pre-tracked)"
  remote="$(mktemp -d)/o/r.git"; mkdir -p "$(dirname "$remote")"
  git init -q --bare "$remote"; git -C "$remote" symbolic-ref HEAD refs/heads/main
  seed="$(mktemp -d)"
  ( cd "$seed"
    gitq init -q; git symbolic-ref HEAD refs/heads/main
    printf 'let a = 1;\n' > f.ts; gitq add f.ts; gitq commit -qm base
    gitq remote add origin "$remote"; gitq push -q origin main
    gitq checkout -qb release; gitq push -q origin release
    gitq checkout -qb pr
    printf 'let a = 1;\nlet b = 2;\n' > f.ts; gitq commit -qam feature
    gitq push -q origin pr:refs/pull/5/head )
  dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://github.com/o/r/pull/5" release
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/release\.\.\.[0-9a-f]{7,40}$" )

( t "base override fetches a base branch the consumer has NOT tracked yet"
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"      # tracks only main
  w="$(mktemp -d)"; gitq clone -q "$remote" "$w" >/dev/null 2>&1
  ( cd "$w"; git config protocol.file.allow always
    gitq checkout -qb release; printf 'let r = 5;\n' >> f.ts; gitq commit -qam rel; gitq push -q origin release )
  cd "$dir"
  [ -z "$(git rev-parse --verify --quiet origin/release || true)" ] && ok || bad "precondition: origin/release must not pre-exist"
  run "https://github.com/o/r/pull/5" release
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/release\.\.\.[0-9a-f]{7,40}$" )

( t "unknown base override -> clear error naming the override"
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://github.com/o/r/pull/5" nonesuch
  assert_exit_fail "$RC"; assert_match "$ERR" "nonesuch" )

( t "master-default remote resolves base to master"
  remote="$(mktemp -d)/o/r.git"; build_bare "$remote" "let b = 2;" refs/pull/5/head master
  dir="$(mktemp -d)/consumer"; gitq clone -q "$remote" "$dir" >/dev/null 2>&1
  ( cd "$dir"; git config protocol.file.allow always )
  cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/master\.\.\.[0-9a-f]{7,40}$" )

( t "default_base falls through to the main/master loop when the remote HEAD is unresolvable"
  # Bare HEAD -> unborn main; only 'master' and the pull ref exist, so ls-remote
  # --symref HEAD returns nothing and default_base must reach its main/master loop.
  bare="$(mktemp -d)/o/r.git"; mkdir -p "$(dirname "$bare")"
  git init -q --bare "$bare"; git -C "$bare" symbolic-ref HEAD refs/heads/main
  seed="$(mktemp -d)"
  ( cd "$seed"
    gitq init -q; git symbolic-ref HEAD refs/heads/master
    printf 'let a = 1;\n' > f.ts; gitq add f.ts; gitq commit -qm base
    gitq remote add origin "$bare"; gitq push -q origin master
    gitq checkout -qb pr; printf 'let a = 1;\nlet b = 2;\n' > f.ts; gitq commit -qam feature
    gitq push -q origin pr:refs/pull/5/head )
  # Manual init + fetch (NOT clone) so origin/HEAD is never set locally either.
  dir="$(mktemp -d)/consumer"; mkdir -p "$dir"
  ( cd "$dir"; gitq init -q; git config protocol.file.allow always
    gitq remote add origin "$bare"; gitq fetch -q origin >/dev/null 2>&1 )
  cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/master\.\.\.[0-9a-f]{7,40}$" )

( t "default_base resolves via ls-remote --symref HEAD (tier 2) when local origin/HEAD is unset"
  # The bare's default branch is 'develop' — deliberately NOT in default_base's
  # main/master fallback loop — so ONLY tier 2 (ls-remote --symref HEAD) can resolve
  # it: were tier 2 broken, resolution would fall through and FAIL rather than
  # silently pass via 'main'. origin/HEAD is deleted after fetch (recent git sets it
  # on fetch) so tier 1 (rev-parse origin/HEAD) yields nothing and tier 2 must run.
  bare="$(mktemp -d)/o/r.git"; build_bare "$bare" "let b = 2;" refs/pull/5/head develop
  dir="$(mktemp -d)/consumer"; mkdir -p "$dir"
  ( cd "$dir"; gitq init -q; git config protocol.file.allow always
    gitq remote add origin "$bare"; gitq fetch -q origin >/dev/null 2>&1
    gitq remote set-head origin -d >/dev/null 2>&1 || true )
  cd "$dir"
  [ -z "$(git rev-parse --verify --quiet origin/HEAD || true)" ] && ok || bad "precondition: origin/HEAD must not be set locally"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"; assert_match "$RANGE" "^origin/develop\.\.\.[0-9a-f]{7,40}$" )

( t "full-ref base override (refs/heads/main) resolves via the fetched-SHA endpoint"
  # `git fetch origin refs/heads/main` succeeds but updates no origin/refs/heads/main
  # tracking ref, so BASE_REF falls back to the freshly-fetched SHA (both endpoints SHAs).
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://github.com/o/r/pull/5" refs/heads/main
  assert_exit_ok "$RC"
  assert_match "$RANGE" "^[0-9a-f]{7,40}\.\.\.[0-9a-f]{7,40}$" )

( t "base fetch fails but a tracking ref exists -> uses it WITH a staleness warning"
  # release is pushed then deleted on the remote AFTER the consumer cloned it, so
  # origin/release exists locally but `git fetch origin release` fails.
  remote="$(mktemp -d)/o/r.git"; mkdir -p "$(dirname "$remote")"
  git init -q --bare "$remote"; git -C "$remote" symbolic-ref HEAD refs/heads/main
  seed="$(mktemp -d)"
  ( cd "$seed"
    gitq init -q; git symbolic-ref HEAD refs/heads/main
    printf 'let a = 1;\n' > f.ts; gitq add f.ts; gitq commit -qm base
    gitq remote add origin "$remote"; gitq push -q origin main
    gitq checkout -qb release; gitq push -q origin release
    gitq checkout -qb pr; printf 'let a = 1;\nlet b = 2;\n' > f.ts; gitq commit -qam feature
    gitq push -q origin pr:refs/pull/5/head )
  dir="$(make_consumer "$remote")"                              # clones origin/release
  git -C "$remote" update-ref -d refs/heads/release             # now gone on the remote
  cd "$dir"
  [ -n "$(git rev-parse --verify --quiet origin/release || true)" ] && ok || bad "precondition: origin/release must pre-exist locally"
  run "https://github.com/o/r/pull/5" release
  assert_exit_ok "$RC"
  assert_match "$RANGE" "^origin/release\.\.\.[0-9a-f]{7,40}$"
  assert_match "$ERR" "possibly-stale|could not fetch base" )

( t "empty-diff request (head == base) resolves ok; collect.sh reports no changes"
  remote="$(mktemp -d)/o/r.git"; mkdir -p "$(dirname "$remote")"
  git init -q --bare "$remote"; git -C "$remote" symbolic-ref HEAD refs/heads/main
  seed="$(mktemp -d)"
  ( cd "$seed"
    gitq init -q; git symbolic-ref HEAD refs/heads/main
    printf 'let a = 1;\n' > f.ts; gitq add f.ts; gitq commit -qm base
    gitq remote add origin "$remote"; gitq push -q origin main
    gitq push -q origin main:refs/pull/5/head )                 # PR head == main tip (no changes)
  dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"                                          # resolver still succeeds
  ( cd "$WT" && "$COLLECT" "$RANGE" >/dev/null 2>"$WORKROOT/empty_err" ); ec=$?
  [ "$ec" -ne 0 ] && ok || bad "collect.sh should report no changes on an empty-diff PR"
  grep -qi "no changes" "$WORKROOT/empty_err" && ok || bad "collect.sh error should say 'no changes'" )

( t "github base is read from gh (stubbed) when CCR_NO_GH is unset"
  # A fake 'gh' on PATH answers the baseRefName query with a NON-default branch, so
  # a resulting origin/release range proves the gh base-resolution path ran (default
  # would give origin/main). Runs the real script WITHOUT CCR_NO_GH; the stub means
  # no network and the real gh binary is never reached.
  remote="$(mktemp -d)/o/r.git"; mkdir -p "$(dirname "$remote")"
  git init -q --bare "$remote"; git -C "$remote" symbolic-ref HEAD refs/heads/main
  seed="$(mktemp -d)"
  ( cd "$seed"
    gitq init -q; git symbolic-ref HEAD refs/heads/main
    printf 'let a = 1;\n' > f.ts; gitq add f.ts; gitq commit -qm base
    gitq remote add origin "$remote"; gitq push -q origin main
    gitq checkout -qb release; gitq push -q origin release
    gitq checkout -qb pr; printf 'let a = 1;\nlet b = 2;\n' > f.ts; gitq commit -qam feature
    gitq push -q origin pr:refs/pull/5/head )
  dir="$(make_consumer "$remote")"; cd "$dir"
  bindir="$(mktemp -d)/bin"; mkdir -p "$bindir"
  printf '#!/bin/sh\ncase "$*" in\n  *"pr view"*baseRefName*) echo release ;;\n  *) exit 1 ;;\nesac\n' > "$bindir/gh"
  chmod +x "$bindir/gh"
  GH_OUT="$(env -u CCR_NO_GH PATH="$bindir:$PATH" "$SCRIPT" "https://github.com/o/r/pull/5" 2>/dev/null)"; grc=$?
  assert_exit_ok "$grc"
  assert_match "$(printf '%s\n' "$GH_OUT" | sed -n 2p)" "^origin/release\.\.\.[0-9a-f]{7,40}$" )

( t "github base falls back to the default branch when gh is present but failing (unauthenticated)"
  # A fake 'gh' that always exits non-zero (as an unauthenticated gh would) must not
  # abort resolution: the base falls through to the remote default (origin/main).
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  bindir="$(mktemp -d)/bin"; mkdir -p "$bindir"
  printf '#!/bin/sh\nexit 1\n' > "$bindir/gh"; chmod +x "$bindir/gh"
  GH_OUT="$(env -u CCR_NO_GH PATH="$bindir:$PATH" "$SCRIPT" "https://github.com/o/r/pull/5" 2>/dev/null)"; grc=$?
  assert_exit_ok "$grc"
  assert_match "$(printf '%s\n' "$GH_OUT" | sed -n 2p)" "^origin/main\.\.\.[0-9a-f]{7,40}$" )

# ---------------------------------------------------------------- remote selection tiers

( t "picks the remote matching the URL owner/repo over a decoy origin (tier 3 > origin), range names it"
  upstream="$(make_remote o/r refs/pull/5/head "let real = 2;")"
  decoy="$(make_remote x/y refs/pull/5/head "let decoy = 9;")"
  dir="$(mktemp -d)/consumer"; gitq clone -q "$decoy" "$dir" >/dev/null 2>&1      # origin = decoy (x/y)
  ( cd "$dir"; git config protocol.file.allow always
    gitq remote add upstream "$upstream"; gitq fetch -q upstream >/dev/null 2>&1; gitq checkout -q main >/dev/null 2>&1 )
  cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"
  assert_head "$WT" "let real = 2;"
  grep -q "let decoy = 9;" "$WT/f.ts" && bad "must not resolve the origin decoy head" || ok
  assert_match "$RANGE" "^upstream/main\.\.\." )

( t "correct-host remote (tier 1) beats a wrong-host same-owner/repo remote (tier 3)"
  # The github remote is named 'zzz' so it sorts AFTER 'origin': only host+owner/repo
  # tiering (not alphabetical remote order) can promote it above the origin decoy.
  ghbare="$(mktemp -d)/github.com/o/r.git"; build_bare "$ghbare" "let real = 2;"
  glbare="$(mktemp -d)/gitlab.com/o/r.git"; build_bare "$glbare" "let decoy = 9;"
  dir="$(mktemp -d)/consumer"; gitq clone -q "$glbare" "$dir" >/dev/null 2>&1     # origin = wrong-host decoy
  ( cd "$dir"; git config protocol.file.allow always
    gitq remote add zzz "$ghbare"; gitq fetch -q zzz >/dev/null 2>&1; gitq checkout -q main >/dev/null 2>&1 )
  cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"
  assert_head "$WT" "let real = 2;"
  grep -q "let decoy = 9;" "$WT/f.ts" && bad "must not pick the wrong-host remote" || ok )

( t "host-tier match selects a remote by host when no owner/repo matches, and WARNs about the mismatch"
  hostbare="$(mktemp -d)/github.com/other/repo.git"; build_bare "$hostbare" "let real = 2;"
  dir="$(mktemp -d)/consumer"; gitq clone -q "$hostbare" "$dir" >/dev/null 2>&1
  ( cd "$dir"; git config protocol.file.allow always; gitq checkout -q main >/dev/null 2>&1 )
  cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"; assert_head "$WT" "let real = 2;"
  assert_match "$ERR" "does not match the request's owner/repo" )   # unmatched-remote safety WARN must fire

( t "fetch loop tries the next remote when an earlier one lacks the ref"
  empty="$(mktemp -d)/o/r.git"; mkdir -p "$(dirname "$empty")"
  git init -q --bare "$empty"; git -C "$empty" symbolic-ref HEAD refs/heads/main
  s="$(mktemp -d)"; ( cd "$s"; gitq init -q; git symbolic-ref HEAD refs/heads/main
    printf 'let a = 1;\n' > f.ts; gitq add f.ts; gitq commit -qm base; gitq remote add origin "$empty"; gitq push -q origin main )
  real="$(make_remote o/r refs/pull/5/head "let real = 2;")"
  dir="$(mktemp -d)/consumer"; gitq clone -q "$real" "$dir" >/dev/null 2>&1        # origin = real (has pull ref)
  ( cd "$dir"; git config protocol.file.allow always
    gitq remote add aaa "$empty"; gitq fetch -q aaa >/dev/null 2>&1; gitq checkout -q main >/dev/null 2>&1 )   # 'aaa' sorts first, lacks the ref
  cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"; assert_head "$WT" "let real = 2;" )

# ---------------------------------------------------------------- collect.sh integration

( t "resolved range + worktree feed collect.sh: f.ts:2 added, base line f.ts:1 not added"
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  run "https://github.com/o/r/pull/5"
  assert_exit_ok "$RC"
  CO="$( cd "$WT" && "$COLLECT" "$RANGE" 2>"$WORKROOT/collect_err" )"; CRC=$?
  [ "$CRC" -eq 0 ] && ok || bad "collect.sh should succeed in the worktree: $(cat "$WORKROOT/collect_err")"
  assert_file_has  "$CO/addedlines.txt" "f.ts:2"
  assert_file_lacks "$CO/addedlines.txt" "f.ts:1"
  assert_file_has  "$CO/files.txt" "f.ts" )

# ---------------------------------------------------------------- SKILL glue contract (Step 1.5)

( t "SKILL glue: \$(...) capture preserves exit status; two-line parse feeds collect and removal"
  remote="$(make_remote)"; dir="$(make_consumer "$remote")"; cd "$dir"
  PR_OUT="$(CCR_NO_GH=1 "$SCRIPT" "https://github.com/o/r/pull/5")"; rc=$?      # exactly the SKILL.md capture
  assert_exit_ok "$rc"
  W="$(printf '%s\n' "$PR_OUT" | sed -n 1p)"; R="$(printf '%s\n' "$PR_OUT" | sed -n 2p)"
  ( cd "$W" && "$COLLECT" "$R" >/dev/null 2>&1 ) && ok || bad "collect should run in the worktree from the glue"
  git -C "$dir" worktree remove --force "$W" >/dev/null 2>&1 && ok || bad "glue worktree removal should succeed"
  BAD_OUT="$(CCR_NO_GH=1 "$SCRIPT" "https://github.com/o/r/issues/9" 2>/dev/null)"; brc=$?    # failure propagates through $(...)
  assert_exit_fail "$brc"
  [ -z "$BAD_OUT" ] && ok || bad "a failed resolve must emit no stdout" )

# ---------------------------------------------------------------- SKILL.md documents the feature

( t "SKILL.md documents the PR-link target, the resolver, and the isolated worktree"
  grep -qiE "pull request|PR/MR|/pull/" "$SKILL_DIR/SKILL.md" && ok || bad "SKILL.md should document the PR-link target"
  grep -q "resolve-pr.sh" "$SKILL_DIR/SKILL.md" && ok || bad "SKILL.md should reference resolve-pr.sh"
  grep -qi "worktree" "$SKILL_DIR/SKILL.md" && ok || bad "SKILL.md should document the isolated worktree + its cleanup" )

# ----------------------------------------------------------------

PASS="$(grep -c '^PASS$' "$RESULTS")"
FAIL="$(grep -c '^FAIL' "$RESULTS")"
rm -rf "$WORKROOT"
echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
