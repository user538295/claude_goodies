---
description: Portable runtime-agnostic — repeatedly run /implement-next on a plan file until every task is complete. Auto-detects Claude Code version and falls back to inline mode (/implement-all-safe) if the Agent tool is unavailable (CC < 2.1.172, Cursor, claude -p, etc.).
---

**You MUST follow the instructions step-be-step, precisely. You MUSTN'T make shortcuts!**

### Step -1: Version check — pick the right execution mode

Run this command and capture stdout:
```
bash -c 'ver=$(echo "$CLAUDE_CODE_EXECPATH" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1); echo "${ver:-unknown}"'
```

- If the output is `unknown` (env var not set — you are in Cursor, `claude -p`, or another non-CC harness): **switch to inline mode** (see below).
- Otherwise parse the version and compare it to `2.1.172`:
  ```
  bash -c 'ver=$(echo "$CLAUDE_CODE_EXECPATH" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1); printf "2.1.172\n%s\n" "$ver" | sort -V -C && echo ok || echo old'
  ```
  - Output `ok` → version is sufficient; proceed with **subagent mode** (Loop body below).
  - Output `old` → version is too old for the `Agent` tool; **switch to inline mode**.

Inform the user which mode was selected and why before continuing.

**Inline mode** — follow the instructions in `/implement-all-safe` verbatim (the plan-file resolution and loop body are identical, but tasks are executed inline instead of via subagents). Do NOT spawn subagents in inline mode.

### Step 0: Resolve the plan file

**First check:** If `$ARGUMENTS` is blank or was not provided, stop and ask the user: "Please provide a plan file path or keyword to search for."

Run `test -f "$ARGUMENTS"`.

