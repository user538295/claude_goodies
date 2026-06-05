# FEAT-001 — Skill, Command & Script HTML Handouts

**Purpose**: Generate per-tool quick-reference HTML pages so developers can look up what a skill/command/script does, when to trigger it, and see concrete examples — without reading raw Markdown source files.
**Audience**: Developers who have installed the Claude Code skill/command set and need to look up a specific tool mid-task.
**Status**: To Do

---

## Background

The only handout page currently is `en.html`, which documents the full 9-step agentic workflow pipeline. There is no quick-reference for individual skills, commands, or scripts. Users must open raw `SKILL.md` or command `.md` files, which are written for implementers, not consumers. This documentation debt is real: the skill library is mature, yet discoverability is poor.

## Goal

Every GitHub-tracked skill, command, and script group has its own HTML handout page. Each page follows the `en.html` visual identity, contains all 7 required template sections, and includes at minimum 2 concrete usage examples drawn from actual source content. The `index.html` is redesigned as a categorized directory. After this work, a developer can navigate to `handout/index.html`, click any tool, and know immediately whether it applies to their task and how to invoke it.

---

## Scope

### In Scope
- 2 shared CSS files: `styles.css` (shared primitives) and `card.css` (card layout)
- 6 skill handout pages: `skill-aaa.html`, `skill-documentation-standard.html`, `skill-llm-wiki.html`, `skill-llm-wiki-product.html`, `skill-plan-maker.html`, `skill-skill-packager.html`
- 5 command handout pages: `cmd-da-review.html`, `cmd-feature-refinement.html`, `cmd-implement-all.html`, `cmd-implement-next.html`, `cmd-iterative-review.html`
- 2 script group handout pages: `scripts-plan.html`, `scripts-logging.html` (Note: the GitHub-tracked filter applies to skills and commands. Script groups are included by explicit brief decision regardless of GitHub tracking status — scripts are invocation tools, not installable packages.)
- Updated `en.html` and `hu.html` to import `styles.css`
- Redesigned `index.html` with three categorized sections (Skills / Commands / Scripts) plus demoted workflow links
- Total: 13 new HTML files + 2 new CSS files + 3 updated files = 18 artifacts

### Out of Scope
- `e2e` and `test-coverage` commands (not on GitHub)
- 16 local-only skills (commit-context, commit-history, forget, gde-*, handoff, interju-generator, md-reviewer, ralph-tui-*, recall, recap, remember, session-history)
- Built-in Claude Code skills (init, review, security-review, etc.)
- Hungarian translations (deferred)
- Dark mode

---

## Acceptance Criteria

> Acceptance criteria are verified in the final task. See [Task 5.1 — Final verification & documentation update].

---

## What does NOT change
- `en.html` visual rendering at 1280×800 — must render without visible difference before and after `styles.css` extraction (verified by screenshot comparison or DevTools inspection)
- `hu.html` content and layout — only gains the `styles.css` import
- All pipeline-specific CSS (`.flow`, `.node`, `.detail`, `.control`, `.mode-btn`, grid layouts) stays inline in `en.html`
- Source Markdown files (`SKILL.md`, command `.md` files, scripts) — read-only for this feature

---

## Known limitations / accepted trade-offs
- The dependency diagram for `scripts-plan.html` may be implemented as a static table instead of an interactive SVG/Mermaid diagram; if deferred, it is noted in Future Iterations on that page.
- All examples are either drawn from actual source content or, if no examples exist in the source, are constructed illustrations labeled as such — never silently invented.
- `llm-wiki` and `llm-wiki-product` each get separate pages despite their similarity; the distinction (general-domain vs. product-team wikis) must be stated prominently at the top of each.

---

## Architecture

### New files
- `handout/styles.css` — shared CSS primitives: `:root` variable block, Google Fonts `@import`, `*` box-sizing reset, `body` base styles, `.badge` variants (MUST / SUGGESTED / OPTIONAL), `.brand` class, `.brand-row` class (needed by handout page headers)
- `handout/card.css` — card layout: single-column page structure, `max-width: 860px` centering, section separators (`<hr>`-based or heading-based), responsive rules at 375px and 1280px
- `handout/skill-*.html` (6 files) — each imports `styles.css` + `card.css`, contains 7-section template, 2+ examples, source HTML comment
- `handout/cmd-*.html` (5 files) — same structure
- `handout/scripts-plan.html`, `handout/scripts-logging.html` — same structure; `scripts-plan.html` additionally contains a dependency table or diagram

### Updated files
- `handout/en.html` — removes inline `:root`, fonts import, reset, body, badge, brand CSS; replaces with `<link rel="stylesheet" href="styles.css">`
- `handout/hu.html` — same `<link>` addition
- `handout/index.html` — rewritten as categorized directory (Skills / Commands / Scripts), card-style layout inline (does not import `card.css`), workflow handouts demoted to footer section

### Data flow
Each handout page is a static HTML file. No build system. Content is read from source `.md` files by the implementer and hand-authored into the HTML. The `<!-- Source: ... -->` comment in each file enables future drift detection.

Multi-source `<!-- Source: ... -->` comments use space-separated paths on one line, e.g., `<!-- Source: path/a.sh path/b.sh -->`. The `<!-- Source:` prefix is required on all HTML files including `index.html`.

### Per-page 7-section template structure
1. One-sentence summary
2. When to use / trigger phrases
3. Invocation syntax / parameters
4. Example 1 — full input → output
5. Example 2 — full input → output
6. Related tools (with working links to peer handout pages)
7. Footer link back to `index.html` and `en.html`

