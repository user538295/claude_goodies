#!/usr/bin/env bash
# count-uncompleted-tasks.sh <plan_file>
#
# Counts TOP-LEVEL lines matching "- [ ]" in a plan file (unindented, so
# sub-tasks are excluded). Each top-level task should produce exactly one commit.
# Prints the count to stdout.
#
# Only counts tasks within the recognized task section heading:
#   "## Tasks", "## Task", or "## Task breakdown" (case-insensitive).
# Stops counting at the next "## " heading after the task section.
#
# Exit 0 = success (count printed)
# Exit 2 = usage error or file not found
#
# Output format: number_of_uncompleted_tasks=<count>  (key=value, always on stdout)
# Usage: output=$(bash ~/.claude/scripts/count-uncompleted-tasks.sh path/to/plan.md)
#        then parse: number_of_uncompleted_tasks=$(echo "$output" | grep -o '[0-9]*$')

set -uo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: count-uncompleted-tasks.sh <plan_file>" >&2
    exit 2
fi

plan_file="$1"

if [ ! -f "${plan_file}" ]; then
    echo "ERROR: plan file not found: ${plan_file}" >&2
    exit 2
fi

# Only count top-level tasks (line starts with "- [ ]", no leading spaces) that
# appear within a recognized task section heading:
#   "## Tasks", "## Task", or "## Task breakdown" (case-insensitive).
# Stops at the next "## " heading after the task section.
# Sub-tasks (indented) are checked off as part of their parent — not separate commits.
_scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
count=$(awk "$(cat "$_scripts_dir/task_section.awk")
found && /^- \[ \]/ { c++ }
END { print c+0 }" "${plan_file}")
count="${count:-0}"

# Warn if no tasks were found but the file has uncompleted checkboxes — likely
# a missing or unrecognized task section heading.
if [ "${count}" -eq 0 ] && grep -q '^- \[ \]' "${plan_file}"; then
    echo "WARNING: ${plan_file} has uncompleted tasks (- [ ]) but no recognized task section heading (## Tasks / ## Task breakdown). Count may be wrong." >&2
fi

echo "number_of_uncompleted_tasks=${count}"
