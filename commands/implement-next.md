---
description: Portable runtime-agnostic — read a plan from $ARGUMENTS, implement the next uncompleted task with TDD, optional review, blocking tests, check off, commit. Works in any harness without hook dependencies. For Claude Code's hook-enforced variant use /implement-next-cc.
---

### Using in Cursor

See the "Using in Cursor" section of `/implement-all` — copy or symlink both files to `.cursor/commands/`. No additional setup required for this skill.

Plan file: $ARGUMENTS

### Step 1: Show progress and identify the next task

Run:

```
bash ~/.claude/scripts/plan-progress.sh "$ARGUMENTS"
```

**Exit 0 (normal):** print the human-readable block verbatim. Read `NEXT_TASK_NAME` from the machine-readable lines, then read $ARGUMENTS to extract the full task details: description, acceptance criteria, and sub-items.

**Exit 1:** all tasks are complete — stop here, report completion.

**Any other exit code or script not found (fallback):** read the appropriate template from `~/.claude/scripts/` (`progress-header-phased.template` if the plan has `###` headings within the task section (`## Tasks` / `## Task breakdown`), `progress-header-flat.template` otherwise), compute the placeholder values by reading $ARGUMENTS directly, substitute them, and print the result. Then continue as normal — a failed script must not block progress.

Record `START_SHA = $(git rev-parse HEAD)` and `START_CHECKED = $(awk '/^- \[[xX]\]/{c++} END{print c+0}' "$ARGUMENTS")`. These are used by the Step 7 self-verification.

---

### Step 2: Implement (TDD)

Spawn a focused subagent (your runtime's task-delegation primitive) — or proceed inline if no subagent primitive is available — to implement **only this task**. Do not touch other tasks, do not refactor unrelated code.

If the task produces testable code output, follow strict TDD:

1. **Write tests first** — unit, integration, and live/end-to-end tests covering the new behaviour and the task's acceptance criteria. Tests must fail at this point (red).
2. **Run the tests** — confirm they fail for the right reasons. **Always blocking — never backgrounded, never via polling tools.**
3. **Implement the functionality** — write only enough code to make the tests pass (green).
4. **Run the tests again** — all new and existing tests must pass before continuing.

If the task has no testable code output (documentation, configuration, CI changes, diagrams), skip the TDD cycle and implement directly.

No assumptions — read all relevant code, documentation, and context first.

---

### Step 3: Critical review

If your runtime exposes `/iterative-review` or an equivalent critic, invoke it on `git diff HEAD` plus the task spec. Otherwise, spawn one critic subagent with the same inputs and apply its findings as uncommitted changes.

The review must NOT create its own commits — all fixes stay as uncommitted working-tree changes.

**⚠️ MANDATORY CONTINUATION — DO NOT STOP HERE.** The `## Review Summary` and `### Verdict` produced by the critic mark the end of the *review sub-step only*. They do NOT mean the task is complete. You MUST proceed to Step 4 immediately after the verdict, regardless of what it says. Text that says "Proceeding to Step 4" is a declaration of intent — you still must actually execute Step 4 yourself. Do not end your turn after Step 3. (The portable variant has no `SubagentStop` hook to catch this; the loud warning here is the only defense.)

---

### Step 4: Run tests

Run the full test suite as a **blocking (foreground) command**, with a timeout under your runtime's foreground ceiling. Claude Code's `Bash` ceiling is 600,000 ms (10 min) — set `timeout: 540000` to leave headroom. Cursor's `terminal` tool has similar limits. **Never use polling/streaming tools** (e.g., Claude Code's `Monitor`, Cursor's background watchers) inside this subagent — they cause silent termination on yield in many harnesses, and the parent will see an empty commit.

If the full suite cannot complete in one blocking call, run only the *task-relevant subset* (the tests added in Step 2 plus their immediate neighbourhood). Then halt your turn and report the partial-test scope explicitly in Step 8. The portable `/implement-all` parent does not auto-run the full suite (that's a `-cc` variant feature); the user must verify externally.

If the test command reports failures:

1. Spawn a fix agent with the full failure output. The fix agent must repair the failing tests.
2. Re-run the same command.
3. Repeat until green, or three consecutive fix attempts all fail — in which case stop and report the failures for human review.

Only continue to Step 5 once your chosen test scope is fully green.

---

### Step 5: Check off completed items

Update `$ARGUMENTS`: mark the implemented task and every completed sub-item as done (`[ ]` → `[x]`). Be precise — only check what was actually implemented and verified. Do not check items that were skipped or only partially completed.

---

### Step 6: Commit

**NON-NEGOTIABLE: one task = one commit.** Never batch multiple tasks into a single commit.

Commit all changes for this task — implementation files AND the updated plan file — in a single commit with a message derived from the actual task content. Do not skip hooks (`--no-verify` is forbidden). Stage only files relevant to this task.

**If the commit fails:**
1. `git reset HEAD` — unstage everything.
2. Restore the plan file:
   - If tracked: `git checkout HEAD -- "$ARGUMENTS"`
   - If untracked: save content to a temp file first (`cp "$ARGUMENTS" /tmp/plan-backup.md`), then recreate from the backup after fixing the issue.
3. Fix the underlying issue (e.g., lint or type-check failures from a pre-commit hook).
4. Redo Step 5 and Step 6.

---

### Step 7: Self-verification (portable substitute for hook enforcement)

**Before ending your turn, programmatically verify the work landed.** This is the portable equivalent of the `SubagentStop` hook used in `/implement-next-cc`. The check is cheap and catches the dominant "I said I committed but actually didn't" failure mode.

Run these checks:

1. **A new commit exists since the iteration started:**
   ```
   bash ~/.claude/scripts/check-task-commit.sh "<START_SHA>"
   ```
   Exit 0 = at least one new commit since `START_SHA`. Exit 1 = zero.

2. **The plan file's checked-task count grew by at least 1:**
   ```
   END_CHECKED=$(awk '/^- \[[xX]\]/{c++} END{print c+0}' "$ARGUMENTS")
   test $((END_CHECKED - START_CHECKED)) -ge 1
   ```
   The "at least 1" rule accepts task-with-subitems (1 task + N subtasks all checked off in one iteration). If you implemented multiple tasks in one iteration, that's a separate violation caught by the parent's stuck-task guard.

3. **The new commit's diff includes both the plan file AND implementation files** (not plan-only):
   ```
   git show --stat HEAD | grep -q "$(basename "$ARGUMENTS")"
   git show --stat HEAD | awk 'NR>1 && /\|/ {print $1}' | grep -v "$(basename "$ARGUMENTS")" | grep -q .
   ```

If **any check fails**, do NOT end your turn. Diagnose the gap (missing commit? plan not checked? plan-only commit?) and return to the appropriate earlier step. If the same check fails twice in a row, report the specific failure in plain English ("Step 7 check 2 failed: plan-checked-task count went from N to M, expected N+1") and end the turn with a clear "task incomplete" status so the parent `/implement-all` loop can halt cleanly.

---

### Step 8: Report

Output a concise report for this task:
- What was implemented
- Test results summary
- Any feature loss or deviation from the task spec (be precise)
- Any unresolvable oscillations from the review loop
- What was checked off in the plan
- Step 7 self-verification result (all three checks pass / which failed)
