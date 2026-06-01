---
name: llm-wiki
description: >
  Set up or operate a product-oriented LLM Wiki (Karpathy pattern) in any project.
  Use when the user asks to "set up an LLM wiki", "create a product wiki", "apply the Karpathy
  wiki pattern", "ingest into the wiki", "draft a spec from the wiki", "create a feature page",
  "lint the wiki", or any task that involves the `llm-wiki/` directory with `raw/`, `wiki/`,
  `drafts/` layers. Also triggers when the user mentions building a persistent, LLM-maintained
  knowledge base from product docs, specs, source-code notes, and competitor documents.
---

# LLM Wiki (Product Edition)

Applies Andrej Karpathy's LLM Wiki pattern to a product team. The wiki is a persistent,
LLM-maintained markdown knowledge base that sits between raw sources (product docs, specs, code
notes, competitor docs) and the people who need answers or want to draft new specs.

The pattern stays minimal. **No automation, no agents, no RAG, no vector DBs, no graph DBs, no
eval systems, no governance.** Just markdown files, an index, and a log.

The full original idea is in `reference/karpathy-llm-wiki.md` — read it if context is missing.

## Scope vs. other skills

This skill governs everything **inside `llm-wiki/`**. Project documentation that lives outside
`llm-wiki/` (e.g. `Documentation/`, `docs/`, `README.md`) belongs to other skills such as
`documentation-standard`. The wiki references those external docs as sources via the mapping
table in `schema.md`, but does not own them.

**Single declared exception:** the skill maintains a short HTML-comment-anchored *pointer
block* in `CLAUDE.md` and/or `AGENTS.md` at the repo root so future agents discover the wiki.
Insertion and removal happen only with explicit user confirmation (see Step 1c). All structural
detail lives in `llm-wiki/schema.md`; the pointer block is a stable stub that does not change
when `schema.md` evolves. No other mutations to those files are permitted by this skill.

**Non-goals.** This skill assumes the wiki lives at `llm-wiki/` directly under the repo root.
Relocating the wiki (e.g. `docs/llm-wiki/`, per-package wikis in a monorepo) is explicitly out
of scope — if you need that, fork the skill and parameterise the paths. Half-supporting it
would produce subtle path mismatches across `CLAUDE.md`, `schema.md`, and the pointer block.

---

## When to set up vs. operate

- **No `llm-wiki/` directory exists** → run **Setup** (Step 1).
- **`llm-wiki/` exists and is complete** (contains `schema.md` and the full layer tree) → run
  the requested **Operation** (Step 2).
- **`llm-wiki/` exists but is incomplete** (partial setup) → run **Repair** (Step 1b).

Use `ls llm-wiki/` and check for `schema.md`, `index.md`, `log.md`, `raw/`, `wiki/`, `drafts/`
before deciding.

---

## Step 1 — Setup (first time in a project)

Create exactly this structure at the repo root:

```
llm-wiki/
  karpathy-llm-wiki.md   ← copy from skill's reference/
  schema.md              ← from templates/schema.md, adapted to project
  index.md               ← from templates/index.md
  log.md                 ← from templates/log.md  (bookkeeping; not part of the original Karpathy
                            ask but part of the Karpathy pattern — keep)
  raw/
    product-docs/
    specs/
    code-notes/
    competitor-docs/
  wiki/
    overview.md          ← from templates/overview.md
    glossary.md          ← from templates/glossary.md
    features/
    decisions/
  drafts/
    specs/
```

The skill itself lives at one of these paths (resolve at runtime by checking which exists):

1. `~/.claude/skills/llm-wiki/` — user-level install (most common)
2. `<repo>/.claude/skills/llm-wiki/` — project-level install

Use `ls ~/.claude/skills/llm-wiki/SKILL.md` to confirm the user-level path; fall back to the
project-level path otherwise. Call the resolved root `<SKILL_ROOT>` below.

Steps:

