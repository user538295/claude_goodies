#!/usr/bin/env bash
# implement-next-state-clear.sh <cwd>
#
# Removes the SubagentStop-hook sentinel. Called by /implement-all-cc after a
# task completes (whether by normal subagent or by Case-B rescue), and as a
# safety cleanup at the end of the loop.
#
# Exit 0 = sentinel removed or already absent.
# Exit 2 = usage error.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: implement-next-state-clear.sh <cwd>" >&2
    exit 2
fi

cwd="$1"

state_file="$cwd/.claude/implement-next-state.json"
if [ -f "$state_file" ]; then
    rm -f "$state_file"
    echo "Sentinel cleared: $state_file"
fi
