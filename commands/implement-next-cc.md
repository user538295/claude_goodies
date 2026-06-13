---
description: Claude Code variant — implement the next uncompleted task in $ARGUMENTS with TDD, parallel DA reviews, blocking tests, check off, commit. Paired with /implement-all-cc whose SubagentStop hook blocks turn-end until a commit lands. For a portable runtime-agnostic version use /implement-next.
---

<!-- RECOVERY_SCHEMA_V2 -->

Plan file: $ARGUMENTS

### Step 0: Triage prior state

Before anything else, shell out to the triage classifier:

```
bash ~/.claude/scripts/implement-next-triage.sh "$(pwd)" "$ARGUMENTS" "cc"
```

Read the exit code FIRST.

- **Non-zero exit**: print the `RECOVERY:` diagnostic line from stdout (and any stderr), then **exit your turn immediately**. Do NOT run Step 1 or any subsequent step.
- **Exit 0**: parse `KEY=VALUE` lines from stdout. Record:
  - `CASE` (one of: `R-Fresh`, `R-A`, `R-B`, `R-AB`, `R-C`)
  - `START_SHA` (use this for Step 7's self-verification)
  - `START_CHECKED` (use this for Step 7's self-verification)
  - `SHA_BEFORE` (R-A/R-B/R-AB only)
  - `BRANCH_NAME` (informational; warnings already printed by triage)
  - `TASK_NAME` (next task to act on)
  - `REVIEW_RANGE` (passed to Step 3)
  - `STEP_2_RESUME` (R-C only)
  - `REVIEW_ABORT_COUNT` (informational)
- Print the `RECOVERY:` diagnostic line verbatim so the user sees the case.

**Dispatch on `CASE`:**

- `R-Fresh` → proceed to Step 1 (existing flow).
- `R-A` → SKIP Step 1 and Step 2; jump to Step 3 with `REVIEW_RANGE=HEAD+worktree`.
- `R-B` → SKIP Step 1 and Step 2; the breadcrumb's `sha_before` already contains the orphan impl commit. Insert the plan-file checkoff for `TASK_NAME` into the working tree (do not commit yet). Jump to Step 3 with `REVIEW_RANGE=<sha_before>..HEAD`. Step 6's commit message MUST begin with `recovery(R-B): ` followed by a task-derived summary.
- `R-AB` → SKIP Step 1 and Step 2; jump to Step 3 with `REVIEW_RANGE=<sha_before>..HEAD+worktree`. Step 6's commit message MUST begin with `recovery(R-AB): ` followed by a task-derived summary.
- `R-C` → SKIP Step 1; resume Step 2 implementing ONLY the sub-items unchecked in `git show HEAD:$ARGUMENTS` (if `git show HEAD:$ARGUMENTS` fails — untracked plan or first-time commit — treat ALL sub-items as unchecked-in-HEAD).

**Standalone-child breadcrumb write** (R-Fresh only): after triage emits R-Fresh, the child writes a breadcrumb via `--upsert` so the `SubagentStop` hook has something to coordinate against AND so a subsequent interruption is recoverable:

```
bash ~/.claude/scripts/implement-next-state-write.sh --upsert "$(pwd)" "$START_SHA" "$ARGUMENTS" "$TASK_NAME" "" "cc"
```

Note: empty arg 5 (`expected_agent_id`) — a standalone child cannot reliably know its own agentId; the hook fails open on empty `expected_agent_id` (per `implement-next-stop-gate.sh:62-64`). The `--upsert` flag's read-merge semantics mean a parent-written breadcrumb (with a real `expected_agent_id`) is preserved verbatim — the child only writes its own when there is no parent breadcrumb on disk. The skill does NOT need to inspect parent identity; the writer's merge logic handles both cases.

---

### Step 1: Show progress and identify the next task

Run:

```
bash ~/.claude/scripts/plan-progress.sh "$ARGUMENTS"
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

If `REVIEW_RANGE` was set by Step 0, use it as the review target (e.g., `git diff <sha_before>..HEAD` or `git diff HEAD` with worktree per the case); otherwise default to `git diff HEAD`.

The DA review must NOT create its own commits — all fixes stay as uncommitted working tree changes.

**Review-abort handling.** If the iterative-review aborts mid-flow with unresolved findings, restart it ONCE. If the restart also aborts:

```
bash ~/.claude/scripts/implement-next-state-write.sh --increment-review-abort "$(pwd)"
```

Then HALT — do NOT commit. Print the unresolved findings, leave the working tree as-is, end your turn with non-zero exit. The next invocation's Step 0 triage will see `review_abort_count >= 2` and dispatch `R-Stuck`.

**⚠️ MANDATORY CONTINUATION — DO NOT STOP HERE.** The `## Review Summary` and `### Verdict` produced by `/iterative-review` mark the end of the *review sub-step only*. They do NOT mean the task is complete. You MUST proceed to Step 4 immediately after the review verdict, regardless of what the verdict says. Any text that says "Proceeding to Step 4" is a declaration of intent — you still must actually execute Step 4 yourself. Do not end your turn after Step 3.

---

### Step 4: Run tests

**Subagent-specific guidance — read this carefully.**

If you are running inside a subagent spawned by `/implement-all-cc`, the test suite for this project may exceed `Bash`'s 10-minute foreground ceiling (verified via anthropics/claude-code GitHub issue #25881, accessed 2026-06-11). Do NOT use the `Monitor` tool inside this subagent to wait for tests — `Monitor` instructs you to yield ("Keep working — do not poll … Events may arrive while you are waiting for the user"), but a subagent has no future user turn for events to attach to, so the run silently dies and the parent sees an empty commit. This was the dominant failure mode of historical implement-next runs.

Two acceptable options inside a subagent:

1. **Tests complete in ≤ 9 minutes (preferred).** Run the full suite with `Bash` foreground, `timeout: 540000` (9 minutes — leaves headroom under the 600,000 ms ceiling). Block until it returns.

2. **Tests do NOT fit in 9 minutes.** Do not attempt a full suite here. Run only the *task-relevant subset* (the tests you added in Step 2 plus their immediate neighbourhood). End your turn with the working tree still uncommitted but the relevant subset green. `/implement-all-cc`'s Case-B recovery path at the parent level will run the full suite there (where `Monitor` works correctly) before committing.

In both options, never use `run_in_background` inside the subagent unless you can complete the wait inside a single blocking `Bash` call that also reads the exit code — which in practice means option 1.

If the chosen test command reports failures:

1. Spawn a fix agent with the full failure output. The agent must fix all failing tests.
2. Re-run the same command.
3. Repeat until green, or three consecutive fix attempts all fail — in which case stop and report the failures for human review.

Only continue to Step 5 once your chosen test scope is fully green.

---

### Step 5: Check off completed items

Spawn an agent to update $ARGUMENTS: mark the implemented task and every completed sub-item as done (`[ ]` → `[x]`). Be precise — only check what was actually implemented and verified. Do not check items that were skipped or only partially completed.

---

### Step 6: Commit

**NON-NEGOTIABLE: Each task gets its own commit. One task = one commit. Never batch multiple tasks into a single commit.**

Commit all changes for this task — implementation files AND the updated plan file — in a single commit with a message derived from the actual task content. Do not skip hooks (`--no-verify` is forbidden). Stage only files relevant to this task.

**Recovery-case commit-subject prefixes.** If Step 0 dispatched `R-B`, the commit subject MUST begin with `recovery(R-B): ` (no other prefix). If Step 0 dispatched `R-AB`, the commit subject MUST begin with `recovery(R-AB): `. `audit-plan-run.sh` matches against these anchored prefixes to downgrade the post-loop VIOLATION to a WARNING.

**If the commit fails:** revert the plan file and unstage implementation files, then retry:
1. `git reset HEAD` — unstage everything
2. Restore the plan file:
   - If tracked: `git checkout HEAD -- "$ARGUMENTS"`
   - If untracked: save content to a temp file first (`cp "$ARGUMENTS" /tmp/plan-backup.md`), then recreate from the backup after fixing the issue
3. Fix the underlying issue (e.g., lint or type-check failures from a pre-commit hook)
4. Redo Step 5 and Step 6

---

### Step 7: Self-verification

**Before ending your turn, programmatically verify the work landed.** The `SubagentStop` hook used in `/implement-all-cc` already blocks turn-end until a commit lands, but the additional checks here catch silent failure modes the hook cannot detect (plan not checked off, plan-only commit).

Run these checks (with `START_SHA` and `START_CHECKED` from Step 0; for R-B, `START_SHA` is the breadcrumb's `sha_before`):

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

3. **The new commit's diff includes both the plan file AND implementation files** (not plan-only). Wrap this in a self-contained R-B detection — if the latest commit's subject begins with `recovery(R-B):`, the commit is plan-only by design; skip the check:
   ```
   if git log -1 --format='%s' HEAD | grep -q '^recovery(R-B):'; then
     echo "Step 7 check 3: SKIPPED (R-B recovery commit is plan-only by design)"
   else
     git show --stat HEAD | grep -q "$(basename "$ARGUMENTS")"
     git show --stat HEAD | awk 'NR>1 && /\|/ {print $1}' | grep -v "$(basename "$ARGUMENTS")" | grep -q .
   fi
   ```
   This eliminates LLM-memory dependence on the Step 0 case.

If **any check fails**, do NOT end your turn. Diagnose the gap (missing commit? plan not checked? plan-only commit?) and return to the appropriate earlier step. If the same check fails twice in a row, report the specific failure in plain English ("Step 7 check 2 failed: plan-checked-task count went from N to M, expected N+1") and end the turn with a clear "task incomplete" status so the parent `/implement-all-cc` loop can halt cleanly.

On success, clear the breadcrumb:

```
bash ~/.claude/scripts/implement-next-state-clear.sh "$(pwd)"
```

---

### Step 8: Report

Output a concise report for this task:
- What was implemented
- Test results summary
- Any feature loss or deviation from the task spec (be precise)
- Any unresolvable oscillations from the DA loop
- What was checked off in the plan
- Step 7 self-verification result (all three checks pass / which failed)
