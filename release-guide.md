# Release Guide

One installation path exists. A release must satisfy it.

| Path | Entry point | Version source |
|------|-------------|----------------|
| Plugin marketplace | `.claude-plugin/plugin.json` | `"version"` field in that file |

---

## How the install path works

### Plugin marketplace
```bash
claude plugin marketplace add user538295/claude_goodies
claude plugin install claude-goodies
# update later:
claude plugin update claude-goodies@user538295
```
Claude Code reads `.claude-plugin/plugin.json` to resolve the plugin. The `"version"` field in that file is what `claude plugin` reports and uses to decide whether an update is available.

`.claude-plugin/marketplace.json` defines the marketplace listing — it does not contain a version and does not need to change on every release.

---

## Pre-release checklist

### 1. New files or directories?
Update `sync-manifest.txt` before anything else. It is the curated list of paths that live in both `~/.claude` and this repo — `release.sh` prompts you to confirm it is current.

- New skill directory → `skills/my-skill/` (trailing slash = recursive copy)
- New command file → `commands/my-command.md`
- New script → `scripts/my-script.sh`
- New single-file agent → `agents/my-agent.md`

Files not in the manifest are not tracked as curated runtime paths.

### 2. Bump the version in `plugin.json`
Open `.claude-plugin/plugin.json` and update the `"version"` field:

```json
{
  "name": "claude-goodies",
  "version": "X.Y.Z",
  ...
}
```

Follow semver (`MAJOR.MINOR.PATCH`):
- PATCH — bug fixes, doc updates, small additions
- MINOR — new skill, command, or agent
- MAJOR — breaking change to the workflow or install contract

### 3. Commit
```bash
git add sync-manifest.txt .claude-plugin/plugin.json
git commit -m "chore(release): bump version to X.Y.Z"
```

---

## Tag naming convention

Tags must follow `vMAJOR.MINOR.PATCH` — no prefixes, no suffixes.

```
v1.0.2   ✓
v1.0.3   ✓
v1.0.4   ✓
claude-goodies--v1.0.4   ✗  (wrong — do not repeat)
```

---

## Cutting the release

```bash
# Confirm you are on main and it is clean
git checkout main
git status          # must be clean

# Create an annotated tag
git tag -a vX.Y.Z -m "Release vX.Y.Z"

# Push
git push origin main
git push origin vX.Y.Z
```

---

## Post-release verification

### Plugin marketplace
```bash
claude plugin update claude-goodies@user538295
```
Should report the new version number from `.claude-plugin/plugin.json`.

---

## Summary: what changes every release

| File | What to do |
|------|------------|
| `sync-manifest.txt` | Add any new paths |
| `.claude-plugin/plugin.json` | Bump `"version"` |
| git tag | Create `vX.Y.Z` on the release commit |
| `.claude-plugin/marketplace.json` | No change needed (listing metadata only) |