### Related-tools map (authoritative)
- `implement-next` ↔ `implement-all` ↔ `iterative-review`
- `da-review` ↔ `iterative-review`
- `plan-maker` ↔ `feature-refinement`
- `llm-wiki` ↔ `llm-wiki-product`
- `skill-packager` ↔ `documentation-standard`
- `scripts-plan` ↔ `implement-next`
- `aaa` ↔ `da-review` / `iterative-review`
- `scripts-logging` ↔ `en.html`
- Skills/commands with no obvious peer: list `en.html`

---

## Task breakdown

### Phase 1 — Shared CSS Foundation
> **Releasable**: after Task 1.2 — `en.html` and `hu.html` render identically at 1280px with external CSS; `styles.css` and `card.css` are ready to import.

#### Task 1.1 — Extract `styles.css` from `en.html`
- [x] **File**: `handout/styles.css`
- **Depends on**: nothing
- **Description**:
  - **Canonical source**: Use `en.html` as the ONLY canonical extraction source — not `hu.html`, not `index.html`.
  - **What IS extracted** into `styles.css` — in this exact order (CSS spec requires `@import` to be first): (1) Google Fonts `@import url(...)`, (2) `:root` variable block, (3) `*`/`*::before`/`*::after` box-sizing reset, (4) `html { scroll-behavior }`, (5) `body` base styles, (6) `.badge` variants (MUST / SUGGESTED / OPTIONAL color rules), (7) `.brand` class, (8) `.brand-row` class.
  - **IMPORTANT**: The `@import url(...)` rule MUST be the first line in `styles.css`. Placing any rule before `@import` (including `:root`) makes the `@import` invalid per CSS spec and silently drops the Google Fonts. Verbatim copy from `en.html` will produce the correct order if en.html's @import is at the top of its `<style>` block.
  - **Google Fonts `@import`**: Use the `en.html` @import verbatim — it loads the superset of font weights (Inter 400/500/600/700/800, JetBrains Mono 400/500/600). Do not merge or trim to match `index.html`'s subset.
  - **`.brand-row` inclusion**: `.brand-row` is needed by handout pages for their header layout and must be added to `styles.css`.
  - **`.brand` conflict note**: `index.html` currently defines `.brand` differently from `en.html` (no pill background). Since `index.html` is being fully redesigned in Task 5.1, it will adopt `en.html`'s `.brand` pill style. No class renaming is needed; the redesign resolves the conflict.
  - **`body` conflict note**: `index.html` currently uses `display: grid; place-items: center` on `body`. The extracted `styles.css` body rule (from `en.html`) does NOT include `display: grid`. The Task 5.1 redesign of `index.html` must add any layout-specific body overrides inline — `styles.css` provides the baseline (font, color, background, line-height, min-height) only.
  - **What is EXCLUDED** from `styles.css`: Do NOT extract `.wrap`, `.legend`, `.lg`, `.sw`, `.lang`, `h1` (element selector, not class), any `.flow`/`.node`/`.detail`/`.control`/`.mode-btn` rules, grid layouts. Additionally, ALL of the following stay inline in `en.html` even though they are not in the exclusion list above: `header {}` (element selector), `footer {}` (element selector), `.sub {}`, `h1 .accent {}`, `footer .principle {}`, `@media` queries, any `.da-*` class, any `.grid*`, `.panel`, `.cmd-*`, `.rule`, `.decision`, `.matrix`, `.mode-card`, `.detail-*`, `.flow-*`, `.node-*` families, and `@keyframes pop`. The rule is: ONLY rules explicitly listed in the inclusion list (items 1-8 above) are extracted. Everything else stays inline.
  - **Releasable**: `styles.css` exists and contains all shared primitives
- **Tests (TDD)**:
  **Structural pre-checks** (run before marking Task 1.1 complete):
  - `grep -c '@import.*fonts.googleapis' handout/styles.css` must output `1`
  - `grep -c ':root' handout/styles.css` must output `1` (exactly one `:root` block)
  - `grep -c 'box-sizing' handout/styles.css` must output at least `1`
  - `grep -c '\.badge' handout/styles.css` must output at least `1`
  - `grep -c '\.brand' handout/styles.css` must output at least `2` (`.brand` and `.brand-row`)
  - `grep -c '\.brand-row' handout/styles.css` must output `1`
  - `grep -c 'body' handout/styles.css` must output at least `1`
  - Verify `@import` appears on line 1 of `styles.css`: `head -1 handout/styles.css | grep -q '@import'` must succeed
  - Verify no hardcoded hex values outside `:root`: `grep -v ':root' handout/styles.css | grep -E '#[0-9a-fA-F]{3,6}' | grep -v '/\*'` should return empty (no hex colors in rule bodies). Note: if `en.html` contains hardcoded hex in extracted rules (e.g., `.badge.optional`), either (a) replace with the appropriate `var()` expression if the color matches an existing variable, or (b) document in Known limitations that the hardcoded value was preserved from `en.html` verbatim.
  - Checkpoint: open `en.html` in browser; font renders as Inter (not system-ui fallback) — confirms Google Fonts loaded

