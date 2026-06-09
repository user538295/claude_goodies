# Update this file when command output format changes significantly

Output assets/demo.gif
Set Shell "zsh"
Set Theme "Dracula"
Set Width 1000
Set Height 600
Set FontSize 14
Set TypingSpeed 40ms

# ---------------------------------------------------------------------------
# Title card: Act 1
# ---------------------------------------------------------------------------
Hide
Type "clear"
Enter
Sleep 200ms
Type 'echo ""'
Enter
Type 'echo "  1 / Refine the idea"'
Enter
Show
Sleep 3s

# ---------------------------------------------------------------------------
# Act 1 — "1 / Refine the idea" (~16s)
# ---------------------------------------------------------------------------
Hide
Type "clear"
Enter
Sleep 200ms
Show

Set TypingSpeed 40ms
Type 'echo "❯ /feature-refinement Add dark mode toggle to the settings page"'
Enter
Sleep 300ms

Set TypingSpeed 0ms
Type 'echo ""'
Enter
Type 'echo "Investigating the codebase before we start..."'
Enter
Type 'echo ""'
Enter
Type 'echo "Found:"'
Enter
Type 'echo "• SettingsPage.tsx renders a flat list — no toggle components yet"'
Enter
Type 'echo "• No existing theme or body-class mechanism in the codebase"'
Enter
Type 'echo "• localStorage already used for other prefs (language, timezone)"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "> **Scope boundary**"'
Enter
Type 'echo "> - **Option A: Desktop only** — Pro: ships faster, scoped CSS. Con: inconsistent on mobile."'
Enter
Type 'echo "> - **Option B: Desktop + mobile** — Pro: consistent UX. Con: doubles CSS surface area."'
Enter
Type 'echo "> - **Recommendation**: Option A — ship desktop now, mobile in a follow-up."'
Enter
Type 'echo ""'
Enter
Type 'echo "Should dark mode persist across sessions?"'
Enter
Type 'echo "- **Option A: localStorage** — Pro: matches existing prefs pattern, zero extra infra. Con: lost if user clears storage."'
Enter
Type 'echo "- **Option B: Server-side user profile** — Pro: persists across devices. Con: overkill for a UI-only toggle."'
Enter
Type 'echo "- **Option C: Session only** — Pro: simplest to implement. Con: resets every visit, poor UX."'
Enter
Type 'echo "- **Recommendation**: Option A — localStorage already used for prefs; consistent with existing patterns."'
Enter
Sleep 500ms

Set TypingSpeed 40ms
Type 'echo "❯ Option A for both"'
Enter
Sleep 500ms

Set TypingSpeed 0ms
Type 'echo ""'
Enter
Type 'echo "Feature Brief saved → Documentation/Backlog/dark-mode-toggle-brief.md"'
Enter
Type 'echo ""'
Enter
Type 'echo "Run /plan-maker Documentation/Backlog/dark-mode-toggle-brief.md to turn this into an implementation plan."'
Enter
Sleep 2s

# ---------------------------------------------------------------------------
# Title card: Act 2
# ---------------------------------------------------------------------------
Hide
Type "clear"
Enter
Sleep 200ms
Type 'echo ""'
Enter
Type 'echo "  2 / Build the plan"'
Enter
Show
Sleep 3s

# ---------------------------------------------------------------------------
# Act 2 — "2 / Build the plan" (~14s)
# ---------------------------------------------------------------------------
Hide
Type "clear"
Enter
Sleep 200ms
Show

Set TypingSpeed 40ms
Type 'echo "❯ /plan-maker Documentation/Backlog/dark-mode-toggle-brief.md"'
Enter
Sleep 300ms

