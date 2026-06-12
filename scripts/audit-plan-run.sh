#!/usr/bin/env bash
# RECOVERY_SCHEMA_V2
# audit-plan-run.sh <plan_file> <sha_start>
#
# Standalone post-run audit. Independently verifies that the number of
# non-merge commits since sha_start matches the number of completed tasks
# (- [x]) in the plan file.
#
# Recovery-aware: commits whose subject begins with `recovery(R-B):` or
# `recovery(R-AB):` are counted as recovery commits. If the difference
# `(commits - recovery_commits) == completed`, a WARNING is emitted and exit 0.
# Audit also surfaces existence of `<cwd>/.claude/recovery-anomalies.log`.
#
# Run this after /implement-all or /implement-all-cc to verify the run without relying on Claude.
# Can also be run at any time to audit a historical run.
#
# Exit 0 = PASS (including PASS-with-WARNING for recovery commits)
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

# Count recovery commits (subject anchored at column 1, matches both R-B and R-AB).
# Uses --no-merges so a merge commit with a recovery-looking subject is excluded
# (consistent with the `commits` count above).
recovery_commits=$(git log --format='%s' --no-merges "${sha_start}..HEAD" 2>/dev/null | grep -cE '^recovery\((R-B|R-AB)\):' || true)

echo "Plan file : ${plan_file}"
echo "sha_start : ${sha_start}"
echo "Tasks completed in this run (top-level) : ${completed}"
echo "Non-merge commits since sha_start : ${commits}"
echo ""
git log --oneline --no-merges "${sha_start}..HEAD" >&2
echo "" >&2

# Anomalies log existence surface: append to stdout regardless of audit verdict.
# Anchor to the repo root (matches where the triage script writes the log).
# Falls back to $(pwd) if outside a repo, but the early git checks above
# guarantee we're inside a repo by this point.
_anomalies_log="${repo_root:-$(pwd)}/.claude/recovery-anomalies.log"
_anomalies_surface=""
if [ -f "${_anomalies_log}" ]; then
    _anomalies_lines=$(wc -l < "${_anomalies_log}" 2>/dev/null | tr -d '[:space:]')
    _anomalies_surface="RECOVERY ANOMALIES LOG: ${_anomalies_log} (lines=${_anomalies_lines:-0})"
fi

# Recovery-aware dispatch:
#   - (commits - recovery_commits) == completed AND recovery_commits > 0
#     → PASS with WARNING (recovery commits accepted, audit downgraded)
#   - commits == completed AND recovery_commits == 0
#     → existing PASS
#   - otherwise → VIOLATION
if [ "$recovery_commits" -gt 0 ] && [ $((commits - recovery_commits)) -eq "$completed" ]; then
    # Build the sorted, space-separated list of marker types present in the range.
    _recovery_types=$(git log --format='%s' --no-merges "${sha_start}..HEAD" 2>/dev/null \
        | grep -oE '^recovery\((R-B|R-AB)\):' \
        | sed -E 's/^recovery\(//; s/\):$//' \
        | sort -u \
        | tr '\n' ' ')
    echo "WARNING: Recovery commit(s) detected (count=${recovery_commits}, types: ${_recovery_types})"
    echo "PASS: ${commits} commits (${recovery_commits} recovery) for ${completed} completed tasks — counts match after recovery adjustment"
    # Emit recovery subjects to stderr for human eyeball review.
    {
        echo "Recovery commit subjects:"
        git log --format='%h %s' --no-merges "${sha_start}..HEAD" 2>/dev/null \
            | grep -E '^[a-f0-9]+ recovery\((R-B|R-AB)\):'
    } >&2
    if [ -n "${_anomalies_surface}" ]; then
        echo "${_anomalies_surface}"
    fi
    exit 0
elif [ "$commits" -eq "$completed" ]; then
    echo "PASS: ${commits} commits for ${completed} completed tasks — counts match"
    if [ -n "${_anomalies_surface}" ]; then
        echo "${_anomalies_surface}"
    fi
    exit 0
else
    echo "VIOLATION: ${commits} commits for ${completed} completed tasks — counts do not match"
    if [ -n "${_anomalies_surface}" ]; then
        echo "${_anomalies_surface}"
    fi
    exit 1
fi
