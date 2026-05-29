#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level with a valid CLAUDE_DIR.
export CLAUDE_DIR="$BATS_TMPDIR/test-sentinel-src"
mkdir -p "$CLAUDE_DIR"
git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

setup() {
  CLAUDE_DIR="$BATS_TMPDIR/test-sentinel-$$"
  mkdir -p "$CLAUDE_DIR"
  git init "$CLAUDE_DIR" >/dev/null 2>&1
  GITIGNORE_FILE="$CLAUDE_DIR/.gitignore"
  reset_globals
  # Re-set constants that reference CLAUDE_DIR (which changed after reset_globals)
  GITIGNORE_FILE="$CLAUDE_DIR/.gitignore"
  SENTINEL_BEGIN="# BEGIN claude-sync"
  SENTINEL_END="# END claude-sync"
}

teardown() {
  [[ -d "${CLAUDE_DIR:-}" ]] && rm -rf "$CLAUDE_DIR"
}

# ---------------------------------------------------------------------------
# test_sentinel_created_from_scratch
# ---------------------------------------------------------------------------
@test "test_sentinel_created_from_scratch" {
  CONF_STATE["secrets.txt"]="i"

  write_sentinel_section

  [ -f "$GITIGNORE_FILE" ]
  grep -qF "# BEGIN claude-sync" "$GITIGNORE_FILE"
  grep -qF "secrets.txt" "$GITIGNORE_FILE"
  grep -qF "# END claude-sync" "$GITIGNORE_FILE"
}

# ---------------------------------------------------------------------------
# test_sentinel_creates_gitignore_if_not_exists
# ---------------------------------------------------------------------------
@test "test_sentinel_creates_gitignore_if_not_exists" {
  [ ! -f "$GITIGNORE_FILE" ]

  write_sentinel_section

  [ -f "$GITIGNORE_FILE" ]
  grep -qF "# BEGIN claude-sync" "$GITIGNORE_FILE"
  grep -qF "# END claude-sync" "$GITIGNORE_FILE"
}

# ---------------------------------------------------------------------------
# test_sentinel_replaces_existing_block
# ---------------------------------------------------------------------------
@test "test_sentinel_replaces_existing_block" {
  # Write a sentinel block with a stale entry
  printf '# BEGIN claude-sync\nold-entry.txt\n# END claude-sync\n' > "$GITIGNORE_FILE"

  # New CONF_STATE has a different 'i' entry
  CONF_STATE["new-entry.txt"]="i"

  write_sentinel_section

  grep -qF "new-entry.txt" "$GITIGNORE_FILE"
  ! grep -qF "old-entry.txt" "$GITIGNORE_FILE"
}

# ---------------------------------------------------------------------------
# test_sentinel_preserves_lines_before
# ---------------------------------------------------------------------------
@test "test_sentinel_preserves_lines_before" {
  printf '# hand-written rule\n*.log\n# BEGIN claude-sync\nold.txt\n# END claude-sync\n' > "$GITIGNORE_FILE"

  CONF_STATE["new.txt"]="i"

  write_sentinel_section

  # Content check
  grep -qF "# hand-written rule" "$GITIGNORE_FILE"
  grep -qF "*.log" "$GITIGNORE_FILE"
  grep -qF "new.txt" "$GITIGNORE_FILE"

  # Ordering: before-lines must appear before BEGIN marker
  local begin_line hand_line log_line
  begin_line=$(grep -nF "# BEGIN claude-sync" "$GITIGNORE_FILE" | cut -d: -f1)
  hand_line=$(grep -nF "# hand-written rule" "$GITIGNORE_FILE" | cut -d: -f1)
  log_line=$(grep -nF "*.log" "$GITIGNORE_FILE" | cut -d: -f1)
  [ "$hand_line" -lt "$begin_line" ]
  [ "$log_line" -lt "$begin_line" ]
}

# ---------------------------------------------------------------------------
# test_sentinel_preserves_lines_after
# ---------------------------------------------------------------------------
@test "test_sentinel_preserves_lines_after" {
  printf '# BEGIN claude-sync\nold.txt\n# END claude-sync\n# trailing comment\n*.tmp\n' > "$GITIGNORE_FILE"

  CONF_STATE["new.txt"]="i"

  write_sentinel_section

  # Content check
  grep -qF "# trailing comment" "$GITIGNORE_FILE"
  grep -qF "*.tmp" "$GITIGNORE_FILE"
  grep -qF "new.txt" "$GITIGNORE_FILE"

  # Ordering: after-lines must appear after END marker
  local end_line trail_line tmp_line
  end_line=$(grep -nF "# END claude-sync" "$GITIGNORE_FILE" | cut -d: -f1)
  trail_line=$(grep -nF "# trailing comment" "$GITIGNORE_FILE" | cut -d: -f1)
  tmp_line=$(grep -nF "*.tmp" "$GITIGNORE_FILE" | cut -d: -f1)
  [ "$trail_line" -gt "$end_line" ]
  [ "$tmp_line" -gt "$end_line" ]
}

# ---------------------------------------------------------------------------
# test_sentinel_empty_block_when_no_i_entries
# ---------------------------------------------------------------------------
@test "test_sentinel_empty_block_when_no_i_entries" {
  CONF_STATE["tracked.md"]="r"

  write_sentinel_section

  [ -f "$GITIGNORE_FILE" ]
  grep -qF "# BEGIN claude-sync" "$GITIGNORE_FILE"
  grep -qF "# END claude-sync" "$GITIGNORE_FILE"

  # Nothing between the markers (no extra lines)
  local between
  between=$(awk '/# BEGIN claude-sync/{found=1; next} /# END claude-sync/{found=0} found' "$GITIGNORE_FILE")
  [ -z "$between" ]
}

