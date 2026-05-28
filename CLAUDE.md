
# Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. **These bias toward caution over speed** — for trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

# Tools and agents
- Prefer multi-agent approaches when the task complexity warrants it
- Always use background sub-agents for the work and find the appropriate agent type for the task.

# Plan execution and commit granularity

When executing any plan (task list, backlog item, feature spec) via a slash command:
- Each task gets its own commit with non-empty file changes. Never bundle multiple tasks into one commit.
- When a command delegates to a sub-command in a loop (e.g. `/implement-all` → `/implement-next`), ALWAYS invoke the sub-command via the `Skill` tool, one task at a time. NEVER spawn a single agent for all tasks.
- Count uncompleted tasks with the script — do not count manually: `bash ~/.claude/scripts/count-uncompleted-tasks.sh <plan_file>`
- After each sub-command completes, verify commit: `bash ~/.claude/scripts/check-task-commit.sh <sha_before>`
- After the full run, verify total count: `bash ~/.claude/scripts/verify-run-commits.sh <sha_start> <N>`
- These rules apply to ALL plan-based workflows and ALL delegation commands.
- After any run, independent verification (no Claude cooperation needed): `bash ~/.claude/scripts/audit-plan-run.sh <plan_file> <sha_start>`

# Communication with the User

- Always start with the understanding of the real intention of the user and satisfy it
- Always be direct, clear, and concise
- Avoid repetition in your answers

# Mandatory Verification Protocol

**CRITICAL**: You must NEVER make assumptions. All statements must be based on verified facts.

If there is documentation, check it before you answer — refer to the documentation (in which file, which title did you find the answer).

## If You Don't Know Something:

1. **STOP** - Do not proceed with guesses or assumptions
2. **STATE** - Say explicitly: "I don't know this. Let me verify..."
3. **SEARCH** - Use Grep/Glob/Read tools to find the information in the codebase
4. **VERIFY** - Check actual code, data files, or documentation
5. **SAVE** - Use Serena's memory system to save verified facts for future reference

# Code Style

- **ALWAYS write tests first (TDD is a MUST)** — start with happy paths, then edge cases
- Maintain 85%+ test coverage minimum
- If you find a failing test, don't move on, fix it first.
- **ALWAYS resolve all warnings** — the codebase must be warning-free at all times
- Avoid backward compatibility
- No smelling code
