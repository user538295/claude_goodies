#!/usr/bin/env bash
# resolve-pr.sh — resolve a pull/merge-request URL to a reviewable worktree+range.
#
# /clean-code-review's detection scripts scan the working tree on disk, so a
# request review needs its commits checked out. This checks the request head out
# into an ISOLATED temporary worktree (`git worktree`) — the caller's branch and
# working tree are never touched, and no branch-restore dance is needed — then
# prints the worktree path and the `base...head` range /clean-code-review runs
# collect.sh against.
#
# Works with any provider that publishes request refs over git, one ref per URL
# kind: GitHub/Gitea `.../pull/<n>` or `.../pulls/<n>` -> refs/pull/<n>/head
#       GitLab       `.../merge_requests/<n>`          -> refs/merge-requests/<n>/head
#       Bitbucket    `.../pull-requests/<n>`           -> refs/pull-requests/<n>/from
#
# Usage: resolve-pr.sh <request-url> [base-branch]
#   base-branch  optional override for the branch the request targets; needed
#                when the request does not target the remote's default branch and
#                the base cannot be discovered automatically (see below).
#   Stdout: two lines — the worktree path, then `<base>...<head>` (a three-dot
#           range = the request's own changes since its merge-base, matching the
#           web diff). The caller removes the worktree with `git worktree remove`.
#   Stderr: human-readable status (which remote/base were used, cleanup hint).
#
# Base branch: an explicit 2nd argument wins; else, for github.com, the GitHub
# CLI is asked (`gh pr view`) when it is installed and CCR_NO_GH is unset; else
# the remote's default branch. gh is used ONLY to read the base name — the fetch
# and checkout are always plain git, so every host works without extra tooling.
set -u

err() { echo "ERROR: $*" >&2; exit 1; }

URL="${1:-}"; BASE_OVERRIDE="${2:-}"
[ -n "$URL" ] || err "No request URL given. Usage: resolve-pr.sh <request-url> [base-branch]."

# Parse <host>, the owner/repo path, and the request kind + number. A trailing
# .diff/.patch suffix and any /files, ?query or #fragment tail are tolerated;
# GitLab's `/-/` router segment is stripped from the repo path afterwards.
if [[ "$URL" =~ ^https?://([^/]+)/(.+)/(pull|pulls|merge_requests|merge-requests|pull-requests)/([0-9]+)(\.(diff|patch))?([/?#].*)?$ ]]; then
  HOST="${BASH_REMATCH[1]}"; REPO_PATH="${BASH_REMATCH[2]}"; KIND="${BASH_REMATCH[3]}"; NUM="${BASH_REMATCH[4]}"
  REPO_PATH="${REPO_PATH%/-}"          # gitlab: group/project/- -> group/project
  REPO_PATH="${REPO_PATH%.git}"
else
  err "Not a recognised pull/merge-request URL: '$URL' (expected .../pull/<n>, .../merge_requests/<n>, or .../pull-requests/<n>)."
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
  err "Not inside a git repository — cd into a checkout of the repository first."

# The single request ref for this URL kind (no brute-force across conventions:
# the URL's own path already names the provider's convention).
case "$KIND" in
  merge_requests|merge-requests) HEAD_REFSPEC="refs/merge-requests/$NUM/head" ;;
  pull-requests)                 HEAD_REFSPEC="refs/pull-requests/$NUM/from" ;;
  *)                             HEAD_REFSPEC="refs/pull/$NUM/head" ;;   # pull, pulls (Gitea)
esac

# Remotes to try, best first, so the RIGHT repo on the RIGHT host wins over a
# same-named repo elsewhere, and a fork checkout (origin=fork, upstream=base)
# still finds the head ref on upstream:
#   1. request's host AND owner/repo   2. request's host   3. owner/repo (any host)
#   4. origin                          5. the rest
# REPO_PATH is matched as a literal suffix (quoted in the ${..%..} patterns) so a
# glob metacharacter in it cannot mis-match.
matches_repo() {  # $1=remote-url (….git already stripped)
  [ "${1%"/$REPO_PATH"}" != "$1" ] || [ "${1%":$REPO_PATH"}" != "$1" ]
}
ordered_remotes() {
  local r url all; all="$(git remote)"; [ -n "$all" ] || return 0
  while IFS= read -r r; do
    url="$(git remote get-url "$r" 2>/dev/null)"; url="${url%.git}"
    case "$url" in *"$HOST"*) matches_repo "$url" && echo "$r" ;; esac
  done <<< "$all"
  while IFS= read -r r; do
    case "$(git remote get-url "$r" 2>/dev/null)" in *"$HOST"*) echo "$r" ;; esac
  done <<< "$all"
  while IFS= read -r r; do
    url="$(git remote get-url "$r" 2>/dev/null)"; url="${url%.git}"
    matches_repo "$url" && echo "$r"
  done <<< "$all"
  printf '%s\n' "$all" | grep -qx origin && echo origin
  printf '%s\n' "$all"
}
REMOTES="$(ordered_remotes | awk 'NF && !seen[$0]++')"
[ -n "$REMOTES" ] || err "No git remote configured — add a remote for $REPO_PATH first."