# ---------------------------------------------------------------------------
# test_sentinel_dry_run_no_write
# ---------------------------------------------------------------------------
@test "test_sentinel_dry_run_no_write" {
  printf '# existing content\n' > "$GITIGNORE_FILE"
  local original_content
  original_content=$(cat "$GITIGNORE_FILE")

  CONF_STATE["secrets.txt"]="i"
  DRY_RUN=true

  local out
  out=$(write_sentinel_section)

  local current_content
  current_content=$(cat "$GITIGNORE_FILE")
  [ "$current_content" = "$original_content" ]
  echo "$out" | grep -qF "DRY-RUN"
}

# ---------------------------------------------------------------------------
# test_sentinel_idempotent
# ---------------------------------------------------------------------------
@test "test_sentinel_idempotent" {
  CONF_STATE["config.yaml"]="i"
  CONF_STATE["secrets.txt"]="i"

  write_sentinel_section
  local first_run
  first_run=$(cat "$GITIGNORE_FILE")

  write_sentinel_section
  local second_run
  second_run=$(cat "$GITIGNORE_FILE")

  [ "$first_run" = "$second_run" ]
}

# ---------------------------------------------------------------------------
# test_sentinel_escapes_metacharacters
# ---------------------------------------------------------------------------
@test "test_sentinel_escapes_metacharacters" {
  # Create a file with metacharacter in name so git check-ignore can verify
  local special_file="[special].txt"
  touch "$CLAUDE_DIR/$special_file"

  CONF_STATE["$special_file"]="i"

  write_sentinel_section

  # The pattern should be escaped in .gitignore
  grep -qF '\[special\].txt' "$GITIGNORE_FILE"

  # git check-ignore should match the actual file with the escaped pattern
  git -C "$CLAUDE_DIR" check-ignore -q -- "$special_file"
}

# ---------------------------------------------------------------------------
# test_sentinel_blank_separator
# ---------------------------------------------------------------------------
@test "test_sentinel_blank_separator_inserted_when_before_lines_not_empty" {
  # before_lines present and last line is non-blank → blank separator inserted
  printf '# existing rule\n*.log\n# BEGIN claude-sync\nold.txt\n# END claude-sync\n' > "$GITIGNORE_FILE"
  CONF_STATE["new.txt"]="i"

  write_sentinel_section

  # The line immediately before BEGIN should be blank (the separator)
  local begin_line
  begin_line=$(grep -nF "# BEGIN claude-sync" "$GITIGNORE_FILE" | cut -d: -f1)
  local separator_line
  separator_line=$(sed -n "$((begin_line - 1))p" "$GITIGNORE_FILE")
  [ -z "$separator_line" ]
}

@test "test_sentinel_blank_separator_suppressed_when_before_ends_blank" {
  # before_lines present but last line is already blank → no extra blank inserted
  printf '# existing rule\n\n# BEGIN claude-sync\nold.txt\n# END claude-sync\n' > "$GITIGNORE_FILE"
  CONF_STATE["new.txt"]="i"

  write_sentinel_section

  # Line immediately before BEGIN should be blank (the existing one, not a new duplicate)
  local begin_line
  begin_line=$(grep -nF "# BEGIN claude-sync" "$GITIGNORE_FILE" | cut -d: -f1)
  local line_before_begin
  line_before_begin=$(sed -n "$((begin_line - 1))p" "$GITIGNORE_FILE")
  [ -z "$line_before_begin" ]

  # The line before that should NOT be blank (only one separator, not two)
  local two_before_begin
  two_before_begin=$(sed -n "$((begin_line - 2))p" "$GITIGNORE_FILE")
  [ -n "$two_before_begin" ]
}

# ---------------------------------------------------------------------------
# test_escape_gitignore_path_special_prefixes
# ---------------------------------------------------------------------------
@test "test_escape_gitignore_path_hash_prefix" {
  local result
  result=$(_escape_gitignore_path "#comment-looking-file")
  [ "$result" = '\#comment-looking-file' ]
}

@test "test_escape_gitignore_path_bang_prefix" {
  local result
  result=$(_escape_gitignore_path "!negation-looking-file")
  [ "$result" = '\!negation-looking-file' ]
}

@test "test_escape_gitignore_path_space_prefix" {
  local result
  result=$(_escape_gitignore_path " leading-space-file")
  [ "$result" = '\ leading-space-file' ]
}

# ---------------------------------------------------------------------------
# test_sentinel_parses_file_without_trailing_newline
# ---------------------------------------------------------------------------
@test "test_sentinel_parses_file_without_trailing_newline" {
  # Write sentinel with no trailing newline after END marker
  printf '# hand-written\n# BEGIN claude-sync\nold.txt\n# END claude-sync' > "$GITIGNORE_FILE"

  CONF_STATE["new.txt"]="i"

  write_sentinel_section

  # Sentinel should be replaced (not duplicated)
  local begin_count
  begin_count=$(grep -cF "# BEGIN claude-sync" "$GITIGNORE_FILE")
  [ "$begin_count" -eq 1 ]

  local end_count
  end_count=$(grep -cF "# END claude-sync" "$GITIGNORE_FILE")
  [ "$end_count" -eq 1 ]

  # old.txt should be gone, new.txt present
  ! grep -qF "old.txt" "$GITIGNORE_FILE"
  grep -qF "new.txt" "$GITIGNORE_FILE"

  # hand-written line preserved
  grep -qF "# hand-written" "$GITIGNORE_FILE"

  # Run again to assert no duplication
  write_sentinel_section

  begin_count=$(grep -cF "# BEGIN claude-sync" "$GITIGNORE_FILE")
  [ "$begin_count" -eq 1 ]
}
