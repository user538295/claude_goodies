---
name: quick-plan
description: >
  Lightweight task decomposition — define a measurable goal, success criteria, and 4–12 actionable
  steps before doing any work. Use when the user says "plan this", "break this down", "decompose",
  "quick plan", "what are the steps", or when a task is complex enough to benefit from upfront
  structure. Outputs inline — no file created.
  Plan only — does not execute.
---

# Quick Plan

Decompose a task into a measurable goal, success criteria, and 4–12 concrete steps.

---

## Process

### 1. Goal

State one measurable goal derived from the user's request. Show it to the user.

Format:
> **Goal:** [one sentence — what is done when this succeeds]

### 2. Success Criteria

List 2–6 criteria that are individually verifiable (a command, a test, a visible behavior).
Show them to the user.

Format:
> **Success criteria:**
> - [ ] [criterion — how to verify it]

If a criterion is vague ("make it work", "should be good"), stop and ask the user to clarify
before continuing. Strong criteria let you loop independently; weak criteria require constant
clarification.

### 3. Match Check

Verify the goal and criteria actually match the user's request. If they drift, fix them and
show the corrected versions. Do not proceed until all three align: request, goal, criteria.

### 4. Steps

Define 4–12 steps that achieve the goal and satisfy every success criterion.

Rules:
- Use /plain-language — every step must be understandable by a non-expert.
- Each step names what to do, which file or area it touches, and how to verify it worked.
- Embed verification inside the steps — not only at the end. A step that changes behavior
  should include its check ("run X and confirm Y").
- Include test steps where non-trivial logic is introduced.
- Steps are ordered by dependency — earlier steps don't depend on later ones.

### 5. Review Loop

Review the steps for: gaps, wrong order, missing verifications, steps that are too large,
steps that don't trace to a success criterion.

Fix any issues found. Repeat up to 3 passes. If still broken after 3, show the remaining
issues to the user and ask for guidance.

### 6. Show the Plan

Present the final plan in this format:

```
**Goal:** ...

**Success criteria:**
- [ ] ...

**Steps:**
1. ...
2. ...
...
```

Do not suggest next steps.

---

## Replanning

If during execution (by another skill or manually) the steps need to change:
- Show the updated full plan with changes marked
- Continue from the current position

---

## Scope

- This skill outputs inline text, not a file.
- This skill does not execute. It plans.
- 4 steps minimum, 12 steps maximum.
