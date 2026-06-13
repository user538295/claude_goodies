---
description: Portable runtime-agnostic — repeatedly run /implement-next on a plan file until every task is complete. Works in any harness (Claude Code, Cursor, claude -p, etc.) without hook dependencies. For Claude Code's hook-enforced variant with auto-rescue, use /implement-all-cc.
---

<!-- RECOVERY_SCHEMA_V2 -->

### Step 0: Resolve the plan file

**First check:** If `$ARGUMENTS` is blank or was not provided, stop and ask the user: "Please provide a plan file path or keyword to search for."

Run `test -f "$ARGUMENTS"`.

- If the file exists: set the resolved path to `$ARGUMENTS` and continue to the Loop body.
- If it does not exist: search for `**/*.md` files (your runtime's glob primitive), filter results by keyword match on name or path, then read each keyword-matched candidate and check it contains at least one unchecked task line (`- [ ]`). Discard any that does not.
  - Exactly one match → set the resolved path to that path, note it to the user.
  - Multiple matches → stop and ask the user to choose: "Found multiple matching plan files: [list them]. Please provide the full path to the one you want."
  - No match → stop and ask the user: "Could not find a plan file matching '$ARGUMENTS'. Please provide the full path."

### Loop body

Track `previous_task_name` (initially empty) and `iteration_count` (initially 0) across iterations. Increment `iteration_count` at the start of each iteration. If `iteration_count` exceeds 50, clear the recovery breadcrumb and stop:
```
bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
```
Then report: "Loop has exceeded 50 iterations without completing — possible infinite loop. Please investigate."

**Termination condition:** All tasks in the plan file are marked complete (plan-progress.sh returns exit 1). Repeat steps 1–5 until this condition is met.

Each iteration:

1. **Progress + stuck-task guard.** Run, replacing `<plan-path>` with the resolved file path:
   ```
   bash ~/.claude/scripts/plan-progress.sh "<plan-path>"
   ```
   - Exit 1 → all tasks complete — stop.
   - Exit 2 or 3 → stop and report the error.
   - Any other exit code → stop and report the unexpected exit code.
   - Exit 0 → tasks remain, note the reported NEXT_TASK_NAME and continue.

   **Stuck-task guard:** If the NEXT_TASK_NAME reported in this iteration is the same as `previous_task_name`, clear the recovery breadcrumb and stop:
   ```
   bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
   ```
   Then report: "Task '<task-name>' appears to be stuck — it was reported as next in two consecutive iterations. Please investigate before continuing." Otherwise, update `previous_task_name` to the current NEXT_TASK_NAME before proceeding.

2. **Capture pre-state.**
   - `START_SHA = $(git rev-parse HEAD)`
   - `CWD = $(pwd)`
   - Write the start sha to a durable file (file-existence guard makes this safe to invoke every iteration). The file is namespaced by a short hash of the plan path so different plans don't collide and a stale file from one halted plan can't poison another run:
     ```
     mkdir -p "$CWD/.claude"
     PLAN_HASH=$(printf '%s' "<plan-path>" | shasum | cut -c1-8)
     SHA_FILE="$CWD/.claude/implement-all-start-sha-$PLAN_HASH"
     [ -f "$SHA_FILE" ] || echo "$START_SHA" > "$SHA_FILE"
     ```
     This file persists across iterations so Step 5's audit doesn't depend on the LLM remembering a variable.

3. **Spawn a subagent to implement this task.** Use whatever subagent primitive your runtime offers:
   - Claude Code: the `Agent` tool, `subagent_type: general-purpose`, `run_in_background: true`.
   - Cursor: the `Task` tool.
   - Headless runtimes without subagent primitives: invoke `/implement-next` inline.

   The subagent's prompt:
   > Run `/implement-next` on plan file `<plan-path>`.

   Immediately after spawning the subagent, write the recovery breadcrumb (the portable variant has no SubagentStop hook to coordinate with, so use `--upsert` with empty `expected_agent_id`):

   ```
   bash ~/.claude/scripts/implement-next-state-write.sh --upsert "$CWD" "$START_SHA" "<plan-path>" "$NEXT_TASK_NAME" "" "portable"
   ```

   The `--upsert` flag is required because portable parents don't have an agentId; the hook fails open on empty `expected_agent_id`, but the child's breadcrumb-based recovery still works.

   Then wait for the subagent to return before continuing.

4. **Recovery check — verify the task landed.** This step is the portable substitute for hook enforcement. It does not auto-rescue; on any failure it halts with a diagnostic so a human can intervene.

   Capture `END_SHA = $(git rev-parse HEAD)` and `END_DIRTY = $(git status --porcelain | wc -l)`, then:

   - **`END_SHA != START_SHA` and working tree clean:** Task likely committed. Run `plan-progress.sh` again; if NEXT_TASK_NAME changed → continue to next iteration (the child's Step 7 has cleared the breadcrumb). If NEXT_TASK_NAME is unchanged → the subagent committed *something* but did not check off the task; clear the recovery breadcrumb and halt with the new commit SHA and ask the user to investigate:
     ```
     bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
     ```

   - **`END_SHA == START_SHA` and uncommitted changes exist:** Subagent did work but never committed (the Monitor-stall failure mode, the dominant cause of the original ~7.6% failure rate). Clear the recovery breadcrumb and halt with diagnostic:
     ```
     bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
     ```
     Print `git status --short`, the names of changed files, and the NEXT_TASK_NAME. Tell the user: "Subagent stalled mid-flow. The portable variant does not auto-rescue. Inspect the changes and complete the task manually. (If your harness is Claude Code, the `-cc` variant — `/implement-all-cc` — auto-rescues this failure mode.)"

   - **`END_SHA == START_SHA` and working tree clean:** Subagent did nothing visible (network error, OOM, quota hit, or just yielded early). Clear the recovery breadcrumb and halt:
     ```
     bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
     ```
     Then report: "Subagent for task '<NEXT_TASK_NAME>' returned without making any changes. Please investigate."

   - **`END_SHA != START_SHA` and uncommitted changes exist:** A commit landed but more changes remain. Clear the recovery breadcrumb and halt:
     ```
     bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
     ```
     Then report the anomaly — often a pre-commit hook left files modified.

5. **Audit.** After the loop terminates normally (all tasks complete), run:
   ```
   PLAN_HASH=$(printf '%s' "<plan-path>" | shasum | cut -c1-8)
   SHA_FILE="$CWD/.claude/implement-all-start-sha-$PLAN_HASH"
   FIRST_START_SHA=$(cat "$SHA_FILE")
   bash ~/.claude/scripts/audit-plan-run.sh "<plan-path>" "$FIRST_START_SHA"
   rm -f "$SHA_FILE"
   ```
   This is the same independent audit available for the -cc variant. Exit 0 = clean run, exit 1 = mismatch between commits and checked tasks. The `rm -f` at the end cleans up so subsequent runs don't pick up a stale sha.

   Defense-in-depth — clear the recovery breadcrumb after the audit completes (the child's Step 7 should have cleared it on the final iteration, but a leftover sentinel from any path would poison the next run):
   ```
   bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
   ```

### Why this variant has lower reliability than -cc

This variant relies on the subagent following the `/implement-next` markdown instructions to commit before ending its turn. Plan-and-Solve research (arxiv.org/abs/2305.04091, accessed 2026-06-11) identifies missing-step errors as a known failure class for prompt-only multi-step flows. Our archon-search measurement of ~7.6% of `/implement-next` subagents failing to commit is consistent with that qualitative pattern; the paper does not quantify the rate. Halting on each failure bounds the damage to one iteration but does not auto-recover — the user must intervene manually.

For higher reliability when running in Claude Code, use `/implement-all-cc`, which adds a `SubagentStop` hook that blocks turn-end until a commit lands (Anthropic's *"deterministic gate"* pattern — `code.claude.com/docs/en/best-practices` (accessed 2026-06-11)).
