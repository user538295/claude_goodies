# Product Wiki Schema

This document tells the LLM how the wiki works. Follow it exactly. Update it when conventions
evolve (see **Evolve schema** below).

Based on Karpathy's LLM Wiki pattern (see `karpathy-llm-wiki.md` in this folder), adapted for
product work.

---

## Directory Layout

```
llm-wiki/
  schema.md          ← you are here
  index.md           ← catalog of all wiki pages (LLM maintains)
  log.md             ← append-only activity log (LLM maintains)
  raw/               ← immutable sources (LLM never modifies)
    product-docs/    ← official product documentation
    specs/           ← accepted/shipped feature specs
    code-notes/      ← notes extracted from source code
    competitor-docs/ ← competitor screenshots, docs, teardowns
  wiki/              ← LLM-maintained knowledge (write here)
    overview.md      ← product summary and architecture
    glossary.md      ← shared terminology
    features/        ← one page per feature
    decisions/       ← key product decisions and rationale
    archive/         ← retired pages (created lazily on first archive)
  drafts/            ← work in progress (not product truth)
    specs/           ← draft specs under review
```

Additional `wiki/` subdirectories (e.g. `wiki/architecture/`, `wiki/testing/`,
`wiki/integrations/`) may emerge as the wiki grows. **Add them via the Evolve schema operation
— register the new category here before creating the directory.**

## Existing project documentation

<!--
  SETUP STEP — REPLACE THIS COMMENT BLOCK ENTIRELY.

  Replace this entire HTML comment with a real table mapping the project's existing
  documentation roots to raw/ layers. Do not leave the comment in place.

  Example:

  | Path                    | Treat as              | Evidence level |
  |-------------------------|-----------------------|----------------|
  | `docs/architecture/`    | `raw/product-docs/`   | Strong         |
  | `docs/adrs/`            | `raw/product-docs/`   | Strong         |
  | `docs/shipped/`         | `raw/specs/`          | Strong         |
  | `docs/testing/`         | `raw/product-docs/`   | Supporting     |
  | `docs/backlog/`         | `drafts/specs/`       | Weak           |

  Backlog/planned folders are ALWAYS draft-level evidence — never cite as current behavior.

  If no external docs exist, replace this comment with:
  _No external documentation roots detected. All sources will live under `raw/`._
-->

When ingesting from external docs, note the source as the full path
(e.g. `source: docs/adrs/001-foo.md`).

**Immutability scope:** the LLM never modifies files in `raw/` or in any mapped external path.
Humans may edit external paths freely (they are the source of truth that the LLM reads from).

---

## Source Hierarchy (trust order)

**This list is reproduced from `SKILL.md` for project-local discoverability. SKILL.md holds the
canonical version — if the two ever diverge, SKILL.md wins for this list only. (For everything
else in this document, schema.md is authoritative over SKILL.md.)**

When sources conflict, prefer in this order:

1. **Source code** — what the app actually does. Strongest evidence.
2. **Accepted specs** (`raw/specs/`) — what was intentionally built.
3. **Product docs** (`raw/product-docs/`) — may be stale.
4. **Draft specs** (`drafts/specs/`) — aspirational, not truth.
5. **Competitor docs** (`raw/competitor-docs/`) — external, observation only.

Always note the source of a claim. When sources conflict, state the conflict explicitly on the
wiki page — do not silently choose one.

---

## Layer Rules

### raw/ — Sources (append-only for the LLM)

- **Create-yes, modify-no.** The LLM may *create* new files in `raw/` during ingest of
  user-provided material (pasted text, fetched URL content, transcribed screenshots). The LLM
  **never modifies or deletes** files already in `raw/`. When a source changes (e.g. an App
  Store listing is updated), the LLM creates a *new* raw file with a new dated filename — the
  old file stays as the audit trail.
- Most sources are markdown or text. **Non-text sources are allowed** (PDFs, screenshots,
  exported HTML, CSV):
  - For binary sources: **the human places the binary file at the target path themselves**
    (the LLM does not write binary content via text-edit tools). The LLM then creates a
    sibling markdown file capturing the extracted/transcribed text plus the provenance header
    below; the wiki page cites the markdown sibling (not the binary).
  - For PDFs specifically, the LLM may *read* the PDF directly (multimodal) for extraction,
    even though it cannot *write* one.
- Filename convention: `YYYY-MM-DD_short-description.<ext>`

### wiki/ — Compiled knowledge (LLM writes)

