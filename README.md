# Claude Goodies

A curated set of Claude Code slash commands, skills, agents, and supporting scripts that implement a structured, high-quality software development workflow — from feature ideation through implementation, review, and verification.

---

## What's included

| Type | Name | Invocation | Purpose |
|---|---|---|---|
| Agent | `devils-advocate` | automatic | Adversarial reviewer that stress-tests outputs, catches blind spots, and flags hallucinations |
| Command | `feature-refinement` | `/feature-refinement <idea>` | Guides a rough feature idea into a well-scoped Feature Brief ready for planning |
| Command | `plan-maker` | `/plan-maker <brief>` | Turns a Feature Brief or requirement into a detailed, TDD-ready implementation plan |
| Command | `implement-next` | `/implement-next <plan.md>` | Implements the next uncompleted task in a plan file, with DA review and a commit |
| Command | `implement-all` | `/implement-all <plan.md>` | Runs `/implement-next` in a loop until every task in the plan is complete |
| Command | `iterative-review` | `/iterative-review <target>` | Multi-agent review loop: spawns 3+ DA agents in parallel, applies fixes, repeats until clean |
| Command | `da-review` | `/da-review <target>` | Single-pass devil's advocate review — finds flaws without auto-fixing |
| Skill | `aaa` | `/aaa` | AAA quality assessment of any idea, feature, architecture, or code against world-class benchmarks |
| Skill | `documentation-standard` | `/documentation-standard` | Documentation quality enforcement with Markdown standards and Mermaid diagram support |
| Skill | `plan-maker` | `/plan-maker` | (see Command above — also available as a skill) |
| Config | `CLAUDE.md` | loaded automatically | Global behavioral guidelines: think before coding, simplicity first, surgical changes, TDD, verification protocol |

---

## How the workflow fits together

```
/feature-refinement "my idea"
        │
        ▼  produces Feature Brief (Documentation/Backlog/*.md)
/plan-maker <brief.md>
        │
        ▼  produces plan file (e.g. FEAT-001-my-feature.md)
/implement-all <plan.md>
        │
        ├─ for each task:
        │   /implement-next <plan.md>
        │       ├─ implements task (TDD: tests first, then code)
        │       ├─ /iterative-review  ◄─ spawns 3 devils-advocate agents
        │       │       └─ fix agents apply changes until no critical/major issues remain
        │       ├─ full test suite run
        │       ├─ checks off task in plan
        │       └─ commits (one commit per task, enforced)
        │
        └─ final audit: verifies commit count and full test suite
```

At any point you can run `/da-review <target>` or `/aaa` for a standalone quality check.

---

## Installation

### Quick install

1. Open `install-prompt.md` from this repository.
2. Copy everything below the `---` line.
3. Paste it into Claude Code — Claude will clone the repo, install everything, and clean up after itself.

### What gets installed and where

All files are installed into your Claude Code user profile at `~/.claude/`:

```
~/.claude/
├── CLAUDE.md                            ← global behavioral config (merged, not overwritten)
├── agents/
│   └── devils-advocate.md               ← adversarial review agent
├── commands/
│   ├── da-review.md                     ← /da-review
│   ├── feature-refinement.md            ← /feature-refinement
│   ├── implement-all.md                 ← /implement-all
│   ├── implement-next.md                ← /implement-next
│   └── iterative-review.md              ← /iterative-review
├── scripts/
│   ├── plan-progress.sh                 ← reads plan progress (used by /implement-next)
│   ├── count-uncompleted-tasks.sh       ← counts open tasks (used by /implement-all)
│   ├── check-task-commit.sh             ← verifies a commit was made (used by /implement-all)
│   ├── verify-run-commits.sh            ← audits total commit count after a run
│   ├── audit-plan-run.sh                ← independent post-run audit
│   ├── task_section.awk                 ← shared awk logic used by the scripts above
│   ├── progress-header-flat.template    ← progress display for flat plans
│   └── progress-header-phased.template  ← progress display for phased plans
└── skills/
    ├── aaa/
    │   ├── SKILL.md
    │   └── references/                  ← rubric, protocols, output templates
    ├── documentation-standard/
    │   ├── SKILL.md
    │   ├── references/                  ← markdown quality rules, Mermaid examples, templates
    │   └── scripts/
    │       └── validate_docs.py
    └── plan-maker/
        └── SKILL.md
```

**After installation, restart Claude Code** (or start a new session) for all items to be active.

---

## Commands in detail

### `/feature-refinement <idea>`

Guides you from a rough idea to a well-scoped Feature Brief in three phases:

