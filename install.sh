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

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: install.sh [OPTIONS]

Options:
  --overwrite        Overwrite existing installation
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
# stage_files
# Copies the file manifest from CLONE_DIR into STAGE_DIR.
# ---------------------------------------------------------------------------
stage_files() {
  # Stage CLAUDE.md
  cp "$CLONE_DIR/CLAUDE.md" "$STAGE_DIR/CLAUDE.md"

  # Stage scripts/ (ALL files, not just .sh)
  mkdir -p "$STAGE_DIR/scripts"
  if ls "$CLONE_DIR/scripts/"* >/dev/null 2>&1; then
    cp "$CLONE_DIR/scripts/"* "$STAGE_DIR/scripts/"
  else
    echo "Warning: scripts/ is empty"
  fi

  # Stage install.sh itself
  cp "$CLONE_DIR/install.sh" "$STAGE_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# set_permissions
# Makes .sh files executable; leaves .awk, .template, etc. unchanged.
# ---------------------------------------------------------------------------
set_permissions() {
  find "$STAGE_DIR/scripts" -name "*.sh" -exec chmod +x {} \;
  chmod +x "$STAGE_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# handle_claude_md
# Conditionally copies staged CLAUDE.md to DEST_DIR based on flags and
# existing state. Implements the CLAUDE.md decision table.
# ---------------------------------------------------------------------------
handle_claude_md() {
  local staged="$STAGE_DIR/CLAUDE.md"
  local dest="$DEST_DIR/CLAUDE.md"

  # Fresh install — no existing CLAUDE.md: always copy
  if [ ! -f "$dest" ]; then
    cp "$staged" "$dest" || { echo "Error: failed to install CLAUDE.md" >&2; exit 1; }
    return
  fi

  # Existing CLAUDE.md present — apply decision table
  if [ "$KEEP_CLAUDE_MD" -eq 1 ]; then
    # --keep-claude-md: skip silently
    return
  fi

  if [ "$OVERWRITE" -eq 1 ]; then
    # Determine TTY state
    local is_tty=0
    if [ -n "${_INSTALL_IS_TTY:-}" ]; then
      is_tty="$_INSTALL_IS_TTY"
    elif [ -t 0 ]; then
      is_tty=1
    fi

    if [ "$is_tty" -eq 1 ]; then
      # Interactive: show diff, prompt
      local pager="${_INSTALL_PAGER:-less}"
      diff -u "$dest" "$staged" 2>/dev/null | "$pager" || true
      printf "Overwrite CLAUDE.md? [y/N] "
      local answer
      read -r answer
      if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        cp "$staged" "$dest" || { echo "Error: failed to install CLAUDE.md" >&2; exit 1; }
      else
        echo "CLAUDE.md left unchanged."
      fi
    else
      # Non-interactive: overwrite without prompting
      cp "$staged" "$dest" || { echo "Error: failed to install CLAUDE.md" >&2; exit 1; }
      echo "Non-interactive: CLAUDE.md overwritten."
    fi
    return
  fi

  # Default (no flags): skip and print hint
  echo "CLAUDE.md already exists. Re-run with --overwrite to update it."
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
  local fname
  fname="$(basename "$dst")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would install $fname"
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
  local fname
  fname="$(basename "$dst")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY RUN] Would install $fname"
    WRITE_COUNT=$(( WRITE_COUNT + 1 ))
    return 0
  fi
  cp "$src" "$dst" || { echo "Error: failed to install $dst" >&2; exit 1; }
}

# ---------------------------------------------------------------------------
# move_files
# Safe sequential move of all staged files (except CLAUDE.md) to DEST_DIR.
# Falls back to cp+rm on cross-device link failure.
# ---------------------------------------------------------------------------
move_files() {
  mkdir -p "$DEST_DIR/scripts"

  # Move scripts/*
  # Use mv; fall back to cp on cross-device failure (e.g. mv across filesystems).
  # The staged copy lives in a temp dir cleaned by the EXIT trap — no need to rm on fallback.
  for src in "$STAGE_DIR/scripts/"*; do
    [[ -e "$src" ]] || continue
    local fname
    fname="$(basename "$src")"
    local dst="$DEST_DIR/scripts/$fname"
    if ! mv "$src" "$dst" 2>/dev/null; then
      cp "$src" "$dst" || { echo "Error: failed to install scripts/$fname" >&2; exit 1; }
    fi
  done

  # Move install.sh
  if ! mv "$STAGE_DIR/install.sh" "$DEST_DIR/install.sh" 2>/dev/null; then
    cp "$STAGE_DIR/install.sh" "$DEST_DIR/install.sh" || {
      echo "Error: failed to install install.sh" >&2
      exit 1
    }
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  set -euo pipefail

  parse_flags "$@"
  check_prereqs

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
  stage_files
  set_permissions
  move_files
  handle_claude_md

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
