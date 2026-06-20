---
description: Run a devil's advocate review. Scope — quick single pass or full delegated review — is decided by the target, or state it explicitly. Use /iterative-review to also apply fixes.
---

**Your FIRST action MUST be to invoke the Skill tool and load the `devils-advocate` skill.** Do not read files, analyze, or write any part of the review before that call — the skill defines the mandatory method, severity rubric, and output format, and they are not optional. Reading the command text is not a substitute for invoking the skill.

Then review: $ARGUMENTS (if empty, review the current plan, code, or work in context).

Let the skill size itself to the target — a small, self-contained target gets a quick inline pass; a larger or higher-stakes one gets the full delegated review. Honor any scope the user states explicitly (e.g. "just a quick look", "full review").

**Do not substitute your own format or skip the skill's mandated sections.** Follow the skill's output structure exactly.
