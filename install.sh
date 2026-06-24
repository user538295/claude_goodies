#!/usr/bin/env bash
# install.sh — Claude Goodies installer
# Bash 3.2-compatible. Source-safe: only function definitions execute at top level.

# ---------------------------------------------------------------------------
# Configuration (overridable via environment variables for testing)
# ---------------------------------------------------------------------------
DEST_DIR="${INSTALL_DEST:-${HOME}/.claude}"
REPO_URL="${INSTALL_REPO_URL:-https://github.com/user538295/claude_goodies.git}"
DRY_RUN=0
WRITE_COUNT=0
CLAUDE_BASE_FILE="${INSTALL_CLAUDE_BASE:-}"  # overridable for tests; defaults to $DEST_DIR/.claude-base.md in main()

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: install.sh [OPTIONS]

Options:
  --overwrite        Overwrite existing installation (discards your local CLAUDE.md changes)
  --keep-claude-md   Keep existing CLAUDE.md (do not overwrite)
  --dry-run          Preview actions without writing any files
  --help             Show this help message and exit

Options --overwrite and --keep-claude-md are mutually exclusive.
EOF
}

# ---------------------------------------------------------------------------
# parse_flags [args...]
# Sets global variables OVERWRITE, KEEP_CLAUDE_MD, DRY_RUN, and WRITE_COUNT.
# Exits 1 on unknown flags or conflicting flags; exits 0 on --help.
# ---------------------------------------------------------------------------
parse_flags() {
  OVERWRITE=0
  KEEP_CLAUDE_MD=0
  DRY_RUN=0
  WRITE_COUNT=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --overwrite)
        OVERWRITE=1
        ;;
      --keep-claude-md)
        KEEP_CLAUDE_MD=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        echo "Error: Unknown flag: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  if [[ "$OVERWRITE" -eq 1 && "$KEEP_CLAUDE_MD" -eq 1 ]]; then
    echo "Error: --overwrite and --keep-claude-md are mutually exclusive." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# check_prereqs
