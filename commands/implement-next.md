---
description: Portable runtime-agnostic — read a plan from $ARGUMENTS, implement the next uncompleted task with TDD, optional review, blocking tests, check off, commit. Works in any harness without hook dependencies.
---

Plan file: $ARGUMENTS

**You MUST follow the instructions step-by-step, precisely. You MUST NOT make shortcuts!**

### Step 1: Show progress and identify the next task

Run:

```
bash "${CLAUDE_PLUGIN_ROOT}"/scripts/plan-progress.sh "$ARGUMENTS"
```

**Exit 0 (normal):** print the human-readable block verbatim. Read `NEXT_TASK_NAME` from the machine-readable lines, then read $ARGUMENTS to extract the full task details: description, sub-items, and — for a self-contained plan — acceptance criteria. (For a task-breakdown file with a companion plan, per-task acceptance criteria are the `S#`/`C#` the task `completes`; those are **defined in the companion plan**, not in $ARGUMENTS — see below.)

**Companion plan detection.** $ARGUMENTS may be a self-contained plan, or a task-breakdown file whose scenario/contract definitions (`S#`/`C#`), open questions (`Q#`), architecture, contracts, and acceptance criteria live in a separate **companion plan**. Resolve the companion plan in this order:

1. **References link.** If $ARGUMENTS has a `## References` section, resolve its `**Plan:**` bullet's Markdown link (target: the `*-team-plan.md` file) relative to $ARGUMENTS's directory. The producer (`create-tasks`) co-emits this link and the `plan:` key below, both naming the same sibling, so they normally agree; the link is canonical because, as a relative path, it still resolves correctly if a plan is ever hand-moved. If both are present but resolve to two *different existing* files, STOP and report the inconsistency — that is a corrupt task file, not a precedence choice.
2. **Frontmatter `plan:` key (sibling fallback).** Else, if the frontmatter has a `plan:` key naming a *different* file, resolve it relative to $ARGUMENTS's directory (this assumes the plan is a sibling — the key is a bare filename).
3. **Self-contained.** Else — no References link and no `plan:` key, or the key points at $ARGUMENTS itself — there is no companion plan; $ARGUMENTS holds everything.

If step 1 or 2 identifies a companion plan path but that file **does not exist** (moved/renamed), STOP and report it — do NOT silently fall through to self-contained, because a split plan implemented without its context will resolve `S#`/`C#` wrong.

**Terminology for the rest of this command:** "**the task-breakdown file**" = $ARGUMENTS (holds the checkboxes; this is what progress, check-off in Step 5, and the commit in Step 6 target). "**the companion plan**" = the resolved plan file (context only — never edited, never committed by this run). When a companion plan exists, note its path — you will pass it to every agent below.

**Exit 1:** all tasks are complete — stop here, report completion.

**Any other exit code or script not found (fallback):** read the appropriate template from `"${CLAUDE_PLUGIN_ROOT}"/scripts/` (`progress-header-phased.template` if the plan has `###` headings within the task section (`## Tasks` / `## Task breakdown`), `progress-header-flat.template` otherwise), compute the placeholder values by reading $ARGUMENTS directly, substitute them, and print the result. Then continue as normal — including the companion-plan detection above — a failed script must not block progress.

### Step 2: Implement (TDD)

**Determine the most appropriate agent type for this task, then spawn it to perform the implementation.** Pass it the full task description, sub-items, the working directory, the task-breakdown file path, and — when Step 1 detected one — the **companion plan path**. Instruct it to follow these instructions exactly:

 **You MUST follow these instructions**:

 **CONTEXT — if a companion plan was detected in Step 1:** read the companion plan file FIRST, before any other work. This task's `completes` field cites the scenarios/contracts (`S#`/`C#`) it must satisfy — those, plus the architecture, contracts, and acceptance criteria, are **defined only in the companion plan**; the task-breakdown file gives you the IDs, the plan gives you their meaning. (`needs` cites predecessor task IDs, not `S#`/`C#`; `Q#` are the plan's open questions — read them for context but they are not yours to resolve.) Read only the companion plan itself — do NOT chase its own `brief:`/References links; one hop is enough. This applies to every task, including documentation and close-out tasks that reference the plan's sections by name.

 **SCOPE — non-negotiable:**
 - Implement EXACTLY ONE task: the first uncompleted task in the plan. Do not preview, prepare, or implement any subsequent task.
 - Touch only what THIS task requires: files the task description names, PLUS any minimal side-effect edits the change forces (broken sibling tests, import updates, manifests). No unrelated refactors, cleanups, or "while I'm here" edits on files this task does not require.

 **FORBIDDEN:**
 - Do NOT modify the task-breakdown file, or the companion plan, at all. Checkboxes are toggled by the orchestrator in Step 5, not by you.
 - Do NOT create any git commits — leave all changes as uncommitted working tree modifications.