#### Task 1.2 — Update `en.html` and `hu.html` to import `styles.css`; verify visual parity
- [x] **File**: `handout/en.html`, `handout/hu.html`
- **Depends on**: Task 1.1
- **Description**:
  - In `en.html`: replace the extracted CSS rules with `<link rel="stylesheet" href="styles.css">` at the top of `<style>` (or as a `<link>` tag before `<style>`); remove only the extracted blocks — leave all pipeline-specific CSS in place
  - In `hu.html`: apply the same changes as `en.html` — remove the same extracted CSS blocks (`:root`, Google Fonts import, `*` reset, `body` base, `.badge`, `.brand`) and replace with `<link rel='stylesheet' href='styles.css'>`. `hu.html`'s pipeline-specific CSS stays inline (same as `en.html`). `hu.html` must not import `card.css`.
  - Add a `<!-- Source: handout/en.html (modified — styles extracted to styles.css) -->` comment near the top of `en.html` and `<!-- Source: handout/hu.html (modified — styles extracted to styles.css) -->` to `hu.html` so the grep pre-check passes.
  - Verify: `en.html` must render without visible difference at 1280×800 before and after this change
  - **Releasable**: after this task, the shared CSS system is live; all future handout pages can import `styles.css`
- **Tests (TDD)** — visual:
  - Unit: Pixel parity verification for `en.html`: Open `en.html` in a browser at exactly 1280×800 viewport (Chrome preferred), take a full-page screenshot before the edit and one after. Use ImageMagick `compare` or Playwright screenshot diff with 0px tolerance on the above-the-fold area (first 800px). If Playwright or ImageMagick is unavailable, use browser DevTools pixel inspector to manually spot-check header, badge colors, and body background at identical scroll positions. Any visible difference is a failure.
  - Unit: screenshot `hu.html` at 1280×800 before and after — confirm no visible difference (same method as `en.html`).
  - Checkpoint: open both files in browser and visually compare at 1280×800; confirm badge colors, font, header layout are unchanged

#### Task 1.3 — Create `card.css`
- [x] **File**: `handout/card.css`
- **Depends on**: Task 1.1
- **Description**:
  - Write `card.css` with these rules only (no overlap with `styles.css`):
    - `.card-page` wrapper: `max-width: 860px; margin: 0 auto; padding: 2rem 1.5rem 4rem;`
    - Section separators: `section + section { border-top: 1px solid var(--line); padding-top: 1.5rem; margin-top: 1.5rem; }`
    - Page header: `.page-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem; padding-bottom: 1rem; border-bottom: 1px dashed var(--line2); }`
    - Back link: `.back-link { font-size: 0.85rem; color: var(--muted); text-decoration: none; }` with hover underline
    - Responsive 375px: full-width single column, reduced padding
    - Responsive 1280px: centered at 860px (already default via max-width)
    - Code blocks: `pre, code { font-family: 'JetBrains Mono', monospace; font-size: 0.875rem; background: var(--bg-grid); padding: 0.2em 0.5em; border-radius: 4px; }`
    - Example blocks: `.example { background: var(--paper); border: 1px solid var(--line); border-radius: 8px; padding: 1.25rem; margin: 1rem 0; }`
    - Footer: `footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px dashed var(--line2); font-size: 0.85rem; color: var(--muted); }`
    - No grid, no multi-column
  - **Releasable**: `card.css` exists and provides all layout rules needed by handout pages
- **Tests (TDD)** — visual:
  - Unit: verify every `var(--X)` reference in `card.css` has a matching `--X:` definition in `styles.css`. Extract var references: `grep -oE 'var\(--[a-z0-9-]+\)' handout/card.css | sort -u`. For each, verify the variable name exists in `styles.css`: `grep -c -- '--line:' handout/styles.css` (etc.). Alternatively, open a test HTML page that imports both CSS files in a browser and use DevTools Computed pane to confirm no unresolved custom properties (shown as empty string or 'undefined').
  - Checkpoint: used in Task 2.1; confirm first handout page renders correctly at 375px and 1280px

#### Task 1.4 — Create `_template.html` skeleton
- [ ] **File**: `handout/_template.html`
- **Depends on**: Task 1.3
- **Description**:
  - Create a minimal HTML5 skeleton that all 13 handout pages must copy and fill in. The skeleton defines the exact HTML structure, class names, and section markers so pages are structurally uniform.
  - Each of the 7 required sections is represented by a `<section>` element with a `data-section` attribute (e.g., `data-section='1-summary'` through `data-section='7-footer'`). This defines what 'section' means for automated counting.
  - The 7 sections and the `<footer>` are structured as follows: sections 1-6 use `<section data-section='N-name'>` elements for the 6 content sections (summary, when-to-use, invocation, example-1, example-2, related-tools). Section 7 ('Footer link') is implemented as an HTML `<footer>` element — NOT a `<section>` tag — with `data-section='7-footer'` attribute, containing the back links to `index.html` and `en.html`. So `<footer data-section='7-footer'>` is the 7th element with a `data-section` attribute. The `grep -c 'data-section'` count of 7 must include this `<footer data-section='7-footer'>`.
  - Skeleton includes: `<!DOCTYPE html>`, `<html lang='en'>`, `<head>` with both `<link>` imports (`styles.css` then `card.css`), `<!-- Source: path/to/source.md -->` comment, `<body>` with `.card-page` wrapper, `.page-header` with back-to-index link, 7 `<section data-section='N-name'>` blocks, and `<footer>` with en.html link.
  - `<title>` element with placeholder: `<title>[Tool Name] — Claude Code Handout</title>`. Each handout task that copies the template MUST replace `[Tool Name]` with the actual tool name (e.g., `/aaa`, `/plan-maker`, `scripts-plan`).
  - `<meta name='viewport' content='width=device-width, initial-scale=1.0'>` in `<head>`, before the CSS `<link>` tags. This is required for the 375px responsive rules in `card.css` to activate on real mobile devices.
  - **Heading structure**: The page title (`<h1>`) appears in `.page-header`. Each of the 7 section headings (summary, when-to-use, invocation, example-1, example-2, related-tools, footer) uses `<h2>` as the section title. Content within a section may use `<h3>` for sub-headings. No section should skip heading levels.
  - **Releasable**: after this task, any handout task can copy `_template.html` and fill in the sections.
