#!/usr/bin/env bash
# verify-run-commits.sh <sha_start> <expected_count>
#
# Verifies exactly N non-merge commits were created since sha_start.
# Run as the final audit step in /implement-all.
#
# Exit 0 = PASS
# Exit 1 = VIOLATION
# Exit 2 = usage or git error
#
# Known limitations:
#   - Counts commits, not content. Two tasks swapped into one commit + one empty
#     commit still gives count == N. The per-iteration check-task-commit.sh
#     catches this during the run, not here.
#   - Resume sessions re-record sha_start, so prior-session violations fall
#     outside the audit window. Use audit-plan-run.sh for a full-history check.

set -uo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: verify-run-commits.sh <sha_start> <expected_count>" >&2
    exit 2
fi

sha_start="$1"
expected="$2"

# Validate expected is a non-negative integer
if ! printf '%s' "${expected}" | grep -qE '^[0-9]+$'; then
    echo "ERROR: expected_count '${expected}' is not a non-negative integer" >&2
    exit 2
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "ERROR: cannot resolve HEAD" >&2
    exit 2
fi

if ! git rev-parse --verify "${sha_start}" >/dev/null 2>&1; then
    echo "ERROR: sha_start '${sha_start}' is not a valid git ref" >&2
    exit 2
fi

# --count before range for portability; --no-merges excludes merge commits
if ! actual=$(git rev-list --count --no-merges "${sha_start}..HEAD"); then
    echo "ERROR: git rev-list failed for range '${sha_start}..HEAD'" >&2
    exit 2
fi

echo "Non-merge commits since ${sha_start}: ${actual} (expected ${expected})"
git log --oneline --no-merges "${sha_start}..HEAD" >&2
echo "" >&2

if [ "$actual" -eq "$expected" ]; then
    echo "PASS: ${actual}/${expected} commits — one per task"
    exit 0
else
    echo "VIOLATION: expected ${expected} non-merge commits, got ${actual} — per-task commit rule was broken"
    exit 1
fi