- If the file exists: set the resolved path to `$ARGUMENTS` and continue to the Loop body.
- If it does not exist: search for `**/*.md` files (your runtime's glob primitive), filter results by keyword match on name or path, then read each keyword-matched candidate and check it contains at least one unchecked task line (`- [ ]`). Discard any that does not.
  - Exactly one match → set the resolved path to that path, note it to the user.
  - Multiple matches → stop and ask the user to choose: "Found multiple matching plan files: [list them]. Please provide the full path to the one you want."
  - No match → stop and ask the user: "Could not find a plan file matching '$ARGUMENTS'. Please provide the full path."

### Loop body

**Termination condition:** All tasks in the plan file are marked complete (plan-progress.sh returns exit 1). Repeat all steps until this condition is met.

Each iteration:

#### 1. **Progress** Run, replacing `<plan-path>` with the resolved file path:
   ```
   bash ~/.claude/scripts/plan-progress.sh "<plan-path>"
   ```
   - Exit 1 → all tasks complete — stop.
   - Exit 2 or 3 → stop and report the error.
   - Any other exit code → stop and report the unexpected exit code.
   - Exit 0 → tasks remain, note the reported NEXT_TASK_NAME and continue.

   Always run `plan-progress.sh` script in every new iteration and **copy + show the first two lines of the output of the script to the user. Exactly in the same format, don't reformat it.**

#### 2. **Spawn a subagent to implement this task.** First, run:
   ```
   date '+%H:%M:%S' 2>/dev/null || powershell -Command "Get-Date -Format 'HH:mm:ss'" 2>/dev/null || echo "(time unavailable)"
   ```
   Print the result to the user in this exact format (brackets are literal, e.g. `Launching task 6.1 at [12:50:31]`): `Launching task <NEXT_TASK_NAME> at [HH:MM:SS]`

   Then use whatever subagent primitive your runtime offers:
   - Claude Code: the `Agent` tool, `subagent_type: general-purpose`, `run_in_background: true`.
   - Cursor: the `Task` tool.
   - Headless runtimes without subagent primitives: invoke `/implement-next` inline.

   You MUST give this prompt to the subagent:
   > Run `/implement-next` on plan file `<plan-path>`.
   >
   > **SCOPE — non-negotiable:**
   > - Implement EXACTLY ONE task: the first uncompleted task in the plan. Do not preview, prepare, or implement any subsequent task.
   > - Touch only what THIS task requires: files the task description names, PLUS any minimal side-effect edits the change forces (broken sibling tests, import updates, manifests). No unrelated refactors, cleanups, or "while I'm here" edits on files this task does not require.
   >
   > **ACCEPTANCE CRITERIA:**
   > **YOUR TURN ENDS ONLY when ALL of these are true.**
   > A. Implementation files modified per the task spec.
   > B. `/implement-next` Step 3 completed, you did run `/iterative-review`.
   > C. `/implement-next` Step 4 tests pass — OR, for doc-only tasks where `/implement-next`'s Step 2 explicitly permits skipping the TDD cycle (documentation, configuration, CI changes, diagrams), the inline verification specified by the task spec succeeded.
   > D. Plan file's `- [ ]` for this task flipped to `- [x]`.
   > E. A single git commit exists containing the implementation + plan checkoff.
   > F. `/implement-next` Step 7 report emitted.
   >
   > **Repeat until ALL items in Acceptance Criteria are completed. It is a MUST!**
   >
   > **FORBIDDEN:**
   > - Do NOT use `--no-verify`, `--amend`, or any pre-commit hook bypass.
   > - Do NOT skip `/implement-next` Steps 4, 5, 6, 7 even if `/iterative-review` returned "no issues remain". Review convergence is a green light to proceed to `/implement-next` Step 4 — it is NOT a signal to terminate your turn.
   > - Do NOT bundle this task with adjacent ones into a single commit.
   > - Do NOT spawn nested `/implement-all` invocation from inside your task work.
   > - Do NOT modify the plan file beyond toggling THIS task's checkbox.
   > - MUST NOT make shortcuts! MUST follow the instructions step-by-step precisely.

   Then wait for the subagent to return before continuing.

#### 3. **Recovery check — verify the task landed.**

   - Check that the task is checked in the plan file, and check that the related files are committed.
   - If the task is **not checked** (regardless of commit state) → **you MUST go to step 2 ("Spawn a subagent to implement this task") and redo the full process. This is non-negotiable. You MUST NOT decide differently!** Track attempt count — after 3 failed attempts, stop and report: "Task [N.M] failed after 3 attempts. Manual intervention required."
   - If the task **is checked but the files are not committed** → commit only: run `git status --porcelain` to identify all modified and untracked files (covers both tracked modifications and newly created files). Cross-reference each file against the task description to determine membership. Stage by explicit file path only those that belong to this task's implementation. Do NOT use `git add -A` or `git add .` — that risks including unrelated working-tree changes. If uncertain whether a file belongs to this task, include it and note the uncertainty in the commit message. Never leave modified task files unstaged without reporting them. Then commit. Do NOT respawn the subagent.
     Report this as a violation:
        - Task [N.M] partial ⚠️ — checked but not committed; committed now ([short-hash]).
           - **What:** Task was checked but commit was missing (criterion E violated).
           - **Why:** [determine from context — no assumptions]
           - **Fix:** Committed the missing changes above.
           - **Prevention:** [how to prevent this in the future]
           save the learnings to prevent this next time;
   - **Always report to the user if there was any violation in the instructions or in the process. You and the subagents must follow the instructions strictly. Don't miss that!**
      If there was no violation (task was already checked and committed), tell the user exactly in this format:
         - Task [N.M] ✅ — checked (line [NNN]) and committed ([short-hash]). Checkpoint verified (checkbox + commit).
      If there was any other violation, tell the user exactly in this format:
         - Task [N.M] failed ❌:
            - **What:** [was the violation]
            - **Why:** [was that (no assumptions, fact check!)]
            - **Fix:** [did you fix it?]
            - **Prevention:** [how you will prevent it in the future.]
            save the learnings to prevent this next time;