- **Tests (TDD)**:
  - Unit: `grep -c 'data-section' handout/_template.html` outputs `7`
  - Unit: file contains both `<link rel='stylesheet' href='styles.css'>` and `<link rel='stylesheet' href='card.css'>` in that order
  - Unit: file contains `<!-- Source:` comment
  - Unit: file contains `<title>` element with the expected placeholder: `grep -q '\[Tool Name\]' handout/_template.html` must succeed — the placeholder must be present in the template so downstream tasks know to replace it
  - Unit: file contains `<meta name='viewport'`
  - Unit: `<html lang='en'>` is present in the skeleton
  - Unit: `grep -c '<h1' handout/_template.html` outputs `1` (exactly one h1 per page)
  - Checkpoint: run `npx html-validate handout/_template.html` — zero errors

---

### Phase 2 — Skill Handout Pages
> **Releasable**: after each task — the individual skill handout page is complete and browsable. All 6 tasks in this phase are independent; any completed page is immediately usable.

#### Task 2.1 — `skill-aaa.html`
- [ ] **File**: `handout/skill-aaa.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `skills/aaa/SKILL.md` — read it fully before writing any HTML
  - HTML comment at top: `<!-- Source: skills/aaa/SKILL.md -->`
  - Import: `<link rel="stylesheet" href="styles.css">` and `<link rel="stylesheet" href="card.css">`
  - Populate all 7 template sections from source content; no invented factual claims
  - One-sentence summary drawn from the skill's opening description
  - Trigger phrases: exact phrases from SKILL.md's trigger section
  - Invocation: `/aaa` with parameter syntax as documented
  - Example 1 and Example 2: drawn from actual examples in SKILL.md, or constructed and labeled "Illustrative example" if none exist in source
  - Related tools: `da-review`, `iterative-review` (per related-tools map)
  - Footer: link to `index.html` and `en.html`
  - Back-to-index link in page header
  - **Releasable**: `skill-aaa.html` is complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — visual:
  - Unit: open at 375px — single-column, no overflow
  - Unit: open at 1280px — centered at 860px, all 7 sections visible
  - Unit: click "back to index" → `index.html` (file must exist; acceptable to verify link target is correct even if index.html is not yet redesigned)
  - Unit: click footer "en.html" link → resolves
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open `handout/skill-aaa.html` in browser; count 7 sections; count 2+ examples; verify no inline `:root` block

#### Task 2.2 — `skill-documentation-standard.html`
- [ ] **File**: `handout/skill-documentation-standard.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `skills/documentation-standard/SKILL.md`
  - HTML comment: `<!-- Source: skills/documentation-standard/SKILL.md -->`
  - All 7 sections populated from source; trigger phrases verbatim from SKILL.md
  - Related tools: `skill-packager` (per related-tools map)
  - Same structure and import pattern as Task 2.1
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; related link to `skill-skill-packager.html`

#### Task 2.3 — `skill-llm-wiki.html`
- [ ] **File**: `handout/skill-llm-wiki.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `skills/llm-wiki/SKILL.md`
  - HTML comment: `<!-- Source: skills/llm-wiki/SKILL.md -->`
  - **Critical distinction**: prominently state in the one-sentence summary and in the "When to use" section that `llm-wiki` maintains **general-domain** knowledge wikis, as distinct from `llm-wiki-product` which handles product-team wikis (features, roadmaps, decisions)
  - Related tools: `llm-wiki-product`
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: confirm the word "general" or "general-domain" appears in the summary or when-to-use section
  - Unit: confirm the phrases 'product-team' and 'product wikis' do NOT appear in the summary or when-to-use section — `skill-llm-wiki.html` must not describe itself as serving product-team use cases.
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; distinction from llm-wiki-product is clear

#### Task 2.4 — `skill-llm-wiki-product.html`
- [ ] **File**: `handout/skill-llm-wiki-product.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `skills/llm-wiki-product/SKILL.md` — if this file does not exist under that path, check `skills/llm-wiki/SKILL.md` for product variant documentation
  - HTML comment: `<!-- Source: skills/llm-wiki-product/SKILL.md -->`
  - **Critical distinction**: prominently state this covers **product-team** wikis (features, roadmaps, decisions), not general-domain knowledge
  - Related tools: `llm-wiki`
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: confirm "product" or "product-team" appears in summary or when-to-use
  - Unit: confirm the phrases 'general-domain' and 'general wiki' do NOT appear in the summary or when-to-use section — `skill-llm-wiki-product.html` must not describe itself as serving general-domain use cases.
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; distinction from llm-wiki is clear

