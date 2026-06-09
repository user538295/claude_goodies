# Demo Shot Script — Claude Goodies

**Purpose**: Source of truth for the `demo.tape` author.  
**GIF target duration**: ~40s total (Act 1: ~10s, Act 2: ~5s, Act 3: ~15s; title cards: ~3s each)

---

## Act 1 — "1 / Refine the idea" (~10s)

**Title card**: `  1 / Refine the idea`

**User prompt:**
```
/feature-refinement Add dark mode toggle to the settings page
```

**Claude response (Q&A):**
```
Claude: Should dark mode apply to mobile views as well, or desktop only?

User: desktop only for now

Claude:
  Brief summary:
  • Add a dark/light toggle to the desktop Settings page
  • Applies CSS class on <body>; persists via localStorage
  • Mobile views are out of scope for this iteration
```

---

## Act 2 — "2 / Build the plan" (~5s)

**Title card**: `  2 / Build the plan`

**User prompt:**
```
/plan-maker
```

**Claude response (task list scrolling in):**
```
  [ ] Task 1 — Add darkMode state to SettingsStore
  [ ] Task 2 — Wire toggle component to SettingsPage
  [ ] Task 3 — Apply body class and persist to localStorage
  [ ] Task 4 — Write unit tests for toggle logic
  [ ] Task 5 — Update CLAUDE.md with new setting key

  Plan saved → plans/FEAT-042-dark-mode.md
```

---

## Act 3 — "3 / Ship the task" (~15s)

**Title card**: `  3 / Ship the task`

**User prompt:**
```
/implement-next plans/FEAT-042-dark-mode.md
```

**Claude response (implementation sequence):**
```
  Writing tests first...
  → tests/settings/darkModeToggle.test.ts  ✓ created

  Running tests (red)...
  FAIL  3 tests failed — expected (TDD red phase)

  Implementing toggle logic...
  → src/settings/SettingsStore.ts  ✓ updated
  → src/settings/SettingsPage.tsx  ✓ updated

  Running tests (green)...
  PASS  3 passed in 0.4s

  2 files changed, 47 insertions(+), 3 deletions(-)
  [main a3f7c12] feat(dark-mode): add toggle to settings
```
