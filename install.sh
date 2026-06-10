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
  local dirs=(
    agents assets commands handout scripts
    skills/aaa skills/aaa/references
    skills/documentation-standard skills/documentation-standard/references skills/documentation-standard/scripts
    skills/llm-wiki skills/llm-wiki/reference skills/llm-wiki/templates skills/llm-wiki/tests
    skills/llm-wiki-product skills/llm-wiki-product/reference skills/llm-wiki-product/templates
    skills/plan-maker skills/skill-packager
  )
  local files=(
    agents/devils-advocate.md
    assets/demo.gif
    commands/da-review.md commands/feature-refinement.md commands/implement-all.md
    commands/implement-next.md commands/iterative-review.md commands/options.md
    handout/_template.html handout/agentic-workflow-en.html handout/agentic-workflow-hu.html
    handout/card.css
    handout/cmd-da-review-hu.html handout/cmd-da-review.html
    handout/cmd-feature-refinement-hu.html handout/cmd-feature-refinement.html
    handout/cmd-implement-all-hu.html handout/cmd-implement-all.html
    handout/cmd-implement-next-hu.html handout/cmd-implement-next.html
    handout/cmd-iterative-review-hu.html handout/cmd-iterative-review.html
    handout/index-hu.html handout/index.html
    handout/scripts-logging-hu.html handout/scripts-logging.html
    handout/scripts-plan-hu.html handout/scripts-plan.html
    handout/skill-aaa-hu.html handout/skill-aaa.html
    handout/skill-documentation-standard-hu.html handout/skill-documentation-standard.html
    handout/skill-llm-wiki-hu.html handout/skill-llm-wiki-product-hu.html
    handout/skill-llm-wiki-product.html handout/skill-llm-wiki.html
    handout/skill-plan-maker-hu.html handout/skill-plan-maker.html
    handout/skill-skill-packager-hu.html handout/skill-skill-packager.html
    handout/styles.css
    README.md
    scripts/audit-plan-run.sh scripts/check-task-commit.sh scripts/count-uncompleted-tasks.sh
    scripts/plan-progress.sh scripts/progress-header-flat.template scripts/progress-header-phased.template
    scripts/prompt_log_lib.sh scripts/prompt_log_new_session.sh scripts/prompt_log_save.sh
    scripts/task_section.awk scripts/verify-run-commits.sh
    skills/aaa/references/aaa-rubric.md skills/aaa/references/code-review-protocol.md
    skills/aaa/references/evaluation-prompts.md skills/aaa/references/output-templates.md
    skills/aaa/references/product-feature-protocol.md skills/aaa/references/research-protocol.md
    skills/aaa/SKILL.md
    skills/documentation-standard/references/markdown_quality.md
    skills/documentation-standard/references/mermaid_examples.md
    skills/documentation-standard/references/templates.md
    skills/documentation-standard/scripts/validate_docs.py
    skills/documentation-standard/SKILL.md
    skills/llm-wiki/reference/karpathy-llm-wiki.md
    skills/llm-wiki/SKILL.md
    skills/llm-wiki/templates/glossary.md skills/llm-wiki/templates/index.md
    skills/llm-wiki/templates/log.md skills/llm-wiki/templates/overview.md
    skills/llm-wiki/templates/schema.md
    skills/llm-wiki/tests/__init__.py skills/llm-wiki/tests/test_watcher.py
    skills/llm-wiki/watcher.py
    skills/llm-wiki-product/reference/karpathy-llm-wiki.md
    skills/llm-wiki-product/SKILL.md
    skills/llm-wiki-product/templates/glossary.md skills/llm-wiki-product/templates/index.md
    skills/llm-wiki-product/templates/log.md skills/llm-wiki-product/templates/overview.md
    skills/llm-wiki-product/templates/schema.md
    skills/llm-wiki-product/watcher.py
    skills/plan-maker/SKILL.md
    skills/skill-packager/SKILL.md
  )

  cp "$CLONE_DIR/CLAUDE.md" "$STAGE_DIR/CLAUDE.md"

  for d in "${dirs[@]}"; do
    mkdir -p "$STAGE_DIR/$d"
  done

  for f in "${files[@]}"; do
    cp "$CLONE_DIR/$f" "$STAGE_DIR/$f"
  done

  cp "$CLONE_DIR/install.sh" "$STAGE_DIR/install.sh"
}

