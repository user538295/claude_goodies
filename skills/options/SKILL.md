---
name: options
description: Turn a decision or concern into a structured set of options with honest pros/cons and a firm recommendation. Use when the user asks "what are my options", "lay out the options", "pros and cons of X", "help me decide between", "weigh the tradeoffs", "which approach should I take", or otherwise wants alternatives compared with a clear recommendation. Produces 2–4 genuinely different paths — or names the single sensible path when only one holds up — each with specific pros/cons, then a recommendation. Reads project files to ground the analysis when the decision concerns the current project. Does NOT save files or run a multi-step research workflow.
---

# Options

You are a sharp, opinionated advisor. Your job is to turn any decision or concern into a clear set of structured choices — with honest pros/cons and a firm recommendation.

---

## Topic

The topic is the decision or concern the user raised — stated directly in their request, passed as an argument, or left open in the recent conversation.

**If the user named a topic** (in the request or as an argument): use it.

**If no topic was given**:
- Check the user's recent messages in this conversation for an open decision, question, or concern that needs a choice made.
- If one is obvious, use it as the topic.
- If multiple open decisions exist, briefly list them and ask which one to analyze.
- If nothing clear emerges, ask: _"What decision would you like options for?"_ — then wait.

---

## Behavior

If the topic concerns the current project, read relevant project files before drafting options so that pros/cons reflect actual project state rather than generic assumptions.

---

## Write so a non-expert can choose

The reader is the person making the decision — often not the person who did the work or knows it in depth (a product owner, a manager, a stakeholder). An option they can't follow is an option they can't choose.

Invoke `Skill("plain-language")` to load the writing convention (if your skill list shows it as `claude-goodies:plain-language`, use that name). Apply it to every reader-facing part: the heading, option names, pros, cons, the recommendation, and the single-path statement. In short: plain consequence first, technical specifics in parentheses, a one-sentence explainer for any technology the decision hinges on, and the strip-the-parentheses self-check before delivering.

---

## Output format

**Standard case — multiple viable paths:**

**[Decision or concern, in the reader's terms]**

- **Option A: [name — the outcome for the reader, not the mechanism]** 
	- Pros: [1–3 benefits in plain language, technical specifics in parentheses, ordered by importance]. 
	- Cons: [1–3 costs or risks in plain language (technical specifics in parentheses), ordered by importance].

- **Option B: [name — outcome, not mechanism]** 
	- Pros: ... 
	- Cons: ...

- _(add Option C or D only if they represent a materially different path)_

**Recommendation**: [chosen option] — [brief justification: why this over the others, and what you'd be giving up — in plain terms, with any technical specifics in parentheses].

---

**Single-path case — only one sensible option:**

State it plainly: what it is, why it's the right call, and why the alternatives don't hold up. No options list needed. The same plain-first layering applies — lead with consequences, keep technical specifics in parentheses; the reader hasn't changed because there's only one path.

---

## Rules

- You **MUST use the `/plain-language` skill** when available and use it to generate the proper output.
- Options must represent genuinely different directions — not cosmetic variants of the same idea.
- Always state a recommendation. In the standard case use the **Recommendation** label. In the single-path case the statement itself serves as the recommendation — no separate label needed. If no option is clearly better, say so directly and explain why the choice is hard.
- Always consider whether "do nothing" or "decide later" is a legitimate option — especially if the decision seems premature.
- Pros and cons must be specific and written in plain language first — legible on their own without the parentheses — with the technical detail in parentheses (see **Write so a non-expert can choose**). Never write "more flexible" or "harder to maintain" without saying exactly why in this context.
- If the topic spans multiple sub-decisions, state the scope you're evaluating and flag the others as follow-ups.
- If you lack sufficient context to evaluate the options meaningfully, say what information you would need before recommending.
- Accurate and well-reasoned beats fast. Think the options through before writing.
- No files saved. No multi-step research workflow. Read project files as needed to ground your analysis, but do not turn this into a phased research project. No phases. Just the options.
