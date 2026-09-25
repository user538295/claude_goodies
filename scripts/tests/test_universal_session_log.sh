#!/usr/bin/env bash
# Behavioral tests for the universal session-log package.
# Run: bash scripts/tests/test_universal_session_log.sh
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$REPO/install-universal-session-log.sh"
FAIL=0
WORKROOT="$(mktemp -d)"
trap 'cd /; mv "$WORKROOT" "$HOME/.Trash/universal-session-log-test-$$" 2>/dev/null || true' EXIT

fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }
pass() { printf 'PASS: %s\n' "$1"; }
assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then pass "$label"; else fail "$label (missing: $needle; actual: $haystack)"; fi
}
assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then pass "$label"; else fail "$label (unexpected: $needle)"; fi
}
assert_exact() {
  local label="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] && pass "$label" || fail "$label (expected: $expected; actual: $actual)"
}
assert_file() { local label="$1" file="$2"; [[ -f "$file" ]] && pass "$label" || fail "$label (missing $file)"; }
assert_not_file() { local label="$1" file="$2"; [[ ! -e "$file" && ! -L "$file" ]] && pass "$label" || fail "$label (present $file)"; }
assert_mode() {
  local label="$1" expected="$2" file="$3" actual
  actual="$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)"
  [[ "$actual" == "$expected" ]] && pass "$label" || fail "$label (expected $expected, got $actual)"
}
assert_link() {
  local label="$1" expected="$2" file="$3" actual
  actual="$(readlink "$file" 2>/dev/null || true)"
  [[ -L "$file" && "$actual" == "$expected" ]] && pass "$label" || fail "$label (expected link $expected, got $actual)"
}
package_root_for() {
  case "$1" in
    claude) printf '%s\n' "$TEST_HOME/.claude/skills/session-log" ;;
    opencode) printf '%s\n' "$TEST_HOME/.config/opencode/skills/session-log" ;;
    omp) printf '%s\n' "$TEST_HOME/.omp/agent/skills/session-log" ;;
    *) fail "unsupported test harness: $1" ;;
  esac
}
run_session_log() {
  HOME="$TEST_HOME" "$(package_root_for claude)/bin/session-log" "$@"
}
run_harness() {
  local harness="$1"
  shift
  HOME="$TEST_HOME" "$(package_root_for "$harness")/bin/session-log" \
    --entrypoint "$harness" --harness "$harness" "$@"
}
run_harness_at_home() {
  local home="$1"
  local harness="$2"
  shift 2
  HOME="$home" "$(package_root_for "$harness")/bin/session-log" \
    --entrypoint "$harness" --harness "$harness" "$@"
}
run_harness_at_home_and_dir() {
  local home="$1"
  local cwd="$2"
  local harness="$3"
  shift 3
  (
    cd "$cwd"
    HOME="$home" "$(package_root_for "$harness")/bin/session-log" \
      --entrypoint "$harness" --harness "$harness" "$@"
  )
}

TEST_HOME="$WORKROOT/home"
mkdir -p "$TEST_HOME/.Trash"

printf '=== install copies complete packages without enabling logging ===\n'
HOME="$TEST_HOME" bash "$INSTALL" >"$WORKROOT/install.out" 2>"$WORKROOT/install.err"
assert_file "Claude package entrypoint seeded" "$TEST_HOME/.claude/skills/session-log/SKILL.md"
assert_file "Claude package installer seeded" "$TEST_HOME/.claude/skills/session-log/install.sh"
assert_file "Claude package CLI seeded" "$TEST_HOME/.claude/skills/session-log/bin/session-log"
assert_file "Claude package hook seeded" "$TEST_HOME/.claude/skills/session-log/adapters/claude/claude_hook.sh"
assert_file "OpenCode package entrypoint seeded" "$TEST_HOME/.config/opencode/skills/session-log/SKILL.md"
assert_file "OpenCode package adapter seeded" "$TEST_HOME/.config/opencode/skills/session-log/adapters/opencode/session-log.js"
assert_file "OMP package entrypoint seeded" "$TEST_HOME/.omp/agent/skills/session-log/SKILL.md"
assert_file "OMP package adapter seeded" "$TEST_HOME/.omp/agent/skills/session-log/adapters/omp/session-log.js"
assert_file "OpenCode slash command seeded" "$TEST_HOME/.config/opencode/commands/session-log.md"
assert_not_file "global CLI wrapper is not installed" "$TEST_HOME/.local/bin/session-log"
assert_not_file "global runtime release is not installed" "$TEST_HOME/.local/share/universal-session-log"
assert_not_file "Claude logging remains disabled" "$TEST_HOME/.claude/prompt-logs/.enabled"
assert_not_file "OpenCode logging remains disabled" "$TEST_HOME/.config/opencode/prompt-logs/.enabled"
assert_not_file "OMP logging remains disabled" "$TEST_HOME/.omp/agent/prompt-logs/.enabled"
assert_contains "install reports all harnesses" "Claude Code" "$(cat "$WORKROOT/install.out")"
assert_contains "install reports all harnesses" "OpenCode" "$(cat "$WORKROOT/install.out")"
assert_contains "install reports all harnesses" "OMP" "$(cat "$WORKROOT/install.out")"
for harness in claude opencode omp; do
  case "$harness" in
    claude) package_root="$TEST_HOME/.claude/skills/session-log" ;;
    opencode) package_root="$TEST_HOME/.config/opencode/skills/session-log" ;;
    omp) package_root="$TEST_HOME/.omp/agent/skills/session-log" ;;
  esac
  while IFS= read -r relative; do
    assert_file "$harness package asset installed: $relative" "$package_root/$relative"
  done <<'EOF'
SKILL.md
VERSION
install.sh
bin/session-log
adapters/claude/claude_hook.sh
adapters/claude/scripts/prompt_log_lib.sh
adapters/claude/scripts/prompt_log_new_session.sh
adapters/claude/scripts/prompt_log_prices.json
adapters/claude/scripts/prompt_log_save.sh
adapters/claude/scripts/prompt_log_stop.sh
adapters/claude/scripts/prompt_log_subagent.sh
adapters/claude/scripts/prompt_log_usage.jq
adapters/claude/scripts/prompt_log_usage.sh
adapters/opencode/session-log.js
adapters/opencode/session_log_usage.sh
adapters/omp/session-log.js
adapters/omp/session_log_usage.ts
templates/opencode/SKILL.md
templates/opencode/command.md
templates/omp/SKILL.md
EOF
done
initial_claude_status="$(run_harness claude status 2>&1)"
assert_exact "initial Claude status is exact" "Claude Code: off" "$initial_claude_status"

