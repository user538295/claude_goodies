#!/usr/bin/env bash
# audit-plan-run.sh <plan_file> <sha_start>
#
# Standalone post-run audit. Independently verifies that the number of
# non-merge commits since sha_start matches the number of completed tasks
# (- [x]) in the plan file.
#
# Run this after /implement-all or /implement-all-cc to verify the run without relying on Claude.
# Can also be run at any time to audit a historical run.
#
# Exit 0 = PASS
# Exit 1 = VIOLATION or mismatch
# Exit 2 = usage or git error
#
# Example:
#   bash ~/.claude/scripts/audit-plan-run.sh Documentation/Backlog/FEAT-017.md abc1234

set -uo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: audit-plan-run.sh <plan_file> <sha_start>" >&2
    exit 2
fi

plan_file="$1"
sha_start="$2"

if [ ! -f "${plan_file}" ]; then
    echo "ERROR: plan file not found: ${plan_file}" >&2
    exit 2
fi

if ! git rev-parse --verify "${sha_start}" >/dev/null 2>&1; then
    echo "ERROR: '${sha_start}' is not a valid git ref" >&2
    exit 2
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "ERROR: cannot resolve HEAD" >&2
    exit 2
fi

# Normalize plan_file to a repo-relative path for git tree lookups.
# git show requires repo-relative paths; absolute paths silently fail.
# Strategy: strip repo root prefix from absolute paths; fall back to git ls-files for relative.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
plan_file_rel=""
if [ -n "${repo_root}" ] && [ "${plan_file#"${repo_root}/"}" != "${plan_file}" ]; then
    # Absolute path inside the repo: strip the repo root prefix
    plan_file_rel="${plan_file#"${repo_root}/"}"
else
    # Relative path: ask git for the canonical repo-relative form
    plan_file_rel=$(git ls-files --full-name -- "${plan_file}" 2>/dev/null || true)
fi

# Count TOP-LEVEL completed tasks (unindented) — case-insensitive [x]/[X].
# Only counts tasks within the recognised task section heading (## Tasks / ## Task breakdown),
# stopping at the next ## heading. Shared awk logic lives in task_section.awk.
# Sub-tasks are excluded because they are checked off as part of their parent task.
# Compute only tasks completed during this run by diffing against sha_start.
_scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_section_completed_awk="$(cat "$_scripts_dir/task_section.awk")
found && /^- \[[xX]\]/ { c++ }
END { print c+0 }"

pre_completed=0
if [ -n "${plan_file_rel}" ] && git cat-file -e "${sha_start}:${plan_file_rel}" 2>/dev/null; then
    if _pre=$(git show "${sha_start}:${plan_file_rel}" 2>/dev/null | awk "${_section_completed_awk}"); then
        pre_completed="${_pre:-0}"
    fi
else
    echo "INFO: Plan file not found in git tree at ${sha_start} — assuming 0 pre-existing completed tasks." >&2
fi
if _all=$(awk "${_section_completed_awk}" "${plan_file}" 2>/dev/null); then
    all_completed="${_all:-0}"
else
    all_completed=0
fi
completed=$((all_completed - pre_completed))

# Guard against negative count (tasks were unchecked during the run)
if [ "${completed}" -lt 0 ]; then
    echo "WARNING: Task regression detected — ${pre_completed} task(s) were completed at sha_start, but only ${all_completed} are completed now." >&2
    echo "         Cannot determine how many tasks were completed in this run. Aborting." >&2
    exit 1
fi

# Count non-merge commits since sha_start
if ! commits=$(git rev-list --count --no-merges "${sha_start}..HEAD"); then
    echo "ERROR: git rev-list failed for range '${sha_start}..HEAD'" >&2
    exit 2
fi

echo "Plan file : ${plan_file}"
echo "sha_start : ${sha_start}"
echo "Tasks completed in this run (top-level) : ${completed}"
echo "Non-merge commits since sha_start : ${commits}"
echo ""
git log --oneline --no-merges "${sha_start}..HEAD" >&2
echo "" >&2

if [ "$commits" -eq "$completed" ]; then
    echo "PASS: ${commits} commits for ${completed} completed tasks — counts match"
    exit 0
else
    echo "VIOLATION: ${commits} commits for ${completed} completed tasks — counts do not match"
    exit 1
fi