If the task produces testable code output, follow strict TDD:

1. **Write tests first** — unit, integration, and live/end-to-end tests covering the new behaviour and the task's acceptance criteria. Tests must fail at this point (red).
2. **Run the tests** — confirm they fail for the right reasons. One test run at a time: before starting any run, verify no earlier test run is still alive with `ps -Ao comm=,args= | awk '$1 ~ /[Pp]ython/ && /\/pytest/'` (must be empty — `pgrep -fl pytest` self-matches the shell and must not be used). Overlapping runs multiply parallel workers and can OOM the machine.
3. **Implement the functionality** — write only enough code to make the tests pass (green).
4. **Run the tests again** — all new and existing tests must pass before continuing.

If the task has no testable code output (documentation, configuration, CI changes, diagrams), skip the TDD cycle and implement directly.

No assumptions — read all relevant code, documentation, and context first.

Return a summary of what was implemented and which files were changed.

Instruct the agent with all of the above. Wait for the agent to return before continuing.

### Step 3: Critical review

**You MUST run `/iterative-review`** (or `claude-goodies:iterative-review` if that is the name shown in your skill list)**.** When a companion plan was detected in Step 1, pass its path in the review target and instruct the reviewers to read it first — the acceptance criteria and `S#`/`C#` this task must satisfy are defined there, not in the task-breakdown file.

After `/iterative-review` returns — regardless of what its Verdict says — you MUST immediately continue to Step 4. The Review Summary is a sub-task result, not your completion signal. **Do NOT stop here.**

### Step 4: Run tests

You MUST run the full test suite. In Claude Code the `Bash` foreground ceiling is **~120 seconds** — commands that run longer are auto-backgrounded, ending your turn before any commit lands. To run a suite that takes longer than 120 s:

1. Launch pytest with `run_in_background: true` — capture the process ID from the result.
2. Immediately call the `Monitor` tool on that process — it streams stdout line-by-line and **keeps your session alive** for the full duration.
3. Read the Monitor result to determine pass/fail and continue to Step 5.

In Cursor or other harnesses without `Monitor`, fall back to the *task-relevant subset* (tests added in Step 2 plus their immediate neighbourhood) as a blocking call; report the partial scope in Step 7.

**Before any test run, verify no earlier run is still alive:** `ps -Ao comm=,args= | awk '$1 ~ /[Pp]ython/ && /\/pytest/'` must be empty (`pgrep -fl pytest` self-matches the shell — do not use it). Stacked suite runs multiply parallel workers and have OOM-crashed a 48 GB machine.

If the test command reports failures:

1. Spawn the same agent type as Step 2. Pass it: the full test failure output, the task description, the companion plan path with the "read it first" instruction if one was detected in Step 1 (the acceptance criteria live there), the SCOPE and FORBIDDEN constraints from Step 2, the working directory, and — on retries — the output and changes from all prior fix attempts so the agent knows what was already tried and why it failed.
2. Re-run the same command.
3. Repeat until green, or three consecutive fix attempts all fail — in which case stop and report the failures for human review.

Only continue to next Step once your chosen test scope is fully green.

### Step 5: Check off completed items

Update `$ARGUMENTS`: mark the implemented task and every completed sub-item as done (`[ ]` → `[x]`). Be precise — only check what was actually implemented and verified. Do not check items that were skipped or only partially completed.

### Step 6: Commit

**NON-NEGOTIABLE: one task = one commit.** Never batch multiple tasks into a single commit.

Commit all changes for this task — implementation files AND the updated task-breakdown file ($ARGUMENTS, with its newly checked boxes) — in a single commit with a message derived from the actual task content. The companion plan, if any, is not modified and is not part of the commit.

### Step 7: Report

Output a concise report for this task in the following exact form. Do NOT prose, you MUST report it and in the exact form. This is non-negotiable.
> **Task [N.M] Implementation report:**
> - Implemented: [What was imlemented]
> - Tests: [Test results summary, max 250 chars]
> - Feature loss or deviation: [Any feature loss or deviation from the task spec (be extremely precise); max 250 chars]
> - Unresolvable oscillations: [Any unresolvable oscillations from the review loop; max 250 chars]
> - Task [N.M] — checked at line [NNN] and committed ([full-hash])