printf '=== identity is explicit and strict ===\n'
set +e
missing_identity="$(run_session_log status 2>&1)"
missing_rc=$?
unknown_identity="$(run_session_log --entrypoint unknown --harness unknown status 2>&1)"
unknown_rc=$?
set -e
[[ "$missing_rc" -ne 0 ]] && pass "missing harness identity fails" || fail "missing harness identity fails"
assert_contains "missing identity is actionable" "active harness identity is required" "$missing_identity"
[[ "$unknown_rc" -ne 0 ]] && pass "unknown harness identity fails" || fail "unknown harness identity fails"
assert_contains "unknown identity lists supported harnesses" "claude, opencode, omp" "$unknown_identity"
set +e
trailing_status="$(run_harness claude status unexpected 2>&1)"
trailing_status_rc=$?
set -e
[[ "$trailing_status_rc" -ne 0 ]] && pass "direct status rejects trailing arguments" || fail "direct status rejects trailing arguments"
assert_contains "trailing argument error is explicit" "trailing arguments are not valid for status" "$trailing_status"
set +e
unknown_before_command="$(run_harness claude --bogus status 2>&1)"
unknown_before_command_rc=$?
set -e
[[ "$unknown_before_command_rc" -ne 0 ]] && pass "unknown CLI argument before command fails" || fail "unknown CLI argument before command fails"
assert_contains "unknown CLI argument error names the argument" "unknown argument: --bogus" "$unknown_before_command"



printf '=== each native adapter installs lazily ===\n'
OPENCODE_HOME="$WORKROOT/opencode-home"
OMP_HOME="$WORKROOT/omp-home"
mkdir -p "$OPENCODE_HOME/.Trash" "$OMP_HOME/.Trash"
opencode_on="$(run_harness_at_home "$OPENCODE_HOME" opencode on 2>&1)"
omp_on="$(run_harness_at_home "$OMP_HOME" omp on 2>&1)"
assert_exact "OpenCode on status is exact" "OpenCode: on — restart required" "$opencode_on"
assert_exact "OMP on status is exact" "OMP: on — restart required" "$omp_on"
assert_file "OpenCode flag created" "$OPENCODE_HOME/.config/opencode/prompt-logs/.enabled"
assert_file "OpenCode plugin installed" "$OPENCODE_HOME/.config/opencode/plugins/session-log.js"
assert_file "OMP flag created" "$OMP_HOME/.omp/agent/prompt-logs/.enabled"
assert_file "OMP extension installed" "$OMP_HOME/.omp/agent/extensions/session-log.js"
assert_file "OMP usage parser installed" "$OMP_HOME/.omp/agent/skills/session-log/scripts/session_log_usage.ts"
set +e
opencode_plugin_smoke="$(
  HOME="$OPENCODE_HOME" SESSION_LOG_PLUGIN="$OPENCODE_HOME/.config/opencode/plugins/session-log.js" \
    bun --eval 'const loaded = await import(process.env.SESSION_LOG_PLUGIN); const hooks = await loaded.SessionLogPlugin({ directory: "fixture" }); process.stdout.write(Object.keys(hooks).sort().join(","));' \
    2>&1
)"
opencode_plugin_smoke_rc=$?
omp_plugin_smoke="$(
  HOME="$OMP_HOME" OMP_SESSION_LOG_PLUGIN="$OMP_HOME/.omp/agent/extensions/session-log.js" \
    bun --eval 'const events = []; const pi = { registerCommand: (name) => events.push(`command:${name}`), on: (name) => events.push(name) }; const loaded = await import(process.env.OMP_SESSION_LOG_PLUGIN); loaded.default(pi); process.stdout.write(events.join(","));' \
    2>&1
)"
omp_plugin_smoke_rc=$?
set -e
[[ "$opencode_plugin_smoke_rc" -eq 0 ]] && pass "OpenCode plugin lifecycle API loads" || fail "OpenCode plugin lifecycle API loads (actual: $opencode_plugin_smoke)"
assert_exact "OpenCode plugin registers native handlers" "chat.message,event" "$opencode_plugin_smoke"
assert_file "OpenCode plugin lifecycle writes runtime state" "$OPENCODE_HOME/.config/opencode/session-log/runtime.json"
[[ "$omp_plugin_smoke_rc" -eq 0 ]] && pass "OMP extension lifecycle API loads" || fail "OMP extension lifecycle API loads (actual: $omp_plugin_smoke)"
assert_exact "OMP extension registers native handlers" "command:session-log,session_start,session_shutdown,before_agent_start,agent_end,session_stop" "$omp_plugin_smoke"
assert_file "OMP extension lifecycle writes runtime state" "$OMP_HOME/.omp/agent/session-log/runtime.json"


printf '=== first on installs only the selected adapter and requires restart ===\n'
claude_on="$(run_harness claude on 2>&1)"
assert_exact "Claude on status is exact" "Claude Code: on — restart required" "$claude_on"
assert_file "Claude flag created" "$TEST_HOME/.claude/prompt-logs/.enabled"
assert_mode "Claude flag is private" "600" "$TEST_HOME/.claude/prompt-logs/.enabled"
assert_file "Claude adapter state created" "$TEST_HOME/.claude/session-log/adapter.version"
assert_not_file "OpenCode adapter remains absent from Claude activation" "$TEST_HOME/.config/opencode/session-log/adapter.version"
assert_not_file "OMP adapter remains absent from Claude activation" "$TEST_HOME/.omp/agent/session-log/adapter.version"
assert_file "Claude hooks settings created" "$TEST_HOME/.claude/settings.json"
assert_contains "Claude settings preserve owned hook marker" "universal-session-log" "$(cat "$TEST_HOME/.claude/settings.json")"
CLAUDE_HOOK="$TEST_HOME/.claude/skills/session-log/adapters/claude/claude_hook.sh"
printf '%s\n' '{"session_id":"claude-runtime","cwd":"'"$PWD"'"}' | HOME="$TEST_HOME" bash "$CLAUDE_HOOK" session-start >/dev/null
claude_status="$(run_harness claude status 2>&1)"
assert_exact "Claude loaded status is exact" "Claude Code: on" "$claude_status"
assert_contains "Claude runtime records package version" '"version": "1.0.0"' "$(cat "$TEST_HOME/.claude/session-log/runtime.json")"
printf '0.0.0\n' > "$TEST_HOME/.claude/session-log/adapter.version"
claude_update="$(run_harness claude on 2>&1)"
assert_exact "outdated Claude adapter status is exact" "Claude Code: on — restart required" "$claude_update"
assert_contains "outdated Claude adapter is updated" "1.0.0" "$(cat "$TEST_HOME/.claude/session-log/adapter.version")"