#### Task 2.5 — `skill-plan-maker.html`
- [ ] **File**: `handout/skill-plan-maker.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `skills/plan-maker/SKILL.md`
  - HTML comment: `<!-- Source: skills/plan-maker/SKILL.md -->`
  - Note: `plan-maker` is partially described in `en.html` — handout must be self-contained but may include a cross-reference note pointing to `en.html` for workflow context
  - Related tools: `feature-refinement`
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; cross-reference to en.html present

#### Task 2.6 — `skill-skill-packager.html`
- [ ] **File**: `handout/skill-skill-packager.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `skills/skill-packager/SKILL.md`
  - HTML comment: `<!-- Source: skills/skill-packager/SKILL.md -->`
  - Related tools: `documentation-standard`
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; related link to `skill-documentation-standard.html`

---

### Phase 3 — Command Handout Pages
> **Releasable**: after each task — the individual command handout page is complete and browsable. All 5 tasks are independent.

#### Task 3.1 — `cmd-da-review.html`
- [ ] **File**: `handout/cmd-da-review.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `commands/da-review.md`
  - HTML comment: `<!-- Source: commands/da-review.md -->`
  - Note from brief: "Single-pass devil's advocate review. Finds flaws without auto-fixing."
  - Key distinction: `da-review` reviews but does not fix; `iterative-review` both reviews AND applies fixes in a loop. State this distinction in "When to use".
  - Related tools: `iterative-review`, `aaa` (per related-tools map: aaa ↔ da-review / iterative-review)
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; distinction from iterative-review is clear

#### Task 3.2 — `cmd-feature-refinement.html`
- [ ] **File**: `handout/cmd-feature-refinement.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `commands/feature-refinement.md`
  - HTML comment: `<!-- Source: commands/feature-refinement.md -->`
  - Note from brief: `feature-refinement` is partially described in `en.html` — handout is self-contained but may cross-reference `en.html`
  - Related tools: `plan-maker`
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples

#### Task 3.3 — `cmd-implement-all.html`
- [ ] **File**: `handout/cmd-implement-all.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `commands/implement-all.md`
  - HTML comment: `<!-- Source: commands/implement-all.md -->`
  - Key behavior: `implement-all` runs `/implement-next` repeatedly until every task in the plan is complete. State the delegation relationship clearly.
  - Related tools: `implement-next`, `iterative-review`
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; delegation to implement-next described

#### Task 3.4 — `cmd-implement-next.html`
- [ ] **File**: `handout/cmd-implement-next.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `commands/implement-next.md`
  - HTML comment: `<!-- Source: commands/implement-next.md -->`
  - Related tools: `implement-all`, `iterative-review`, `scripts-plan`
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; relationship to implement-all and scripts-plan noted

#### Task 3.5 — `cmd-iterative-review.html`
- [ ] **File**: `handout/cmd-iterative-review.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source: `commands/iterative-review.md`
  - HTML comment: `<!-- Source: commands/iterative-review.md -->`
  - Key behavior: spawns multiple DA agents in parallel, then fix agents; loops until no critical/major/moderate issues remain
  - Related tools: `da-review`, `implement-next`, `implement-all`, `aaa` (per related-tools map: aaa ↔ da-review / iterative-review)
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — same visual checklist as Task 2.1
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Checkpoint: open in browser; 7 sections; 2+ examples; loop behavior described

---

### Phase 4 — Script Group Handout Pages
> **Releasable**: after each task — the script group handout page is complete.

#### Task 4.1 — `scripts-plan.html`
- [ ] **File**: `handout/scripts-plan.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source files: `scripts/plan-progress.sh`, `scripts/count-uncompleted-tasks.sh`, `scripts/audit-plan-run.sh`, `scripts/verify-run-commits.sh`, `scripts/check-task-commit.sh` (user-invocable); `scripts/task_section.awk`, `scripts/progress-header-flat.template`, `scripts/progress-header-phased.template` (internal dependencies)
  - HTML comment: `<!-- Source: scripts/plan-progress.sh scripts/audit-plan-run.sh scripts/verify-run-commits.sh scripts/count-uncompleted-tasks.sh scripts/check-task-commit.sh -->`
  - **User-invocable scripts** (document at full depth with invocation syntax, parameters, and examples): `plan-progress.sh`, `count-uncompleted-tasks.sh`, `audit-plan-run.sh`, `verify-run-commits.sh`, `check-task-commit.sh`
  - **Internal dependencies** (mention only — what they are, called by whom, no full docs): `task_section.awk`, `progress-header-flat.template`, `progress-header-phased.template`
  - **Dependency table OR diagram**: include a visual element (HTML table preferred; SVG/Mermaid if feasible) that distinguishes user-invocable scripts from internal ones and shows which user scripts call which internal scripts. If the diagram is deferred, include a "Future Iterations" note on the page.
  - Also show: which hook or pipeline stage calls each script automatically (context column in the table)
  - Minimum 2 examples: one showing `audit-plan-run.sh` CLI invocation, one showing `plan-progress.sh` output
  - Ensure the dependency table uses `table-layout: fixed` with `overflow-wrap: break-word` or `word-break: break-word` on cells so long filenames like `progress-header-phased.template` wrap rather than overflow.
  - Related tools: `implement-next`
  - **Releasable**: page complete; dependency table present
