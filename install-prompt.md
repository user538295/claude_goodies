# Claude Skills Installer

## How to use this file

1. Clone the repository:
   ```bash
   git clone git@github.com:user538295/claude_goodies.git
   ```
2. Open Claude Code in any project (or your home directory).
3. Paste the block below ─ everything after the `---` ─ into the Claude Code prompt, replacing `<EXTRACTED_PATH>` with the full path to the cloned folder (e.g. `/Users/yourname/claude_goodies`).

---

Install a set of shared Claude Code skills, commands, agents, and scripts into my user profile from the directory `<EXTRACTED_PATH>`.

## What you are installing

| Item | Source path (relative to `<EXTRACTED_PATH>`) | Destination in `~/.claude/` |
|---|---|---|
| Agent: `devils-advocate` | `agents/devils-advocate.md` | `agents/devils-advocate.md` |
| Command: `/da-review` | `commands/da-review.md` | `commands/da-review.md` |
| Command: `/feature-refinement` | `commands/feature-refinement.md` | `commands/feature-refinement.md` |
| Command: `/implement-all` | `commands/implement-all.md` | `commands/implement-all.md` |
| Command: `/implement-next` | `commands/implement-next.md` | `commands/implement-next.md` |
| Command: `/iterative-review` | `commands/iterative-review.md` | `commands/iterative-review.md` |
| Script: `plan-progress.sh` | `scripts/plan-progress.sh` | `scripts/plan-progress.sh` |
| Script: `count-uncompleted-tasks.sh` | `scripts/count-uncompleted-tasks.sh` | `scripts/count-uncompleted-tasks.sh` |
| Script: `check-task-commit.sh` | `scripts/check-task-commit.sh` | `scripts/check-task-commit.sh` |
| Script: `verify-run-commits.sh` | `scripts/verify-run-commits.sh` | `scripts/verify-run-commits.sh` |
| Script: `audit-plan-run.sh` | `scripts/audit-plan-run.sh` | `scripts/audit-plan-run.sh` |
| Script helper: `task_section.awk` | `scripts/task_section.awk` | `scripts/task_section.awk` |
| Script helper: `progress-header-flat.template` | `scripts/progress-header-flat.template` | `scripts/progress-header-flat.template` |
| Script helper: `progress-header-phased.template` | `scripts/progress-header-phased.template` | `scripts/progress-header-phased.template` |
| Skill: `aaa` | `skills/aaa/` (entire directory) | `skills/aaa/` |
| Skill: `documentation-standard` | `skills/documentation-standard/` (entire directory) | `skills/documentation-standard/` |
| Skill: `plan-maker` | `skills/plan-maker/SKILL.md` | `skills/plan-maker/SKILL.md` |
| Global config | `CLAUDE.md` | `CLAUDE.md` (**see special handling below**) |

## Installation steps

Perform each step in order. Do not skip any step.

### Step 1 — Verify the source directory

Confirm that `<EXTRACTED_PATH>` exists and contains the expected top-level items:

```bash
ls <EXTRACTED_PATH>
```

Expected output must include: `agents`, `commands`, `scripts`, `skills`, `CLAUDE.md`, `install-prompt.md`.

Stop and report if any of these are missing.

### Step 2 — Create destination directories

Create any directories that do not yet exist. Do not delete or overwrite anything that already exists.

```bash
mkdir -p ~/.claude/agents
mkdir -p ~/.claude/commands
mkdir -p ~/.claude/scripts
mkdir -p ~/.claude/skills/aaa/references
mkdir -p ~/.claude/skills/documentation-standard/references
mkdir -p ~/.claude/skills/documentation-standard/scripts
mkdir -p ~/.claude/skills/plan-maker
mkdir -p ~/.claude/agent-memory/devils-advocate
```

### Step 3 — Copy the agent

```bash
cp <EXTRACTED_PATH>/agents/devils-advocate.md ~/.claude/agents/devils-advocate.md
```

### Step 4 — Copy the commands