1. Verify `llm-wiki/` does not already exist. If it does, switch to **Step 1b (Repair)**.
2. Create the directories above.
3. Copy `<SKILL_ROOT>/reference/karpathy-llm-wiki.md` into `llm-wiki/karpathy-llm-wiki.md`.
4. Copy each file from `<SKILL_ROOT>/templates/` into the matching location.
5. **Adapt `llm-wiki/schema.md` to the project — MANDATORY:**
   - Detect existing documentation roots (e.g. `Documentation/`, `docs/`, `specs/`,
     `adr/`, `rfcs/`).
   - **Replace the HTML comment block** in the "Existing project documentation" section with a
     real table. Do not leave the comment in place — it must be substituted, not appended.
   - Mapping rules:
     | Source type | Map to | Evidence level |
     |---|---|---|
     | Architecture/design docs, ADRs/RFCs | `raw/product-docs/` | Strong |
     | Shipped/completed feature specs | `raw/specs/` | Strong |
     | Testing strategy docs | `raw/product-docs/` | Supporting |
     | Backlog/planned-work folders | `drafts/specs/` | **Weak (never cite as current behavior)** |
   - If no external docs exist, replace the comment with: `_No external documentation roots
     detected. All sources will live under `raw/`._`
6. Append the init entry to `llm-wiki/log.md`:
   `## [YYYY-MM-DD] init | wiki created | schema.md, index.md, wiki/overview.md, wiki/glossary.md`
7. Tell the user what was created and the next recommended operation (usually: ingest the most
   authoritative docs first).
8. **Offer Pointer Injection.** Run Step 1c — it will detect `CLAUDE.md`/`AGENTS.md`, show the
   exact block to be inserted, and only mutate after explicit user confirmation. If the user
   declines, log the skip and stop.

Do **not** ingest anything during setup unless the user explicitly asks.

### Step 1b — Repair (partial wiki exists)

1. List what exists vs. the canonical layout above.
2. Show the user the diff. Ask: "Fill in missing pieces, or wipe and restart?"
3. On "fill in": create only the missing directories/files, leaving existing files untouched.
   For `schema.md`, classify it:
   - **Missing** → create from template and adapt (run Setup step 5).
   - **Contains the unmodified template HTML comment** in the "Existing project documentation"
     section → adapt (run Setup step 5).
   - **Adapted (well-formed markdown table follows the heading)** → leave as-is.
   - **Half-adapted** (the HTML comment is gone but the section has no table, or has a table
     missing the `| Path | Treat as | Evidence level |` header row, or has rows whose `Treat
     as` column does not match `raw/...` or `drafts/...`) → **do not auto-adapt**. Surface
     this as a finding to the user and ask for manual resolution. Silently rewriting a
     half-adapted schema risks discarding human work.
4. **Non-mutating pointer check.** Run Step 1c's *Detect-only phase D* (D1–D3): if any
   pointer-eligible file exists without a marker, surface this to the user as a finding
   ("`CLAUDE.md` has no llm-wiki pointer — run pointer injection separately if desired?"). Do
   not mutate anything during repair without an explicit second confirmation.
5. On "wipe": confirm again, then `rm -rf llm-wiki/` and run Step 1.

### Step 1c — Pointer Injection (CLAUDE.md / AGENTS.md)

Goal: make sure future agents discover `llm-wiki/` and the skill. **Never executes a mutation
without explicit user confirmation.**

**Repo-root resolution.** Assign once at the start of the procedure:

```bash
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$(pwd)"
```

If `git rev-parse` failed, tell the user the project is not a git repo and that
case-insensitive name resolution will fall back to `ls`.

**Detect-only phase D** (no writes — safe to run from Repair via Step 1b.4):

- **D1.** Resolve which of `CLAUDE.md` / `AGENTS.md` exist at `$ROOT` using their tracked
  casing. In a git repo:

  ```bash
  git -C "$ROOT" ls-files | grep -iE '^(CLAUDE|AGENTS)\.md$'
  ```

  Outside git, fall back to:

  ```bash
  (cd "$ROOT" && ls 2>/dev/null | grep -iE '^(CLAUDE|AGENTS)\.md$')
  ```

  Use the exact string the command returns — never write to a name with different casing on
  case-insensitive filesystems (macOS/Windows), or you may create a duplicate file under
  case-sensitive CI.
- **D2.** **Never create either file** if it does not exist (this is a Hard Rule — see
  below). If neither exists, tell the user and stop.
- **D3.** For each existing file, check for the anchor marker and capture the detected
  version. **Pre-strip CR characters so CRLF-terminated files match correctly** (otherwise
  the trailing `-->\r` defeats the regex and you will double-inject):

  ```bash
  tr -d '\r' < "$file" | grep -oE '<!-- llm-wiki:pointer v[0-9]+ -->'
  ```

  Classify each file:
  - **No marker** → eligible for fresh injection.
  - **Marker matches the current target version** (the version in the block at M's
    template) → "already pointed (current)"; skip for any mutation. The marker is the single
    idempotency gate; the human-readable heading underneath is for readers and may be edited
    freely.
  - **Marker version is older than the current target** → "already pointed (outdated)";
    not silently skipped — surface to the user in M1 as an upgrade candidate.