- **Tests (TDD)** — visual:
  - Unit: dependency table at 375px — verify `document.documentElement.scrollWidth <= document.documentElement.clientWidth` using browser DevTools console at 375px viewport, or use Playwright: `await page.setViewportSize({ width: 375, height: 667 }); const noScroll = await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth); expect(noScroll).toBe(true);`
  - Unit: user-invocable and internal scripts are visually distinct (e.g., separate rows, badge, or color)
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Unit: verify all 5 user-invocable scripts are mentioned in the page body (outside the HTML comment): `grep -Ec 'plan-progress|audit-plan-run|verify-run-commits|count-uncompleted-tasks|check-task-commit' handout/scripts-plan.html` must output at least 5 (one per script).
  - Checkpoint: open in browser; 7 sections; table present; 2+ examples with real CLI syntax

#### Task 4.2 — `scripts-logging.html`
- [ ] **File**: `handout/scripts-logging.html`
- **Depends on**: Task 1.2, Task 1.3, Task 1.4
- **Description**:
  - Copy `_template.html` and fill in the sections.
  - Source files: `scripts/prompt_log_lib.sh`, `scripts/prompt_log_new_session.sh`, `scripts/prompt_log_save.sh`
  - HTML comment: `<!-- Source: scripts/prompt_log_lib.sh scripts/prompt_log_new_session.sh scripts/prompt_log_save.sh -->`
  - Document all three scripts: what each does, CLI invocation, which hook calls it automatically
  - Minimum 2 examples: one showing new session initialization, one showing save-log invocation
  - Related tools: `en.html` (logging hooks support the overall agentic workflow)
  - **Releasable**: page complete and correct; Related tools links may be forward references if peer pages haven't been built yet — all must resolve by Task 6.1.
- **Tests (TDD)** — visual:
  - Unit: open at 375px — single-column, no overflow
  - Unit: open at 1280px — centered at 860px, all 7 sections visible
  - Unit: click 'back to index' → `index.html` resolves
  - Unit: click footer 'en.html' link → resolves
  - Unit: verify each `href` in the Related tools section matches an expected filename from the authoritative related-tools map. If the target page does not yet exist, note the broken link as a known forward reference — do not fail the task, but log it. Broken forward references must all resolve by Task 6.1.
  - Unit: verify all 3 logging scripts are mentioned in the page body: `grep -Ec 'prompt_log_lib|prompt_log_new_session|prompt_log_save' handout/scripts-logging.html` must output at least `3`
  - Checkpoint: open in browser; 7 sections; 2+ examples; hook context explained for each script

---

### Phase 5 — Index Redesign