printf '=== off is idempotent and does not install an absent adapter ===\n'
OFF_HOME="$WORKROOT/off-home"
mkdir -p "$OFF_HOME/.Trash"
off_output="$(HOME="$OFF_HOME" "$TEST_HOME/.config/opencode/skills/session-log/bin/session-log" --entrypoint opencode --harness opencode off 2>&1)"
assert_exact "off status is exact" "OpenCode: off" "$off_output"
assert_not_file "off does not install adapter" "$OFF_HOME/.config/opencode/session-log/adapter.version"

printf '=== unsupported relocated roots fail without mutation ===\n'
set +e
relocated="$(XDG_CONFIG_HOME="$WORKROOT/relocated" run_harness opencode on 2>&1)"
relocated_rc=$?
set -e
[[ "$relocated_rc" -ne 0 ]] && pass "relocated OpenCode root fails" || fail "relocated OpenCode root fails"
assert_contains "relocated root error is explicit" "relocated" "$relocated"
assert_not_file "relocated root is not mutated" "$WORKROOT/relocated/prompt-logs/.enabled"

INSTALL_ROOT_HOME="$WORKROOT/install-root-home"
mkdir -p "$INSTALL_ROOT_HOME/.Trash"
set +e
install_root_error="$(HOME="$INSTALL_ROOT_HOME" XDG_CONFIG_HOME="$WORKROOT/custom-config" bash "$INSTALL" 2>&1)"
install_root_rc=$?
set -e
[[ "$install_root_rc" -ne 0 ]] && pass "installer rejects relocated roots" || fail "installer rejects relocated roots"
assert_contains "installer relocation error is explicit" "custom roots are unsupported" "$install_root_error"
assert_not_file "installer relocation leaves package absent" "$INSTALL_ROOT_HOME/.config/opencode/skills/session-log/SKILL.md"

UNOWNED_HOME="$WORKROOT/unowned-home"
mkdir -p "$UNOWNED_HOME/.Trash" "$UNOWNED_HOME/.config/opencode/plugins"
printf 'user plugin\n' > "$UNOWNED_HOME/.config/opencode/plugins/session-log.js"
set +e
unowned_error="$(HOME="$UNOWNED_HOME" "$TEST_HOME/.config/opencode/skills/session-log/bin/session-log" --entrypoint opencode --harness opencode on 2>&1)"
unowned_rc=$?
set -e
[[ "$unowned_rc" -ne 0 ]] && pass "unowned adapter file is protected" || fail "unowned adapter file is protected"
assert_contains "unowned adapter error is explicit" "unowned adapter file" "$unowned_error"
assert_contains "unowned adapter remains unchanged" "user plugin" "$(cat "$UNOWNED_HOME/.config/opencode/plugins/session-log.js")"

SYMLINK_HOME="$WORKROOT/symlink-home"
mkdir -p "$SYMLINK_HOME/.Trash" "$SYMLINK_HOME/.omp/agent/prompt-logs"
printf 'sentinel\n' > "$WORKROOT/sentinel"
ln -s "$WORKROOT/sentinel" "$SYMLINK_HOME/.omp/agent/prompt-logs/.enabled"
set +e
symlink_error="$(HOME="$SYMLINK_HOME" "$TEST_HOME/.omp/agent/skills/session-log/bin/session-log" --entrypoint omp --harness omp on 2>&1)"
symlink_rc=$?
set -e
[[ "$symlink_rc" -ne 0 ]] && pass "symlinked enable flag is protected" || fail "symlinked enable flag is protected"
assert_contains "symlinked flag error is explicit" "symlinked enable flag" "$symlink_error"
assert_contains "symlink target remains unchanged" "sentinel" "$(cat "$WORKROOT/sentinel")"

MIGRATION_SYMLINK_HOME="$WORKROOT/migration-symlink-home"
mkdir -p "$MIGRATION_SYMLINK_HOME/.Trash" "$MIGRATION_SYMLINK_HOME/.claude"
printf 'settings sentinel\n' > "$WORKROOT/settings-sentinel"
ln -s "$WORKROOT/settings-sentinel" "$MIGRATION_SYMLINK_HOME/.claude/settings.json"
set +e
migration_symlink_error="$(HOME="$MIGRATION_SYMLINK_HOME" bash "$REPO/skills/session-log/install.sh" --install --harness claude 2>&1)"
migration_symlink_rc=$?
set -e
[[ "$migration_symlink_rc" -ne 0 ]] && pass "symlinked migration settings fail safely" || fail "symlinked migration settings fail safely"
assert_contains "symlinked migration error is explicit" "symlinked Claude settings" "$migration_symlink_error"
assert_link "symlinked migration settings remain unchanged" "$WORKROOT/settings-sentinel" "$MIGRATION_SYMLINK_HOME/.claude/settings.json"
assert_contains "symlinked migration target remains unchanged" "settings sentinel" "$(cat "$WORKROOT/settings-sentinel")"
assert_not_file "symlinked migration has no partial package" "$MIGRATION_SYMLINK_HOME/.claude/skills/session-log/SKILL.md"


printf '=== migration removes only known legacy files and preserves settings ===\n'
LEGACY_HOME="$WORKROOT/legacy-home"
mkdir -p "$LEGACY_HOME/.Trash" "$LEGACY_HOME/.omp/agent/skills/session-log-omp/scripts" "$LEGACY_HOME/.omp/agent/extensions" "$LEGACY_HOME/.config/opencode/commands" "$LEGACY_HOME/.config/opencode/plugins" "$LEGACY_HOME/.config/opencode/scripts" "$LEGACY_HOME/.claude/scripts" "$LEGACY_HOME/.claude/skills/session-log"
printf '# universal-session-log: managed\nlegacy\n' > "$LEGACY_HOME/.omp/agent/skills/session-log-omp/SKILL.md"
printf '# universal-session-log: managed\nlegacy\n' > "$LEGACY_HOME/.omp/agent/extensions/session-log-omp.js"
printf '# universal-session-log: managed\nlegacy\n' > "$LEGACY_HOME/.config/opencode/commands/session-log-omp.md"
printf '# universal-session-log: managed\nlegacy\n' > "$LEGACY_HOME/.config/opencode/plugins/session-log-omp.js"
printf '# universal-session-log: managed\nlegacy\n' > "$LEGACY_HOME/.config/opencode/plugins/session-log.js"
printf '# universal-session-log: managed\nlegacy\n' > "$LEGACY_HOME/.config/opencode/scripts/session_log_usage.sh"
for legacy_script in prompt_log_save.sh prompt_log_new_session.sh prompt_log_stop.sh prompt_log_subagent.sh prompt_log_lib.sh prompt_log_usage.sh prompt_log_usage.jq prompt_log_prices.json; do

  printf '# universal-session-log: managed\nlegacy\n' > "$LEGACY_HOME/.claude/scripts/$legacy_script"
