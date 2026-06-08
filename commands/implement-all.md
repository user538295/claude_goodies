---
description: Repeatedly run /implement-next on $ARGUMENTS until every task in the plan is complete.
---

Plan file: $ARGUMENTS

### Step 0: Resolve the plan file

Run `test -f "$ARGUMENTS"`.

- If the file exists: set PLAN_FILE=$ARGUMENTS and continue to step 1.
- If it does not exist: use Glob and/or Bash `find` to search for plan files
  whose name or path contains keywords from $ARGUMENTS. Search the current
  directory recursively (maxdepth 5) and common locations like `./plans/` and
  `./docs/`.
  - Exactly one match → set PLAN_FILE to that path, note the resolved path to the user.
  - Multiple matches → pick the most likely one based on name similarity
    (prefer exact stem match, then shallowest path), explain the choice to the user.
  - No match → stop and ask the user: "Could not find a plan file matching
    '$ARGUMENTS'. Please provide the full path."

/goal All tasks in PLAN_FILE are marked complete.

Each iteration toward the goal:

1. Run `bash ~/.claude/scripts/plan-progress.sh $PLAN_FILE`
   - Exit 1 → all tasks complete — goal achieved, stop.
   - Exit 2 or 3 → stop and report the error.
   - Exit 0 → tasks remain, continue to step 2.

2. Spawn an agent with the prompt:
   > Use the /implement-next skill (via the Skill tool) to implement the next unfinished task in file $PLAN_FILE.
