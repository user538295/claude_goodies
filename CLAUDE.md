
# Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. **These bias toward caution over speed** — for trivial tasks, use judgment.

## 1. Think Before Coding

**You mustn't make assumptions. Don't hide confusion. Surface tradeoffs.**

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

## 3. Documentation Must Stay Current

**Every code or behavior change requires a documentation update in the same session. No exceptions.**

Before closing any task:
- Identify all docs that describe the changed behavior (handouts, README, CLAUDE.md, install.sh, inline comments, HTML pages).
- Update every affected file to match the new reality.
- If you added a new command, skill, or script: add it to every place that lists or describes similar items.

This is not optional. Outdated documentation is a bug. Treat it as one.

## 4. Surgical Changes (code)

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

## 5. Goal-Driven Execution

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

# File Deletion
- **Never use `rm`** to delete files. Always move files to trash instead: `trash <file>` (macOS). If `trash` is not available, use `mv <file> ~/.Trash/`.
  - **Exception — machine-managed sentinel files**: scripts under `~/.claude/scripts/` MAY use `rm -f` for the following sentinel file because it is ephemeral state and shipping it to trash creates clutter without recovery value:
    - `<project>/.claude/implement-next-state.json` (recovery breadcrumb)
  - Note: `<project>/.claude/recovery-anomalies.log` is NEVER `rm`'d (truncation uses `tail > .tmp && mv`); it does NOT require this carve-out. Only `implement-next-state.json` is carved out for `rm -f`.
  - All other deletions follow the `trash` rule.

# Tools and agents
- Prefer multi-agent approaches when the task complexity warrants it
- Always use background sub-agents for the work and find the appropriate agent type for the task.

# Communication with the User

- Always start with the understanding of the real intention of the user and satisfy it
- Always be direct, clear, and concise
- Avoid repetition in your answers
- **Never soften findings.** State problems and severity directly. Don't qualify with "probably," "might be worth," "it could be argued" unless real uncertainty exists.

# Mandatory Verification Protocol

**You must fact check everything. NO EXCEPTIONS.** Never state any fact, file path, function name, configuration value, line number, or behavior as true without first verifying it with tools (Read, Grep, Glob, Bash). Confidence is not verification.

- Verify each file path, function name, configuration value, and behavioral claim before stating it.
- Never skip verification because the answer "seems obvious" or you "remember" it from earlier context.
- Never answer from training data alone when the answer can be verified in the codebase or documentation.
- Always cite where you found the answer: file path + section or line number.

## Verification steps — apply before every factual claim:

1. **STOP** - Do not respond with unverified claims, regardless of confidence
2. **SEARCH** - Use Read/Grep/Glob/Bash to locate the actual information
3. **VERIFY** - Confirm the fact in the source
4. **CITE** - Reference the exact file and location in your answer
5. **SAVE** - Use the available memory system to persist verified facts for future conversations

# Coding Standards

- Follow Clean Architecture layer separation strictly; all dependencies must point inward
- SOLID principles and Clean Code — no smelling code
- Use protocol-based abstractions for cross-layer communication
- Implement constructor-based dependency injection
- **ALWAYS write tests first (TDD is a MUST)** — start with happy paths, then edge cases
- Maintain 85%+ test coverage minimum; if you find a failing test, fix it before moving on
- **ALWAYS resolve all compiler warnings** — the codebase must be warning-free at all times
- **Avoid magic numbers** — use descriptive named constants instead of hardcoded values