done

SELECTIVE_HOME="$WORKROOT/selective-migration-home"
mkdir -p "$SELECTIVE_HOME/.Trash" "$SELECTIVE_HOME/.config/opencode/plugins" \
  "$SELECTIVE_HOME/.claude/scripts" "$SELECTIVE_HOME/.omp/agent/extensions"
printf '# universal-session-log: managed\nlegacy OpenCode\n' > "$SELECTIVE_HOME/.config/opencode/plugins/session-log.js"
printf 'unselected Claude legacy\n' > "$SELECTIVE_HOME/.claude/scripts/prompt_log_save.sh"
printf 'unselected OMP legacy\n' > "$SELECTIVE_HOME/.omp/agent/extensions/session-log-omp.js"
HOME="$SELECTIVE_HOME" bash "$REPO/skills/session-log/install.sh" --install --harness opencode >/dev/null 2>&1
assert_not_file "selective migration removes selected OpenCode legacy" "$SELECTIVE_HOME/.config/opencode/plugins/session-log.js"
assert_file "selective migration preserves unselected Claude legacy" "$SELECTIVE_HOME/.claude/scripts/prompt_log_save.sh"
assert_file "selective migration preserves unselected OMP legacy" "$SELECTIVE_HOME/.omp/agent/extensions/session-log-omp.js"
printf '# universal-session-log: managed\nlegacy prompt_log_usage.sh command\n' > "$LEGACY_HOME/.claude/skills/session-log/SKILL.md"
printf '%s\n' "{\"hooks\":{\"SessionEnd\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"echo keep-me\"},{\"type\":\"command\",\"command\":\"bash $LEGACY_HOME/.claude/scripts/prompt_log_save.sh\"}]}]}}" > "$LEGACY_HOME/.claude/settings.json"
HOME="$LEGACY_HOME" bash "$INSTALL" >/dev/null 2>&1
assert_not_file "legacy OMP skill removed" "$LEGACY_HOME/.omp/agent/skills/session-log-omp/SKILL.md"
assert_not_file "legacy OMP extension removed" "$LEGACY_HOME/.omp/agent/extensions/session-log-omp.js"
assert_not_file "legacy OpenCode command removed" "$LEGACY_HOME/.config/opencode/commands/session-log-omp.md"
assert_not_file "legacy OpenCode plugin removed" "$LEGACY_HOME/.config/opencode/plugins/session-log-omp.js"
assert_not_file "legacy OpenCode standalone plugin removed" "$LEGACY_HOME/.config/opencode/plugins/session-log.js"
assert_not_file "legacy OpenCode standalone parser removed" "$LEGACY_HOME/.config/opencode/scripts/session_log_usage.sh"
assert_not_file "legacy Claude standalone scripts removed" "$LEGACY_HOME/.claude/scripts/prompt_log_save.sh"
assert_contains "unrelated settings preserved" "keep-me" "$(cat "$LEGACY_HOME/.claude/settings.json")"
assert_contains "legacy Claude skill replaced by managed entrypoint" "universal-session-log: managed" "$(cat "$LEGACY_HOME/.claude/skills/session-log/SKILL.md")"
assert_not_contains "known standalone hook removed" "$LEGACY_HOME/.claude/scripts/prompt_log_save.sh" "$(cat "$LEGACY_HOME/.claude/settings.json")"
UNOWNED_LEGACY_HOME="$WORKROOT/unowned-legacy-home"
mkdir -p "$UNOWNED_LEGACY_HOME/.Trash" "$UNOWNED_LEGACY_HOME/.config/opencode/plugins"
printf 'user plugin\n' > "$UNOWNED_LEGACY_HOME/.config/opencode/plugins/session-log.js"
set +e
unowned_legacy_error="$(HOME="$UNOWNED_LEGACY_HOME" bash "$INSTALL" 2>&1)"
unowned_legacy_rc=$?
set -e
[[ "$unowned_legacy_rc" -ne 0 ]] && pass "unowned legacy collision is protected" || fail "unowned legacy collision is protected"
assert_contains "unowned legacy error is explicit" "unowned legacy path" "$unowned_legacy_error"
assert_contains "unowned legacy file remains unchanged" "user plugin" "$(cat "$UNOWNED_LEGACY_HOME/.config/opencode/plugins/session-log.js")"
assert_not_file "unowned legacy collision leaves package absent" "$UNOWNED_LEGACY_HOME/.config/opencode/skills/session-log/SKILL.md"

HOOK_COLLISION_HOME="$WORKROOT/hook-collision-home"
mkdir -p "$HOOK_COLLISION_HOME/.Trash" "$HOOK_COLLISION_HOME/.claude"
printf '%s\n' '{"hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"echo prompt_log_save.sh"}]}]}}' > "$HOOK_COLLISION_HOME/.claude/settings.json"
HOME="$HOOK_COLLISION_HOME" bash "$INSTALL" >/dev/null 2>&1
assert_contains "unrelated hook text is preserved" "echo prompt_log_save.sh" "$(cat "$HOOK_COLLISION_HOME/.claude/settings.json")"


MALFORMED_HOME="$WORKROOT/malformed-home"
mkdir -p "$MALFORMED_HOME/.Trash" "$MALFORMED_HOME/.claude/scripts" "$MALFORMED_HOME/.claude"
printf 'legacy\n' > "$MALFORMED_HOME/.claude/scripts/prompt_log_save.sh"
printf '{not-json\n' > "$MALFORMED_HOME/.claude/settings.json"
set +e
malformed_error="$(HOME="$MALFORMED_HOME" bash "$INSTALL" 2>&1)"
malformed_rc=$?
set -e
[[ "$malformed_rc" -ne 0 ]] && pass "malformed settings fail before migration" || fail "malformed settings fail before migration"
assert_file "malformed settings preserve legacy files" "$MALFORMED_HOME/.claude/scripts/prompt_log_save.sh"
assert_contains "malformed settings error names JSON" "JSON" "$malformed_error"
assert_not_file "malformed settings leave package absent" "$MALFORMED_HOME/.claude/skills/session-log/SKILL.md"

