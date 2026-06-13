---
description: Claude Code variant — repeatedly run /implement-next-cc on a plan file until every task is complete, with SubagentStop-hook enforcement on each spawned subagent. For a portable runtime-agnostic version without hook dependency, use /implement-all.
---

<!-- RECOVERY_SCHEMA_V2 -->

### Step 0: Resolve the plan file

**First check:** If `$ARGUMENTS` is blank or was not provided, stop and ask the user: "Please provide a plan file path or keyword to search for."

Run `test -f "$ARGUMENTS"`.

- If the file exists: set the resolved path to `$ARGUMENTS` and continue to the Loop body below.
- If it does not exist: use the Glob tool to search for `**/*.md` files, filter results by keyword match on name or path, then Read each keyword-matched candidate and check it contains at least one unchecked task line (`- [ ]`). Discard any that does not.
  - Exactly one match → set the resolved path to that path, note it to the user.
  - Multiple matches → stop and ask the user to choose: "Found multiple matching plan files: [list them]. Please provide the full path to the one you want."
  - No match → stop and ask the user: "Could not find a plan file matching '$ARGUMENTS'. Please provide the full path."

### Loop body

Track `previous_task_name` (initially empty) and `iteration_count` (initially 0) across iterations. Increment `iteration_count` at the start of each iteration. If `iteration_count` exceeds 50, clear the recovery breadcrumb and stop:
```
bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
```
Then report: "Loop has exceeded 50 iterations without completing — possible infinite loop. Please investigate."

**Termination condition:** All tasks in the plan file are marked complete (plan-progress.sh returns exit 1). Repeat steps 1–6 until this condition is met.

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
   - `START_DIRTY = $(git status --porcelain | wc -l)`
   - `CWD = $(pwd)`
   - Persist the first iteration's START_SHA durably for Step 8's audit (file-existence guard so it only writes once across the whole loop). The file is namespaced by a short hash of the plan path so different plans don't collide and a stale file from one halted plan can't poison another run:
     ```
     mkdir -p "$CWD/.claude"
     PLAN_HASH=$(printf '%s' "<plan-path>" | shasum | cut -c1-8)
     SHA_FILE="$CWD/.claude/implement-all-start-sha-$PLAN_HASH"
     [ -f "$SHA_FILE" ] || echo "$START_SHA" > "$SHA_FILE"
     ```

3. **Spawn background Agent.** Spawn a background agent with the prompt (replacing `<plan-path>`):
   > Call the Skill tool with skill `implement-next-cc` and args `<plan-path>`.

   The Agent tool returns an `agentId` synchronously. **Record this id** — you will need it in step 4.

4. **Arm the SubagentStop gate AND the recovery breadcrumb.** Call the writer AFTER `Agent` returned the `agentId` (Step 3) and BEFORE waiting on the agent (Step 5). Default-mode write (no `--upsert`) — the parent owns the breadcrumb and has a real `agentId` to pin it to. The 6th arg `"cc"` records the skill variant for the child's Step 0 triage:
   ```
   bash ~/.claude/scripts/implement-next-state-write.sh "<CWD>" "<START_SHA>" "<plan-path>" "<NEXT_TASK_NAME>" "<agentId-from-step-3>" "cc"
   ```

   This writes `<CWD>/.claude/implement-next-state.json` with the v2 schema (including `expected_agent_id`, `branch_name`, `skill_variant: "cc"`, `review_abort_count: 0`). The `SubagentStop` hook configured in `~/.claude/settings.json` (`implement-next-stop-gate.sh`) reads this sentinel and **refuses to let the spawned subagent end its turn until a new commit exists since START_SHA**. The hook filters on `agentId` so nested sub-sub-agents (devils-advocate, fix agents, the check-off agent) are passed through and only the outer `/implement-next-cc` subagent is gated. Per `code.claude.com/docs/en/hooks` (accessed 2026-06-11), no consecutive-block cap is documented for SubagentStop (the 8-block cap is documented only for the `Stop` event). This means a runaway subagent may be blocked indefinitely; the recovery check in Step 6 is the user's escape hatch.

   The same breadcrumb also feeds the child's Step 0 triage: on any re-invocation (interruption / crash / hook bypass), the child reads this sentinel and dispatches the correct recovery case (R-A / R-B / R-AB / R-C).

5. **Wait for the agent to return.**

