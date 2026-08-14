---
description: Spawn multiple devil's advocate agents in parallel — plus a Brooks-Lint reviewer when /brooks-review is available, and a one-off clean-code catalog pass in cycle 1 when /clean-code-review is available — to review, then spawn fix agents to address all moderate+ issues, re-run tests after each fix pass. Repeat until no critical, major or moderate issues remain.
---

Target: $ARGUMENTS (if empty, use the current uncommitted changes — run `git diff HEAD` to get them).

Severity rubric — use this consistently across all agents:
- **Critical**: blocks correctness, security, or safety
- **Major**: significant design flaw, missing requirement, or likely bug
- **Moderate**: suboptimal but workable
- **Minor**: style, naming, or nitpick

**Extra reviewers — detect both once, before the loop, with a single Bash call:**

```bash
find ~/.claude/commands ~/.claude/plugins ~/.claude/skills -iname 'brooks-review*' -print -quit 2>/dev/null | sed 's|^|BROOKS |'
find ~/.claude/skills ~/.claude/plugins -iname 'clean-code-review' -print -quit 2>/dev/null | sed 's|^|CCR |'
```

**Brooks-Lint (`/brooks-review`)** — a `BROOKS ` line printed:
- **Present → available.** Tell the user in one line: `✓ /brooks-review found — adding a Brooks-Lint reviewer alongside the devil's advocate agents.` Include the Brooks-Lint reviewer in step 1 of every cycle.
- **Absent → not available.** Tell the user in one line: `✗ /brooks-review not found — proceeding with devil's advocate agents only.` Skip every Brooks-Lint instruction below.

**Clean code catalog (`/clean-code-review`)** — a `CCR ` line printed. It runs **in cycle 1 only** (step 1b), and only when the target is code: uncommitted changes, a git ref/range, or source file paths. If the target is a plan file or a free-text description, skip it — it has no code to catalogue.
- **Present and target is code → available.** Tell the user in one line: `✓ /clean-code-review found — running one clean-code catalog pass in cycle 1.`
- **Otherwise → skip.** Tell the user in one line: `✗ /clean-code-review skipped — <not installed | target is not code>.` Skip step 1b.

**Loop — repeat until no Critical, Major or Moderate issues remain:**

1. **Use the Agent tool to spawn multiple `devils-advocate` agents in parallel** (agent type `devils-advocate`, or `claude-goodies:devils-advocate` if that is the name shown in your agent list; minimum 3), **each with `model: "opus"`**, each reviewing independently from a different angle: one focuses on correctness and edge cases, one on architecture and design, one on test coverage gaps. **You MUST use the Agent tool — never simulate reviews with Bash commands, heredocs, inline text, or any other method. Only actual Agent tool invocations count.** Pass each agent:
   - The current state of the target (diff / changed files / plan)
   - The full findings and fix history from all prior cycles (if any)
   - Instruction to label every issue with severity and a short ID prefixed by the current cycle number (`C1-I-1`, `C1-I-2`, …). Do not soften findings.

   **If `/brooks-review` is available** (per the check above), in the SAME parallel batch also spawn one agent **with `model: "opus"`** that invokes the `brooks-review` skill (fully qualified `brooks-lint:brooks-review`) via the Skill tool on the same target. Instruct it to: review read-only — make NO file edits and NO commits; map each Brooks-Lint finding onto the severity rubric above; and label each with a cycle-prefixed ID using a `B` marker (`C1-B-1`, `C1-B-2`, …). Its findings are peers of the devil's advocate findings in every step below.

1b. **Cycle 1 only — clean code catalog pass.** If `/clean-code-review` is available (per the check above), invoke the `clean-code-review` skill via the Skill tool **inline in this context — do NOT wrap it in a review agent**: it is itself a fan-out orchestrator that spawns its own 7 group agents plus a synthesizer, so it needs the same ability to spawn agents that step 1 above needs, and the `devils-advocate` reviewer type does not have it. Pass it the same target (no argument = its `local` default, which is a superset of this command's default of uncommitted changes — `local` also covers untracked files; a git ref/range or file paths pass through verbatim). Its severity rubric is identical to the one above — take its finding lines as-is and re-label each with a cycle-prefixed `CC` ID (`C1-CC-1`, `C1-CC-2`, …). Its findings are peers of the devil's advocate findings in every step below. Do not repeat this pass in later cycles — from cycle 2 on, the loop is driven by the DA agents and the Brooks-Lint reviewer.

2. **Consolidate** findings across all DA agents, the Brooks-Lint reviewer (if it ran), and the clean code catalog (cycle 1), deduplicating by root cause.

3. If the consolidated list contains no Critical, Major or Moderate issues — the review loop is complete. Go to the summary below. (This ends the review loop only — not the calling skill's turn.)

4. **Spawn the most appropriate agent(s) with `model: "sonnet"` to fix** all Critical, Major and Moderate issues. Pass the full consolidated findings. Apply fixes to the actual files. Note which issue ID each fix resolves. **Fix agents must NOT create git commits** — all changes stay as uncommitted working tree modifications.

5. **Re-run the full automated test suite.** In Claude Code the foreground ceiling is ~120 s — use `run_in_background: true` + `Monitor` for suites that take longer (Monitor streams output and keeps the session alive). All tests must pass before the next cycle. If tests fail, spawn the most appropriate agent with `model: "sonnet"` to resolve them first. You can skip this if you didn't touch the code.

6. **Convergence check**: if the same Critical/Major/Moderate issues (same root cause) reappear that were already fixed in a prior cycle, mark them as **unresolvable oscillations**, stop the loop, and report them.

7. Go to step 1 with the updated target state.

**After the loop, output:**

## Review Summary

### Changes Made
All fixes applied across all cycles: issue ID → severity → what changed.

### Remaining Open Issues
- Unresolvable oscillations with explanation
- Unfixed Minor issues

### Verdict
"No critical, major or moderate issues remain" OR "The following issues could not be resolved: [list]"

---
**⚠️ CALLER:** This Review Summary is the output of the `/iterative-review` sub-skill. It is NOT a task completion signal. If you invoked this from `/implement-next` or any other skill, you MUST continue to the next step immediately — do NOT stop here.