printf '=== complete copied packages bootstrap locally ===\n'
PACKAGE_OPENCODE_HOME="$WORKROOT/package-opencode-home"
mkdir -p "$PACKAGE_OPENCODE_HOME/.Trash" "$PACKAGE_OPENCODE_HOME/.config/opencode/skills"
cp -R "$REPO/skills/session-log" "$PACKAGE_OPENCODE_HOME/.config/opencode/skills/session-log"
cp "$REPO/skills/session-log/templates/opencode/SKILL.md" "$PACKAGE_OPENCODE_HOME/.config/opencode/skills/session-log/SKILL.md"
PACKAGE_OPENCODE_ROOT="$(cd "$PACKAGE_OPENCODE_HOME/.config/opencode/skills/session-log" && pwd -P)"
package_opencode_on="$(HOME="$PACKAGE_OPENCODE_HOME" bash "$PACKAGE_OPENCODE_HOME/.config/opencode/skills/session-log/install.sh" --harness opencode --arguments on 2>&1)"
assert_contains "copied OpenCode package enables logging" "OpenCode: on — restart required" "$package_opencode_on"
assert_link "copied OpenCode package installs its plugin" \
  "$PACKAGE_OPENCODE_ROOT/adapters/opencode/session-log.js" \
  "$PACKAGE_OPENCODE_HOME/.config/opencode/plugins/session-log.js"
assert_not_file "copied OpenCode package does not need global wrapper" "$PACKAGE_OPENCODE_HOME/.local/bin/session-log"
package_opencode_seed="$(HOME="$PACKAGE_OPENCODE_HOME" bash "$PACKAGE_OPENCODE_ROOT/install.sh" --install --harness opencode 2>&1)"
assert_contains "copied v1 package seeds its v2 ownership manifest" \
  "Universal session-log installed for opencode" "$package_opencode_seed"
assert_file "copied v2 package writes its ownership manifest" \
  "$PACKAGE_OPENCODE_ROOT/.universal-session-log.manifest"
mv "$PACKAGE_OPENCODE_ROOT/.universal-session-log.manifest" "$WORKROOT/v1-package.manifest"
package_opencode_reinstall="$(HOME="$PACKAGE_OPENCODE_HOME" bash "$PACKAGE_OPENCODE_ROOT/install.sh" --install --harness opencode 2>&1)"
assert_contains "v1 copied package can reinstall into the v2 manifest format" \
  "Universal session-log installed for opencode" "$package_opencode_reinstall"
assert_file "v1-to-v2 reinstall recreates the ownership manifest" \
  "$PACKAGE_OPENCODE_ROOT/.universal-session-log.manifest"
printf 'tampered package asset\n' > "$PACKAGE_OPENCODE_ROOT/VERSION"
set +e
tampered_package="$(HOME="$PACKAGE_OPENCODE_HOME" bash "$PACKAGE_OPENCODE_ROOT/install.sh" --install --harness opencode 2>&1)"
tampered_package_rc=$?
set -e
[[ "$tampered_package_rc" -ne 0 ]] && pass "tampered copied package asset is rejected" || fail "tampered copied package asset is rejected"
assert_contains "tampered package rejection names the asset" "VERSION" "$tampered_package"


PACKAGE_OMP_HOME="$WORKROOT/package-omp-home"
mkdir -p "$PACKAGE_OMP_HOME/.Trash" "$PACKAGE_OMP_HOME/.omp/agent/skills"
cp -R "$REPO/skills/session-log" "$PACKAGE_OMP_HOME/.omp/agent/skills/session-log"
cp "$REPO/skills/session-log/templates/omp/SKILL.md" "$PACKAGE_OMP_HOME/.omp/agent/skills/session-log/SKILL.md"
PACKAGE_OMP_ROOT="$(cd "$PACKAGE_OMP_HOME/.omp/agent/skills/session-log" && pwd -P)"
package_omp_on="$(HOME="$PACKAGE_OMP_HOME" bash "$PACKAGE_OMP_HOME/.omp/agent/skills/session-log/install.sh" --harness omp --arguments on 2>&1)"
assert_contains "copied OMP package enables logging" "OMP: on — restart required" "$package_omp_on"
assert_link "copied OMP package installs its extension" \
  "$PACKAGE_OMP_ROOT/adapters/omp/session-log.js" \
  "$PACKAGE_OMP_HOME/.omp/agent/extensions/session-log.js"
PACKAGE_CLAUDE_HOME="$WORKROOT/package-claude-home"
mkdir -p "$PACKAGE_CLAUDE_HOME/.Trash" "$PACKAGE_CLAUDE_HOME/.claude/skills"
cp -R "$REPO/skills/session-log" "$PACKAGE_CLAUDE_HOME/.claude/skills/session-log"
package_claude_on="$(HOME="$PACKAGE_CLAUDE_HOME" bash "$PACKAGE_CLAUDE_HOME/.claude/skills/session-log/install.sh" --harness claude --arguments on 2>&1)"
assert_contains "copied Claude package enables logging" "Claude Code: on — restart required" "$package_claude_on"
assert_file "copied Claude package installs native hooks" "$PACKAGE_CLAUDE_HOME/.claude/settings.json"

PACKAGE_PLUGIN_HOME="$WORKROOT/package-plugin-home"
mkdir -p "$PACKAGE_PLUGIN_HOME/.Trash" "$PACKAGE_PLUGIN_HOME/plugin/skills"
cp -R "$REPO/skills/session-log" "$PACKAGE_PLUGIN_HOME/plugin/skills/session-log"
package_plugin_on="$(HOME="$PACKAGE_PLUGIN_HOME" CLAUDE_PLUGIN_ROOT="$PACKAGE_PLUGIN_HOME/plugin" bash "$PACKAGE_PLUGIN_HOME/plugin/skills/session-log/install.sh" --harness claude --arguments on 2>&1)"
assert_contains "marketplace package enables logging" "Claude Code: on — restart required" "$package_plugin_on"
assert_not_file "marketplace package does not rewrite settings" "$PACKAGE_PLUGIN_HOME/.claude/settings.json"
printf '%s\n' '{"session_id":"plugin-package-session","cwd":"'"$PWD"'"}' |
  HOME="$PACKAGE_PLUGIN_HOME" CLAUDE_PLUGIN_ROOT="$PACKAGE_PLUGIN_HOME/plugin" \
  bash "$PACKAGE_PLUGIN_HOME/plugin/skills/session-log/adapters/claude/claude_hook.sh" session-start >/dev/null
