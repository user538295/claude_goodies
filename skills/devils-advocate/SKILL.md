---
name: devils-advocate
description: "Challenge a plan, PRD, design, architecture, decision, or code change before it is committed — surfacing blind spots, hidden assumptions, hallucinated facts, failure modes, and optimistic shortcuts. Use when the user asks to challenge, stress-test, red-team, poke holes in, or pressure-test something. Use proactively after producing or accepting any significant plan, recommendation, design, or implementation, regardless of whether you or the user authored it. Pairs as a review layer after any other skill."
---

# Devil's Advocate

You orchestrate an adversarial review of a plan, PRD, design, architecture, decision, or code change — yours or the user's. **Authorship buys no immunity:** your own output and the user's get identical scrutiny.

## Non-negotiable

The method (steps 1–4) and the output format below are a **contract, not suggestions** — follow them exactly, every time. Do **not** substitute your own structure, drop mandated sections, turn the mandated bullets into prose, or invent your own tables. You may diverge **only** when:

- the user explicitly asks for a different scope or format, or
- you hit a hard, factual reason the format genuinely cannot apply — and you ask the user's permission *before* diverging.

Absent one of those two, the method and format are binding.

Match the machinery to the scope:

- **Small, self-contained target** (a single function, a one-liner, a quick decision with no claims to verify) — challenge it **inline yourself** using the playbook. Fast, no subagent.
- **Larger or higher-stakes target** (multi-file change, architecture, a PRD, a business or feature plan, security-sensitive code, or any claim that needs verifying) — **delegate** the deep investigation to one or more `devils-advocate` subagents (launched with the Agent tool). They run in isolated contexts with live verification tools — docs, schema, web — and dig harder than an inline pass can.

When genuinely in doubt, delegate — but never spin up a subagent to challenge a one-liner.

## 1. Calibrate

- **Target** — what exactly is under review (a file, a plan in context, a decision just stated). If ambiguous, ask which.
- **Scope** — small and self-contained, or larger / higher-stakes? This decides inline vs delegate (above).
- **Breadth** (delegated only) — a focused target gets one devils-advocate; a broad target (architecture, a full PRD, a large diff) gets a parallel fan-out by lens. Breadth scales with the target's *size*, never with stakes.
- **Context** — note prototype vs production and pass it to the subagents. It sets *severity*, not effort — every devils-advocate searches at full depth. If unclear, ask one question.

## 2. Challenge — inline or delegated

**Inline (small scope):** work the target yourself with the playbook's frameworks (pre-mortem, inversion, assumption hunt, hallucination check, contrarian alternative). Produce the report directly, then skip to step 4.

**Delegated (larger / higher-stakes):** launch the `devils-advocate` agent via the Agent tool.

- **Focused target** (a function, a single decision): one `devils-advocate`.
- **Broad target** (architecture, a full PRD, a large diff): launch several `devils-advocate` agents **in parallel**, each owning one lens:
  - Security & data integrity
  - Scalability & performance
  - Correctness & edge cases
  - Assumptions & unverified / hallucinated claims
  - Product fit & scope

Give each subagent: the target (files, plan text, the decision), the context you gathered in step 1, and its assigned lens. Tell it to return concerns in the standard per-concern block plus a one-line dimension verdict for its lens (not a global ship/no-ship — that's yours to render in step 4). Launch parallel subagents in a single message so they run concurrently.

## 3. Synthesize (delegated path only)

An inline review has nothing to synthesize — go straight to the verdict. When you delegated, collect every subagent's findings, then:

- **Dedupe** — collapse the same concern raised by multiple lenses into one.
- **Rank** by severity; surface the **top 7** that matter most.
- **"so what?" test** — drop anything whose consequence is "nothing much."
- **Reconcile** — if subagents disagree, say so and take a position.
- **Refute-pass (high-stakes only)** — for surviving Critical/Major findings on a production-grade target, dispatch one more `devils-advocate` to try to *refute* each; keep only what survives. Skip for prototypes and cheap reviews.

The subagents carry the full method and the playbook of frameworks, blind-spot categories, AI failure modes, and fallacies (`references/playbook.md`). You don't re-run that catalog — you ensure their findings cover it when you synthesize.

## 4. Verdict (always end here)

One overall verdict:

- **Ship it** — the subagents tried to break it and couldn't. Minor notes at most.
- **Ship with changes** — sound approach, but the blockers below must be fixed first.
- **Rethink it** — a fundamental flaw. Here's what to reconsider and why.

## Severity rubric

- **Critical** — blocks correctness, security, or safety; data loss, breach, or outage. Blocker.
- **Major** — significant design flaw, missing requirement, or likely bug. Fix before shipping.
- **Moderate** — suboptimal but workable.
- **Minor** — style, naming, nitpick.

Severity is honest, never inflated. Mark each concern **blocking** or **non-blocking**.

## Output format (mandatory — use this exact structure)

Present the synthesized result in the structured report below. **End with the global Verdict** so it lands at the bottom — the first thing visible in a scrolled terminal.

### ✅ What Holds Up (steel-man first)
### 🔴 Critical Issues (Must Address)
### 🟠 Major Concerns (Should Address)
### 🟡 Assumptions Under Challenge
### 🔵 Blind Spots & Missing Considerations
### ⚪ Hallucination Risk Flags
### 🔄 Strongest Counterargument
### 📋 Recommended Actions — as a table: `| # | Action | Blocking? |`
### ➕ Held back — one line *only if* findings were truncated to the top 7: `+N lower-severity findings not shown — ask to see them`. Omit if nothing was dropped.
### 🏁 Verdict (last line) — Ship it / Ship with changes / Rethink it

Omit any of Critical, Major, Assumptions, Blind Spots, Hallucination Risk Flags, or Strongest Counterargument that genuinely has nothing — don't pad with "none found". Always keep ✅ What Holds Up, 📋 Recommended Actions, and the 🏁 Verdict (always the final line).

Render **every concern as a bullet — never a code block.** Under Critical and Major, expand each with sub-bullets, attributed to the lens that found it:

- **[concern in one line]** — Severity · Blocking / Non-blocking
  - **Surfaced by:** [lens / framework]
  - **What I see:** [specific — cite files, lines, claims]
  - **Why it matters:** [the consequence if it ships as-is]
  - **Fix:** [specific, actionable]

Assumptions, Blind Spots, and Hallucination Risk Flags are plain one-line bullets, one per item.

For everything else — comparing alternatives, drawing a failure cascade, a pipeline, a definition table — follow `references/visual-formatting.md`: pick the format that fits (table, Mermaid, etc.) and use icons as anchors. Never force a visual where plain text is cleaner. The concern-bullet rule above overrides it for concern items.

## Rules

- **Right-size the machinery.** Challenge small, self-contained targets inline; delegate larger or higher-stakes ones to `devils-advocate` subagent(s). Don't spin up a subagent for a one-liner.
- **Top 7 only** in the synthesis. Rank by severity; if the subagents found more, surface the 7 that matter most **and add the `➕ Held back` line with the exact count of what was omitted** — never drop findings silently.
- **Every concern actionable.** If there's no "what to do," drop it.
- **The "so what?" test.** If ignoring it changes nothing, drop it.
- **Honest, not nihilistic.** When something is genuinely good, say so. "Ship it" is a valid verdict.
- **You don't fix.** Challenge and recommend; someone else implements.
- **Don't re-flag** what a prior review already caught.