- LLM creates and updates these files.
- Every page must have a one-line `> summary:` at the top.
- Use `[[page-name]]` for internal links (Obsidian-compatible).
- Cross-reference generously. Orphan pages are a smell.
- When a claim comes from a source, cite it inline: `(source: raw/specs/login.md)`.
- **Filename collisions:** if two features would produce the same kebab-case name (e.g.
  `import.md` for CSV import vs. bank import), disambiguate by domain prefix:
  `csv-import.md`, `bank-import.md`. Never overwrite an existing page silently.

**Feature pages** (`wiki/features/<feature-name>.md`):
- What it does (current behavior, from code/specs)
- Key behaviors and edge cases
- Related features (links)
- Open questions
- Conflicts or gaps between sources

**Decision pages** (`wiki/decisions/<decision-name>.md`):
- What was decided
- Why
- Alternatives considered
- Source reference

### drafts/ — Work in progress (not truth)

- Draft specs live here until reviewed and accepted.
- Top of every draft: `> STATUS: draft | author: X | date: YYYY-MM-DD`
- A draft becomes truth only when moved to `raw/specs/` after review.
- Never cite a draft as evidence of product behavior.

### Competitor docs

- Observations only. Never mix into internal product claims.
- When referencing competitor behavior in wiki pages, prefix with: `(competitor: <name>)`
- Keep competitor raw docs in `raw/competitor-docs/` only.

---

## Operations

## Pre-flight check

**Run this check before every operation.** It handles crash recovery and surfaces pending
raw-file ingests from the watcher queue.

**Skip check**: If `llm-wiki/.watcher/` does not exist, skip the entire pre-flight check and proceed directly to the requested operation.

### Step PF-1 — Check for crashed ingest (`pending.processing.tmp`)

If `llm-wiki/.watcher/pending.processing.tmp` exists:
- A crash occurred during the atomic rename. Delete `pending.processing.tmp`.
- Proceed with `pending.processing` as-is (the `#done:` marker for the last file was not
  written; it will be re-ingested on resume). Continue to Step PF-2.

### Step PF-2 — Check for interrupted ingest (`pending.processing`)

If `llm-wiki/.watcher/pending.processing` exists, a prior ingest was interrupted.

1. Read the file. Identify remaining lines — those **without** a `#done:` prefix.
2. Skip any remaining line that does not resolve to an existing path under `llm-wiki/raw/`
   (corrupt partial write from a mid-rewrite crash).
3. If no valid remaining lines exist after filtering, silently delete `pending.processing` and proceed to Step PF-3 (no user prompt needed).
4. Say: *"A previous ingest was interrupted with N file(s) remaining. Resume or discard?"*
   - **Resume**: treat the valid remaining lines as the ingest set; proceed to ingest
     (no rename needed — `pending.processing` already exists).
   - **Discard**: delete `pending.processing`; continue to Step PF-3.

### Step PF-3 — Check pending queue

Read `llm-wiki/.watcher/pending`. If the file is absent or empty, no action needed.

If non-empty:
1. Filter `pending` to only paths that exist under `llm-wiki/raw/` — silently skip non-existent paths. Show the user only the count of existing files.
2. Cross-reference against `llm-wiki/.watcher/pending.snoozed`: any path present in both
   files means the file changed after snooze — remove it from `pending.snoozed` before
   presenting to the user. Write the filtered content to `pending.snoozed.tmp`, then
   atomically rename to `pending.snoozed` (`mv pending.snoozed.tmp pending.snoozed`).
3. Say: *"N new file(s) detected in raw/ — ingest them first?"*
   - **Yes**: rename `pending` → `pending.processing`; ingest files one at a time using
     the Ingest operation (each file gets its own Ingest call and its own `log.md` entry).
     After each successful ingest, write the modified content with `#done:` prepended to
     that line to a sibling temp file `pending.processing.tmp`, then rename it over
     `pending.processing` (atomic crash-safety). After ALL files are processed, delete
     `pending.processing`. Append to `log.md`:
     `## [YYYY-MM-DD] ingest | <file1>, <file2> (from watcher queue) | <pages touched>`
   - **No**: for each path, run `python3 -c "import os,sys; s=os.stat(sys.argv[1]); print(f'{s.st_mtime}\t{s.st_size}', end='')" "$path"` (the path must be shell-quoted to handle filenames with spaces) to get the current float mtime and integer size. Read existing `pending.snoozed` content (if any) to preserve prior snoozed entries. Write the combined content (existing entries + new declined paths as `<path>\t<mtime>\t<size>` lines) to `pending.snoozed.tmp` first, then atomically rename to `pending.snoozed` (`mv pending.snoozed.tmp pending.snoozed`). If a file no longer exists, skip it (do not snooze). After successfully writing to `pending.snoozed` (rename complete), delete `pending` (the snoozed paths are now tracked in `pending.snoozed`; the watcher will create a fresh `pending` on its next poll cycle if new files are detected). Snoozed files will not be re-prompted. User can run `check-pending` to review snoozed files.

