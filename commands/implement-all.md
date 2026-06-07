---
description: Repeatedly run /implement-next on $ARGUMENTS until every task in the plan is complete.
---

Plan file: $ARGUMENTS

/goal All tasks in $ARGUMENTS are marked complete.

Each iteration toward the goal:

1. Run `bash ~/.claude/scripts/plan-progress.sh $ARGUMENTS`
   - Exit 1 → all tasks complete — goal achieved, stop.
   - Exit 2 or 3 → stop and report the error.
   - Exit 0 → tasks remain, continue to step 2.

2. Spawn an agent with the prompt:
   > Use the /implement-next skill (via the Skill tool) to implement the next unfinished task in file $ARGUMENTS.