package_plugin_status="$(HOME="$PACKAGE_PLUGIN_HOME" CLAUDE_PLUGIN_ROOT="$PACKAGE_PLUGIN_HOME/plugin" bash "$PACKAGE_PLUGIN_HOME/plugin/skills/session-log/install.sh" --harness claude --arguments status 2>&1)"
assert_contains "marketplace package becomes loaded through plugin hook" "Claude Code: on" "$package_plugin_status"

printf '=== native reports keep their raw payload after one harness label ===\n'
set +e
claude_missing="$(run_harness claude usage --latest 2>&1)"
claude_missing_rc=$?
set -e
[[ "$claude_missing_rc" -ne 0 ]] && pass "missing Claude transcript fails directly" || fail "missing Claude transcript fails directly"
assert_contains "Claude usage names harness on failure" "Claude Code: usage" "$claude_missing"

CLAUDE_KEY="$(printf '%s' "$PWD" | sed 's|[/._]|-|g')"
CLAUDE_PROJECT="$TEST_HOME/.claude/projects/$CLAUDE_KEY"
mkdir -p "$CLAUDE_PROJECT"
printf '%s\n' '{"type":"user","timestamp":"2026-08-28T10:00:00.000Z","promptSource":"typed","isMeta":false,"message":{"role":"user","content":"hello"}}' > "$CLAUDE_PROJECT/universal.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-08-28T10:00:01.000Z","effort":"high","requestId":"req_1","message":{"id":"msg_1","model":"claude-haiku-4-5","role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0},"speed":"standard"}}}' >> "$CLAUDE_PROJECT/universal.jsonl"
claude_usage="$(run_harness claude usage --latest 2>&1)"
assert_contains "Claude usage keeps native session output" "session: " "$claude_usage"
assert_contains "Claude usage keeps native total output" "TOTAL" "$claude_usage"
mkdir -p "$CLAUDE_PROJECT/relative"
cp "$CLAUDE_PROJECT/universal.jsonl" "$CLAUDE_PROJECT/relative/transcript.jsonl"
relative_claude_usage="$(run_harness_at_home_and_dir "$TEST_HOME" "$CLAUDE_PROJECT" claude usage relative/transcript.jsonl 2>&1)"
assert_contains "Claude usage accepts one relative path with a slash" "session: relative/transcript.jsonl" "$relative_claude_usage"
assert_contains "relative Claude usage keeps native total output" "TOTAL" "$relative_claude_usage"

set +e
multiple_usage="$(run_harness claude usage --latest "$CLAUDE_PROJECT/universal.jsonl" 2>&1)"
multiple_usage_rc=$?
set -e
[[ "$multiple_usage_rc" -ne 0 ]] && pass "usage rejects multiple transcript targets" || fail "usage rejects multiple transcript targets"
assert_contains "multiple usage target error is explicit" "at most one session transcript target" "$multiple_usage"


mkdir -p "$OPENCODE_HOME/.local/share/opencode"
sqlite3 "$OPENCODE_HOME/.local/share/opencode/opencode.db" <<'SQL'
CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, time_updated INTEGER, time_created INTEGER, title TEXT);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
INSERT INTO session VALUES ('oc-session', NULL, 2, 1, 'fixture');
INSERT INTO message VALUES ('user-1', 'oc-session', 1, 1, '{"role":"user","time":{"created":1000}}');
INSERT INTO message VALUES ('assistant-1', 'oc-session', 2, 2, '{"role":"assistant","time":{"created":1000,"completed":3000},"tokens":{"input":1,"output":2,"reasoning":0,"cache":{"read":0,"write":0}},"cost":0.01,"modelID":"fixture-model"}');
INSERT INTO part VALUES ('part-1', 'assistant-1', 'oc-session', 2, 2, '{"type":"text","text":"done"}');
SQL
opencode_usage="$(run_harness_at_home "$OPENCODE_HOME" opencode usage --latest 2>&1)"
assert_contains "OpenCode usage names harness" "OpenCode: usage" "$opencode_usage"
assert_contains "OpenCode usage keeps native total output" "TOTAL" "$opencode_usage"

OPENCODE_FAILURE_HOME="$WORKROOT/opencode-failure-home"
mkdir -p "$OPENCODE_FAILURE_HOME/.Trash" "$OPENCODE_FAILURE_HOME/.local/share/opencode"
printf 'not a SQLite database\n' > "$OPENCODE_FAILURE_HOME/.local/share/opencode/opencode.db"
set +e
opencode_failure="$(run_harness_at_home "$OPENCODE_FAILURE_HOME" opencode usage --latest 2>&1)"
opencode_failure_rc=$?
set -e
[[ "$opencode_failure_rc" -ne 0 ]] && pass "OpenCode SQLite failure returns nonzero" || fail "OpenCode SQLite failure returns nonzero"
assert_contains "OpenCode SQLite failure is explicit" "native OpenCode usage failed" "$opencode_failure"
assert_not_contains "OpenCode SQLite failure does not report totals" "TOTAL" "$opencode_failure"
sqlite3 "$OPENCODE_HOME/.local/share/opencode/opencode.db" <<'SQL'
INSERT OR REPLACE INTO part VALUES ('event-main-1', 'event-main-1', 'event-root', 1, 1, '{"type":"text","text":"main response"}');
INSERT OR REPLACE INTO part VALUES ('event-main-2', 'event-main-2', 'event-root', 2, 2, '{"type":"text","text":"main response after child deletion"}');
SQL
opencode_event_output="$(
  HOME="$OPENCODE_HOME" SESSION_LOG_PLUGIN="$OPENCODE_HOME/.config/opencode/plugins/session-log.js" \
    bun --eval '
      const loaded = await import(process.env.SESSION_LOG_PLUGIN);
      const hooks = await loaded.SessionLogPlugin({ directory: "event-fixture" });
      const event = hooks.event;
      await hooks["chat.message"]({ sessionID: "event-root" }, { parts: [{ type: "text", text: "main prompt" }] });
      await event({ event: { type: "session.created", properties: { info: { id: "event-child", parentID: "event-root" } } } });
      const child = { id: "event-child-message", sessionID: "event-child", role: "assistant", mode: "Explore", time: { created: 1000, completed: 3000 }, tokens: { input: 1, output: 2 } };
      await event({ event: { type: "message.updated", properties: { info: child } } });
      await event({ event: { type: "message.updated", properties: { info: child } } });
      const first = { id: "event-main-1", sessionID: "event-root", role: "assistant", modelID: "fixture-model", mode: "standard", time: { created: 1000, completed: 4000 }, tokens: { input: 2, output: 3 } };
      await event({ event: { type: "message.updated", properties: { info: first } } });
      await event({ event: { type: "message.updated", properties: { info: first } } });
      await event({ event: { type: "session.deleted", properties: { info: { id: "event-child" } } } });
      const second = { id: "event-main-2", sessionID: "event-root", role: "assistant", modelID: "fixture-model", mode: "standard", time: { created: 5000, completed: 7000 }, tokens: { input: 2, output: 3 } };
      await event({ event: { type: "message.updated", properties: { info: second } } });
      await event({ event: { type: "message.updated", properties: { info: second } } });
      const fs = await import("node:fs");
      const files = fs.readdirSync(process.env.HOME + "/.config/opencode/prompt-logs/event-fixture").filter(name => name.endsWith(".md"));
      process.stdout.write(fs.readFileSync(process.env.HOME + "/.config/opencode/prompt-logs/event-fixture/" + files[0], "utf8"));
    ' 2>"$WORKROOT/opencode-event.err"
)"
assert_contains "OpenCode logs the main prompt event" "main prompt" "$opencode_event_output"
assert_contains "OpenCode logs the main response event" "main response" "$opencode_event_output"
assert_contains "OpenCode logs the child response event" "sub-agent finished: Explore (event-child)" "$opencode_event_output"
assert_contains "OpenCode keeps main logging after child deletion" "main response after child deletion" "$opencode_event_output"
assert_exact "OpenCode suppresses duplicate main events" "2" \
  "$(printf '%s\n' "$opencode_event_output" | grep -c '^### .* response$')"