### Watcher health warning (non-blocking)

After processing Step PF-3, read `llm-wiki/.watcher/watcher.pid` (if it exists) and check
the heartbeat timestamp (line 2):
- Heartbeat age **90s–300s**: warn "watcher heartbeat is stale — it may be hung" but do
  not block the operation.
- Heartbeat age **> 300s** or PID file absent: warn "watcher is not running — run
  start-watch to resume monitoring" but do not block the operation.

### Log line format

All operations append a single line to `log.md` in this shape:

```
## [YYYY-MM-DD] <verb> | <subject> | <objects-touched>
```

- `<verb>`: the operation name, lowercase (e.g. `init`, `ingest`, `re-ingest`, `feature`,
  `draft`, `archive`, `schema`, `lint`, `infra`).
- `<subject>`: the primary input of the operation — usually a filename, but for `init` it is
  a short phrase like `wiki created`, for `infra` it is `pointer injected` or similar.
- `<objects-touched>`: comma-separated list of pages or files modified by the operation. Use
  `-` if no objects were touched.

Pipes `|` are field separators — never use `|` inside any field. Use "or" or restructure the
text if needed.

### Ingest a source

1. The human provides material in one of three ways:
   - **(a)** drops a file into the appropriate `raw/` subfolder (or an external mapped path)
     and says "Ingest `<path>`";
   - **(b)** pastes text or gives a URL — the LLM creates the raw file under `raw/<bucket>/`
     using the filename convention and the provenance header below;
   - **(c)** provides a binary file (PDF, image) — the human places the binary at the target
     path; the LLM creates a sibling markdown file with extracted text and the provenance
     header, and treats *that* sibling as the citable source.
2. **Provenance header** — every LLM-created raw markdown file begins with:

   ```markdown
   # <Short title>

   **Source:** <URL | path | "user-paste" | "user-binary: relative/path/to/file.pdf">
   **Ingested:** YYYY-MM-DD
   **Original format:** <html | pdf-text | plain-text | screenshots | url | ...>
   **Supersedes:** <prior-raw-filename>  ← only present on Re-ingest

   ---
   ```

   Use the most specific source identifier available — `user-paste` is the fallback when no
   URL or path applies. `Supersedes:` is included only when this file replaces an earlier raw
   file (see Re-ingest below) — it provides the forward-discoverable audit chain that the
   append-only rule on `raw/` would otherwise lose. Existing raw files without all fields are
   grandfathered (Lint may flag missing fields as informational, never as an error).

   **Filename convention.** New raw files should use the date-prefixed form
   `YYYY-MM-DD_short-description.<ext>` (e.g. `2026-05-30_ynab.md`). Legacy raw files
   ingested before this convention may lack the prefix — leave them as-is; Re-ingest of a
   legacy file produces a properly-named new file with `Supersedes: <legacy-name>`.
3. **Save-format rule.** Preserve all substantive claims from the source. Structured
   reformatting into tables/sections is fine; lossy summarisation that drops claims is not.
4. LLM reads the source and creates or updates the relevant wiki pages, citing the raw file
   inline as `(source: raw/<bucket>/<file>)`.
5. LLM updates `index.md`.
6. LLM appends to `log.md`: `## [YYYY-MM-DD] ingest | <filename> | <pages touched>`

**Re-ingest (source updated).** When a tracked source changes — App Store listing revised,
competitor's landing page rewritten — create a *new* raw file with the new ingestion date in
the filename (e.g. `2026-08-01_app-store-listing.md`) and include `Supersedes: <prior-name>`
in its provenance header. Update wiki citations to point at the new file: **trace the full
supersession chain back via `Supersedes:` links and grep for citations of every predecessor
filename**, not just the immediate prior one — at chain depth > 1, a wiki page that was never
updated during an earlier re-ingest may still cite the original. The old files stay untouched
as the audit trail; the Supersedes field makes the chain forward-discoverable without
modifying them. Log:
`## [YYYY-MM-DD] re-ingest | <new-filename> supersedes <old-filename> | <pages touched>`

**Sync trigger.** Beyond explicit user-initiated ingests, the LLM should proactively refresh
the wiki in the same session as any substantive change to the underlying codebase or product
— new feature, architectural decision, removed feature, or behaviour change in an existing
feature. Skip for trivial edits (typos, whitespace, comment-only, single-line refactors,
no-behaviour dependency bumps). When in doubt, ask the user before re-ingesting — re-ingest
is cheaper than spurious churn but still costs a session.