Set TypingSpeed 0ms
Type 'echo ""'
Enter
Type 'echo "# FEAT-042 — Dark Mode Toggle"'
Enter
Type 'echo "**Purpose**: Persistent dark/light toggle on the desktop Settings page"'
Enter
Type 'echo "**Audience**: Desktop users"'
Enter
Type 'echo "**Status**: To Do"'
Enter
Type 'echo ""'
Enter
Type 'echo "## Background"'
Enter
Type 'echo "..."'
Enter
Type 'echo ""'
Enter
Type 'echo "---"'
Enter
Type 'echo ""'
Enter
Type 'echo "## Goal"'
Enter
Type 'echo "..."'
Enter
Type 'echo ""'
Enter
Type 'echo "## Scope"'
Enter
Type 'echo ""'
Enter
Type 'echo "### In Scope"'
Enter
Type 'echo "..."'
Enter
Type 'echo ""'
Enter
Type 'echo "### Out of Scope"'
Enter
Type 'echo "..."'
Enter
Type 'echo ""'
Enter
Type 'echo "---"'
Enter
Type 'echo ""'
Enter
Type 'echo "## Acceptance criteria"'
Enter
Type 'echo "..."'
Enter
Type 'echo ""'
Enter
Type 'echo "## Architecture"'
Enter
Type 'echo "..."'
Enter
Type 'echo ""'
Enter
Type 'echo "---"'
Enter
Type 'echo ""'
Enter
Type 'echo "## Task breakdown"'
Enter
Type 'echo ""'
Enter
Type 'echo "### Phase 1 — Core toggle"'
Enter
Type 'echo "> **Releasable**: after Task 1.2 — toggle visible and functional on Settings page"'
Enter
Type 'echo ""'
Enter
Type 'echo "#### Task 1.1 — darkMode state in SettingsStore"'
Enter
Type 'echo "- [ ] **File**: \`src/settings/SettingsStore.ts\`"'
Enter
Type 'echo "#### Task 1.2 — Toggle component on SettingsPage"'
Enter
Type 'echo "- [ ] **File**: \`src/settings/SettingsPage.tsx\`"'
Enter
Type 'echo "#### Task 1.3 — Apply body CSS class"'
Enter
Type 'echo "- [ ] **File**: \`src/settings/theme.ts\`"'
Enter
Type 'echo ""'
Enter
Type 'echo "### Final Phase — Verification & Documentation"'
Enter
Type 'echo "#### Task 2.1 — Final verification & documentation update"'
Enter
Type 'echo "- [ ] **File**: N/A (agent task)"'
Enter
Sleep 500ms
Type 'echo ""'
Enter
Type 'echo "Plan saved → plans/FEAT-042-dark-mode.md"'
Enter
Sleep 1s

# ---------------------------------------------------------------------------
# Title card: Act 3
# ---------------------------------------------------------------------------
Hide
Type "clear"
Enter
Sleep 200ms
Type 'echo ""'
Enter
Type 'echo "  3 / Ship the task"'
Enter
Show
Sleep 3s

# ---------------------------------------------------------------------------
# Act 3 — "3 / Ship the task" (~15s)
# ---------------------------------------------------------------------------
Hide
Type "clear"
Enter
Sleep 200ms
Show

Set TypingSpeed 40ms
Type 'echo "❯ /implement-next plans/FEAT-042-dark-mode.md"'
Enter
Sleep 300ms

Set TypingSpeed 0ms
Type 'echo ""'
Enter
Type 'echo "Progress   : [░░░░░░░░░░░░] 0%  (0/4 tasks, 0/2 phases)"'
Enter
Type 'echo "Next task  : 1.1  **File**: \`src/settings/SettingsStore.ts\`"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "Writing tests first..."'
Enter
Type 'echo "→ tests/settings/SettingsStore.test.ts  ✓ created"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "Running tests (red)..."'
Enter
Type 'echo "FAIL  2 tests failed — expected (TDD red phase)"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "Implementing..."'
Enter
Type 'echo "→ src/settings/SettingsStore.ts  ✓ updated"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "Running tests (green)..."'
Enter
Type 'echo "PASS  2 passed in 0.3s"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "Running iterative review (3 agents in parallel)..."'
Enter
Type 'echo "→ No critical or major issues found"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "Running full test suite..."'
Enter
Type 'echo "PASS  47 passed in 1.2s"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "Updating plan..."'
Enter
Type 'echo "→ Task 1.1 checked off in plans/FEAT-042-dark-mode.md"'
Enter
Sleep 300ms

Type 'echo ""'
Enter
Type 'echo "3 files changed, 32 insertions(+), 1 deletion(-)"'
Enter
Type 'echo "[main a3f7c12] feat(dark-mode): add darkMode state to SettingsStore"'
Enter
Sleep 500ms

Type 'echo ""'
Enter
Type 'echo "Implemented: darkMode state + toggleDarkMode() in SettingsStore"'
Enter
Type 'echo "Tests: 2 new passing (47 total)"'
Enter
Type 'echo "Checked off: Task 1.1"'
Enter
Type 'echo "Deviations: none"'
Enter
Type 'echo "DA oscillations: none"'
Enter
Sleep 3s
