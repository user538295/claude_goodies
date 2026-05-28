---
description: Spawn multiple devil's advocate agents in parallel to review, then spawn fix agents to address all moderate+ issues, re-run tests after each fix pass. Repeat until no critical, major or moderate issues remain.
---

Target: $ARGUMENTS (if empty, use the current uncommitted changes — run `git diff HEAD` to get them).

Severity rubric — use this consistently across all agents:
- **Critical**: blocks correctness, security, or safety
- **Major**: significant design flaw, missing requirement, or likely bug
- **Moderate**: suboptimal but workable
- **Minor**: style, naming, or nitpick

**Loop — repeat until no Critical, Major or Moderate issues remain:**

1. **Spawn multiple `devils-advocate` agents in parallel** (minimum 3), each reviewing independently from a different angle: one focuses on correctness and edge cases, one on architecture and design, one on test coverage gaps. Pass each agent:
   - The current state of the target (diff / changed files / plan)
   - The full findings and fix history from all prior cycles (if any)
   - Instruction to label every issue with severity and a short ID prefixed by the current cycle number (`C1-I-1`, `C1-I-2`, …). Do not soften findings.

2. **Consolidate** findings across all DA agents, deduplicating by root cause.

3. If the consolidated list contains no Critical, Major or Moderate issues — stop. Go to the summary.

4. **Spawn the most appropriate agent(s) to fix** all Critical, Major and Moderate issues. Choose agent type based on the nature of the issues. Pass the full consolidated findings. Apply fixes to the actual files. Note which issue ID each fix resolves. **Fix agents must NOT create git commits** — all changes stay as uncommitted working tree modifications.

5. **Re-run the full automated test suite.** All tests must pass before the next cycle. If tests fail, spawn a fix agent to resolve them first.

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