### Create a feature page

1. Human: "Create a feature page for <feature name>"
2. LLM checks `index.md` — does the page already exist?
3. LLM searches raw sources for relevant material (specs, code-notes, docs).
4. LLM creates `wiki/features/<feature-name>.md` using the feature page structure above.
5. LLM links it from related pages and `wiki/overview.md` if appropriate.
6. LLM updates `index.md`.
7. LLM appends to `log.md`.

### Draft a spec

1. Human: "Draft a spec for <feature>"
2. LLM reads the relevant feature page from `wiki/features/`.
3. LLM reads any existing specs in `raw/specs/` for context and consistency.
4. LLM creates `drafts/specs/<feature-name>.md` with STATUS header.
5. LLM does NOT update `index.md` or treat draft as product truth.
6. Human reviews and edits the draft.
7. When accepted: human moves to `raw/specs/`, LLM updates wiki.

### Query

1. Human asks a question.
2. LLM reads `index.md` to find relevant pages.
3. LLM reads those pages and synthesizes an answer with citations.
4. If the answer is reusable (a comparison, an analysis), LLM asks: "Should I file this as a wiki page?"

### Lint (periodic)

Ask the LLM to health-check the wiki:
- Pages with no inbound links
- Claims without source citations
- Contradictions between pages
- Features mentioned in overview but lacking a feature page
- Draft specs that have been sitting without review

### Archive (retire a stale page)

1. Human: "Archive `wiki/<path>`" (with optional `superseded by <new-page>`).
2. LLM moves the file to `wiki/archive/<original-path>` (preserving the original subpath).
3. LLM adds a top-of-file note: `> ARCHIVED YYYY-MM-DD — superseded by [[new-page]]` (or
   `> ARCHIVED YYYY-MM-DD — no longer relevant`).
4. LLM updates inbound links: either redirect them or remove them.
5. LLM updates `index.md` (move row to an "Archive" section, do not delete).
6. LLM appends to `log.md`: `## [YYYY-MM-DD] archive | <page> | superseded by <new-page>`

### Evolve schema (add a new wiki page category)

When the wiki organically needs a new category (e.g. `wiki/architecture/`, `wiki/testing/`,
`wiki/integrations/`):

1. Human: "Evolve schema — add `<category>` pages."
2. **Validate the proposed category name:**
   - Reserved peer directories (must not be used as wiki/ subdirectory names — they exist at
     the top level of `llm-wiki/`): `raw`, `drafts`.
   - Reserved wiki/ subdirectories (already defined): `features`, `decisions`, `archive`.
   - Reserved wiki/ filenames (do not name a category the same as an existing top-level wiki
     file): `overview`, `glossary`.
   - Must not duplicate an existing category in the Directory Layout.
   - Must be lowercase kebab-case.
   - If validation fails, stop and ask the human for a different name.
3. **Show the human the exact diff to `schema.md` first** and get explicit confirmation
   before writing. The Evolve schema operation is the only path by which the LLM modifies
   `schema.md` — treat it with the same care as a `raw/` write would deserve if it were
   allowed.
4. LLM updates `schema.md`: add the new directory to the **Directory Layout** section above,
   with a one-line description.
5. LLM creates the new directory.
6. LLM appends to `log.md`: `## [YYYY-MM-DD] schema | added wiki/<category>/ | schema.md`

**Rollback:** if the new category turns out wrong, run Evolve schema in reverse — show the
removal diff, get confirmation, remove the line from Directory Layout, and either delete the
(empty) directory or archive any pages in it via the Archive operation first.

---

## Page Frontmatter (optional but useful)

```yaml
---
type: feature | decision | overview | glossary | architecture | testing
sources: [raw/specs/foo.md, raw/code-notes/bar.md]
updated: YYYY-MM-DD
status: current | stale | disputed | archived
---
```

---

## What the LLM must never do

- Modify or delete existing files in `raw/` or in any external mapped path. (The LLM may
  *create* new files in `raw/` during ingest — see the Ingest operation.)
- Treat a draft spec as product truth.
- Mix competitor observations into internal product claims without a clear label.
- Invent behavior not supported by a source.
- Leave a conflict unresolved — always flag it explicitly.
- Create a new `wiki/` subdirectory without first registering it via **Evolve schema** —
  with one exception: `wiki/archive/` is pre-registered in the Directory Layout and is
  created lazily on the first Archive operation, no Evolve ceremony required.
- Overwrite an existing wiki page on filename collision — disambiguate with a domain prefix.
