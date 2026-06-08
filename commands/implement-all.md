---
description: Repeatedly run /implement-next on a plan file until every task is complete. Accepts an exact file path or a name/keyword — resolves automatically for unique matches, asks for clarification when ambiguous.
---

### Step 0: Resolve the plan file

**First check:** If `$ARGUMENTS` is blank or was not provided, stop and ask the user: "Please provide a plan file path or keyword to search for."

Run `test -f "$ARGUMENTS"`.

- If the file exists: set the resolved path to `$ARGUMENTS` and continue to the Loop body below.
- If it does not exist: use the Glob tool to search for `**/*.md` files, filter results by keyword match on name or path, then Read each keyword-matched candidate and check it contains at least one unchecked task line (`- [ ]`). Discard any that does not.
  - Exactly one match → set the resolved path to that path, note it to the user.
  - Multiple matches → stop and ask the user to choose: "Found multiple matching plan files: [list them]. Please provide the full path to the one you want."
  - No match → stop and ask the user: "Could not find a plan file matching '$ARGUMENTS'. Please provide the full path."

/goal All tasks in the plan file are marked complete (plan-progress.sh returns exit 1).

### Loop body

Track `previous_task_name` (initially empty) and `iteration_count` (initially 0) across iterations. Increment `iteration_count` at the start of each iteration. If `iteration_count` exceeds 50, stop and report: "Loop has exceeded 50 iterations without completing — possible infinite loop. Please investigate."

Each iteration toward the goal:

1. Run the following, replacing `<plan-path>` with the actual resolved file path from Step 0 (the literal path string):
   ```
   bash ~/.claude/scripts/plan-progress.sh "<plan-path>"
   ```
   - Exit 1 → all tasks complete — goal achieved, stop.
   - Exit 2 or 3 → stop and report the error.
   - Any other exit code → stop and report the unexpected exit code.
   - Exit 0 → tasks remain, note the reported NEXT_TASK_NAME and continue to step 2.

   **Stuck-task guard:** If the NEXT_TASK_NAME reported in this iteration is the same as `previous_task_name`, stop and report: "Task '<task-name>' appears to be stuck — it was reported as next in two consecutive iterations. Please investigate before continuing." Otherwise, update `previous_task_name` to the current NEXT_TASK_NAME before proceeding.

2. Spawn a background agent with the prompt (replacing `<plan-path>` with the actual resolved file path — the literal path string):
   > Call the Skill tool with skill `implement-next` and args `<plan-path>`.