assert_exact "OpenCode suppresses duplicate child events" "1" \
  "$(printf '%s\n' "$opencode_event_output" | grep -c 'sub-agent finished: Explore (event-child)')"

set +e
opencode_invalid_id="$(
  HOME="$OPENCODE_HOME" SESSION_LOG_PLUGIN="$OPENCODE_HOME/.config/opencode/plugins/session-log.js" \
    bun --eval '
      const loaded = await import(process.env.SESSION_LOG_PLUGIN);
      const hooks = await loaded.SessionLogPlugin({ directory: "event-fixture" });
      await hooks.event({ event: { type: "message.updated", properties: { info: { id: "escape", sessionID: "../outside", role: "assistant", time: { created: 1, completed: 2 } } } } });
    ' 2>&1
)"
opencode_invalid_id_rc=$?
set -e
[[ "$opencode_invalid_id_rc" -eq 0 ]] && pass "OpenCode ignores invalid session IDs safely" || fail "OpenCode ignores invalid session IDs safely"
assert_not_file "OpenCode invalid session ID creates no escaped log" "$OPENCODE_HOME/.config/opencode/prompt-logs/outside/session_escape.md"

OPENCODE_SAFE_HOME="$WORKROOT/opencode-safe-home"
mkdir -p "$OPENCODE_SAFE_HOME/.Trash" "$OPENCODE_SAFE_HOME/.config/opencode/skills"
cp -R "$REPO/skills/session-log" "$OPENCODE_SAFE_HOME/.config/opencode/skills/session-log"
mkdir -p "$OPENCODE_SAFE_HOME/.config/opencode/prompt-logs"
touch "$OPENCODE_SAFE_HOME/.config/opencode/prompt-logs/.enabled"
mkdir -p "$WORKROOT/opencode-outside"
printf 'opencode sentinel\n' > "$WORKROOT/opencode-outside/sentinel"
ln -s "$WORKROOT/opencode-outside" "$OPENCODE_SAFE_HOME/.config/opencode/prompt-logs/safe-fixture"
set +e
opencode_symlink_log="$(
  HOME="$OPENCODE_SAFE_HOME" SESSION_LOG_PLUGIN="$OPENCODE_SAFE_HOME/.config/opencode/skills/session-log/adapters/opencode/session-log.js" \
    bun --eval '
      const loaded = await import(process.env.SESSION_LOG_PLUGIN);
      const hooks = await loaded.SessionLogPlugin({ directory: "safe-fixture" });
      await hooks["chat.message"]({ sessionID: "safe-root" }, { parts: [{ type: "text", text: "must not escape" }] });
    ' 2>&1
)"
opencode_symlink_log_rc=$?
set -e
[[ "$opencode_symlink_log_rc" -ne 0 ]] && pass "OpenCode rejects symlinked log paths" || fail "OpenCode rejects symlinked log paths"
assert_exact "OpenCode symlinked log target remains unchanged" "opencode sentinel" "$(cat "$WORKROOT/opencode-outside/sentinel")"

mkdir -p "$OPENCODE_SAFE_HOME/.config/opencode/session-log"
if [[ -e "$OPENCODE_SAFE_HOME/.config/opencode/session-log/runtime.json" ||
      -L "$OPENCODE_SAFE_HOME/.config/opencode/session-log/runtime.json" ]]; then
  mv "$OPENCODE_SAFE_HOME/.config/opencode/session-log/runtime.json" "$WORKROOT/opencode-runtime-existing"
fi

printf 'runtime sentinel\n' > "$WORKROOT/opencode-runtime-sentinel"
ln -s "$WORKROOT/opencode-runtime-sentinel" "$OPENCODE_SAFE_HOME/.config/opencode/session-log/runtime.json"
set +e
opencode_symlink_runtime="$(
  HOME="$OPENCODE_SAFE_HOME" SESSION_LOG_PLUGIN="$OPENCODE_SAFE_HOME/.config/opencode/skills/session-log/adapters/opencode/session-log.js" \
    bun --eval 'const loaded = await import(process.env.SESSION_LOG_PLUGIN); await loaded.SessionLogPlugin({ directory: "runtime-fixture" });' 2>&1
)"
opencode_symlink_runtime_rc=$?
set -e
[[ "$opencode_symlink_runtime_rc" -ne 0 ]] && pass "OpenCode rejects symlinked runtime state" || fail "OpenCode rejects symlinked runtime state"
assert_exact "OpenCode symlinked runtime target remains unchanged" "runtime sentinel" "$(cat "$WORKROOT/opencode-runtime-sentinel")"