#### Task 5.1 — Redesign `index.html` as categorized directory
- [ ] **File**: `handout/index.html`
- **Depends on**: Task 1.2, Task 1.3 (CSS foundation). One-line descriptions are written directly from source files (`SKILL.md` / `commands/*.md` / scripts), not from the finished HTML pages. All 13 handout pages should ideally exist before this task runs, but the index can be drafted from source content and linked pages verified at checkpoint.
- **Description**:
  - Rewrite `index.html` as a categorized directory page with three sections: **Skills**, **Commands**, **Scripts**
  - Each section lists its handout pages with a one-line description (drawn from the page's own one-sentence summary)
  - Working links to all 13 handout pages
  - Workflow handout links (`en.html`, `hu.html`) demoted to a secondary section or footer — remain navigable
  - Layout: inline CSS (does NOT import `card.css` — its layout is unique); DOES import `styles.css`
  - HTML comment: `<!-- Source: directory — links to all 13 handout pages -->`
  - No `<link href="card.css">` on this page
  - **CSS custom properties**: The redesigned `index.html` must use CSS custom properties from `styles.css` for all colors, not hardcoded hex values. Use `var(--bg)` instead of `#f7f6f1`, `var(--ink)` instead of `#1a1a1f`, `var(--muted)` instead of `#797982`, `var(--line)` instead of `#d8d6cc`, `var(--ai)` instead of `#4f46e5`, etc. Do not re-declare hardcoded hex values in inline CSS.
  - **No inline `:root` block**: `index.html` must NOT define a `:root` block. All custom property values come from `styles.css`.
  - **`body` overrides**: The `styles.css` body rule (extracted from `en.html`) does NOT include `display: grid`, `place-items: center`, `padding`, or the `background` gradient at `rgba(0,0,0,0.03)`. The current `index.html` uses all four of these. The Task 5.1 redesign must make explicit decisions for each:
    - `display: grid; place-items: center`: Add inline if the redesign centers content vertically; otherwise omit.
    - `padding: 1.5rem` on body: Decide whether to keep (add inline) or remove (use `.card-page` or similar wrapper padding instead).
    - Background gradient opacity `rgba(0,0,0,0.03)` vs `styles.css`'s `rgba(0,0,0,0.025)`: Accept the styles.css baseline (0.025) or override inline with the 0.03 value if the difference is noticeable. Document the decision.
  - **Releasable**: after this task, the complete handout system is navigable from a single entry point
- **Tests (TDD)** — visual:
  - Unit: all 13 links resolve to existing files (check `href` values)
  - Unit: three section headings visible: Skills, Commands, Scripts
  - Unit: `en.html` and `hu.html` links present in secondary section or footer
  - Unit: renders correctly at 375px and 1280px
  - Unit: `grep -c 'card.css' handout/index.html` outputs `0` — index.html must NOT import card.css
  - Unit: `grep -c ':root' handout/index.html` outputs `0` — index.html must NOT define a :root block
  - Checkpoint: open in browser; count 3 sections; click every link; confirm none 404

---

### Phase 6 — Final Verification

#### Task 6.1 — Final verification & documentation update
- [ ] **File**: N/A (agent task)
- **Depends on**: Task 5.1 (all prior tasks)
- **Description**:
  - **Automated pre-checks (run before manual verification)**: Run all pre-checks from the `handout/` directory (e.g., `cd /Users/manczg/.claude/handout`). Replace `/path/to/handout` with the actual path. Execute the following shell commands:
    ```
    cd /path/to/handout && \
    grep -L 'styles.css' *.html              # must be empty — all 16 HTML files (plus _template.html) import styles.css
    grep -l 'card.css' en.html hu.html index.html  # must be empty — these 3 must NOT import card.css
    grep -L 'card.css' skill-*.html cmd-*.html scripts-*.html  # must be empty — all 13 import card.css
    grep -L '<!-- Source:' *.html            # must be empty — all files have source comment
    grep -l ':root' *.html                  # must be empty — no inline :root blocks
    grep -E -l 'max-width.*860|\.card-page|\.page-header|\.back-link' skill-*.html cmd-*.html scripts-*.html   # must be empty — no inline card layout rules
    # Check for hardcoded hex in styles.css rule bodies (outside :root):
    grep -v ':root' styles.css | grep -E '#[0-9a-fA-F]{3,6}' | grep -v '/\*'   # ideally empty; document any matches
    # Note: Any match is not a hard failure — the rule may have been copied verbatim from en.html. But each match should be justified: either the hex should be replaced with a CSS variable, or documented as an accepted exception.
    grep -L '<title>' skill-*.html cmd-*.html scripts-*.html   # must be empty — all pages have <title>
    grep -L 'viewport' skill-*.html cmd-*.html scripts-*.html  # must be empty — all pages have viewport meta
    # Verify no two pages share the same <title>:
    grep -h '<title>' skill-*.html cmd-*.html scripts-*.html | sort | uniq -d   # must be empty — all titles unique
    # Verify no unfilled title placeholders:
    grep -h '<title>' skill-*.html cmd-*.html scripts-*.html | grep -iE 'template|placeholder|\[Tool Name\]'   # must be empty — no unfilled placeholders
    # Verify all handout pages have lang="en":
    for f in skill-*.html cmd-*.html scripts-*.html; do grep -q 'lang="en"' "$f" || echo "FAIL lang: $f"; done   # must be empty — all handout pages use lang="en"
    ```
    CSS load order check: For each handout page, verify `styles.css` link appears before `card.css` link. Run:
    ```
    for f in skill-*.html cmd-*.html scripts-*.html; do sl=$(grep -n 'styles.css' $f | cut -d: -f1); cl=$(grep -n 'card.css' $f | cut -d: -f1); [ -n "$sl" ] && [ -n "$cl" ] && [ "$sl" -lt "$cl" ] || echo "FAIL: "$f; done
    ```
    Output must be empty (no FAIL lines).
    Example count check: verify each handout page has exactly 2 example sections:
    ```
    for f in skill-*.html cmd-*.html scripts-*.html; do
      count=$(grep -cE 'data-section=.4-example|data-section=.5-example' "$f" 2>/dev/null || echo 0)
      [ "$count" -ge 2 ] || echo "FAIL examples: $f (count=$count)"
    done   # must be empty — every handout page has at least 2 example sections
    ```
    - These checks are pass/fail and must all pass before manual verification begins.
  - **Source path existence check**: For each handout page, extract the path(s) from the `<!-- Source: ... -->` comment and verify each path resolves to an existing file relative to the project root (`/Users/manczg/.claude/`). Run:
    ```
    for f in skill-*.html cmd-*.html scripts-*.html; do
      paths=$(grep -o '<!-- Source: [^-][^>]*-->' "$f" | sed 's/<!-- Source: //' | sed 's/ -->//')
      for p in $paths; do
        [ -f "/Users/manczg/.claude/$p" ] || echo "MISSING: $f references $p"
      done
    done
    ```
    Output must be empty. Any MISSING line indicates a typo or wrong path in a source comment.
  - **HTML5 validity check**: Run `npx --yes html-validate handout/*.html` (installs html-validate on first run; no global install needed). All files must pass. Alternatively, curl each file to the W3C Nu validator: `curl -s -H 'Content-Type: text/html; charset=utf-8' --data-binary @skill-aaa.html 'https://validator.w3.org/nu/?out=text'` and confirm output contains 'The document validates' or zero errors. Fix any reported errors before proceeding.
  - Check that `styles.css` is imported by all 16 HTML files (en.html, hu.html, index.html, 13 handout pages)
  - Check that `card.css` is imported by all 13 handout pages and NOT by index.html, en.html, or hu.html
  - Check that no HTML file contains an inline `:root` variable block (all variables come from `styles.css`)
  - Check that every handout page has a `<!-- Source: ... -->` comment
  - Check that every handout page has exactly 7 sections populated — verified by `grep -c 'data-section' skill-aaa.html` (and repeat for each file) must output `7` for each. Run for each of the 13 handout pages only — do not count `_template.html` (it also outputs 7 but is not a published page).
  - Check that every handout page has 2+ examples
  - Check that all internal links (back-to-index, footer, related-tools) resolve to existing files
  - **Verify related-tools links**: for each of the 13 handout pages, verify the Related tools section contains exactly the peers listed in the authoritative related-tools map. Verify bidirectionality: for every `↔` pair in the map, confirm both pages link to each other. Note: all `↔` relationships require both directions EXCEPT `scripts-logging ↔ en.html`, which is one-way by design (en.html is a pre-existing page that is not a handout and is not modified to add a Related tools section). Reference list:
    - `skill-aaa.html` must link to: `cmd-da-review.html`, `cmd-iterative-review.html`
    - `skill-documentation-standard.html` must link to: `skill-skill-packager.html`
    - `skill-llm-wiki.html` must link to: `skill-llm-wiki-product.html`
    - `skill-llm-wiki-product.html` must link to: `skill-llm-wiki.html`
    - `skill-plan-maker.html` must link to: `cmd-feature-refinement.html`
    - `skill-skill-packager.html` must link to: `skill-documentation-standard.html`
    - `cmd-da-review.html` must link to: `cmd-iterative-review.html`, `skill-aaa.html`
    - `cmd-feature-refinement.html` must link to: `skill-plan-maker.html`
    - `cmd-implement-all.html` must link to: `cmd-implement-next.html`, `cmd-iterative-review.html`
    - `cmd-implement-next.html` must link to: `cmd-implement-all.html`, `cmd-iterative-review.html`, `scripts-plan.html`
    - `cmd-iterative-review.html` must link to: `cmd-da-review.html`, `cmd-implement-next.html`, `cmd-implement-all.html`, `skill-aaa.html`
    - `scripts-plan.html` must link to: `cmd-implement-next.html`
    - `scripts-logging.html` must link to: `en.html` (one-way link — `en.html` is not a handout page and cannot link back; this is the only intentional one-way entry in the related-tools map)
  - **Content accuracy**: Exclude `_template.html` from content accuracy and constructed-examples checks — it is a skeleton with placeholder content, not a published handout page. For every handout page, verify the one-sentence summary and at least one trigger phrase or invocation syntax are traceable to the corresponding source file. Open each source file (`skills/<name>/SKILL.md` or `commands/<name>.md` or the relevant script file) and grep for the key terms used in the HTML. This does not require reading every sentence — spot-check the summary and trigger phrases. Flag any handout page where the summary contradicts or cannot be located in the source.
  - **`scripts-plan.html` content check**: grep the body for each of the 5 user-invocable script names — all must appear at least once outside the `<!-- Source: -->` comment: `plan-progress.sh`, `audit-plan-run.sh`, `verify-run-commits.sh`, `count-uncompleted-tasks.sh`, `check-task-commit.sh`.
  - **`scripts-logging.html` content check**: grep the body for each of the 3 logging script names (`prompt_log_lib.sh`, `prompt_log_new_session.sh`, `prompt_log_save.sh`) — all must appear at least once outside the `<!-- Source: -->` comment.
  - **Constructed examples check**: For each handout page, grep the corresponding source file for the example content. If an example's key phrase does not appear in the source file (meaning it was constructed), verify the example block in the HTML contains the word 'illustrative' or 'constructed'. Run: for each page with potentially constructed examples, `grep -i 'illustrative\|constructed' <page>.html` must match at least once per constructed example.
  - Screenshot `en.html` at 1280×800 and confirm visual parity with pre-change state (no changed color, no layout shift, no font-weight change), verified by screenshot comparison or DevTools inspection.
  - Documentation to update if affected: `CLAUDE.md` (if it references handout/index.html), any README that mentions the handout folder structure
- **Releasable**: after this task, the full handout system is verified and ready to distribute.
- **Acceptance criteria** (must all pass):
  - [ ] Each HTML file passes `npx html-validate` or equivalent W3C Nu validator check with zero errors
  - [ ] All 7 required template sections are populated with content drawn from actual `SKILL.md` or command `.md` source files — no invented text (constructed illustrative examples are permitted only when labeled)
  - [ ] Each page renders correctly at both 1280px and 375px viewport widths
  - [ ] Every internal link works — verified by clicking each link and confirming the file exists and contains the expected tool name: "back to index" → `index.html`; footer → `en.html`; related-tool links → correct peer handout page (per the authoritative related-tools map in the Architecture section)
  - [ ] Minimum 2 examples per page, each showing a complete input→output or trigger→result scenario — verified by `grep -cE 'data-section=.4-example|data-section=.5-example'` >= 2 per page
  - [ ] `handout/styles.css` exists and is imported by all 16 HTML files; no HTML file duplicates the `:root` variable block inline
  - [ ] `handout/card.css` exists and is imported by all 13 new handout pages; no handout page duplicates card layout rules inline — verified by the `grep -E -l 'max-width.*860|\.card-page|\.page-header'` automated check
  - [ ] `en.html` renders without visible difference at 1280×800 before and after extraction, verified by screenshot comparison or DevTools inspection; no changed color, no layout shift, no font-weight change
  - [ ] `hu.html` renders without visible difference before and after the `styles.css` import addition, verified by screenshot comparison
  - [ ] `scripts-plan.html` contains either (a) a visual dependency diagram (SVG or Mermaid) or (b) a table distinguishing user-invocable scripts from internal dependencies; if diagram was deferred, a Future Iterations note is present on the page
  - [ ] Each HTML file contains a `<!-- Source: ... -->` comment identifying its authoritative source file
  - [ ] `index.html` presents three categorized sections (Skills, Commands, Scripts) with one-line descriptions for each entry
  - [ ] `index.html` contains working links to all 13 handout pages
- **Tests (TDD)**: N/A — this is a verification and documentation task.
- **Checkpoint**: manually confirm every acceptance criterion above is checked.
