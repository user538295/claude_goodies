---
name: skill-packager
description: Package a Claude Code skill folder as a ZIP file ready to upload to Claude Desktop or claude.ai via Settings → Customize → Skills → Create skill → Upload. Use when the user asks to "package this skill", "zip this skill for Desktop", "make the Desktop version", "bundle the skill for upload", "produce the Desktop ZIP", or as the auto-follow-up after creating any new Claude Code skill so the Desktop version is built alongside the Code one. Output defaults to ~/.claude/dist/<name>.zip.
---

# Skill Packager

Produces an upload-ready ZIP for a Claude Code skill. The Agent Skills format is identical across Claude Code, Claude Desktop, claude.ai, and the API — the only difference is delivery (folder on disk vs. uploaded ZIP), so packaging is the bridge.

## Inputs

- **Skill folder path** — absolute or `~`-anchored, e.g. `~/.claude/skills/my-skill/`.
- **Optional: output path** — if the user names one, honor it; otherwise default to `~/.claude/dist/<name>.zip`.

If no folder is named, ask which skill to package. Do not guess.

## Procedure

1. **Verify the folder exists** and contains `SKILL.md`. If not, stop with a clear message.

2. **Read the `name:` field** from the SKILL.md YAML frontmatter:
   ```bash
   awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "<folder>/SKILL.md"
   ```

3. **Validate the folder name matches `name:`.** Per Anthropic's docs, "Skill folder name doesn't match the skill name" is a documented upload failure. If `basename "<folder>"` differs from `name:`, **refuse** and tell the user to either rename the folder or change the `name:` field — do not zip with a mismatched top-level entry.

4. **Create the output directory** if absent: `mkdir -p ~/.claude/dist/` (or the parent of the user-specified output path).

5. **Build the ZIP** from the parent of the skill folder, so the top-level entry inside the ZIP is `<name>/`:
   ```bash
   cd "<parent-of-folder>" && zip -r "<output-path>" "<name>" \
     -x '*/__pycache__/*' '*/.pytest_cache/*' '*.pyc' \
        '*/.DS_Store' '*/Thumbs.db' \
        '*/.git/*' \
        '*/.env' '*/.env.local' '*/.env.*.local' \
        '*.swp' '*.swo' '*~' \
        '*/node_modules/*'
   ```
   If the output ZIP already exists, delete it first to avoid stale entries lingering — `zip -r` updates in place rather than rewriting.

6. **Report** to the user:
   - Absolute path of the ZIP
   - Size (human-readable, e.g. via `ls -lh`)
   - File count and a one-line `unzip -l` summary
   - The three-step install instructions below

## Install steps to tell the user

1. Open **Settings → Customize → Skills** in Claude Desktop or claude.ai.
2. Click **+ Create skill → Upload a skill**.
3. Select the produced ZIP.

Note: code execution must be enabled in Claude settings, or the Skills section is hidden.

## Hard rules

- **Top-level folder inside the ZIP must equal `name:`** from the frontmatter. Mismatches are rejected by the uploader.
- **Always exclude:**
  - **OS noise:** `.DS_Store` (macOS), `Thumbs.db` (Windows)
  - **Build artefacts / caches:** `__pycache__/`, `.pytest_cache/`, `*.pyc`, `node_modules/`
  - **VCS internals:** `.git/` (the working tree, not `.gitignore`)
  - **Secrets:** `.env`, `.env.local`, `.env.*.local` (catches dotenv "local-only" variants; `.env.example`, `.env.sample`, `.env.template` ship through intentionally)
  - **Editor backups:** `*.swp`, `*.swo` (vim), `*~` (emacs / general)

  These bloat the ZIP, leak secrets, or trip the uploader. If a skill intentionally ships one of these (rare — e.g. a deliberate `.env.example` ships, but `.env` never should), the default behaviour is still correct; if you need to ship something that matches an exclusion, fork the command and drop the specific pattern.
- **Never modify the source skill folder.** Only read from it.
- **Never use `rm` on the source.** If overwriting a stale dist ZIP, only the dist file is removed, never anything under `~/.claude/skills/`.
- **Default output is `~/.claude/dist/<name>.zip`.** Putting the ZIP inside `~/.claude/skills/` risks confusing Claude Code's skill discovery — keep it outside.

## Common failure modes (from Anthropic docs)

- **Folder name doesn't match skill name** → refuse at step 3.
- **ZIP exceeds size limit** → if upload fails, check what is inside; large `reference/` content or accidentally-included binaries (e.g. PDFs in templates) are the usual culprits.
- **Invalid characters in skill name or description** → name should be lowercase kebab-case; description should be plain text without unusual unicode.