**Mutation phase M** (only proceeds after explicit user `yes`):

- **M1.** Present the user with three lists, plus the block and insertion strategy:
  - **Fresh injection targets** — files with no marker.
  - **Already current** — files with a marker matching the target version; will be skipped.
  - **Upgrade candidates** — files with an older marker. Offer per-file: "(a) leave the
    outdated marker, (b) upgrade by removing the old block and injecting the new one." If
    the user picks (b), run the Pointer removal operation first, then continue M3 for that
    file.

  Show: the list of files with casing, the exact block (below, verbatim), the insertion
  strategy ("appended at end-of-file, with one blank line of separation"), and a yes/no/per-
  file prompt as appropriate.
- **M2.** If the user declines, stop and log a skip (step M4).
- **M3.** On `yes`, for each target file:
  - If the file does not end in a newline, append a newline.
  - Append one blank line, then the block below verbatim, then a trailing newline.
  - Do not attempt to detect "obvious sections" — append-at-EOF is the only sanctioned
    placement.

Block to insert (verbatim — do not start with a blank line; M3 controls separation).
**The ```` ```markdown ```` fences below are presentation only — append only the lines between
them, never the fence lines themselves**:

```markdown
<!-- llm-wiki:pointer v2 -->
### LLM Wiki — `/llm-wiki/`

An LLM-maintained markdown knowledge base lives at [`/llm-wiki/`](llm-wiki/). Read [`llm-wiki/schema.md`](llm-wiki/schema.md) for the canonical layer rules, source hierarchy, and operation procedures.

If you are an agent that supports skills, invoke the `llm-wiki` skill (e.g. Claude Code: `Skill(skill: "llm-wiki")`) before any operation on the folder. If the skill is unavailable, follow `llm-wiki/schema.md` directly.

**Keep the wiki in sync with substantive changes.** After a new feature, architectural decision, removed feature, or behaviour change in an existing feature — update the affected page(s) under `llm-wiki/wiki/` and refresh `index.md` in the same session. Skip for trivial edits (typos, whitespace, comment-only, single-line refactors, no-behaviour dependency bumps). When in doubt, ask the user.
<!-- /llm-wiki:pointer v2 -->
```

**Current target version: `v2`.** v2 adds the "Keep the wiki in sync with substantive
changes" paragraph. Files with a v1 marker will be classified as "outdated" by D3 and
surfaced as upgrade candidates in M1 — the user can choose to upgrade per file.

- **M4.** Append to `llm-wiki/log.md` (note the distinct `infra |` prefix — pointer ops are
  not wiki content operations):
  - On mutate: `## [YYYY-MM-DD] infra | pointer injected | <file1>, <file2>`
  - On user-declined: `## [YYYY-MM-DD] infra | pointer skipped (user declined) | -`
  - On all-already-present: `## [YYYY-MM-DD] infra | pointer skipped (already present) | -`
  - On no-target-file: `## [YYYY-MM-DD] infra | pointer skipped (no CLAUDE.md or AGENTS.md) | -`

**Pointer removal operation:**

To remove an injected pointer from a file:

1. Match the versioned pair: opening `<!-- llm-wiki:pointer v<N> -->` to the same-version
   closing `<!-- /llm-wiki:pointer v<N> -->`. Both markers carry the same `<N>`, so v1 and v2
   blocks can coexist and be removed independently. Pre-strip CR characters when scanning to
   tolerate CRLF line endings (same as D3).
2. Show the user the exact lines to be removed (use `grep -n` for line ranges). If any line
   inside the block diverges from the canonical template, warn the user explicitly that
   custom content will be lost.
3. On confirmation, delete the lines from the opening marker through the matching closing
   marker inclusive. If the line immediately after the closing marker is literally blank
   (zero non-whitespace characters), also delete that one line. **Never delete a line that
   has any non-whitespace content** — protect against eating user-edited adjacent content.
4. Log: `## [YYYY-MM-DD] infra | pointer removed (v<N>) | <file>`

