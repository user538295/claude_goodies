---
description: Claude Code rescue variant — called by /implement-all-cc Case-B rescue. Performs only Steps 5 and 6 of /implement-next-cc (check off + commit) on already-staged work. Do NOT invoke directly.
---

<!-- RECOVERY_SCHEMA_V2 -->

Plan file: $ARGUMENTS

This skill exists to rescue a stalled `/implement-next-cc` subagent without redoing work. The parent `/implement-all-cc` Case-B rescue path:
1. Has already run the full test suite at parent level and confirmed tests pass.
2. Has already done the implementation work (it's sitting in the working tree, uncommitted).
3. Spawns this skill to do ONLY the checkoff + commit.

### Step 1: Identify the task to check off

The dirty tree contains exactly one task's worth of implementation (the parent verified this before spawning the rescue). To find WHICH task it is, run:

```bash
bash ~/.claude/scripts/plan-progress.sh "$ARGUMENTS"
```

The first uncompleted task in the plan (NEXT_TASK_NAME) is the one to check off. In the plan file, change that task's checkbox from `- [ ]` to `- [x]`. Also check off any sub-items that the diff clearly indicates were completed.

### Step 2: Commit

NON-NEGOTIABLE: one task = one commit. Stage implementation files AND the updated plan file. Commit with a message derived from the task content. Do NOT skip hooks.

If the commit fails: report the failure to the parent. The parent will halt.

After the commit succeeds, clear the breadcrumb so the parent's next-iteration check isn't poisoned:

```
bash ~/.claude/scripts/implement-next-state-clear.sh "$(pwd)"
```

The clear is the last action on the success path. If the commit fails, the parent's halt-path clear handles cleanup — this skill does NOT clear on commit failure.

### Step 3: Report

Single-line report: "Rescue commit landed: <sha>" or "Rescue failed: <reason>".
