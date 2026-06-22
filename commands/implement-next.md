---
description: Portable runtime-agnostic — read a plan from $ARGUMENTS, implement the next uncompleted task with TDD, optional review, blocking tests, check off, commit. Works in any harness without hook dependencies. For Claude Code's hook-enforced variant use /implement-next-cc.
---

Plan file: $ARGUMENTS

**You MUST follow the instructions step-by-step, precisely. You MUST NOT make shortcuts!**

### Step 1: Show progress and identify the next task

Run:

```
bash ~/.claude/scripts/plan-progress.sh "$ARGUMENTS"
```

**Exit 0 (normal):** print the human-readable block verbatim. Read `NEXT_TASK_NAME` from the machine-readable lines, then read $ARGUMENTS to extract the full task details: description, acceptance criteria, and sub-items.

**Exit 1:** all tasks are complete — stop here, report completion.

**Any other exit code or script not found (fallback):** read the appropriate template from `~/.claude/scripts/` (`progress-header-phased.template` if the plan has `###` headings within the task section (`## Tasks` / `## Task breakdown`), `progress-header-flat.template` otherwise), compute the placeholder values by reading $ARGUMENTS directly, substitute them, and print the result. Then continue as normal — a failed script must not block progress.

### Step 2: Implement (TDD)

 **You MUST follow these instructions**:

 **SCOPE — non-negotiable:**
 - Implement EXACTLY ONE task: the first uncompleted task in the plan. Do not preview, prepare, or implement any subsequent task.
 - Touch only what THIS task requires: files the task description names, PLUS any minimal side-effect edits the change forces (broken sibling tests, import updates, manifests). No unrelated refactors, cleanups, or "while I'm here" edits on files this task does not require.

 **FORBIDDEN:**
 - Do NOT modify the plan file beyond toggling THIS task's checkbox.

If the task produces testable code output, follow strict TDD:

1. **Write tests first** — unit, integration, and live/end-to-end tests covering the new behaviour and the task's acceptance criteria. Tests must fail at this point (red).
2. **Run the tests** — confirm they fail for the right reasons. **Always blocking — never backgrounded, never via polling tools.**
3. **Implement the functionality** — write only enough code to make the tests pass (green).
4. **Run the tests again** — all new and existing tests must pass before continuing.

If the task has no testable code output (documentation, configuration, CI changes, diagrams), skip the TDD cycle and implement directly.

No assumptions — read all relevant code, documentation, and context first.

### Step 3: Critical review

**You MUST run `/iterative-review`.**

After `/iterative-review` returns — regardless of what its Verdict says — you MUST immediately continue to Step 4. The Review Summary is a sub-task result, not your completion signal. **Do NOT stop here.**

### Step 4: Run tests

You MUST run the full test suite as a **blocking (foreground) command**, with a timeout under your runtime's foreground ceiling. Claude Code's `Bash` ceiling is 600,000 ms (10 min) — set `timeout: 540000` to leave headroom. Cursor's `terminal` tool has similar limits. **Never use polling/streaming tools** (e.g., Claude Code's `Monitor`, Cursor's background watchers) inside this subagent — they cause silent termination on yield in many harnesses, and the parent will see an empty commit.

If the full suite cannot complete in one blocking call, run only the *task-relevant subset* (the tests added in Step 2 plus their immediate neighbourhood). Then report the partial-test scope explicitly in Step 7.

If the test command reports failures:

1. Spawn a fix agent with the full failure output. The fix agent must repair the failing tests.
2. Re-run the same command.
3. Repeat until green, or three consecutive fix attempts all fail — in which case stop and report the failures for human review.

Only continue to next Step once your chosen test scope is fully green.

### Step 5: Check off completed items

Update `$ARGUMENTS`: mark the implemented task and every completed sub-item as done (`[ ]` → `[x]`). Be precise — only check what was actually implemented and verified. Do not check items that were skipped or only partially completed.

### Step 6: Commit

**NON-NEGOTIABLE: one task = one commit.** Never batch multiple tasks into a single commit.

Commit all changes for this task — implementation files AND the updated plan file — in a single commit with a message derived from the actual task content.

### Step 7: Report

Output a concise report for this task:
- What was implemented
- Test results summary
- Any feature loss or deviation from the task spec (be precise)
- Any unresolvable oscillations from the review loop
- What was checked off in the plan