**Version bump.** If a future skill release changes the pointer text, the new injection uses
`v2` markers. Detection (D3) is already version-agnostic; the opening regex
`<!-- llm-wiki:pointer v[0-9]+ -->` matches any version, so a `v1` block correctly blocks
duplicate `v2` injection. Upgrade procedure: remove the `v1` block via the removal operation,
then re-inject (which will write `v2`).

---

## Step 2 — Operations

**All operation procedures live in `llm-wiki/schema.md`, which is the single source of truth.**
Before running any operation, re-read `llm-wiki/schema.md` — it evolves per project.

This file (`SKILL.md`) only routes you to schema.md and enforces the hard rules below. If you
detect a conflict between this file and `schema.md`, `schema.md` wins (it was project-adapted)
— **with one carve-out**: the Source Hierarchy is canonical here in `SKILL.md`. `schema.md`
reproduces the list for local discoverability but defers to this file on it.

Operation names defined in `schema.md`:

- **Ingest** — read a source, update wiki pages, update `index.md`, append to `log.md`.
- **Create a feature page** — synthesize a `wiki/features/<name>.md` from raw sources.
- **Draft a spec** — write a `drafts/specs/<name>.md` (not product truth until accepted).
- **Query** — read `index.md`, find pages, synthesize answer with citations.
- **Lint** — health-check the wiki (orphans, missing citations, contradictions).
- **Archive** — retire a stale page by moving it to `wiki/archive/<original-path>` with a
  superseded-by note (see schema.md for details).
- **Evolve schema** — when a new page category emerges (e.g. `wiki/architecture/`,
  `wiki/testing/`), update `schema.md` first, then create the directory.

---

## Hard rules (never break — these override anything elsewhere)

- **`raw/` is append-only for the LLM.** The LLM may *create* new files inside `llm-wiki/raw/`
  during ingest of user-provided material, but **never modifies or deletes** files already
  there. Files in mapped external paths (e.g. `Documentation/ADRs/`) are read-only for the LLM
  entirely. Humans may edit anything freely — the immutability is a constraint on the LLM, not
  on humans.
- **Never create `CLAUDE.md` or `AGENTS.md`.** Pointer injection (Step 1c) only appends to
  these files when they already exist. Creating new top-level agent-instruction files is
  outside this skill's scope.
- **New ingested material lives inside `llm-wiki/raw/`.** When the user asks you to ingest a
  *new* source (App Store listing, competitor teardown, website export, screenshots, PDFs,
  user research, etc.), write the raw file under the matching `llm-wiki/raw/<bucket>/` —
  never into `Documentation/`, `docs/`, or any sibling directory you invent. The mapping table
  in `schema.md` only governs *pre-existing* project docs; net-new material always goes into
  `raw/`. Bucket routing (`schema.md` may extend this list via Evolve schema):
  - Our own product material (App Store copy, marketing site, press) → `raw/product-docs/`
  - Competitor material (listings, teardowns, screenshots) → `raw/competitor-docs/`
  - Source-code extracts / notes → `raw/code-notes/`
  - Accepted/shipped feature specs → `raw/specs/`
  Synthesised analyses (comparisons, gap analyses, audits) are wiki output, not raw — write
  them under `llm-wiki/wiki/`, not `raw/`.
- **Save format for ingested material.** Every raw file must (a) preserve all substantive
  claims from the source — structured reformatting into tables/sections is fine; lossy
  summarisation that drops claims is not — and (b) begin with the provenance header defined
  in `schema.md` (Ingest operation). Binary sources are placed by the human; the LLM creates
  the sibling markdown file with extracted/transcribed text.
- Never treat a draft spec as product truth.
- Never mix competitor observations into internal product claims without a clear
  `(competitor: <name>)` label.
- Never invent behavior unsupported by a source.
- Never leave a conflict unresolved — flag it explicitly on the page.
- **Source hierarchy** when sources conflict — this is the canonical list; `schema.md`
  reproduces it for project-local discoverability, but if the two disagree, this list wins:
  1. Source code (strongest)
  2. Accepted specs (`raw/specs/`)
  3. Product docs (`raw/product-docs/`)
  4. Draft specs (`drafts/specs/`) — aspirational, not truth
  5. Competitor docs (`raw/competitor-docs/`) — observation only

---

## Resources

- `reference/karpathy-llm-wiki.md` — original pattern (read for context, never copy into wiki output).
- `templates/schema.md` — generic schema template; adapt during setup.
- `templates/index.md`, `templates/log.md`, `templates/overview.md`, `templates/glossary.md` — empty starters.