# Verifies git and curl are installed, and bash >= 3.2.
# ---------------------------------------------------------------------------
check_prereqs() {
  local missing=0

  if ! command -v git > /dev/null 2>&1; then
    echo "Error: git is required but not installed." >&2
    missing=1
  fi

  if ! command -v curl > /dev/null 2>&1; then
    echo "Error: curl is required but not installed." >&2
    missing=1
  fi

  if ! command -v jq > /dev/null 2>&1; then
    echo "Warning: jq is not installed; SubagentStop hook registration will be skipped (manual instructions will be printed)." >&2
  fi

  if [[ "$missing" -eq 1 ]]; then
    exit 1
  fi

  local major="${BASH_VERSINFO[0]}"
  local minor="${BASH_VERSINFO[1]}"
  if [[ "$major" -lt 3 ]] || [[ "$major" -eq 3 && "$minor" -lt 2 ]]; then
    echo "Error: bash >= 3.2 is required (found ${major}.${minor})." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# cleanup — remove temp dirs; called by EXIT trap.
# Only removes CLONE_TEMP_DIR (the mktemp'd clone dir) and STAGE_DIR.
# Never touches INSTALL_FIXTURE_DIR — that is user-owned, not ours.
# ---------------------------------------------------------------------------
cleanup() {
  rm -rf "${CLONE_TEMP_DIR:-}" "${STAGE_DIR:-}"
}

# ---------------------------------------------------------------------------
# do_clone
# Clones REPO_URL into CLONE_TEMP_DIR and sets CLONE_DIR to it, or sets
# CLONE_DIR to INSTALL_FIXTURE_DIR when INSTALL_SKIP_CLONE=1 (no temp dir).
# ---------------------------------------------------------------------------
do_clone() {
  if [[ "${INSTALL_SKIP_CLONE:-}" == "1" ]]; then
    if [[ -z "${INSTALL_FIXTURE_DIR:-}" ]]; then
      echo "Error: INSTALL_SKIP_CLONE=1 requires INSTALL_FIXTURE_DIR to be set" >&2
      exit 1
    fi
    CLONE_DIR="$INSTALL_FIXTURE_DIR"
  else
    if ! git clone --depth 1 "$REPO_URL" "$CLONE_TEMP_DIR"; then
      echo "Error: failed to clone repository" >&2
      exit 1
    fi
    CLONE_DIR="$CLONE_TEMP_DIR"
  fi
}

# ---------------------------------------------------------------------------
# read_manifest_entries MANIFEST
# Prints curated paths (one per line) from the shared sync-manifest.txt,
# skipping comments, blank lines, and CLAUDE.md (handled by handle_claude_md).
# This is the SAME manifest claude-sync.sh consumes — one source of truth.
# ---------------------------------------------------------------------------
read_manifest_entries() {
  local manifest="$1" line
  if [ ! -f "$manifest" ]; then
    echo "Error: manifest not found: $manifest" >&2
    exit 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%$'\r'}"
    case "$line" in
      ''|\#*)    continue ;;
      CLAUDE.md) continue ;;
      /*|*..*)   echo "Warning: skipping unsafe manifest path: $line" >&2; continue ;;
      *)         printf '%s\n' "$line" ;;
    esac
  done < "$manifest"
}

# ---------------------------------------------------------------------------
# _copy_into SRC_ROOT DST_ROOT ENTRY
# Copies one manifest entry. A trailing slash means a directory copied
# recursively; otherwise a single file. Parent directories are created.
# ---------------------------------------------------------------------------
_copy_into() {
  local src_root="$1" dst_root="$2" entry="$3"
  if [ "${entry%/}" != "$entry" ]; then
    local rel="${entry%/}"
    # Source is always a fresh `git clone` (do_clone), so it carries only tracked
    # files — no untracked junk to filter. The repo stays junk-free because
    # claude-sync.sh excludes junk on capture. Hence a plain recursive cp is safe.
    if [ ! -d "$src_root/$rel" ]; then
      echo "Error: manifest directory missing in repo: $rel" >&2
      exit 1
    fi
    mkdir -p "$dst_root/$rel"
    cp -R "$src_root/$rel/." "$dst_root/$rel/"
  else
    mkdir -p "$dst_root/$(dirname "$entry")"
    cp "$src_root/$entry" "$dst_root/$entry"
  fi
}

# ---------------------------------------------------------------------------
# manifest_lists PATH MANIFEST — returns 0 if PATH is an active (uncommented)
# entry in MANIFEST. Used to special-case CLAUDE.md (merged, not plain-copied)
# only when this repo actually ships it (the private repo does not).
# ---------------------------------------------------------------------------
manifest_lists() {
  local target="$1" manifest="$2" line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    [ "$line" = "$target" ] && return 0
  done < "$manifest"
  return 1
}

# ---------------------------------------------------------------------------
# stage_files
# Copies the curated manifest from CLONE_DIR into STAGE_DIR. CLAUDE.md is staged
# only when the manifest ships it (it is merged later by handle_claude_md).
# install.sh is intentionally NOT staged — it is repo-only and must never land
# in ~/.claude (keeps the runtime dir clean).
# ---------------------------------------------------------------------------
stage_files() {
  local manifest="$CLONE_DIR/sync-manifest.txt"
  if manifest_lists "CLAUDE.md" "$manifest"; then
    cp "$CLONE_DIR/CLAUDE.md" "$STAGE_DIR/CLAUDE.md"
  fi

  local entry
  while IFS= read -r entry; do
    _copy_into "$CLONE_DIR" "$STAGE_DIR" "$entry"
  done < <(read_manifest_entries "$manifest")
}

# ---------------------------------------------------------------------------
# set_permissions
# Makes .sh files executable; leaves .awk, .template, etc. unchanged.
# ---------------------------------------------------------------------------
set_permissions() {
  find "$STAGE_DIR" -name "*.sh" -exec chmod +x {} \;
  find "$STAGE_DIR" -name "*.py" -exec chmod +x {} \;
}

# ---------------------------------------------------------------------------
# register_subagent_stop_hook
# Idempotently merges the SubagentStop hook entry into ~/.claude/settings.json
# so /implement-all-cc has its enforcement gate from a fresh install.
# No-ops cleanly when settings.json is missing, jq is missing, or the hook
# is already registered.
# ---------------------------------------------------------------------------
register_subagent_stop_hook() {
    local settings="${DEST_DIR}/settings.json"
    if [ ! -f "$settings" ]; then
        if ! command -v jq >/dev/null 2>&1; then
            echo "  Note: ${settings} not found and jq not installed; cannot bootstrap settings.json automatically."
            echo "  Create ${settings} with this content:"
            printf '    {"hooks":{"SubagentStop":[{"matcher":"*","hooks":[{"type":"command","command":"$HOME/.claude/scripts/implement-next-stop-gate.sh"}]}]}}\n'
            return 0
        fi
        # Bootstrap minimal settings.json with just the hook
        mkdir -p "$(dirname "$settings")"
        jq -n '{
            hooks: {
                SubagentStop: [{
                    matcher: "*",
                    hooks: [{
                        type: "command",
                        command: "$HOME/.claude/scripts/implement-next-stop-gate.sh"
                    }]
                }]
            }
        }' > "$settings"
        echo "  Bootstrapped ${settings} with SubagentStop hook."
        return 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "  Note: jq not installed; cannot register SubagentStop hook automatically."
        echo "  Manually add this to ${settings} under hooks.SubagentStop:"
        printf '    [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/scripts/implement-next-stop-gate.sh"}]}]\n'
        return 0
    fi

    # Idempotency: check if already registered
    if jq -e '.hooks.SubagentStop[]? | .hooks[]? | select(.command | test("implement-next-stop-gate.sh"))' "$settings" >/dev/null 2>&1; then
        echo "  SubagentStop hook already registered in ${settings}."
        return 0
    fi

    # Merge the hook entry, preserving everything else
    local tmp
    tmp=$(mktemp)
    if jq '
        .hooks //= {} |
        .hooks.SubagentStop //= [] |
        .hooks.SubagentStop += [{
            "matcher": "*",
            "hooks": [{
                "type": "command",
                "command": "$HOME/.claude/scripts/implement-next-stop-gate.sh"
            }]
        }]
    ' "$settings" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$settings"
        echo "  Registered SubagentStop hook in ${settings}."
    else
        rm -f "$tmp"
        echo "  ERROR: ${settings} appears malformed; cannot register hook automatically." >&2
        echo "  Fix the JSON syntax and re-run install.sh, or add the hook manually:" >&2
        printf '    {"matcher":"*","hooks":[{"type":"command","command":"$HOME/.claude/scripts/implement-next-stop-gate.sh"}]}\n' >&2
    fi
}

# ---------------------------------------------------------------------------
# save_claude_base DST
# Saves a copy of the installed CLAUDE.md as the merge base for future runs.
# ---------------------------------------------------------------------------
save_claude_base() {
  local dst="$1"
  cp "$dst" "$CLAUDE_BASE_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# handle_claude_md
# Conditionally copies staged CLAUDE.md to DEST_DIR based on flags and
# existing state. Implements the CLAUDE.md decision table.
#
# Default (no flags, base exists): 3-way merge via git merge-file.
#   Clean merge  → apply automatically, update base.
#   Conflicts    → open $EDITOR for resolution, update base after save.
#   No base      → skip with hint.
# ---------------------------------------------------------------------------
handle_claude_md() {
  local staged="$STAGE_DIR/CLAUDE.md"
  local dest="$DEST_DIR/CLAUDE.md"

  # Fresh install — no existing CLAUDE.md: always copy
  if [ ! -f "$dest" ]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY RUN] Would copy CLAUDE.md"
      WRITE_COUNT=$(( WRITE_COUNT + 1 ))
      return
    fi
    cp "$staged" "$dest" || { echo "Error: failed to install CLAUDE.md" >&2; exit 1; }
    save_claude_base "$dest"
    return
  fi

  # Existing CLAUDE.md present — apply decision table
  if [ "$KEEP_CLAUDE_MD" -eq 1 ]; then
    return
  fi

  if [ "$OVERWRITE" -eq 1 ]; then
    local is_tty=0
    if [ -n "${_INSTALL_IS_TTY:-}" ]; then
      is_tty="$_INSTALL_IS_TTY"
    elif [ -t 0 ]; then
      is_tty=1
    fi

    if [ "$is_tty" -eq 1 ]; then
      if [[ "$DRY_RUN" -eq 1 ]]; then
        local pager="${_INSTALL_PAGER:-less}"
        diff -u "$dest" "$staged" 2>/dev/null | "$pager" || true
        echo "[DRY RUN] Would prompt: Overwrite CLAUDE.md? [y/N]"
        WRITE_COUNT=$(( WRITE_COUNT + 1 ))
        return
      fi
      local pager="${_INSTALL_PAGER:-less}"
      diff -u "$dest" "$staged" 2>/dev/null | "$pager" || true
      printf "Overwrite CLAUDE.md? [y/N] "
      local answer
      read -r answer
      if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        cp "$staged" "$dest" || { echo "Error: failed to install CLAUDE.md" >&2; exit 1; }
        save_claude_base "$dest"
      else
        echo "CLAUDE.md left unchanged."
      fi
    else
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DRY RUN] Would overwrite CLAUDE.md"
        WRITE_COUNT=$(( WRITE_COUNT + 1 ))
        return
      fi
      cp "$staged" "$dest" || { echo "Error: failed to install CLAUDE.md" >&2; exit 1; }
      save_claude_base "$dest"
      echo "Non-interactive: CLAUDE.md overwritten."
    fi
    return
  fi

  # Default (no flags): check for changes first, then attempt 3-way merge if base exists
  if diff -q "$dest" "$staged" >/dev/null 2>&1; then
    # Identical — nothing to merge
    echo "CLAUDE.md is already up to date, nothing to merge."
    return
  fi

  if [ -f "$CLAUDE_BASE_FILE" ]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      local tmp_merged
      tmp_merged="$(mktemp)"
      if git merge-file -p "$dest" "$CLAUDE_BASE_FILE" "$staged" > "$tmp_merged" 2>/dev/null; then
        echo "[DRY RUN] Would update CLAUDE.md (merging new changes with your modifications)"
      else
        echo "[DRY RUN] Would open editor to resolve CLAUDE.md conflicts"
      fi
      rm -f "$tmp_merged"
      WRITE_COUNT=$(( WRITE_COUNT + 1 ))
      return
    fi

    local tmp_merged
    tmp_merged="$(mktemp)"
    if git merge-file -p "$dest" "$CLAUDE_BASE_FILE" "$staged" > "$tmp_merged" 2>/dev/null; then
      cp "$tmp_merged" "$dest" || { echo "Error: failed to write merged CLAUDE.md" >&2; rm -f "$tmp_merged"; exit 1; }
      rm -f "$tmp_merged"
      save_claude_base "$dest"
      echo "CLAUDE.md updated — new changes merged with your modifications."
    else
      # Conflicts — write markers to dest, open editor for resolution
      cp "$tmp_merged" "$dest" || { echo "Error: failed to write CLAUDE.md with conflict markers" >&2; rm -f "$tmp_merged"; exit 1; }
      rm -f "$tmp_merged"
      local editor="${VISUAL:-${EDITOR:-vi}}"
      echo "CLAUDE.md has merge conflicts. Opening $editor to resolve..."
      "$editor" "$dest"
      save_claude_base "$dest"
      echo "CLAUDE.md saved."
    fi
    return
  fi

  # No base — cannot merge, skip with hint
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would skip CLAUDE.md (no merge base — use --overwrite to replace)"
    return
  fi
  echo "CLAUDE.md already exists and cannot be auto-merged (no base file). Re-run with --overwrite to replace it."
}

# ---------------------------------------------------------------------------
# dry_mkdir DIR — guard for mkdir -p to INSTALL_DEST
#   DRY_RUN=1: print "[DRY RUN] Would create directory DIR"; no I/O; WRITE_COUNT unchanged
#   DRY_RUN=0: mkdir -p DIR
# ---------------------------------------------------------------------------
dry_mkdir() {
  local dir="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would create directory $dir"
    return 0
  fi
  mkdir -p "$dir"
}

# ---------------------------------------------------------------------------
# dry_mv SRC DST — guard for mv (with cp fallback) to INSTALL_DEST
#   DRY_RUN=1: print "[DRY RUN] Would install BASENAME(DST)"; WRITE_COUNT++; no I/O
#   DRY_RUN=0: mv SRC DST; on failure, cp SRC DST; on cp failure, exit 1 with error
# ---------------------------------------------------------------------------
dry_mv() {
  local src="$1" dst="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would install $dst"
    WRITE_COUNT=$(( WRITE_COUNT + 1 ))
    return 0
  fi
  if ! mv "$src" "$dst" 2>/dev/null; then
    cp "$src" "$dst" || { echo "Error: failed to install $dst" >&2; exit 1; }
  fi
}

# ---------------------------------------------------------------------------
# dry_cp SRC DST — guard for cp to INSTALL_DEST
#   DRY_RUN=1: print "[DRY RUN] Would install BASENAME(DST)"; WRITE_COUNT++; no I/O
#   DRY_RUN=0: cp SRC DST; on failure, exit 1 with error
# ---------------------------------------------------------------------------
dry_cp() {
  local src="$1" dst="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would install $dst"
    WRITE_COUNT=$(( WRITE_COUNT + 1 ))
    return 0
  fi
  cp "$src" "$dst" || { echo "Error: failed to install $dst" >&2; exit 1; }
}

# ---------------------------------------------------------------------------
# check_cc_variant_integrity
# Post-install sanity check that the CC variant's required skills are present.
# Warns to stderr (does not exit) if any are missing. Only meaningful after a
# real install — caller must gate on DRY_RUN != 1.
# RECOVERY_SCHEMA_V2 — includes scripts/implement-next-triage.sh.
# ---------------------------------------------------------------------------
check_cc_variant_integrity() {
    local missing=()
    for f in commands/implement-next-cc.md commands/implement-next-cc-resume.md commands/implement-all-cc.md \
             scripts/implement-next-stop-gate.sh scripts/implement-next-state-write.sh \
             scripts/implement-next-state-clear.sh scripts/implement-next-triage.sh; do
        if [ ! -f "${DEST_DIR}/${f}" ]; then
            missing+=("$f")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "  WARNING: CC variant is incomplete; missing files:" >&2
        printf '    - %s\n' "${missing[@]}" >&2
        echo "  /implement-all-cc will fail at rescue path. Re-run install or use /implement-all (portable) instead." >&2
    fi
}

# ---------------------------------------------------------------------------
# check_portable_variant_integrity
# RECOVERY_SCHEMA_V2 — Post-install sanity check that the portable variant's
# required skills/scripts are present. Without this, a portable-only install
# missing the triage script would fail at Step 0 with a raw "bash: not found"
# and no diagnostic. Both variants share scripts/implement-next-triage.sh.
# Warns to stderr (does not exit) if any are missing.
# ---------------------------------------------------------------------------
check_portable_variant_integrity() {
    local missing=()
    for f in commands/implement-all.md commands/implement-next.md \
             scripts/implement-next-triage.sh; do
        if [ ! -f "${DEST_DIR}/${f}" ]; then
            missing+=("$f")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "  WARNING: portable variant is incomplete; missing files:" >&2
        printf '    - %s\n' "${missing[@]}" >&2
        echo "  /implement-all (portable) will fail at Step 0 triage. Re-run install to restore the manifest." >&2
    fi
}

# ---------------------------------------------------------------------------
# move_files
# Safe sequential move of all staged files (except CLAUDE.md) to DEST_DIR.
# Falls back to cp+rm on cross-device link failure (via dry_mv).
# ---------------------------------------------------------------------------
move_files() {
  local manifest="$CLONE_DIR/sync-manifest.txt"

  local entry
  while IFS= read -r entry; do
    _move_into "$entry"
  done < <(read_manifest_entries "$manifest")

  # install.sh is intentionally NOT moved into DEST_DIR — it is repo-only.
  # CLAUDE.md is installed by handle_claude_md (called from main after move_files).
  if [[ "$DRY_RUN" -ne 1 ]]; then
    check_manifest_integrity
  fi
}

# ---------------------------------------------------------------------------
# _move_into ENTRY
# Moves one staged manifest entry into DEST_DIR (dry-run aware). Directory
# entries (trailing /) are copied recursively; files use dry_mv.
# ---------------------------------------------------------------------------
_move_into() {
  local entry="$1"
  if [ "${entry%/}" != "$entry" ]; then
    local rel="${entry%/}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[DRY RUN] Would install ${rel}/"
      WRITE_COUNT=$(( WRITE_COUNT + 1 ))
      return 0
    fi
    mkdir -p "$DEST_DIR/$rel"
    cp -R "$STAGE_DIR/$rel/." "$DEST_DIR/$rel/"
  else
    [[ "$DRY_RUN" -eq 1 ]] || mkdir -p "$DEST_DIR/$(dirname "$entry")"
    dry_mv "$STAGE_DIR/$entry" "$DEST_DIR/$entry"
  fi
}

# ---------------------------------------------------------------------------
# check_manifest_integrity
# Post-install sanity check: every curated manifest path (plus CLAUDE.md) is
# present in DEST_DIR. Warns to stderr (does not exit) if any are missing.
# Replaces the former CC-variant integrity checks, which referenced files the
# CC-recovery removal deleted.
# ---------------------------------------------------------------------------
check_manifest_integrity() {
  local manifest="$CLONE_DIR/sync-manifest.txt" entry
  local -a missing=()
  while IFS= read -r entry; do
    if [ "${entry%/}" != "$entry" ]; then
      [ -d "$DEST_DIR/${entry%/}" ] || missing+=("$entry")
    else
      [ -f "$DEST_DIR/$entry" ] || missing+=("$entry")
    fi
  done < <(read_manifest_entries "$manifest")
  # CLAUDE.md is intentionally not checked here — it is installed later by
  # handle_claude_md (after move_files), which has its own error handling.
  if [ ${#missing[@]} -gt 0 ]; then
    echo "  WARNING: install incomplete; missing in ${DEST_DIR}:" >&2
    printf '    - %s\n' "${missing[@]}" >&2
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  set -euo pipefail

  parse_flags "$@"
  check_prereqs

  # Set base file path now that DEST_DIR is final
  if [ -z "$CLAUDE_BASE_FILE" ]; then
    CLAUDE_BASE_FILE="$DEST_DIR/.claude-base.md"
  fi

  # Initialize temp dir vars before the trap so cleanup always has defined vars under set -u
  STAGE_DIR=""
  CLONE_TEMP_DIR=""
  CLONE_DIR=""

  # Create CLONE_TEMP_DIR first (only when actually cloning — not for fixture mode)
  if [[ "${INSTALL_SKIP_CLONE:-}" != "1" ]]; then
    CLONE_TEMP_DIR="$(mktemp -d)" || { echo "Error: cannot create temp directory in /tmp" >&2; exit 1; }
  fi

  # Register cleanup trap immediately after CLONE_TEMP_DIR is created
  trap cleanup EXIT

  # Create STAGE_DIR
  if [[ -n "${INSTALL_STAGE_DIR:-}" ]]; then
    STAGE_DIR="$INSTALL_STAGE_DIR"
  else
    STAGE_DIR="$(mktemp -d)" || { echo "Error: cannot create temp directory in /tmp" >&2; exit 1; }
  fi

  do_clone

  if [ ! -f "$CLONE_DIR/sync-manifest.txt" ]; then
    echo "Error: sync-manifest.txt missing from repo — cannot determine what to install." >&2
    exit 1
  fi

  stage_files
  set_permissions
  move_files
  if manifest_lists "CLAUDE.md" "$CLONE_DIR/sync-manifest.txt"; then
    handle_claude_md
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo ""
    echo "$WRITE_COUNT file(s) would be installed."
    return
  fi

  echo ""
  echo "Claude Goodies installed successfully to $DEST_DIR"
  echo "Restart Claude Code to apply changes."
}

# ---------------------------------------------------------------------------
# Entry point — only call main when executed directly (not sourced)
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