```bash
cp <EXTRACTED_PATH>/commands/da-review.md           ~/.claude/commands/da-review.md
cp <EXTRACTED_PATH>/commands/feature-refinement.md  ~/.claude/commands/feature-refinement.md
cp <EXTRACTED_PATH>/commands/implement-all.md       ~/.claude/commands/implement-all.md
cp <EXTRACTED_PATH>/commands/implement-next.md      ~/.claude/commands/implement-next.md
cp <EXTRACTED_PATH>/commands/iterative-review.md    ~/.claude/commands/iterative-review.md
```

### Step 5 — Copy the scripts and make shell scripts executable

```bash
cp <EXTRACTED_PATH>/scripts/plan-progress.sh               ~/.claude/scripts/plan-progress.sh
cp <EXTRACTED_PATH>/scripts/count-uncompleted-tasks.sh     ~/.claude/scripts/count-uncompleted-tasks.sh
cp <EXTRACTED_PATH>/scripts/check-task-commit.sh           ~/.claude/scripts/check-task-commit.sh
cp <EXTRACTED_PATH>/scripts/verify-run-commits.sh          ~/.claude/scripts/verify-run-commits.sh
cp <EXTRACTED_PATH>/scripts/audit-plan-run.sh              ~/.claude/scripts/audit-plan-run.sh
cp <EXTRACTED_PATH>/scripts/task_section.awk               ~/.claude/scripts/task_section.awk
cp <EXTRACTED_PATH>/scripts/progress-header-flat.template  ~/.claude/scripts/progress-header-flat.template
cp <EXTRACTED_PATH>/scripts/progress-header-phased.template ~/.claude/scripts/progress-header-phased.template

chmod +x ~/.claude/scripts/plan-progress.sh
chmod +x ~/.claude/scripts/count-uncompleted-tasks.sh
chmod +x ~/.claude/scripts/check-task-commit.sh
chmod +x ~/.claude/scripts/verify-run-commits.sh
chmod +x ~/.claude/scripts/audit-plan-run.sh
```

### Step 6 — Copy the skills

```bash
cp <EXTRACTED_PATH>/skills/aaa/SKILL.md                                     ~/.claude/skills/aaa/SKILL.md
cp <EXTRACTED_PATH>/skills/aaa/references/aaa-rubric.md                     ~/.claude/skills/aaa/references/aaa-rubric.md
cp <EXTRACTED_PATH>/skills/aaa/references/code-review-protocol.md           ~/.claude/skills/aaa/references/code-review-protocol.md
cp <EXTRACTED_PATH>/skills/aaa/references/evaluation-prompts.md             ~/.claude/skills/aaa/references/evaluation-prompts.md
cp <EXTRACTED_PATH>/skills/aaa/references/output-templates.md               ~/.claude/skills/aaa/references/output-templates.md
cp <EXTRACTED_PATH>/skills/aaa/references/product-feature-protocol.md       ~/.claude/skills/aaa/references/product-feature-protocol.md
cp <EXTRACTED_PATH>/skills/aaa/references/research-protocol.md              ~/.claude/skills/aaa/references/research-protocol.md

cp <EXTRACTED_PATH>/skills/documentation-standard/SKILL.md                          ~/.claude/skills/documentation-standard/SKILL.md
cp <EXTRACTED_PATH>/skills/documentation-standard/references/markdown_quality.md    ~/.claude/skills/documentation-standard/references/markdown_quality.md
cp <EXTRACTED_PATH>/skills/documentation-standard/references/mermaid_examples.md    ~/.claude/skills/documentation-standard/references/mermaid_examples.md
cp <EXTRACTED_PATH>/skills/documentation-standard/references/templates.md           ~/.claude/skills/documentation-standard/references/templates.md
cp <EXTRACTED_PATH>/skills/documentation-standard/scripts/validate_docs.py          ~/.claude/skills/documentation-standard/scripts/validate_docs.py

cp <EXTRACTED_PATH>/skills/plan-maker/SKILL.md  ~/.claude/skills/plan-maker/SKILL.md
```

