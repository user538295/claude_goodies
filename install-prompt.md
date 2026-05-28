# Claude Goodies — Installer

Copy everything below the `---` and paste it into Claude Code. That's it — Claude will handle the rest.

---

Fetch and run the Claude Goodies installer:

1. Clone the repository into a temp directory:
   ```bash
   git clone git@github.com:user538295/claude_goodies.git /tmp/claude_goodies_install
   ```
   If the clone fails, stop and report the error.

2. Create destination directories:
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

3. Copy all files:
   ```bash
   cp -r /tmp/claude_goodies_install/agents/.    ~/.claude/agents/
   cp -r /tmp/claude_goodies_install/commands/.  ~/.claude/commands/
   cp -r /tmp/claude_goodies_install/scripts/.   ~/.claude/scripts/
   cp -r /tmp/claude_goodies_install/skills/.    ~/.claude/skills/
   ```

4. Make shell scripts executable:
   ```bash
   chmod +x ~/.claude/scripts/*.sh
   ```

5. Initialize the devils-advocate agent memory file if it does not already exist:
   ```bash
   [ -f ~/.claude/agent-memory/devils-advocate/MEMORY.md ] || touch ~/.claude/agent-memory/devils-advocate/MEMORY.md
   ```

6. Merge `CLAUDE.md` — **never overwrite**:
   - If `~/.claude/CLAUDE.md` does not exist: copy it directly.
     ```bash
     cp /tmp/claude_goodies_install/CLAUDE.md ~/.claude/CLAUDE.md
     ```
   - If it already exists: show a diff and ask the user which sections to merge before making any changes.
     ```bash
     diff ~/.claude/CLAUDE.md /tmp/claude_goodies_install/CLAUDE.md
     ```

7. Verify — list installed files and report any that are missing:
   ```bash
   find ~/.claude/agents ~/.claude/commands ~/.claude/scripts ~/.claude/skills -type f | sort
   ```

8. Smoke test:
   ```bash
   bash ~/.claude/scripts/count-uncompleted-tasks.sh /dev/null 2>&1 | head -5
   ```
   If this exits with a non-zero code and the output is not about a missing `## Tasks` heading, stop and report the full output.

9. Clean up:
   ```bash
   rm -rf /tmp/claude_goodies_install
   ```

After installation, restart Claude Code (or start a new session). You will then have:

- `/da-review` — single-pass devil's advocate review
- `/iterative-review` — multi-agent review loop with auto-fixes
- `/implement-next <plan.md>` — implement the next task in a plan file
- `/implement-all <plan.md>` — implement all remaining tasks in a plan file
- `/feature-refinement <idea>` — refine a feature idea into a Feature Brief
- `/aaa` — AAA quality assessment of any idea, feature, architecture, or code
- `/plan-maker` — create or update a detailed implementation plan
- `/documentation-standard` — documentation quality enforcement