mkdir -p "$OMP_HOME/.omp/agent/sessions"
printf '{"type":"session","id":"omp-session","cwd":"%s","timestamp":"2026-08-28T10:00:00.000Z"}\n{"type":"message","message":{"role":"user","content":"hello","timestamp":"2026-08-28T10:00:00.000Z"}}\n{"type":"message","message":{"role":"assistant","model":"fixture-model","timestamp":"2026-08-28T10:00:01.000Z","completedAt":"2026-08-28T10:00:03.000Z","usage":{"input":1,"output":2,"reasoning":3,"cacheRead":4,"cacheWrite":5,"cost":{"total":0.01}}}}\n' "$PWD" > "$OMP_HOME/.omp/agent/sessions/omp-session.jsonl"
omp_usage="$(run_harness_at_home "$OMP_HOME" omp usage --latest 2>&1)"
assert_contains "OMP usage names harness" "OMP: usage" "$omp_usage"
assert_contains "OMP usage keeps native total output" "TOTAL" "$omp_usage"
assert_contains "OMP usage sums all token components when totalTokens is absent" "total_tokens: 15" "$omp_usage"
OMP_SAFE_HOME="$WORKROOT/omp-safe-home"
mkdir -p "$OMP_SAFE_HOME/.Trash" "$OMP_SAFE_HOME/.omp/agent/skills"
cp -R "$REPO/skills/session-log" "$OMP_SAFE_HOME/.omp/agent/skills/session-log"
mkdir -p "$OMP_SAFE_HOME/.omp/agent/prompt-logs" "$OMP_SAFE_HOME/.omp/agent/sessions"
touch "$OMP_SAFE_HOME/.omp/agent/prompt-logs/.enabled"
printf '{"type":"session","id":"omp-safe","cwd":"omp-safe-fixture"}\n' \
  > "$OMP_SAFE_HOME/.omp/agent/sessions/omp-safe.jsonl"
set +e
omp_invalid_id="$(
  HOME="$OMP_SAFE_HOME" OMP_SESSION_LOG_PLUGIN="$OMP_SAFE_HOME/.omp/agent/skills/session-log/adapters/omp/session-log.js" \
    bun --eval '
      const loaded = await import(process.env.OMP_SESSION_LOG_PLUGIN);
      const handlers = {};
      loaded.default({ registerCommand() {}, on(name, handler) { handlers[name] = handler; } });
      const ctx = { cwd: "omp-invalid-fixture", sessionManager: { getSessionFile: () => "omp-safe.jsonl", getSessionId: () => "../escape", getHeader: () => ({ cwd: "omp-invalid-fixture" }), getEntries: () => [] }, model: { id: "fixture" } };
      await handlers.before_agent_start({ prompt: "must not escape" }, ctx);
    ' 2>&1
)"
omp_invalid_id_rc=$?
set -e
[[ "$omp_invalid_id_rc" -eq 0 ]] && pass "OMP ignores invalid session IDs safely" || fail "OMP ignores invalid session IDs safely"
assert_not_file "OMP invalid session ID creates no log" "$OMP_SAFE_HOME/.omp/agent/prompt-logs/omp-invalid-fixture/session_unknown-session.md"
printf '{"type":"session","id":"omp-safe","cwd":"omp-symlink-fixture"}\n' \
  > "$OMP_SAFE_HOME/.omp/agent/sessions/omp-safe.jsonl"


mkdir -p "$WORKROOT/omp-outside"
printf 'omp sentinel\n' > "$WORKROOT/omp-outside/sentinel"
ln -s "$WORKROOT/omp-outside" "$OMP_SAFE_HOME/.omp/agent/prompt-logs/omp-symlink-fixture"
set +e
omp_symlink_log="$(
  HOME="$OMP_SAFE_HOME" OMP_SESSION_LOG_PLUGIN="$OMP_SAFE_HOME/.omp/agent/skills/session-log/adapters/omp/session-log.js" \
    bun --eval '
      const loaded = await import(process.env.OMP_SESSION_LOG_PLUGIN);
      const handlers = {};
      loaded.default({ registerCommand() {}, on(name, handler) { handlers[name] = handler; } });
      const ctx = { cwd: "omp-symlink-fixture", sessionManager: { getSessionFile: () => "omp-safe.jsonl", getSessionId: () => "omp-safe", getHeader: () => ({ cwd: "omp-symlink-fixture" }), getEntries: () => [] }, model: { id: "fixture" } };
      await handlers.before_agent_start({ prompt: "must not escape" }, ctx);
    ' 2>&1
)"
omp_symlink_log_rc=$?
set -e
[[ "$omp_symlink_log_rc" -ne 0 ]] && pass "OMP rejects symlinked log paths" || fail "OMP rejects symlinked log paths"
assert_exact "OMP symlinked log target remains unchanged" "omp sentinel" "$(cat "$WORKROOT/omp-outside/sentinel")"

mkdir -p "$OMP_SAFE_HOME/.omp/agent/session-log"
if [[ -e "$OMP_SAFE_HOME/.omp/agent/session-log/runtime.json" ||
      -L "$OMP_SAFE_HOME/.omp/agent/session-log/runtime.json" ]]; then
  mv "$OMP_SAFE_HOME/.omp/agent/session-log/runtime.json" "$WORKROOT/omp-runtime-existing"
fi

printf 'omp runtime sentinel\n' > "$WORKROOT/omp-runtime-sentinel"
ln -s "$WORKROOT/omp-runtime-sentinel" "$OMP_SAFE_HOME/.omp/agent/session-log/runtime.json"
set +e
omp_symlink_runtime="$(
  HOME="$OMP_SAFE_HOME" OMP_SESSION_LOG_PLUGIN="$OMP_SAFE_HOME/.omp/agent/skills/session-log/adapters/omp/session-log.js" \
    bun --eval 'const loaded = await import(process.env.OMP_SESSION_LOG_PLUGIN); loaded.default({ registerCommand() {}, on() {} });' 2>&1
)"
omp_symlink_runtime_rc=$?
set -e
[[ "$omp_symlink_runtime_rc" -ne 0 ]] && pass "OMP rejects symlinked runtime state" || fail "OMP rejects symlinked runtime state"
assert_exact "OMP symlinked runtime target remains unchanged" "omp runtime sentinel" "$(cat "$WORKROOT/omp-runtime-sentinel")"


set +e
omp_no_session="$(run_harness_at_home "$OMP_HOME" omp usage --no-session 2>&1)"
omp_no_session_rc=$?
set -e
[[ "$omp_no_session_rc" -ne 0 ]] && pass "OMP no-session usage fails directly" || fail "OMP no-session usage fails directly"
assert_contains "OMP no-session error explains missing reconstruction" "cannot be reconstructed" "$omp_no_session"

printf '\nResults: %s\n' "$([[ "$FAIL" -eq 0 ]] && echo passed || echo FAILED)"
exit "$FAIL"