### Step 7 — Initialize the devils-advocate agent memory

The `devils-advocate` agent stores persistent memory in `~/.claude/agent-memory/devils-advocate/MEMORY.md`. Create it if it does not already exist:

```bash
[ -f ~/.claude/agent-memory/devils-advocate/MEMORY.md ] || touch ~/.claude/agent-memory/devils-advocate/MEMORY.md
```

Do not overwrite an existing MEMORY.md — the agent may have already written useful content there.

### Step 8 — Merge CLAUDE.md (do NOT overwrite)

`CLAUDE.md` contains global behavioral instructions that Claude Code loads on every session. You may already have one at `~/.claude/CLAUDE.md` with your own customizations. **Never overwrite it.**

Do the following:

1. Check whether `~/.claude/CLAUDE.md` already exists:
   ```bash
   ls -la ~/.claude/CLAUDE.md
   ```

2. **If it does not exist**: copy the file directly:
   ```bash
   cp <EXTRACTED_PATH>/CLAUDE.md ~/.claude/CLAUDE.md
   ```

3. **If it already exists**: read both files — `~/.claude/CLAUDE.md` and `<EXTRACTED_PATH>/CLAUDE.md` — then show the user a diff:
   ```bash
   diff ~/.claude/CLAUDE.md <EXTRACTED_PATH>/CLAUDE.md
   ```
   Ask the user which sections from the new file they want merged into their existing one, then apply only the changes they approve. Do not modify the existing file without explicit user confirmation.

### Step 9 — Verify the installation

Run these checks and report the result of each:

```bash
# Agents
ls -la ~/.claude/agents/devils-advocate.md

# Commands
ls -la ~/.claude/commands/da-review.md
ls -la ~/.claude/commands/feature-refinement.md
ls -la ~/.claude/commands/implement-all.md
ls -la ~/.claude/commands/implement-next.md
ls -la ~/.claude/commands/iterative-review.md

# Scripts (check executable bit with -l)
ls -la ~/.claude/scripts/plan-progress.sh
ls -la ~/.claude/scripts/count-uncompleted-tasks.sh
ls -la ~/.claude/scripts/check-task-commit.sh
ls -la ~/.claude/scripts/verify-run-commits.sh
ls -la ~/.claude/scripts/audit-plan-run.sh
ls -la ~/.claude/scripts/task_section.awk
ls -la ~/.claude/scripts/progress-header-flat.template
ls -la ~/.claude/scripts/progress-header-phased.template

# Skills
ls -la ~/.claude/skills/aaa/SKILL.md
ls -la ~/.claude/skills/aaa/references/
ls -la ~/.claude/skills/documentation-standard/SKILL.md
ls -la ~/.claude/skills/documentation-standard/references/
ls -la ~/.claude/skills/documentation-standard/scripts/validate_docs.py
ls -la ~/.claude/skills/plan-maker/SKILL.md

# Agent memory directory
ls -la ~/.claude/agent-memory/devils-advocate/
```

Report: `OK` for each file that is present, or `MISSING` for each file that is not found.

### Step 10 — Quick smoke test of the scripts

Run this to confirm the plan scripts execute without error (they are designed to handle missing input gracefully):

```bash
bash ~/.claude/scripts/count-uncompleted-tasks.sh /dev/null 2>&1 | head -5
```

If the command exits with a non-zero code and prints an error other than a message about a missing `## Tasks` heading, stop and report the full output.

## After installation

Restart Claude Code (or start a new session) for all items to be picked up. Then you can use:

- `/da-review` — single-pass devil's advocate review of any target
- `/iterative-review` — multi-agent review loop that also applies fixes
- `/implement-next <plan.md>` — implement the next task in a plan file
- `/implement-all <plan.md>` — implement all remaining tasks in a plan file
- `/feature-refinement <idea>` — refine a feature idea into a Feature Brief
- `/aaa` — AAA quality assessment of any idea, feature, architecture, or code
- `/plan-maker` — create or update a detailed implementation plan
- `/documentation-standard` — documentation quality enforcement
