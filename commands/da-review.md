---
description: Single-pass devil's advocate review. Finds flaws without auto-fixing. Use /iterative-review to also apply fixes.
allowed-tools: Read, Grep, Glob
---

Review the following target: $ARGUMENTS (if empty, review the current plan/code/work in context).
Use the `devils-advocate` agent for the review (agent type `devils-advocate`, or `claude-goodies:devils-advocate` if that is the name shown in your agent list; minimum 3).
Your goal is to find every flaw — do not soften findings. Don't assume, fact check everything including your findings that are correct.

Use the following severity rubrics:
- **Critical**: blocks correctness, security, or safety
- **Major**: significant design flaw, missing requirement, or likely bug
- **Moderate**: suboptimal but workable
- **Minor**: style, naming, or nitpick

For each issue found, provide:
- Severity label
- filename:line_number (omit when no file location applies — e.g. a plan-level, conceptual, or cross-cutting finding; never invent one)
- Short description of the problem and why it matters / what could go wrong. **Must be under 250 chars**

Group findings by severity (Critical first). At the end, give a one-sentence overall verdict.

Do not propose fixes — only identify problems.
