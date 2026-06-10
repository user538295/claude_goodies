---
description: Read a plan from $ARGUMENTS, implement the next uncompleted task with agents, verify with automated + live tests, run parallel DA reviews, fix all issues, check off completed items, commit.
---

Plan file: $ARGUMENTS

### Step 1: Show progress and identify the next task

Run:

```
bash ~/.claude/scripts/plan-progress.sh $ARGUMENTS
```

**Exit 0 (normal):** print the human-readable block verbatim. Read `NEXT_TASK_NAME` from the machine-readable lines, then read $ARGUMENTS to extract the full task details: description, acceptance criteria, and sub-items.

**Exit 1:** all tasks are complete — stop here, report completion.

**Any other exit code or script not found (fallback):** read the appropriate template from `~/.claude/scripts/` (`progress-header-phased.template` if the plan has `###` headings within the task section (`## Tasks` / `## Task breakdown`), `progress-header-flat.template` otherwise), compute the placeholder values by reading $ARGUMENTS directly, substitute them, and print the result. Then continue as normal — a failed script must not block progress.

---

### Step 2: Implement

Spawn the most appropriate agent to implement **only this task** — do not touch other tasks, do not refactor unrelated code.

If the task produces testable code output, follow strict TDD:

1. **Write tests first** — unit tests, integration tests, and live/end-to-end tests that cover the new behaviour and acceptance criteria. Tests must fail at this point (red).
2. **Run the tests** — confirm they fail for the right reasons. **Always blocking — never backgrounded.**
3. **Implement the functionality** — write only enough code to make the tests pass (green).
4. **Run the tests again** — all new and existing tests must pass before continuing. **Always blocking — never backgrounded.**

If the task has no testable code output (documentation, configuration, CI changes, diagrams), skip the TDD cycle and implement directly.

No assumptions — read all relevant code, documentation, and context first.

---

### Step 3: DA review loop

Invoke `/iterative-review` passing the output of `git diff HEAD` followed by the task spec (description + acceptance criteria from Step 1) as `$ARGUMENTS`. Review agents use the diff as their target and the task spec to validate against acceptance criteria.

The DA review must NOT create its own commits — all fixes stay as uncommitted working tree changes.

**⚠️ MANDATORY CONTINUATION — DO NOT STOP HERE.** The `## Review Summary` and `### Verdict` produced by `/iterative-review` mark the end of the *review sub-step only*. They do NOT mean the task is complete. You MUST proceed to Step 4 immediately after the review verdict, regardless of what the verdict says. Any text that says "Proceeding to Step 4" is a declaration of intent — you still must actually execute Step 4 yourself. Do not end your turn after Step 3.

---

### Step 4: Run tests

**IMPORTANT: Run all test commands as blocking (foreground) calls — never use `run_in_background`. The commit step cannot proceed until the test result is known. This rule overrides the general "use background agents" guidance in CLAUDE.md, which applies to sub-agent delegation, not to test commands.**

Run the full test suite. If any tests fail:

1. Spawn a fix agent with the full failure output. The agent must fix all failing tests.
2. Run the full test suite again.
3. Repeat until the suite is fully green, or three consecutive fix attempts all fail — in which case stop and report the failures for human review.

Only continue to Step 5 once the suite is fully green.

---

### Step 5: Check off completed items

Spawn an agent to update $ARGUMENTS: mark the implemented task and every completed sub-item as done (`[ ]` → `[x]`). Be precise — only check what was actually implemented and verified. Do not check items that were skipped or only partially completed.

---

### Step 6: Commit

**NON-NEGOTIABLE: Each task gets its own commit. One task = one commit. Never batch multiple tasks into a single commit.**

Commit all changes for this task — implementation files AND the updated plan file — in a single commit with a message derived from the actual task content. Do not skip hooks (`--no-verify` is forbidden). Stage only files relevant to this task.

**If the commit fails:** revert the plan file and unstage implementation files, then retry:
1. `git reset HEAD` — unstage everything
2. Restore the plan file:
   - If tracked: `git checkout HEAD -- $ARGUMENTS`
   - If untracked: save content to a temp file first (`cp $ARGUMENTS /tmp/plan-backup.md`), then recreate from the backup after fixing the issue
3. Fix the underlying issue (e.g., lint or type-check failures from a pre-commit hook)
4. Redo Step 5 and Step 6

---

### Step 7: Report

Output a concise report for this task:
- What was implemented
- Test results summary
- Any feature loss or deviation from the task spec (be precise)
- Any unresolvable oscillations from the DA loop
- What was checked off in the plan
