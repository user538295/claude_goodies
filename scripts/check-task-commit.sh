#!/usr/bin/env bash
# check-task-commit.sh <sha_before>
#
# Verifies AT LEAST ONE non-merge commit with non-empty file changes was created
# since sha_before. Run as part of /implement-next Step 7 self-verification
# (portable) or by /implement-next-cc parent-level checks.
#
# This script intentionally accepts >=1 commit (matching the SubagentStop hook
# in implement-next-stop-gate.sh), since a single task may legitimately produce
# multiple commits (e.g. test commit then implementation commit). The
# one-task-one-commit aggregate invariant is enforced by audit-plan-run.sh.
#
# Exit 0 = PASS (at least one non-merge commit since sha_before)
# Exit 1 = FAIL (zero commits — task didn't commit)
# Exit 2 = usage or git error
#
# Known limitations:
#   - Counts commits, not whether the Skill tool was used. A bypass that still
#     commits per task will pass this check.
#   - Interactive rebase after the fact can manipulate counts retroactively.

set -uo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: check-task-commit.sh <sha_before>" >&2
    exit 2
fi

sha_before="$1"

# Verify HEAD is resolvable (catches detached HEAD anomalies and non-git dirs)
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "ERROR: cannot resolve HEAD — not a git repo or in unusual state" >&2
    exit 2
fi

# Verify sha_before is a valid ref (consistent with verify-run-commits.sh and audit-plan-run.sh)
if ! git rev-parse --verify "${sha_before}" >/dev/null 2>&1; then
    echo "ERROR: '${sha_before}' is not a valid git ref" >&2
    exit 2
fi

# Count non-merge commits since sha_before
# --count before range for portability; --no-merges excludes merge commits
if ! count=$(git rev-list --count --no-merges "${sha_before}..HEAD"); then
    echo "ERROR: git rev-list failed for range '${sha_before}..HEAD'" >&2
    exit 2
fi

if [ "$count" -eq 0 ]; then
    echo "FAIL: no commit was created since ${sha_before}"
    exit 1
fi

# count >= 1: verify the HEAD commit has non-empty file changes.
# git diff-tree works on all commits including root and merge commits.
if ! changed=$(git diff-tree --no-commit-id -r --name-only HEAD | awk 'END{print NR}'); then
    echo "ERROR: git diff-tree failed" >&2
    exit 2
fi

if [ "${changed}" -eq 0 ]; then
    sha_new=$(git rev-parse --short HEAD)
    echo "FAIL: commit ${sha_new} has no file changes (empty commit)"
    exit 1
fi

sha_new=$(git rev-parse --short HEAD)
echo "PASS: ${count} commit(s) (HEAD=${sha_new}), ${changed} file(s) changed in HEAD"
exit 0