6. **Recovery check — verify the task actually landed.** Even with the SubagentStop gate, some failures bypass it: OOM kills (`Exit code 137`), transport errors, and account-quota hits. The recovery check catches all of these.

   Do NOT clear the breadcrumb here. The child's Step 7 self-verification clears it on a successful run; on failure paths (Cases B-after-rescue, C, D below), the parent clears it explicitly before halting. This leaves the breadcrumb intact for the child to triage on a subsequent re-invocation.

   Capture `END_SHA = $(git rev-parse HEAD)` and `END_DIRTY = $(git status --porcelain | wc -l)`, then dispatch on the four cases:

   **Case A — `END_SHA != START_SHA` and working tree clean.** Task likely committed.
   - Run `plan-progress.sh` again. If NEXT_TASK_NAME changed (progress was made), continue to the next iteration.
   - If NEXT_TASK_NAME is still the same: the subagent committed *something* but did not check off this task. Report the anomaly with the new commit SHA and halt.

   **Case B — `END_SHA == START_SHA` and uncommitted changes exist.** Subagent did work but never committed (and the hook is somehow bypassed (e.g., OOM, transport error, account-quota hit)). At the parent level:
   1. Run the full test suite. Use `Bash` with `run_in_background: true`, then `Monitor` with a tight filter for pass/fail signatures (`grep -E --line-buffered "passed|failed|error|FAILED|Traceback|Killed|OOM"`). The parent loop runs in the main conversation, where `Monitor` works correctly.
   2. If tests fail: spawn one background fix-agent with the failure output. After it returns, re-run tests. Retry at most twice; if still failing, halt with the failures.
   3. If tests pass: spawn a small background agent with the prompt:
      > Call the Skill tool with skill `implement-next-cc-resume` and args `<plan-path>`.

      Before spawning, write a fresh sentinel for this rescue agent (same procedure as step 4, using the new agentId). The hook gates this rescue too.
   4. Re-capture `END_SHA` / `END_DIRTY` and re-evaluate Case A vs Case B once more. If still Case B after the rescue, clear the breadcrumb and halt:
      ```
      bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
      ```
      Then report the diagnostic.

   **Case C — `END_SHA == START_SHA` and working tree clean.** Subagent did nothing visible (network error, OOM before any tool call, quota hit). Clear the breadcrumb and halt:
   ```
   bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
   ```
   Then report: "Subagent for task '<NEXT_TASK_NAME>' returned without making any changes. Last subagent transcript: <path>. Please investigate."

   **Case D — `END_SHA != START_SHA` and uncommitted changes exist.** A commit landed but more changes remain staged/unstaged. Clear the breadcrumb and halt:
   ```
   bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
   ```
   Then report the anomaly — often indicates a pre-commit hook left files modified.

7. Return to step 1.

8. **Final audit.** After the loop terminates normally (all tasks complete), run the independent post-hoc audit:
   ```
   PLAN_HASH=$(printf '%s' "<plan-path>" | shasum | cut -c1-8)
   SHA_FILE="$CWD/.claude/implement-all-start-sha-$PLAN_HASH"
   FIRST_START_SHA=$(cat "$SHA_FILE")
   bash ~/.claude/scripts/audit-plan-run.sh "<plan-path>" "$FIRST_START_SHA"
   rm -f "$SHA_FILE"
   ```
   Exit 0 = clean run, exit 1 = mismatch between commits and checked tasks (investigate manually). The `FIRST_START_SHA` is read from the durable file written in Step 2 (which uses a file-existence guard so only the first iteration's SHA is captured). The `rm -f` cleans up so subsequent runs don't pick up a stale sha.

   Defense-in-depth — clear the recovery breadcrumb after the audit completes (the child's Step 7 should have cleared it on the final iteration, but a leftover sentinel from any path would poison the next run):
   ```
   bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"
   ```

### Recovery-check diagnostic

When Cases B, C, or D halt the loop, include in the report:
- `START_SHA`, `END_SHA`
- Output of `git status --short`
- `tail -40` of the subagent's transcript file (find via `ls -t ~/.claude/projects/$(pwd | sed 's|[/.]|-|g')/*/subagents/agent-<agentId>.jsonl`)
- The detected case (B, C, or D)
- The actions the parent attempted (for Case B)
- Whether the SubagentStop hook fired and how many times it blocked (look for `decision: "block"` entries in the parent session's transcript)

### Architectural notes — why this works

This design implements Anthropic's officially-prescribed pattern for "agent stops mid-flow" (see `code.claude.com/docs/en/best-practices` (accessed 2026-06-11), section *"Closing the loop"*): a deterministic gate (Stop hook) that blocks turn-end until a verification script passes. Plan-and-Solve (arxiv.org/abs/2305.04091, accessed 2026-06-11) names missing-step errors as a category; this user's own archon-search data shows 7.6% of /implement-next subagents historically never committed — a concrete instance of that failure class. The same pattern is the convergent recommendation of LangGraph, Temporal, Restate, Inngest, OpenHands, Aider, and Replit — several production systems that host long-running LLM agents externalize the "did we finish?" decision into code (based on research conducted 2026-06-10; see project transcripts for cited primary sources).

Layer 1 (`SubagentStop` hook) is the primary defense. Layer 2 (parent-level recovery check + Case B rescue) is the safety net for failures that bypass the hook (OOM, transport, quota).
