---
description: Single-pass devil's advocate review. Finds flaws without auto-fixing. Use /iterative-review to also apply fixes.
allowed-tools: Read, Grep, Glob
---

Review the following target: $ARGUMENTS (if empty, review the current plan/code/work in context).

Adopt an adversarial perspective. Your goal is to find every flaw — do not soften findings.

Use the severity rubric defined in `/iterative-review`:
- **Critical**: blocks correctness, security, or safety
- **Major**: significant design flaw, missing requirement, or likely bug
- **Moderate**: suboptimal but workable
- **Minor**: style, naming, or nitpick

(This rubric is the single source of truth in `iterative-review.md` — keep them in sync if updated.)

For each issue found, provide:
- Severity label
- Short description of the problem
- Why it matters / what could go wrong

Group findings by severity (Critical first). At the end, give a one-sentence overall verdict.

Do not propose fixes — only identify problems.
