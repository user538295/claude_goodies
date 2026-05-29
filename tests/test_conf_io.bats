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

# ---------------------------------------------------------------------------
# test_write_round_trip
# ---------------------------------------------------------------------------
@test "test_write_round_trip" {
  # Fixture: comment, entry, blank, entry, comment
  printf '# header\nfoo=r\n\nbar=i\n# footer\n' > "$CONF_FILE"
  parse_conf

  # Snapshot state before write
  local -A state_before=()
  local key
  for key in "${!CONF_STATE[@]}"; do
    state_before["$key"]="${CONF_STATE[$key]}"
  done
  local -a order_types_before=("${CONF_ORDER_TYPES[@]}")
  local -a order_paths_before=("${CONF_ORDER_PATHS[@]}")

  write_conf

  # Re-parse after write
  reset_globals
  parse_conf

  # CONF_STATE must match
  [ "${#CONF_STATE[@]}" -eq "${#state_before[@]}" ]
  for key in "${!state_before[@]}"; do
    [ "${CONF_STATE[$key]}" = "${state_before[$key]}" ]
  done

  # CONF_ORDER_TYPES must match
  [ "${#CONF_ORDER_TYPES[@]}" -eq "${#order_types_before[@]}" ]
  local i
  for i in "${!order_types_before[@]}"; do
    [ "${CONF_ORDER_TYPES[$i]}" = "${order_types_before[$i]}" ]
  done

  # CONF_ORDER_PATHS must match
  [ "${#CONF_ORDER_PATHS[@]}" -eq "${#order_paths_before[@]}" ]
  for i in "${!order_paths_before[@]}"; do
    [ "${CONF_ORDER_PATHS[$i]}" = "${order_paths_before[$i]}" ]
  done
}

# ---------------------------------------------------------------------------
# test_write_preserves_comments
# ---------------------------------------------------------------------------
@test "test_write_preserves_comments" {
  printf '# first comment\nfoo=r\n# second comment\nbar=i\n' > "$CONF_FILE"
  parse_conf
  write_conf

  # Verify exact line order: comment, entry, comment, entry
  mapfile -t lines < "$CONF_FILE"
  [ "${lines[0]}" = "# first comment" ]
  [ "${lines[1]}" = "foo=r" ]
  [ "${lines[2]}" = "# second comment" ]
  [ "${lines[3]}" = "bar=i" ]
}

# ---------------------------------------------------------------------------
# test_write_appends_new_entries
# ---------------------------------------------------------------------------
@test "test_write_appends_new_entries" {
  printf 'foo=r\n' > "$CONF_FILE"
  parse_conf

  # Add a new key not present in the original conf
  CONF_STATE["baz"]="i"

  write_conf

  local content
  content=$(cat "$CONF_FILE")
  [[ "$content" == *"baz=i"* ]]

  # Index must be updated for the new key
  [ "${CONF_ORDER_PATH_INDEX["baz"]+set}" = "set" ]
  [ "${CONF_ORDER_PATH_INDEX["baz"]}" = "1" ]
}

# ---------------------------------------------------------------------------
# test_write_skips_removed_entries
# ---------------------------------------------------------------------------
@test "test_write_skips_removed_entries" {
  printf 'foo=r\nbar=i\n' > "$CONF_FILE"
  parse_conf

  unset 'CONF_STATE[foo]'

  write_conf

  local content
  content=$(cat "$CONF_FILE")
  # foo must be absent
  [[ "$content" != *"foo="* ]]
  # bar must be present
  [[ "$content" == *"bar=i"* ]]
}

# ---------------------------------------------------------------------------
# test_write_empty_state_round_trips
# ---------------------------------------------------------------------------
@test "test_write_empty_state_round_trips" {
  printf 'foo=\n' > "$CONF_FILE"
  parse_conf 2>/dev/null
  write_conf 2>/dev/null
  reset_globals
  parse_conf 2>/dev/null
  # After round-trip, foo should exist with empty value (not be missing)
  [[ -n "${CONF_STATE[foo]+exists}" ]]
  [ "${CONF_STATE[foo]}" = "" ]
}

# ---------------------------------------------------------------------------
# test_write_path_with_space_round_trips
# ---------------------------------------------------------------------------
@test "test_write_path_with_space_round_trips" {
  printf 'my file.md=r\n' > "$CONF_FILE"
  parse_conf 2>/dev/null
  write_conf 2>/dev/null
  reset_globals
  parse_conf 2>/dev/null
  [ "${CONF_STATE["my file.md"]}" = "r" ]
}

# ---------------------------------------------------------------------------
# test_write_dry_run_no_write
# ---------------------------------------------------------------------------
@test "test_write_dry_run_no_write" {
  printf 'foo=r\n' > "$CONF_FILE"
  parse_conf

  local before
  before=$(cat "$CONF_FILE")

  DRY_RUN=true
  CONF_STATE["foo"]="i"  # mutate state — must NOT be written

  local output
  output=$(write_conf)

  local after
  after=$(cat "$CONF_FILE")

  # File must be unchanged
  [ "$before" = "$after" ]
  # Output must mention DRY-RUN
  [[ "$output" == *"DRY-RUN"* ]]
}

# ---------------------------------------------------------------------------
# test_write_atomic
# ---------------------------------------------------------------------------
@test "test_write_atomic" {
  local tmpconf_dir
  tmpconf_dir=$(mktemp -d)
  local old_conf_file="$CONF_FILE"
  CONF_FILE="$tmpconf_dir/sync-answers.conf"

  printf 'foo=r\n' > "$CONF_FILE"
  parse_conf 2>/dev/null
  write_conf 2>/dev/null

  # Count any files in the dir that look like temp files (not the final conf file itself)
  local leftover_count
  leftover_count=$(find "$tmpconf_dir" -maxdepth 1 -type f ! -name 'sync-answers.conf' | wc -l | tr -d ' ')
  [ "$leftover_count" -eq 0 ]

  CONF_FILE="$old_conf_file"
  rm -rf "$tmpconf_dir"
}