1. **Investigate** — spawns an Explore agent to read the codebase and find related code, patterns, and risks before asking any questions
2. **Clarify, Challenge + Ideate** — challenges your idea with honest concerns, asks focused questions, and fills gaps with concrete options and recommendations
3. **Feature Brief** — saves a structured brief to `Documentation/Backlog/<name>-brief.md` (or project root if that path doesn't exist)

Output: a Feature Brief with Problem, Goal, Core Flow, In/Out of Scope, Key Decisions, Edge Cases, and a frank Recommendation.

---

### `/plan-maker <input>`

Turns a Feature Brief or requirement into a detailed, TDD-ready implementation plan.

- Resolves architecture decisions through a challenge/question loop before writing anything
- Produces a phased plan where every task has: exact file paths, method signatures, dependency chains, and a full set of named tests (unit, integration, e2e, live e2e)
- Every task includes a `Checkpoint` command to run only that task's tests in isolation
- Plan ends with a mandatory "Final verification & documentation update" task

Output: a plan file (e.g. `FEAT-001-my-feature.md`) saved to wherever the project keeps its plans.

---

### `/implement-next <plan.md>`

Implements exactly one task from the plan:

1. Shows current progress via `plan-progress.sh`
2. Spawns the most appropriate agent to implement the task using strict TDD (tests first, then code)
3. Runs `/iterative-review` — multiple DA agents review in parallel, fix agents apply changes, repeats until no critical/major/moderate issues remain
4. Runs the full test suite — must be fully green before continuing
5. Checks off the task in the plan file
6. Commits all changes (implementation + updated plan) in a single commit

One task = one commit. This is enforced and cannot be bypassed.

---

### `/implement-all <plan.md>`

Runs `/implement-next` in a loop for every uncompleted task:

- Creates a `[IMPLEMENT]` + `[VERIFY]` task pair for each plan task before starting
- After each implementation, a verification agent confirms: new commit exists, task is checked off, tests pass
- After all tasks: runs `verify-run-commits.sh` to confirm commit count, then runs the full test suite
- If tests fail after the run, spawns fix agents and retries up to three times

---

### `/iterative-review <target>`

Quality gate that runs until the code is clean:

- Spawns minimum 3 `devils-advocate` agents in parallel, each from a different angle (correctness/edge cases, architecture/design, test coverage)
- Consolidates and deduplicates findings by root cause
- Spawns fix agents for all Critical, Major, and Moderate issues
- Re-runs tests after each fix pass
- Detects unresolvable oscillations (same issue keeps reappearing) and stops rather than looping forever
- Produces a Review Summary with all changes made, remaining minor issues, and a verdict

Severity rubric:
- **Critical** — blocks correctness, security, or safety
- **Major** — significant design flaw, missing requirement, or likely bug
- **Moderate** — suboptimal but workable
- **Minor** — style, naming, nitpick

---

### `/da-review <target>`

Single-pass review using the `devils-advocate` agent. Finds flaws without applying fixes. Use this for a quick, standalone review. Use `/iterative-review` when you also want fixes applied automatically.

---

### `/aaa`

Evaluates any idea, feature, architecture, or code against world-class standards:

1. Gives an honest initial classification (Weak → Already near AAA/world-class)
2. Loads the appropriate reference protocol (product, code, architecture, etc.)
3. Researches current best practices and benchmarks against real-world leaders
4. Analyzes across relevant dimensions (correctness, differentiation, feasibility, security, etc.)
5. Produces 3–4 materially different upgrade paths with pros, cons, risks, and best-fit scenarios
6. Ends with a clear recommendation

---

### `/documentation-standard`

Enforces documentation quality across a project:

- Validates Markdown structure, terminology consistency, and cross-reference validity
- Checks for contradictions, duplicate content, and voice/tone consistency
- Supports master-follower validation (follower docs checked against an authoritative master)
- Can handle 50+ file documentation sets with resumable progress tracking
- Includes `validate_docs.py` for automated checks

---

## The `devils-advocate` agent

This agent is automatically invoked by `/iterative-review` and `/implement-next`. You can also use it directly via the `Agent` tool.

It operates as a relentless critical analyst:

- **Assumption hunting** — lists every assumption, challenges each one
- **Hallucination detection** — flags unverifiable facts, statistics, and citations
- **Blind spot identification** — what stakeholders, failure modes, and edge cases are absent?
- **Logical fallacy detection** — false dichotomies, survivorship bias, circular reasoning, etc.
- **Contrarian alternative generation** — steelmans the opposing position for every major claim

Output is structured by severity: Critical Issues → Major Concerns → Assumptions Under Challenge → Blind Spots → Hallucination Risk Flags → Strongest Counterargument → What Holds Up → Recommended Actions.

The agent maintains persistent memory at `~/.claude/agent-memory/devils-advocate/` and records recurring failure patterns across sessions.

---

## The supporting scripts

The commands depend on five shell scripts in `~/.claude/scripts/`. These are called internally — you don't invoke them directly in normal use.

| Script | Called by | Purpose |
|---|---|---|
| `plan-progress.sh` | `/implement-next` | Renders the current plan progress and identifies the next task |
| `count-uncompleted-tasks.sh` | `/implement-all` | Counts uncompleted tasks; requires a `## Tasks` or `## Task breakdown` heading |
| `check-task-commit.sh` | `/implement-all` | Verifies a new commit exists since a given SHA |
| `verify-run-commits.sh` | `/implement-all` | Checks that exactly N commits were made during a run |
| `audit-plan-run.sh` | manual / post-run | Independent audit of a full plan run; can be run without Claude |

`task_section.awk` and the two `.template` files are helpers used internally by the scripts above.

---

## CLAUDE.md

`CLAUDE.md` is loaded automatically by Claude Code at the start of every session. It encodes four behavioral principles:

1. **Think Before Coding** — state assumptions, surface tradeoffs, push back when warranted
2. **Simplicity First** — minimum code that solves the problem; nothing speculative
3. **Surgical Changes** — touch only what the task requires; clean up only your own mess
4. **Goal-Driven Execution** — define success criteria upfront and loop until verified

It also enforces:
- TDD as mandatory (tests before code, 85%+ coverage)
- Warning-free codebase at all times
- One commit per plan task
- Never batching multiple tasks into one agent run

The install process diffs your existing `~/.claude/CLAUDE.md` against this one and asks before merging — it will never overwrite your existing configuration without approval.

---

## Requirements

- [Claude Code](https://claude.ai/code) (CLI, desktop app, or IDE extension)
- macOS or Linux (the shell scripts use bash and awk)
- Git (used by the commit-verification scripts)

No MCP servers are required. The commands work with Claude Code's built-in agent and tool capabilities.
