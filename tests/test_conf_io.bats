#!/usr/bin/env bats

SCRIPT="$HOME/.local/bin/claude-sync.sh"

# Source the script once at top level — source guard prevents main() from running.
# We must set CLAUDE_DIR to a valid git repo before sourcing so that global
# variable initialisation (CONF_FILE) resolves correctly, but preflight_check
# is never called from tests directly.
export CLAUDE_DIR="$BATS_TMPDIR/test-claude-src"
mkdir -p "$CLAUDE_DIR"
git init "$CLAUDE_DIR" >/dev/null 2>&1 || true

# shellcheck disable=SC1090
source "$SCRIPT"

setup() {
  # Each test gets a fresh CONF_FILE path and clean global state.
  CONF_FILE="$BATS_TMPDIR/sync-answers.conf"
  reset_globals
}

teardown() {
  rm -f "$BATS_TMPDIR/sync-answers.conf"
}

# ---------------------------------------------------------------------------
# test_parse_empty_file
# ---------------------------------------------------------------------------
@test "test_parse_empty_file" {
  printf '' > "$CONF_FILE"
  parse_conf
  [ "${#CONF_STATE[@]}" -eq 0 ]
  [ "${#CONF_ORDER_TYPES[@]}" -eq 0 ]
  [ "${#CONF_ORDER_PATHS[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_parse_basic_entries
# ---------------------------------------------------------------------------
@test "test_parse_basic_entries" {
  printf 'scripts/=i\nCLAUDE.md=r\n' > "$CONF_FILE"
  parse_conf
  [ "${CONF_STATE["scripts/"]}" = "i" ]
  [ "${CONF_STATE["CLAUDE.md"]}" = "r" ]
  [ "${#CONF_ORDER_TYPES[@]}" -eq 2 ]
  [ "${CONF_ORDER_TYPES[0]}" = "entry" ]
  [ "${CONF_ORDER_TYPES[1]}" = "entry" ]
}

# ---------------------------------------------------------------------------
# test_parse_preserves_comments
# ---------------------------------------------------------------------------
@test "test_parse_preserves_comments" {
  printf '# my comment\nfoo=r\n' > "$CONF_FILE"
  parse_conf
  [ "${CONF_ORDER_TYPES[0]}" = "comment" ]
  [ "${CONF_ORDER_TYPES[1]}" = "entry" ]
  [ "${CONF_ORDER_PATHS[0]}" = "# my comment" ]
  [ "${CONF_ORDER_PATHS[1]}" = "foo" ]
  [ "${CONF_STATE["foo"]}" = "r" ]
}

# ---------------------------------------------------------------------------
# test_parse_preserves_blank_lines
# ---------------------------------------------------------------------------
@test "test_parse_preserves_blank_lines" {
  printf 'foo=r\n\nbar=i\n' > "$CONF_FILE"
  parse_conf 2>/dev/null
  [ "${CONF_ORDER_TYPES[0]}" = "entry" ]
  [ "${CONF_ORDER_TYPES[1]}" = "blank" ]
  [ "${CONF_ORDER_TYPES[2]}" = "entry" ]
  [ "${CONF_ORDER_PATHS[1]}" = "" ]
}

# ---------------------------------------------------------------------------
# test_parse_deduplicates_last_wins
# ---------------------------------------------------------------------------
@test "test_parse_deduplicates_last_wins" {
  printf 'foo=r\nfoo=i\n' > "$CONF_FILE"
  parse_conf
  # Last value wins
  [ "${CONF_STATE["foo"]}" = "i" ]
  # Exactly one element total in order arrays after dedup
  [ "${#CONF_ORDER_TYPES[@]}" -eq 1 ]
  [ "${CONF_ORDER_TYPES[0]}" = "entry" ]
  [ "${CONF_ORDER_PATHS[0]}" = "foo" ]
}

# ---------------------------------------------------------------------------
# test_parse_empty_state
# ---------------------------------------------------------------------------
@test "test_parse_empty_state" {
  printf 'foo=\n' > "$CONF_FILE"
  parse_conf
  # Key must exist with empty string value
  [ "${CONF_STATE["foo"]+set}" = "set" ]
  [ "${CONF_STATE["foo"]}" = "" ]
}

# ---------------------------------------------------------------------------
# test_parse_missing_file
# ---------------------------------------------------------------------------
@test "test_parse_missing_file" {
  rm -f "$CONF_FILE"
  parse_conf
  [ "${#CONF_STATE[@]}" -eq 0 ]
  [ "${#CONF_ORDER_TYPES[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# test_parse_rejects_absolute_path
# ---------------------------------------------------------------------------
@test "test_parse_rejects_absolute_path" {
  printf '/etc/passwd=r\n' > "$CONF_FILE"
  parse_conf 2>/dev/null
  [ "${#CONF_STATE[@]}" -eq 0 ]
  # Should be stored as comment to preserve it
  local found_entry=false
  for i in "${!CONF_ORDER_TYPES[@]}"; do
    [ "${CONF_ORDER_TYPES[$i]}" = "entry" ] && found_entry=true && break
  done
  [ "$found_entry" = "false" ]
  local found_comment=false
  for i in "${!CONF_ORDER_TYPES[@]}"; do
    if [[ "${CONF_ORDER_TYPES[$i]}" == "comment" ]]; then
      found_comment=true
    fi
  done
  [ "$found_comment" = "true" ]
}

# ---------------------------------------------------------------------------
# test_parse_rejects_absolute_path_warning
# ---------------------------------------------------------------------------
@test "test_parse_rejects_absolute_path_warning" {
  printf '/etc/passwd=r\n' > "$CONF_FILE"
  local warn_file="$BATS_TMPDIR/warn.txt"
  parse_conf 2>"$warn_file"
  [[ "$(cat "$warn_file")" == *"WARNING"* ]]
}

# ---------------------------------------------------------------------------
# test_parse_rejects_traversal_path
# ---------------------------------------------------------------------------
@test "test_parse_rejects_traversal_path" {
  printf '../../etc/passwd=d\n' > "$CONF_FILE"
  local warn_file="$BATS_TMPDIR/warn.txt"
  parse_conf 2>"$warn_file"
  [ "${#CONF_STATE[@]}" -eq 0 ]
  [[ "$(cat "$warn_file")" == *"WARNING"* ]]
  local found_comment=false
  for i in "${!CONF_ORDER_TYPES[@]}"; do
    if [[ "${CONF_ORDER_TYPES[$i]}" == "comment" ]]; then
      found_comment=true
    fi
  done
  [ "$found_comment" = "true" ]
}

# ---------------------------------------------------------------------------
# test_parse_rejects_embedded_traversal_path
# ---------------------------------------------------------------------------
@test "test_parse_rejects_embedded_traversal_path" {
  printf 'foo/../../etc/passwd=r\n' > "$CONF_FILE"
  local warn_file="$BATS_TMPDIR/warn.txt"
  parse_conf 2>"$warn_file"
  # Not in CONF_STATE
  [ "${#CONF_STATE[@]}" -eq 0 ]
  # IS stored as 'comment'
  local found_comment=false
  for t in "${CONF_ORDER_TYPES[@]}"; do
    [ "$t" = "comment" ] && found_comment=true && break
  done
  [ "$found_comment" = "true" ]
  # Warning logged
  [[ "$(cat "$warn_file")" == *"WARNING"* ]]
}

# ---------------------------------------------------------------------------
# test_parse_dotdot_in_filename_is_valid
# ---------------------------------------------------------------------------
@test "test_parse_dotdot_in_filename_is_valid" {
  printf 'file..name.sh=r\n' > "$CONF_FILE"
  parse_conf 2>/dev/null
  [ "${CONF_STATE["file..name.sh"]}" = "r" ]
}

# ---------------------------------------------------------------------------
# test_parse_path_with_space
# ---------------------------------------------------------------------------
@test "test_parse_path_with_space" {
  printf 'my file.md=r\n' > "$CONF_FILE"
  parse_conf
  [ "${CONF_STATE["my file.md"]}" = "r" ]
}

# ---------------------------------------------------------------------------
# test_parse_equals_in_filename_stored_as_comment
# ---------------------------------------------------------------------------
@test "test_parse_equals_in_filename_stored_as_comment" {
  # filename "key=value.txt" with state "r" appears as: key=value.txt=r
  printf 'key=value.txt=r\n' > "$CONF_FILE"
  local warn_file="$BATS_TMPDIR/warn.txt"
  parse_conf 2>"$warn_file"
  # NOT in CONF_STATE
  [ "${#CONF_STATE[@]}" -eq 0 ]
  # IS stored as 'comment'
  local found_comment=false
  for t in "${CONF_ORDER_TYPES[@]}"; do
    [ "$t" = "comment" ] && found_comment=true && break
  done
  [ "$found_comment" = "true" ]
  # Warning logged
  [[ "$(cat "$warn_file")" == *"WARNING"* ]]
}

# ---------------------------------------------------------------------------
# test_parse_rejects_bare_dotdot
# ---------------------------------------------------------------------------
@test "test_parse_rejects_bare_dotdot" {
  printf '..=r\n' > "$CONF_FILE"
  local warn_file="$BATS_TMPDIR/warn.txt"
  parse_conf 2>"$warn_file"
  [ "${#CONF_STATE[@]}" -eq 0 ]
  [[ "$(cat "$warn_file")" == *"WARNING"* ]]
  local found_comment=false
  for i in "${!CONF_ORDER_TYPES[@]}"; do
    if [[ "${CONF_ORDER_TYPES[$i]}" == "comment" ]]; then
      found_comment=true
    fi
  done
  [ "$found_comment" = "true" ]
}

# ---------------------------------------------------------------------------
# test_parse_populates_path_index
# ---------------------------------------------------------------------------
@test "test_parse_populates_path_index" {
  printf 'foo=r\nbar=i\n' > "$CONF_FILE"
  parse_conf
  [ "${CONF_ORDER_PATH_INDEX["foo"]}" = "1" ]
  [ "${CONF_ORDER_PATH_INDEX["bar"]}" = "1" ]
}