# ---------------------------------------------------------------------------
# set_permissions
# Makes .sh files executable; leaves .awk, .template, etc. unchanged.
# ---------------------------------------------------------------------------
set_permissions() {
  find "$STAGE_DIR" -name "*.sh" -exec chmod +x {} \;
  find "$STAGE_DIR" -name "*.py" -exec chmod +x {} \;
  chmod +x "$STAGE_DIR/install.sh"
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
# move_files
# Safe sequential move of all staged files (except CLAUDE.md) to DEST_DIR.
# Falls back to cp+rm on cross-device link failure (via dry_mv).
# ---------------------------------------------------------------------------
move_files() {
  local dirs=(
    agents assets commands handout scripts
    skills/aaa skills/aaa/references
    skills/documentation-standard skills/documentation-standard/references skills/documentation-standard/scripts
    skills/llm-wiki skills/llm-wiki/reference skills/llm-wiki/templates skills/llm-wiki/tests
    skills/llm-wiki-product skills/llm-wiki-product/reference skills/llm-wiki-product/templates
    skills/plan-maker skills/skill-packager
  )
  local files=(
    agents/devils-advocate.md
    assets/demo.gif
    commands/da-review.md commands/feature-refinement.md commands/implement-all.md
    commands/implement-next.md commands/iterative-review.md commands/options.md
    handout/_template.html handout/agentic-workflow-en.html handout/agentic-workflow-hu.html
    handout/card.css
    handout/cmd-da-review-hu.html handout/cmd-da-review.html
    handout/cmd-feature-refinement-hu.html handout/cmd-feature-refinement.html
    handout/cmd-implement-all-hu.html handout/cmd-implement-all.html
    handout/cmd-implement-next-hu.html handout/cmd-implement-next.html
    handout/cmd-iterative-review-hu.html handout/cmd-iterative-review.html
    handout/index-hu.html handout/index.html
    handout/scripts-logging-hu.html handout/scripts-logging.html
    handout/scripts-plan-hu.html handout/scripts-plan.html
    handout/skill-aaa-hu.html handout/skill-aaa.html
    handout/skill-documentation-standard-hu.html handout/skill-documentation-standard.html
    handout/skill-llm-wiki-hu.html handout/skill-llm-wiki-product-hu.html
    handout/skill-llm-wiki-product.html handout/skill-llm-wiki.html
    handout/skill-plan-maker-hu.html handout/skill-plan-maker.html
    handout/skill-skill-packager-hu.html handout/skill-skill-packager.html
    handout/styles.css
    README.md
    scripts/audit-plan-run.sh scripts/check-task-commit.sh scripts/count-uncompleted-tasks.sh
    scripts/plan-progress.sh scripts/progress-header-flat.template scripts/progress-header-phased.template
    scripts/prompt_log_lib.sh scripts/prompt_log_new_session.sh scripts/prompt_log_save.sh
    scripts/task_section.awk scripts/verify-run-commits.sh
    skills/aaa/references/aaa-rubric.md skills/aaa/references/code-review-protocol.md
    skills/aaa/references/evaluation-prompts.md skills/aaa/references/output-templates.md
    skills/aaa/references/product-feature-protocol.md skills/aaa/references/research-protocol.md
    skills/aaa/SKILL.md
    skills/documentation-standard/references/markdown_quality.md
    skills/documentation-standard/references/mermaid_examples.md
    skills/documentation-standard/references/templates.md
    skills/documentation-standard/scripts/validate_docs.py
    skills/documentation-standard/SKILL.md
    skills/llm-wiki/reference/karpathy-llm-wiki.md
    skills/llm-wiki/SKILL.md
    skills/llm-wiki/templates/glossary.md skills/llm-wiki/templates/index.md
    skills/llm-wiki/templates/log.md skills/llm-wiki/templates/overview.md
    skills/llm-wiki/templates/schema.md
    skills/llm-wiki/tests/__init__.py skills/llm-wiki/tests/test_watcher.py
    skills/llm-wiki/watcher.py
    skills/llm-wiki-product/reference/karpathy-llm-wiki.md
    skills/llm-wiki-product/SKILL.md
    skills/llm-wiki-product/templates/glossary.md skills/llm-wiki-product/templates/index.md
    skills/llm-wiki-product/templates/log.md skills/llm-wiki-product/templates/overview.md
    skills/llm-wiki-product/templates/schema.md
    skills/llm-wiki-product/watcher.py
    skills/plan-maker/SKILL.md
    skills/skill-packager/SKILL.md
  )

  for d in "${dirs[@]}"; do
    dry_mkdir "$DEST_DIR/$d"
  done

  for f in "${files[@]}"; do
    dry_mv "$STAGE_DIR/$f" "$DEST_DIR/$f"
  done

  dry_mv "$STAGE_DIR/install.sh" "$DEST_DIR/install.sh"
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
  stage_files
  set_permissions
  move_files
  handle_claude_md

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
