---
description: Portable runtime-agnostic SAFE version — repeatedly run /implement-next on a plan file until every task is complete. Works in any harness (Claude Code, Cursor, claude -p, etc.) without hook dependencies.
---

> **Inline execution mode.** All steps execute in the current context — no subagents are spawned. Also used automatically by `/implement-all` when subagents are unavailable (Cursor, `claude -p`, CC < 2.1.172).

**This is not a guidline. You MUST follow the instructions step-be-step, precisely. You MUST NOT make shortcuts, or override the instructions!**

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

**Terminology:** "the plan file" throughout is this resolved file — the one `/implement-next` checks off and commits (its "task-breakdown file"). It may reference a separate **companion plan** that `/implement-next` resolves and reads as **read-only context** (its Step 1); this loop never checks off, stages, or commits the companion plan.

Each iteration:

#### 1. **Progress** Run, replacing `<plan-path>` with the resolved file path:
   ```
   p="${CLAUDE_PLUGIN_ROOT:-}"; [ -n "$p" ] || p=$(jq -r 'first(.plugins | to_entries[] | select(.key | startswith("claude-goodies@")) | .value[0].installPath) // empty' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null); [ -f "$p/scripts/plan-progress.sh" ] || p="$HOME/.claude"; bash "$p/scripts/plan-progress.sh" "<plan-path>"
   ```
   - Exit 1 → all tasks complete — stop.
   - Exit 2 or 3 → stop and report the error.
   - Any other exit code → stop and report the unexpected exit code.
   - Exit 0 → tasks remain, note the reported NEXT_TASK_NAME and continue.

   Always run `plan-progress.sh` script in every new iteration and **show the first two lines of the output of the script to the user. Exactly in the same format, do NOT reformat it. Do NOT prose it!**

#### 2. **Implement next task.** First, run:
   ```
   date '+%H:%M:%S' 2>/dev/null || powershell -Command "Get-Date -Format 'HH:mm:ss'" 2>/dev/null || echo "(time unavailable)"
   ```
   Print the result to the user in this exact format (brackets are literal, e.g. `Starting task 6.1 at [12:50:31]`): `Starting task <NEXT_TASK_NAME> at [HH:MM:SS]`

   You MUST follow these rules:

   Run `/implement-next` on plan file `<plan-path>`. (If your skill list shows it as `claude-goodies:implement-next`, use that name.)

   **SCOPE — non-negotiable:**
   - Implement EXACTLY ONE task: the first uncompleted task in the plan. Do not preview, prepare, or implement any subsequent task.
   - Touch only what THIS task requires: files the task description names, PLUS any minimal side-effect edits the change forces (broken sibling tests, import updates, manifests). No unrelated refactors, cleanups, or "while I'm here" edits on files this task does not require.
   
   **YOUR TURN ENDS ONLY when ALL of these are true:**
   A. Implementation files modified per the task spec.
   B. `/implement-next` Step 3 completed, you did run `/iterative-review`.
   C. `/implement-next` Step 4 tests pass — OR, for doc-only tasks where `/implement-next`'s Step 2 explicitly permits skipping the TDD cycle (documentation, configuration, CI changes, diagrams), the inline verification specified by the task spec succeeded.
   D. Plan file's `- [ ]` for this task flipped to `- [x]`.
   E. A single git commit exists containing the implementation + plan checkoff.
   F. `/implement-next` Step 7 report emitted.

   **Repeat until ALL items in Acceptance Criteria are completed. It is a MUST!**

   **FORBIDDEN:**
   - Do NOT use `--no-verify`, `--amend`, or any pre-commit hook bypass.
   - Do NOT skip `/implement-next` Steps 4, 5, 6, 7 even if `/iterative-review` returned "no issues remain". Review convergence is a green light to proceed to `/implement-next` Step 4 — it is NOT a signal to terminate your turn.
   - Do NOT bundle this task with adjacent ones into a single commit.
   - Do NOT modify the plan file beyond toggling THIS task's checkbox, and never modify a companion plan the task may reference (it is read-only context, never committed).
   - MUST NOT make shortcuts! MUST follow the instructions step-by-step precisely.

#### 3. **Recovery check — verify the task landed.**

   - Check that the task is checked in the plan file, and check that the related files are committed.
   - If the task is **not checked** (regardless of commit state) → **you MUST go to step 2 ("Implement next task") and redo the full process. This is non-negotiable. You MUST NOT decide differently!** Track attempt count — after 3 failed attempts, stop and report: "Task [N.M] failed after 3 attempts. Manual intervention required."
   - If the task **is checked but the files are not committed** → commit only: run `git status --porcelain` to identify all modified and untracked files (covers both tracked modifications and newly created files). Cross-reference each file against the task description to determine membership. Stage by explicit file path only those that belong to this task's implementation. Do NOT use `git add -A` or `git add .` — that risks including unrelated working-tree changes. The companion plan (if the task-breakdown file references one) is read-only context — never stage it; if it shows as modified, report that as a FORBIDDEN violation rather than committing it. If uncertain whether any *other* file belongs to this task, include it and note the uncertainty in the commit message. Never leave modified task files unstaged without reporting them. Then commit. Do NOT re-run `/implement-next`.
     Report exactly this as a violation and do NOT prose it:
        - Task [N.M] partial ⚠️ — checked but not committed; committed now ([short-hash]).
           - **What:** [Task was checked but commit was missing (criterion E violated); max 250 chars]
           - **Why:** [determine from context — no assumptions; max 250 chars]
           - **Fix:** [Committed the missing changes above; max 250 chars]
           - **Prevention:** [how to prevent this in the future; max 250 chars]
           save the learnings to prevent this next time;
   - **Always report to the user if there was any violation in the instructions or in the process. You must follow the instructions strictly. Don't miss that!**
      If there was no violation (task was already checked and committed), tell the user exactly in this format:
         - Task [N.M] ✅ — checked (line [NNN]) and committed ([short-hash]). Checkpoint verified (checkbox + commit).
      If there was any other violation, tell the user exactly in this format:
         - Task [N.M] failed ❌:
            - **What:** [was the violation; max 250 chars]
            - **Why:** [was that (no assumptions, fact check!); max 250 chars]
            - **Fix:** [did you fix it?; max 250 chars]
            - **Prevention:** [how you will prevent it in the future.; max 250 chars]
            save the learnings to prevent this next time;

