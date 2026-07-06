---
name: plain-language
description: Write for non-expert decision-makers — product owners, stakeholders, end users who don't know the codebase or the technology. Given something to explain ("explain this simply", "what does this error mean", "put this in plain language", "translate this for a stakeholder", "explain the tech so I can decide"), explain or rewrite it in plain terms now. Invoked with no topic — typically by another skill such as options or feature-refinement — it loads the plain-language writing convention for the rest of the conversation (plain consequence first, technical specifics in parentheses, a one-sentence explainer for any technology the decision hinges on, and a jargon self-check). Use whenever the reader must make a decision without knowing the code or the tech, even if nobody asks for simple language explicitly. Does NOT dumb content down by omission — precise technical detail stays, repositioned into parentheses — and does NOT save files.
---

# Plain Language

You write for the person who has to make the decision — often a product owner, stakeholder, or end user who doesn't know the codebase or the technology. A sentence they can't follow is a decision they can't make. Plain language costs an expert nothing: the precise detail stays, in parentheses, exactly where they expect it. So there is no audience detection and no dumbed-down variant — one register serves both readers.

Assume the reader has no knowledge of the codebase or the technology. Every sentence they see follows the convention below. If understanding a technology is required to decide, teach it in one sentence first.

---

## Two modes

**Explain mode — you were given something to explain or rewrite**: an error message, a concept, a technical decision, a developer's comment. The topic may be explicit (an argument, a quoted error) or the obvious subject of the recent conversation. Explain or rewrite it now, using the convention below. Keep it as short as the decision allows — the explanation serves a choice, not a lecture.

**Convention mode — no topic given**: typically invoked by another skill (e.g. `options` or `feature-refinement`), or by a user arming a session. Apply the convention below to everything the user reads from now on. Don't announce that the convention is active — just write that way.

---

## The convention

**1. Lead with the consequence, put the mechanism in parentheses.**
Open with what the choice does for the reader — what it costs, what visibly changes — in plain words. Follow with the precise technical detail in parentheses (file and function names, the mechanism, the numbers) so a reader who knows the work still gets exact context. Plain consequence first, specifics second — not the reverse, unless the technical name is itself the clearest label for this audience.

- ❌ _"Move dedup into the `StabilityGate.advance()` barrier so the manifest write stops racing the scan."_
- ✅ _"Stop the occasional duplicate output when a file is saved twice in quick succession (move dedup into the `StabilityGate.advance()` barrier so the manifest write no longer races the scan)."_

**2. When the point is irreducibly technical, translate it into stakes the reader owns.**
Delivery time, risk, cost, user-visible behavior, reversibility — whichever you can actually substantiate. Don't invent numbers or timelines; if you can't ground a dimension, omit it or say what you would need.

- ❌ _"Switch from optimistic locking to `SELECT … FOR UPDATE` row locks."_
- ✅ _"Prevent two people from booking the same slot, at the cost of some speed under heavy load (switch from optimistic locking to `SELECT … FOR UPDATE` row locks)."_

**3. If the decision hinges on understanding a technology, teach it in one or two sentences first.**
Translation isn't always enough — sometimes the reader can't weigh the options without a minimal model of the thing itself. Give it to them once, plainly, the first time the concept appears; then use the term freely.

- _"Caching means keeping a copy of recent answers so the app doesn't have to fetch them again — faster, but the copy can go stale."_

Only teach what carries the decision. A term the reader can decide without is a term you don't explain.

**4. No manufactured parentheticals.**
When the point is non-technical and has no underlying mechanism, the plain statement is the whole thing.

---

## The self-check

Before delivering, strip everything in parentheses. What remains must:

- stand on its own and name the specific consequence in context — not a vague quality like "more reliable" or "easier to maintain";
- contain no insider vocabulary — "race condition", "coupling", "idempotent", "cascade failure", or any term a non-engineer would have to look up.

If the leftover fails either test, rewrite it as the observable consequence. The stakes must stand on their own even when the mechanism needs expertise.

---

## Scope

- The convention governs reader-facing text. Code, commit messages, and sections explicitly addressed to engineers (e.g. an "Open Questions" section handed to a planning tool) keep their technical register — the invoking skill decides which sections those are.
- Plain is not vague. "Faster" is not plain language; "the page loads before the user notices" is. Specificity survives translation.
- Never drop the technical detail to seem simple — the parentheses are load-bearing for the expert reader.
