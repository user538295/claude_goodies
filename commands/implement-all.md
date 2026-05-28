---
description: Repeatedly run /implement-next on $ARGUMENTS until every task in the plan is complete.
---

Plan file: $ARGUMENTS

**CRITICAL — DO NOT BYPASS THIS PROCESS:**
- You MUST build a 2×N task list before starting — one `[IMPLEMENT]` + one `[VERIFY]` pair per plan task.
- You MUST NOT spawn a single agent to implement multiple tasks at once.
- You MUST NOT write code directly — all implementation goes through `/implement-next`.
- Every plan task must produce exactly one commit with non-empty file changes.
- You MUST NOT skip or merge verify tasks.

---

### Setup (before building task list)

1. Run `git rev-parse HEAD` and record as `sha_start`.
2. Run `bash ~/.claude/scripts/count-uncompleted-tasks.sh $ARGUMENTS` capturing both stdout and stderr.
   The script prints a single line to stdout in the form `number_of_uncompleted_tasks=<count>`.
   Parse the integer after `=` and store it as `number_of_uncompleted_tasks`. Do not count manually.
   If stderr contains **"WARNING"** (heading not recognised), **STOP** — do not proceed.
   Report: "count-uncompleted-tasks.sh output was number_of_uncompleted_tasks=0 with a warning. Check that the plan file has a `## Tasks` or `## Task breakdown` section heading."
3. Read $ARGUMENTS and extract the name/title of each uncompleted task, in order.

If `number_of_uncompleted_tasks` equals 0 (and no WARNING), skip the task list and proceed directly to the final audit.

---

### Build the task list

Use the TaskCreate tool to create exactly `2 × number_of_uncompleted_tasks` tasks in alternating pairs:

```
[IMPLEMENT] <task 1 name>
[VERIFY]    <task 1 name>
[IMPLEMENT] <task 2 name>
[VERIFY]    <task 2 name>
…
```

The `[IMPLEMENT]` / `[VERIFY]` prefix is required in every task name.
Create all tasks before executing any of them.

---

### Execute tasks in order

Process each task pair sequentially. For each pair:

#### `[IMPLEMENT]` task

1. Mark the task `in_progress` (TaskUpdate).
2. Run `git rev-parse HEAD` and write the result to `.git/claude-implement-all-sha-before`:
   `git rev-parse HEAD > "$(git rev-parse --git-dir)/claude-implement-all-sha-before"`
   This persists `sha_before` in the worktree's own `.git/` directory (one invocation at a time per worktree).
3. Use the **Skill tool** to run `/implement-next $ARGUMENTS`.
4. Mark the task `completed` (TaskUpdate).

#### `[VERIFY]` task

1. Mark the task `in_progress` (TaskUpdate).
2. Read `sha_before`: `sha_before=$(cat "$(git rev-parse --git-dir)/claude-implement-all-sha-before")`
   If the file is missing, **STOP** — the `[IMPLEMENT]` step did not record it correctly.
3. Delete the file: `rm -f "$(git rev-parse --git-dir)/claude-implement-all-sha-before"`
4. Spawn a **verification agent** with `sha_before` and the plan task name. The agent must check ALL of:
   - `git rev-parse HEAD` differs from `sha_before` — a new commit was made
   - `bash ~/.claude/scripts/check-task-commit.sh <sha_before>` exits 0
   - The plan task is marked `[x]` in $ARGUMENTS
   - All tests in the checkpoint command from the task spec pass
   - Report PASS or FAIL with the specific failing check and full details
5. If the agent reports **PASS**: mark the verify task `completed` (TaskUpdate) and continue.
6. If the agent reports **FAIL**:
   - **Missing commit**: **STOP immediately**. Do NOT commit. The implementation was not completed. Report the partial state for human review.
   - **Plan not checked off** (commit exists, but `[x]` was missed): spawn an agent to mark the task `[x]` in $ARGUMENTS, stage only the plan file, and **amend** the existing commit (`git add $ARGUMENTS && git commit --amend --no-edit`). Then re-run the verification agent. If it still fails: **STOP**.
   - **Tests failing**: **STOP immediately**. Do NOT add a new commit. Report the failing tests for human investigation.
   - For any unrecognised failure: **STOP**. Do NOT mark the verify task complete. Report the full output.

---

### Final audit

After all task pairs are completed:

1. Run `bash ~/.claude/scripts/verify-run-commits.sh <sha_start> <number_of_uncompleted_tasks>` (pass the integer count, not the full key=value string).
   - Exit 0 → audit passed.
   - Exit non-zero → report as VIOLATION.

2. **Full test suite run**: Run the project's full test suite (auto-detect: `npm test`, `pytest`, `go test ./...`, `cargo test`, etc.).
   - If all tests pass → record as CLEAN.
   - If any tests fail → **MANDATORY**: spawn a fix agent with the full failure output. The agent must fix ALL failing tests and commit the fixes. After the agent completes, re-run the full test suite.
   - Repeat until the suite is fully green or three consecutive fix attempts all fail (in which case STOP and report the remaining failures for human review).

   **CRITICAL — NO EXCEPTIONS**: There is no such thing as an "acceptable pre-existing failure". Every failing test MUST be fixed. Do NOT classify failures as "pre-existing" to avoid fixing them. If a test was failing before this run started, it is still broken and must still be fixed. The only acceptable final state is a fully green test suite.

---

### Resume note

If resuming a partially-completed run (some tasks already `[x]` from a prior session):
- Re-record `sha_start` (current HEAD) and rerun `count-uncompleted-tasks.sh` to get the new `number_of_uncompleted_tasks`.
- Recreate the task list for remaining tasks only.
- The final audit covers only this session's commits.
- To audit from the very beginning: `bash ~/.claude/scripts/audit-plan-run.sh $ARGUMENTS <original_sha_start>`

---

### Final report

Output a concise summary:
- What was implemented (one line per task)
- Commit SHAs: run `git log --oneline <sha_start>..HEAD` and include the output
- Final audit result (PASS / VIOLATION + full script output)
- Full test suite result (CLEAN / fixed N failures / still failing)
- Any deviations or feature losses from the plan spec
- Any unresolved DA review issues
