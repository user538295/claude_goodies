# Claude Goodies — Installer

> **This file is deprecated.** The Claude-prompt-paste install path has been replaced by a shell one-liner that works reliably on all surfaces without depending on model behavior.

## Install or update

Run this in any terminal — works for fresh installs and updates. Also works in Claude Code CLI with the `! ` prefix:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/user538295/claude_goodies/main/install.sh)
```

**Prerequisites**: bash, git, curl.

**Windows**: use WSL. Git Bash is not supported.

**Flags**:
- `--overwrite` — overwrite all files including `CLAUDE.md`; shows a diff and asks for confirmation in interactive terminals; overwrites without prompting in non-interactive contexts
- `--keep-claude-md` — overwrite all files except `CLAUDE.md`, no prompt

After installation, restart Claude Code (or start a new session) for changes to load.
