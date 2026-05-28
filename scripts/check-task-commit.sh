#!/usr/bin/env bash
# check-task-commit.sh <sha_before>
#
# Verifies exactly ONE non-merge commit with non-empty file changes was created
# since sha_before. Run after each /implement-next invocation in the loop.
#
# Exit 0 = PASS
# Exit 1 = VIOLATION
# Exit 2 = usage or git error
#
# Known limitations:
#   - Counts commits, not whether the Skill tool was used. A bypass that still
#     commits per task will pass this check.
#   - A merge commit on HEAD itself is not detected as a merge (only the range
#     count uses --no-merges). Merges between tasks in the range cause count > 1,
#     triggering a false VIOLATION — exclude merges or run on non-merge branches.
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
    echo "VIOLATION: no commit was created since ${sha_before}"
    exit 1
elif [ "$count" -gt 1 ]; then
    echo "VIOLATION: expected 1 non-merge commit since ${sha_before}, got ${count}"
    git log --oneline --no-merges "${sha_before}..HEAD"
    exit 1
fi

# count == 1: verify the commit has non-empty file changes
# git diff-tree works on all commits including root and merge commits
if ! changed=$(git diff-tree --no-commit-id -r --name-only HEAD | awk 'END{print NR}'); then
    echo "ERROR: git diff-tree failed" >&2
    exit 2
fi

if [ "${changed}" -eq 0 ]; then
    sha_new=$(git rev-parse --short HEAD)
    echo "VIOLATION: commit ${sha_new} has no file changes (empty commit)"
    exit 1
fi

sha_new=$(git rev-parse --short HEAD)
echo "PASS: 1 commit (${sha_new}), ${changed} file(s) changed"
exit 0