# Fetch the request head from the first remote that has it.
REMOTE=""; HEAD_SHA=""
for r in $REMOTES; do
  if git fetch -q "$r" "$HEAD_REFSPEC" >/dev/null 2>&1; then
    REMOTE="$r"; HEAD_SHA="$(git rev-parse --verify --quiet FETCH_HEAD)"; break
  fi
done
[ -n "$HEAD_SHA" ] || \
  err "Could not fetch request #$NUM ($HEAD_REFSPEC) from any remote (tried: $REMOTES) — check the remote URL and your access to $REPO_PATH."

# Warn if the head came from a remote whose URL does not match the request's
# owner/repo (a host-only or last-resort tier): it may belong to a DIFFERENT
# repository's request #$NUM and would otherwise be reviewed silently as this one.
sel_url="$(git remote get-url "$REMOTE" 2>/dev/null)"; sel_url="${sel_url%.git}"
matches_repo "$sel_url" || \
  echo "WARN: request head fetched from remote '$REMOTE' ($sel_url), whose URL does not match the request's owner/repo '$REPO_PATH'. If that remote is a different repository you may be reviewing its request #$NUM — verify before trusting this review." >&2

# The remote's default branch: prefer the locally-known tracking HEAD (offline),
# then ask the remote (read-only, no `git remote set-head` mutation), then main/master.
default_base() {
  local d c
  d="$(git rev-parse --abbrev-ref "$REMOTE/HEAD" 2>/dev/null)"; d="${d#"$REMOTE"/}"
  [ -n "$d" ] && [ "$d" != "HEAD" ] && { echo "$d"; return; }
  d="$(git ls-remote --symref "$REMOTE" HEAD 2>/dev/null | sed -n 's#^ref:[[:space:]]*refs/heads/\(.*\)[[:space:]]HEAD$#\1#p')"
  [ -n "$d" ] && { echo "$d"; return; }
  for c in main master; do
    git rev-parse --verify --quiet "$REMOTE/$c" >/dev/null 2>&1 && { echo "$c"; return; }
  done
}

# Base branch: explicit override > gh (github.com only) > remote default.
BASE_BRANCH="$BASE_OVERRIDE"
if [ -z "$BASE_BRANCH" ]; then
  case "$HOST" in
    github.com|www.github.com)
      if [ -z "${CCR_NO_GH:-}" ] && command -v gh >/dev/null 2>&1; then
        BASE_BRANCH="$(gh pr view "$NUM" --repo "$REPO_PATH" --json baseRefName -q .baseRefName 2>/dev/null || true)"
      fi ;;
  esac
fi
[ -n "$BASE_BRANCH" ] || BASE_BRANCH="$(default_base)"
[ -n "$BASE_BRANCH" ] || err "Could not determine the base branch for request #$NUM — pass it explicitly as the 2nd argument."

# Resolve the base to a concrete point. Fetch it fresh; a successful fetch that
# also updated the tracking ref gives a readable `<remote>/<base>` endpoint,
# otherwise the freshly-fetched SHA (never a silently-stale tracking ref). If the
# fetch fails but a tracking ref exists, use it WITH a staleness warning.
BASE_REF=""
if git fetch -q "$REMOTE" "$BASE_BRANCH" >/dev/null 2>&1; then
  fetched="$(git rev-parse --verify --quiet FETCH_HEAD || true)"
  track="$(git rev-parse --verify --quiet "$REMOTE/$BASE_BRANCH" || true)"
  if [ -n "$track" ] && [ "$track" = "$fetched" ]; then BASE_REF="$REMOTE/$BASE_BRANCH"
  elif [ -n "$fetched" ]; then BASE_REF="$fetched"
  fi
elif git rev-parse --verify --quiet "$REMOTE/$BASE_BRANCH" >/dev/null 2>&1; then
  BASE_REF="$REMOTE/$BASE_BRANCH"
  echo "WARN: could not fetch base '$BASE_BRANCH' from '$REMOTE'; using possibly-stale $BASE_REF." >&2
fi
[ -n "$BASE_REF" ] || err "Base branch '$BASE_BRANCH' not found on '$REMOTE' — pass the correct base as the 2nd argument."

# Check the head out into an isolated worktree — the caller's branch/worktree are
# left exactly as they were. WT is a fresh empty mktemp dir, so `git worktree
# remove` later deletes it whole (no orphaned parent); on failure the empty dir is
# rmdir'd (any partial worktree registration is stale and harmless).
WT="$(mktemp -d "${TMPDIR:-/tmp}/ccr-pr.XXXXXX")"
if ! git worktree add -q --detach "$WT" "$HEAD_SHA" >/dev/null 2>&1; then
  rmdir "$WT" 2>/dev/null || true
  err "Could not create an isolated worktree for request #$NUM at $HEAD_SHA."
fi

echo "Request #$NUM: head fetched from '$REMOTE', base '$BASE_BRANCH' (override with a 2nd argument)." >&2
echo "Isolated worktree at $WT — your branch and working tree are untouched; remove it when done with: git worktree remove --force $WT" >&2
printf '%s\n' "$WT"
printf '%s\n' "$BASE_REF...$HEAD_SHA"
