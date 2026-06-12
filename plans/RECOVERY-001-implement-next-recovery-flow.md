# RECOVERY-001 — Recovery Flow for Interrupted `/implement-next` Runs
**Purpose**: Add deterministic interruption-recovery to `/implement-next` and `/implement-next-cc` so re-invocation after a crash, Ctrl-C, OOM, transport error, or hook-bypass produces a consistent state (implementation reviewed + tests green + plan checked off + committed) without duplicate work, orphaned tests, or silent loss of partial implementation.
**Audience**: Users running `/implement-all[-cc]` or invoking `/implement-next[-cc]` standalone after a prior interruption; maintainers of the implement-next skill family and its support scripts.
**Status**: Draft

---

## Background

`implement-next-recovery-brief.md` documents the full feature brief. Summary: the implement-next skill family currently has no entry-time recovery in the portable variant, and only parent-level (`/implement-all-cc` Case A/B/C/D) recovery in the `-cc` variant — leaving standalone `/implement-next-cc` users unprotected. When a prior subagent was interrupted, the next invocation proceeds as if fresh: it may duplicate test files, orphan partial implementations, or silently lose work. The cited base rate is ~7.6% of `/implement-next` subagents historically failing to commit (`implement-all.md:81`).

The fix introduces a deterministic breadcrumb-based triage at Step 0 of both child skills, a shared classifier script (`implement-next-triage.sh`), a hardened breadcrumb writer (atomic writes + `--upsert` + `--increment-review-abort` + schema v2 fields), a Step 7 self-verification mirrored across both variants, parent-side breadcrumb writes in both `-cc` and portable parents, breadcrumb clearing in the rescue path (`implement-next-cc-resume.md`), and `audit-plan-run.sh` recognition of the `recovery(R-B):` commit-message marker. Pre-ship gates are bats tests for the pure-shell layer; LLM-driven end-to-end flow is validated by the Manual Integration Test Catalog from the brief.

---

## Goal

When `/implement-next` or `/implement-next-cc` is re-invoked after a prior interruption, Step 0 reads the breadcrumb, deterministically classifies the prior state (R-Fresh / R-A / R-B / R-AB / R-C / R-Halt / R-Stuck), and the skill executes the case-specific action sequence. The recovery path leaves: (a) exactly one task-worth of work committed, (b) the plan file checked off for that task, (c) the breadcrumb cleared on success or on terminal halt, and (d) — for the R-B case — a `recovery(R-B):` commit-message marker that `audit-plan-run.sh` downgrades from VIOLATION to WARNING. Two consecutive review double-aborts trigger `R-Stuck` and halt without retry. The portable `/implement-all` and `-cc` `/implement-all-cc` parents both write the full breadcrumb pre-spawn so the child's Step 0 finds one to triage.

---

## Scope

### In Scope

- New `~/.claude/scripts/implement-next-triage.sh` (classifier with bounded state-hygiene side effects; reads breadcrumb + repo state, prints `CASE=` and ancillary `KEY=VALUE` lines on stdout, exit 0 / 1 / 2 per contract).
- Extensions to `~/.claude/scripts/implement-next-state-write.sh`:
  - Atomic write via tempfile + `mv` in all modes.
  - `schema_version: 2`, `branch_name`, `skill_variant`, `review_abort_count: 0` fields in the written JSON.
  - New 6th positional arg `<skill_variant>` (default-mode signature: `<cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> <skill_variant>`).
  - `--upsert` flag — skips the empty-`expected_agent_id` guard and merges into any existing breadcrumb (preserves non-empty fields so a parent-written `expected_agent_id` is never clobbered by a child's empty value).
  - `--increment-review-abort` flag — read-modify-write that bumps `review_abort_count` by 1, leaves other fields untouched, exits non-zero if breadcrumb missing.
- Extensions to `~/.claude/scripts/audit-plan-run.sh`:
  - Recognize `recovery(R-B):` commit-subject prefix (anchored at start, `--no-merges`); downgrade `(commits - recovery_commits) == completed` from VIOLATION to WARNING with marker count in stdout.
  - Surface `.claude/recovery-anomalies.log` existence + line count at loop end.
- Modifications to `~/.claude/commands/implement-next.md`:
  - Add Step 0 (triage shell-out) before existing Step 1.
  - Move `START_SHA` / `START_CHECKED` capture from line 25 (within Step 1) to Step 0 so recovery paths that skip Step 1 still bind them for Step 7.
- Modifications to `~/.claude/commands/implement-next-cc.md`:
  - Add Step 0 (triage shell-out).
  - Add Step 7 self-verification (mirroring `implement-next.md:94-119`).
  - Renumber existing "Report" step to Step 8.
  - Move `START_SHA` / `START_CHECKED` capture to Step 0.
  - When a parent breadcrumb is present, child does NOT write breadcrumb (parent owns it). Standalone child writes via `--upsert` with empty `expected_agent_id`.
- Modifications to `~/.claude/commands/implement-next-cc-resume.md`:
  - Clear breadcrumb after Step 2's successful commit (insert as Step 2.5 or as the final line of Step 2).
- Modifications to `~/.claude/commands/implement-all-cc.md`:
  - Write the FULL breadcrumb pre-spawn at Step 4 — AFTER `Agent` returns the `agentId`, BEFORE waiting on the agent.
  - REMOVE the unconditional `implement-next-state-clear.sh` invocation at Step 6 (line 64).
  - Clear the breadcrumb explicitly on Cases B-after-rescue-fails, C, D and at the final audit.
- Modifications to `~/.claude/commands/implement-all.md` (portable parent):
  - After Step 3's subagent spawn, write the full breadcrumb via `--upsert` with empty `expected_agent_id`.
  - Clear the breadcrumb on all Step 4 halt paths.
- Modifications to `~/.claude/install.sh`:
  - Add `scripts/implement-next-triage.sh` to both `files` arrays (around lines 177-182 and 542-544).
  - Add `scripts/implement-next-triage.sh` to `check_cc_variant_integrity()` (lines 483-497).
- New bats test files under `~/.claude/tests/recovery/`:
  - `test_writer.bats` — default mode, `--upsert`, `--increment-review-abort`, atomic write, all new fields.
  - `test_triage.bats` — all 15 dispatch branches from the Triage Unit Tests table.
  - `test_audit_marker.bats` — `recovery(R-B):` marker recognition and anomalies-log consumption.
  - `test_hook_gate.bats` — block / pass-through behavior under fixtures s/t/u.
  - `test_step7_blocks_runnable.bats` — extracts Step 7 bash blocks from `implement-next.md` and `implement-next-cc.md`, runs them against a synthetic repo to catch markdown-embedded typos that grep cannot detect.
  - `tests/recovery/extract-bash-blocks.sh` — helper script that reads markdown on stdin and prints the contents of all fenced code blocks (lines between ` ``` ` markers, excluding the fence lines themselves). Used by `test_step7_blocks_runnable.bats` for syntactic equivalence diff against `step7-blocks-expected-{portable,cc}.sh`.
  - `tests/recovery/step7-blocks-expected-portable.sh` — hand-written mirror of the Step 7 bash blocks in `~/.claude/commands/implement-next.md`, used by `test_step7_blocks_runnable.bats` for syntactic equivalence diff.
  - `tests/recovery/step7-blocks-expected-cc.sh` — same role for `~/.claude/commands/implement-next-cc.md`. The two files are EXPECTED to be byte-identical (the two skills' Step 7 sections are textually mirrored); `test_step7_blocks_runnable.bats` includes a `diff step7-blocks-expected-portable.sh step7-blocks-expected-cc.sh` check to enforce this invariant.
  - `test_integration.bats` — shell-only end-to-end integration of triage + writer + re-invocation for fixtures that exercise only the shell layer (see Task 4.3b).
- **`.claude/recovery-anomalies.log` placement and user-side gitignore guidance**. The log is written by the triage script to `$CWD/.claude/recovery-anomalies.log` — i.e., the user's project directory. The triage script, after the FIRST time it appends to the log in a given repo, MUST emit a one-time stderr notice: `NOTE: Created .claude/recovery-anomalies.log. Add this path to your project's .gitignore to keep it out of version control.` The notice fires only when the log was just created (size == 1 line, file new). This is a soft nudge — no user-facing failure if ignored.
- Documentation updates in `~/.claude/handout/` (HTML files for both English and Hungarian variants).

### Out of Scope

- Auto-amending the prior commit in R-B (rejected: silent index contamination + conflicts with "prefer new commits over amends" policy).
- Heuristic file-relatedness detection (replaced entirely by deterministic breadcrumb lookup).
- Branch-switch HARD halt (warn only; the user may legitimately have moved branches).
- Stash-based rollback on review abort (HALT is the new default; see Key Decisions in brief).
- Modifying `~/.claude/commands/iterative-review.md` (recovery uses the existing review skill unchanged).
- Extracting per-case action sequences (review/test/commit) into shared scripts (only Step 0 triage is shared; per-case sequences legitimately differ between variants — parallel DA vs single critic).
- `/implement-next --force` for committing review-unstable code (future iteration).
- `flock`-based advisory locking for concurrent invocations (future iteration; documented constraint: concurrent invocations on the same plan are unsupported).
- Sidecar marker file for multi-developer `recovery(R-B):` integrity (future iteration; documented as soft convention for single-developer use).

---

## Acceptance criteria

> Acceptance criteria are verified in the final task. See [Task 4.4 — Final verification & documentation update].

---

## What does NOT change

- `~/.claude/commands/iterative-review.md` — recovery composes with the existing review skill without modification.
- The shape of `implement-next-stop-gate.sh` — its fail-open behavior on empty `expected_agent_id` (lines 62-64) and its filter logic stay unchanged; only its bats coverage is extended.
- `~/.claude/scripts/plan-progress.sh` — the triage is the new authority on next-task-to-act-on for recovery paths; `plan-progress.sh` continues to serve fresh-run flow unchanged.
- `~/.claude/scripts/check-task-commit.sh` — referenced by Step 7 self-verification (unchanged usage; called with `START_SHA` overridden to `sha_before` in R-B).
- `~/.claude/scripts/implement-next-state-clear.sh` — called from new sites but its 1-arg signature and exit codes are unchanged.
- The R-* case namespace is disjoint from `implement-all-cc.md`'s Case A/B/C/D namespace at the parent layer — both layers' cases coexist without collision.

---

## Known limitations / accepted trade-offs

- **R-B and R-AB both violate the one-task-one-commit invariant.** The audit-script marker (`recovery(R-B):` OR `recovery(R-AB):`) downgrades VIOLATION to WARNING; clean R-B / R-AB runs exit 0. Worst-case cascading: `commits ≥ 2 * tasks`, and R-AB stacking on R-B can produce 3+ commits per task.
- **R-B review fixes co-mingle with the checkoff commit, NOT the impl commit.** `git bisect` blames the impl commit; `git revert` of the impl commit leaves the fix orphaned. Documented cost of forward-progress design.
- **9-step skill is at the LLM-reliability boundary.** Step 0 (shell-out) and Step 7 (exit-code-driven) keep LLM-driven steps at 5. This recovery feature increases per-task failure probability (more steps to miss) but each failure is now recoverable rather than silent.
- **Pre-ship gates are bats-tested shell-layer only.** End-to-end LLM-driven recovery flow is validated manually against a real session (markdown consumed by an LLM cannot be intercepted via shell stubs).
- **Concurrent invocations on the same plan are unsupported.** The breadcrumb is a single file with no lock. `flock`-based locking is a future iteration.
- **`recovery(R-B):` marker is a soft convention.** Manual misuse silently bypasses the commit-count check. Acceptable for single-developer; multi-developer teams should consider a sidecar marker (deferred).
- **`review_abort_count` is cumulative across re-invocations for the same task.** Two total double-aborts trigger `R-Stuck` regardless of intervening successes within the same task scope (success deletes the breadcrumb so the counter resets at the next task). Manual reset = delete `.claude/implement-next-state.json`.
- **`branch_name` capture may be empty (detached HEAD).** Branch-mismatch check is then skipped entirely.
- **Triage script `rm` carve-out**: per `~/.claude/CLAUDE.md`, only `.claude/implement-next-state.json` is the machine-managed sentinel exempt from the `trash`-instead-of-`rm` rule. `.claude/recovery-anomalies.log` is NEVER `rm`'d (truncation uses `tail > .tmp && mv` atomic-mv) and does NOT require this carve-out.
- **R-B convergence walkthrough.** A successful R-B run produces: (impl commit at sha_before+1) + (recovery(R-B): commit at sha_before+2 with plan checkoff). Step 7 then clears the breadcrumb. Two interruption sub-windows exist:
  - **(a) Interrupted between Step 0's WT-checkoff-insert and the Step 6 recovery commit**: re-entry sees `HEAD == sha_before+1` (impl commit only) and working tree dirty (the checkoff edit). Triage dispatches **R-AB** — the recovery commit then includes both the (already-staged) checkoff and any new review fixes. The commit MUST be prefixed `recovery(R-AB):` so the audit recognizes it as a recovery and downgrades VIOLATION to WARNING. Convergent via R-AB + audit-marker downgrade.
  - **(b) Interrupted between the recovery commit and Step 7's breadcrumb-clear**: re-entry sees `HEAD == sha_before+2` (recovery commit landed, plan now has the task checked in HEAD). Triage's "task_name already committed-checked" dispatch row matches first, clears the stale breadcrumb, dispatches **R-Fresh**. Convergent via R-Fresh.

  Both sub-windows converge; the `review_abort_count` cap (2 → R-Stuck) prevents review-driven loops; R-B convergence is guaranteed by the dispatch rows.
- **Audit validates `recovery(R-B):` by subject prefix only.** It does NOT verify (a) the commit is plan-only, (b) the plan-file diff matches the expected `task_name`, (c) the prior commit is the impl this recovery checks off. This is a deliberate, surface-only contract — strengthening it requires either a sidecar marker (deferred to a future iteration; see "Out of Scope") or signed-commit tooling. For added visibility, `audit-plan-run.sh` will emit the full list of R-B commit subjects to stderr when `recovery_commits > 0`, so a human reviewer can eyeball them.
- **Atomic `mv` requires same-filesystem `.tmp` placement.** The writer renders to `$state_file.tmp` (sibling of `$state_file`), guaranteeing same-filesystem placement. This holds for all local POSIX filesystems. **NFS and remote-mounted filesystems are NOT supported** — `mv` semantics on NFS may not be atomic. Document constraint; do not attempt remediation.

---

## Architecture

### Component map

| Component | Type | Role |
|---|---|---|
| `~/.claude/scripts/implement-next-triage.sh` | NEW shell script | Classifier with bounded state-hygiene side effects (deletes stale breadcrumb, appends anomalies log); reads breadcrumb + repo state, prints CASE= and ancillary vars |
| `~/.claude/scripts/implement-next-state-write.sh` | MODIFIED shell script | Atomic write; v2 schema; `--upsert` + `--increment-review-abort` flags |
| `~/.claude/scripts/audit-plan-run.sh` | MODIFIED shell script | Recognizes `recovery(R-B):` marker; surfaces anomalies-log |
| `~/.claude/scripts/implement-next-state-clear.sh` | UNCHANGED | Called from new sites |
| `~/.claude/scripts/implement-next-stop-gate.sh` | UNCHANGED + new tests | Bats coverage extended; source identical |
| `~/.claude/commands/implement-next.md` | MODIFIED skill | Step 0 triage; `START_SHA`/`START_CHECKED` moved to Step 0 |
| `~/.claude/commands/implement-next-cc.md` | MODIFIED skill | Step 0 triage; new Step 7 self-verification; Report renumbered to Step 8 |
| `~/.claude/commands/implement-next-cc-resume.md` | MODIFIED skill | Clear breadcrumb after Step 2 commit |
| `~/.claude/commands/implement-all-cc.md` | MODIFIED skill | Pre-spawn full breadcrumb write; remove unconditional clear; halt-path clears |
| `~/.claude/commands/implement-all.md` | MODIFIED skill | Portable parent breadcrumb write (`--upsert`); halt-path clears |
| `~/.claude/install.sh` | MODIFIED | Manifest + integrity check additions |
| `~/.claude/tests/recovery/` | NEW directory | Four bats test files |
| `~/.claude/handout/` | MODIFIED | English + Hungarian HTML doc updates |

### Data flow

```
                            +-------------------------------+
   /implement-all[-cc]      |  state-write.sh --upsert / default
   parent spawns child  --> |  writes .claude/implement-next-state.json
                            +-------------------------------+
                                          |
                                          v
   /implement-next[-cc]    +-------------------------------+
   Step 0 ───────────────> |  implement-next-triage.sh     |
                           |  → CASE=R-Fresh|R-A|R-B|...   |
                           +-------------------------------+
                                          |
                                          v
                  ┌─────────┬─────────────┼─────────────┬──────────┐
                  v         v             v             v          v
                R-Fresh    R-A           R-B          R-AB        R-C
                  |         |             |             |          |
                  v         v             v             v          v
            Step 1→...   Step 4→...  Step 4→...    Step 4→...  Step 2→...
                  |         |             |             |          |
                  └─────────┴─────────────┼─────────────┴──────────┘
                                          v
                                  Step 7 self-verify
                                          |
                                          v
                              state-clear.sh on success
```

### Breadcrumb JSON schema (v2)

```json
{
  "schema_version": 2,
  "sha_before": "<git sha>",
  "plan_path": "<absolute or repo-relative>",
  "task_name": "<exact task title from plan>",
  "expected_agent_id": "<agentId or empty>",
  "started_at": "<ISO 8601 UTC>",
  "branch_name": "<branch or empty>",
  "skill_variant": "portable | cc",
  "review_abort_count": 0
}
```

**Schema policy**: additive intra-version field additions keep `schema_version: 2` and default missing fields to empty/zero (no corrupt-flag). Breaking changes bump to `schema_version: 3`.

### Triage I/O contract

- **Inputs (positional)**: `$1=cwd`, `$2=plan_path`, `$3=current_skill_variant` (`"portable"` | `"cc"`).
- **stdout (machine-readable, one `KEY=VALUE` per line)**: `CASE`, `START_SHA`, `START_CHECKED`, `SHA_BEFORE`, `BRANCH_NAME`, `TASK_NAME`, `REVIEW_RANGE`, `STEP_2_RESUME`, `REVIEW_ABORT_COUNT`; PLUS one human-readable `RECOVERY: ...` diagnostic line. R-B's check-3 skip is now self-detected in Step 7 from the commit subject (no SKIP_CHECK3 variable needed).
- **Exit codes**: `0` = dispatched, `1` = halt (corrupt breadcrumb in dirty tree, plan missing, R-Stuck), `2` = usage error.
- **Exit-1 stdout contract**: only the `RECOVERY:` line + `CASE=R-Halt` or `CASE=R-Stuck`. The skill MUST check exit code before parsing stdout and exit immediately on non-zero.

**Side effects (bounded, documented)**: the triage script may
- delete `$cwd/.claude/implement-next-state.json` (on the committed-checked and auto-clear dispatch rows)
- append to `$cwd/.claude/recovery-anomalies.log` (on the auto-clear row)
Both are state hygiene operations, not workflow actions. The script never spawns subagents, runs tests, or creates commits.

### Dispatch table (evaluated top-to-bottom; first match wins)

Dispatch order: evaluated top-to-bottom; first match wins. Order chosen so that benign early-exit conditions (already-committed-checked, malformed JSON, plan_path-mismatch) precede potentially-error conditions (task_name-mismatch + dirty). This ordering is authoritative; Task 1.4's dispatch logic mirrors it exactly.

| Condition | Case | Action summary |
|---|---|---|
| `review_abort_count >= 2` | **R-Stuck** | Exit 1 with manual-recovery diagnostic |
| No breadcrumb, OR legacy (no `schema_version` + no v2 fields) | **R-Fresh** | Proceed to existing Step 1 |
| `schema_version != 2` AND one or more v2 fields present | **R-Fresh** (corrupt) | Diagnostic notes inconsistency |
| Malformed JSON | **R-Fresh** | Diagnostic notes malformed JSON treated as absent |
| `plan_path` differs from `$ARGUMENTS` | **R-Fresh** | Stale-plan diagnostic |
| `task_name` is already committed-checked in `git show HEAD:$ARGUMENTS` | **R-Fresh** | Delete stale breadcrumb |
| `task_name` mismatch + `sha_before == HEAD` + clean tree | **R-Fresh** (auto-cleared) | Append WARNING line to `.claude/recovery-anomalies.log` |
| `task_name` mismatch + (dirty OR HEAD moved) | Exit 1 | Diagnostic: plan editing / branch switch / crash |
| `branch_name` non-empty + differs from current branch | (warn + continue) | List both branches |
| `skill_variant` differs from current variant | (warn + continue) | Cross-variant diagnostic |
| Matched + `HEAD == sha_before` + dirty tree | **R-A** | Skip Step 2; review `HEAD+worktree`; tests; check off; commit |
| Matched + `HEAD != sha_before` + clean tree | **R-B** | `START_SHA = sha_before`; report violation; insert plan checkoff; review `<sha_before>..HEAD`; commit with `recovery(R-B):` prefix |
| Matched + `HEAD != sha_before` + dirty tree | **R-AB** | Review `<sha_before>..HEAD+worktree`; commit |
| Matched + `HEAD == sha_before` + clean tree | **R-C** | `STEP_2_RESUME=true`; sub-item delta vs `git show HEAD:$ARGUMENTS` |

### Writer mode matrix

| Mode | Caller | `expected_agent_id` | Behavior |
|---|---|---|---|
| Default | `implement-all-cc.md` Step 4 | Required (real agentId) | Truncate-and-write atomically |
| `--upsert` | `implement-all.md` Step 3; standalone child (no parent breadcrumb) | May be empty | Read-merge non-empty fields; atomic write |
| `--increment-review-abort` | Child Step 3 double-abort path | N/A | Read breadcrumb; +1 to `review_abort_count`; atomic write; exit non-zero if missing |

### Config / env vars introduced

None — all state is in `.claude/implement-next-state.json` and `.claude/recovery-anomalies.log`.

### Step 0 markdown duplication: accepted

Step 0's dispatch prose (the case-by-case "if R-Fresh proceed to Step 1; if R-A skip Step 2..." block) is identical between `implement-next.md` and `implement-next-cc.md` except for the third arg to triage (`"portable"` vs `"cc"`) and the standalone-child `--upsert` write (cc-only). We evaluated extracting it to a shared markdown fragment included by both skills. Rejected for two reasons:
1. **Markdown `# include` semantics are runtime-undefined for slash-command files.** Claude Code reads command markdown verbatim; there is no documented include directive. Including would require a build step (e.g., a pre-install script that concatenates fragments). Build steps are out of scope for this skill family.
2. **The two skills DO diverge at Step 3** (review mechanism: parallel DA vs single critic). A reader expecting "the Step 0 of cc is in fragment X" must still jump between files at Step 3. The cognitive savings are smaller than the indirection cost.

Drift risk is acknowledged and mitigated by the `RECOVERY_SCHEMA_V2` marker check (greppable consistency tag).

### Why three modes in one writer (not three scripts)

`state-write.sh` accumulates three modes (default, `--upsert`, `--increment-review-abort`). We considered splitting into three scripts (`state-upsert.sh`, `state-bump-counter.sh`). Rejected because:
1. All three modes share the atomic `.tmp + mv` pattern, the v2 schema definition, and the same JSON parser. Splitting duplicates ~30 lines of shared logic across three files.
2. The `install.sh` manifest grows by 3 entries instead of 1; the integrity check grows by 3 entries.
3. The mode flags are mutually exclusive (validated explicitly), so a single dispatcher inside the script is straightforward.

If a fourth mode is added in the future, re-evaluate the split.

### Concurrency analysis: writer modes vs SubagentStop hook

The `--upsert` and `--increment-review-abort` modes both do read-modify-write. Concurrent invocations on the same file are explicitly unsupported (no flock). The non-obvious concurrent actor is the SubagentStop hook, which may `rm -f` the breadcrumb on TTL expiry.
- **Parent `--upsert`**: writes BEFORE spawning the subagent. SubagentStop cannot fire until the subagent's turn ends. No race.
- **Child `--upsert`** (standalone, Step 0): writes BEFORE the SubagentStop hook fires for this child. The hook's race window opens only after Step 8. No race.
- **Child `--increment-review-abort`** (review double-abort halt path): the child HALTs without ending its turn normally (explicit non-zero exit). SubagentStop does fire on turn end — but by then the writer has finished. The order is: writer completes → child exits → hook fires. No race.

The only remaining concurrency risk is two parallel `/implement-all[-cc]` invocations on the same `$cwd`. Explicitly unsupported.

---

## Task breakdown

### Phase 1 — Shell-layer foundation
> **Releasable**: after each task individually (each shell script change is unit-tested in isolation by bats). End-to-end recovery is NOT releasable until Phase 3 is complete because skills still don't invoke the new triage and parents still don't write v2 breadcrumbs.

### Releasability semantics

Per-task releasable means each task's shell-layer change is unit-testable in isolation AND does not break any existing caller. End-to-end recovery requires Phase 3.

> **Bats test isolation requirements** (apply to ALL Phase 1 test files):
> - Each test MUST use `setup()` to create a per-test scratch directory via `mktemp -d`, and export it as `$TEST_CWD`. The breadcrumb, anomalies log, and git repo all live under `$TEST_CWD`.
> - Each test MUST use `teardown()` to remove `$TEST_CWD` (best-effort `rm -rf`).
> - No test may write to `$BATS_TMPDIR` directly without a unique subdirectory.
> - The `$CWD` argument passed to scripts is always `$TEST_CWD`, never the developer's working directory.
> - Bats version requirement: 1.5+ for `$BATS_TEST_TMPDIR` (if used).

---

#### Task 0.1 — CLAUDE.md carve-out for machine-managed sentinels (PREREQUISITE)
**MUST be completed before any other task.** Without this, an implementing agent following CLAUDE.md will refuse to add `rm -f` calls in Tasks 1.4 and 1.5.

- [x] **File**: `~/.claude/CLAUDE.md`
- **Depends on**: nothing
- **Description**: Add a sub-bullet to the existing "# File Deletion" section:
  ```
  - **Exception — machine-managed sentinel files**: scripts under `~/.claude/scripts/` MAY use `rm -f` for the following sentinel file because it is ephemeral state and shipping it to trash creates clutter without recovery value:
    - `<project>/.claude/implement-next-state.json` (recovery breadcrumb)
  Note: `<project>/.claude/recovery-anomalies.log` is NEVER `rm`'d (truncation uses `tail > .tmp && mv`); it does NOT require this carve-out. Only `implement-next-state.json` is carved out for `rm -f`.
  All other deletions follow the `trash` rule.
  ```
- **Releasable**: after this task, an implementing agent will not refuse to add `rm -f` calls to the triage script.
- **Tests**: inline check `grep -F "machine-managed sentinel" ~/.claude/CLAUDE.md` returns ≥ 1 line.
- **Checkpoint**: `grep -F "machine-managed sentinel" ~/.claude/CLAUDE.md && grep -F "implement-next-state.json" ~/.claude/CLAUDE.md && echo OK`

---

#### Task 1.1 — `state-write.sh` default mode: atomic write + v2 schema + 6th positional arg
- [x] **File**: `~/.claude/scripts/implement-next-state-write.sh`
- **Depends on**: nothing
- **Description**:
  - Change usage to accept 5 OR 6 positional args. The 6th positional arg `<skill_variant>` (`"portable"` | `"cc"`) is OPTIONAL with a default of `"cc"` when omitted. This preserves backward-compat with the existing 5-arg caller at `implement-all-cc.md:55`; that caller is updated to pass the 6th arg explicitly in Task 3.1. Update the usage error message accordingly.
  - Validate `skill_variant ∈ {"portable", "cc"}` when supplied; exit 2 with diagnostic on any other value. When the 6th arg is omitted, treat it as `"cc"` (no exit 2).
  - Compute `branch_name`: `branch_name=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo "")`. The `-C "$cwd"` is mandatory because the writer may be invoked from a parent's working directory that differs from the script's pwd. Detached HEAD yields empty string.
  - Render JSON with the v2 schema: `schema_version: 2` (integer, not string), all existing fields, plus `branch_name`, `skill_variant`, `review_abort_count: 0` (integer).
  - Atomic write: render to `"$state_file.tmp"` (same filesystem as `$state_file`), then `mv "$state_file.tmp" "$state_file"`. `mv` is POSIX-atomic on same filesystem.
  - Default mode keeps the existing empty-`expected_agent_id` guard (`exit 2` if arg 5 is empty).
  - **Test-only hook**: the writer MUST honor `_RECOVERY_TEST_DELAY_BEFORE_MV` env var by sleeping the specified number of seconds between writing the `.tmp` and the `mv`. This is a test hook ONLY; the env var is undocumented in user-facing usage and must default to no delay.
  - Add a `# RECOVERY_SCHEMA_V2` marker comment near the top of the script for grep-based version checks.
- **Releasable**: after this task, the existing 5-arg caller continues to work via the `cc` default; Task 3.1 updates it to pass the arg explicitly. The writer can also be invoked directly with 6 args by future callers and tests pass.
- **Tests (TDD)** — `~/.claude/tests/recovery/test_writer.bats`:
  - Unit: `test_default_mode_writes_v2_schema` — invoke writer with valid 6 args; assert resulting JSON has `schema_version: 2` (integer), `branch_name` set, `skill_variant` set, `review_abort_count: 0` (integer).
  - Unit: `test_default_mode_accepts_six_or_five_args` — 5-arg invocation succeeds (exit 0) and the written breadcrumb has `skill_variant: "cc"` (default applied); 6-arg invocation succeeds with whatever variant was supplied. 4 args or fewer → exit 2 with usage diagnostic.
  - Unit: `test_default_mode_rejects_invalid_skill_variant` — `skill_variant="bogus"` (explicit 6th arg) → exit 2.
  - Unit: `test_default_mode_empty_expected_agent_id_rejected` — empty arg 5 + default mode → exit 2 (existing guard preserved).
  - Unit: `test_branch_name_captured_on_feature_branch` — set up tmp repo, checkout `feature/foo`, invoke writer; assert `branch_name == "feature/foo"`.
  - Unit: `test_branch_name_empty_on_detached_head` — `git checkout <sha>` (detached); writer succeeds with `branch_name: ""`.
  - Unit: `test_atomic_write_no_partial_file_visible` — invoke writer with env `_RECOVERY_TEST_DELAY_BEFORE_MV=1` so the writer sleeps 1s between writing the `.tmp` and the `mv`. Background the writer; after 0.5s, `kill -9 $!`. Assert the `.tmp` file may exist (or be partially written) but the final `state_file` is absent or contains the prior content (never half-written). This deterministic injection replaces a race-based test that the writer's microsecond runtime made unreliable.
  - Unit: `test_atomic_write_overwrites_cleanly` — invoke twice in sequence; second call's content fully replaces first; no `.tmp` orphan remains.
  - Checkpoint: `bats ~/.claude/tests/recovery/test_writer.bats --filter "default_mode|branch_name|atomic_write"`

---

#### Task 1.2 — `state-write.sh` `--upsert` flag with empty-`expected_agent_id`-permitted + read-merge semantics
- [ ] **File**: `~/.claude/scripts/implement-next-state-write.sh`
- **Depends on**: Task 1.1 (v2 schema baseline + atomic write)
- **Description**:
  - Add `--upsert` flag, parsed before positional args. Flag must precede `<cwd>`.
  - In `--upsert` mode: skip the empty-`expected_agent_id` guard (the writer accepts empty arg 5).
  - **Read-merge semantics**: if `state_file` exists, parse it; for each output field, prefer the existing non-empty value over the new-args value. Specifically:
    - `expected_agent_id`: if existing is non-empty, keep it; else use args.
    - `task_name`, `plan_path`, `sha_before`, `branch_name`, `skill_variant`: same precedence rule (existing non-empty wins).
    - `started_at`: keep existing if present; else compute fresh.
    - `schema_version`: always set to `2` (integer).
    - `review_abort_count`: keep existing if present (integer); else default `0`.
  - If `state_file` does not exist, behavior matches default mode minus the empty-agentId guard.
  - **Malformed existing breadcrumb**: if the file exists but is unparseable JSON, treat it as absent (create fresh). Never clobber the file silently if it parses but has unexpected shape — preserve any field that round-trips through `jq` cleanly.
  - **Safety note on "existing non-empty wins"**: this rule depends on the child invoking `--upsert` AFTER Step 0's triage has cleared any stale breadcrumb. If a future contributor moves the `--upsert` call BEFORE triage, a stale `task_name` could be preserved by the merge. Always invoke `--upsert` after triage in the skill's Step 0 sequence.
  - Atomic write applies as before.
- **Releasable**: after this task, the standalone child and the portable parent can write the breadcrumb without an agentId, and a parent-written `expected_agent_id` is never clobbered by a child's empty value.
- **Tests (TDD)** — `~/.claude/tests/recovery/test_writer.bats`:
  - Unit: `test_upsert_allows_empty_expected_agent_id` — `--upsert` + empty arg 5 → exit 0, JSON written.
  - Unit: `test_upsert_creates_new_breadcrumb_when_absent` — no existing file; `--upsert` writes a fresh v2 breadcrumb with empty `expected_agent_id`.
  - Unit: `test_upsert_preserves_existing_agent_id` — pre-write breadcrumb with `expected_agent_id="REAL_ID"`; `--upsert` with empty arg 5 → resulting JSON still has `expected_agent_id="REAL_ID"`.
  - Unit: `test_upsert_preserves_existing_non_empty_fields` — pre-write with `task_name="X"`, `branch_name="main"`; `--upsert` with different `task_name`, empty `branch_name` → resulting JSON preserves both pre-existing values.
  - Unit: `test_upsert_overwrites_empty_fields_with_new_args` — pre-write with `branch_name=""`; `--upsert` with `branch_name="feature/y"` → resulting JSON has `branch_name="feature/y"`.
  - Unit: `test_upsert_preserves_review_abort_count` — pre-write with `review_abort_count=1`; `--upsert` → still 1.
  - Unit: `test_upsert_keeps_existing_started_at` — pre-write with `started_at="2025-01-01T00:00:00Z"`; `--upsert` → keeps that timestamp.
  - Unit: `test_upsert_on_malformed_existing_breadcrumb_creates_fresh` — pre-write garbage to state file; invoke `--upsert` with valid args; assert writer succeeds with a fresh v2 breadcrumb (treating malformed as absent).
  - Checkpoint: `bats ~/.claude/tests/recovery/test_writer.bats --filter "upsert"`

---

#### Task 1.3 — `state-write.sh` `--increment-review-abort` flag
- [ ] **File**: `~/.claude/scripts/implement-next-state-write.sh`
- **Depends on**: Task 1.1 (atomic write + v2 schema)
- **Description**:
  - Add `--increment-review-abort` flag; takes only `<cwd>` as positional arg (no other positional args required).
  - Behavior:
    - Read existing `$cwd/.claude/implement-next-state.json`. If missing or unreadable: exit non-zero (e.g., `exit 3`) with stderr diagnostic "breadcrumb required for --increment-review-abort but not found at $state_file".
    - If `review_abort_count` field absent: treat as `0` and increment to `1`.
    - If present: increment by 1 (must remain integer in output JSON).
    - Atomic write the modified JSON; ALL other fields preserved verbatim.
  - Add usage diagnostic if combined with `--upsert` or with extra positional args: exit 2.
  - **Malformed existing breadcrumb**: exit non-zero with stderr diagnostic about malformed JSON. The `--increment-review-abort` mode cannot safely increment a counter that doesn't exist or whose surrounding fields cannot be preserved verbatim.
- **Releasable**: after this task, the child's Step 3 review-double-abort path can bump the counter durably so R-Stuck triggers on re-entry.
- **Tests (TDD)** — `~/.claude/tests/recovery/test_writer.bats`:
  - Unit: `test_increment_review_abort_from_zero_to_one` — pre-write breadcrumb with `review_abort_count=0`; invoke `--increment-review-abort`; resulting JSON has `1` (integer).
  - Unit: `test_increment_review_abort_from_one_to_two` — pre-write `1`; invoke; result `2`.
  - Unit: `test_increment_review_abort_treats_missing_field_as_zero` — pre-write breadcrumb without `review_abort_count`; invoke; result `1`.
  - Unit: `test_increment_review_abort_preserves_other_fields` — pre-write breadcrumb with specific values for all v2 fields; after increment, all non-counter fields byte-identical.
  - Unit: `test_increment_review_abort_missing_breadcrumb_exits_nonzero` — no breadcrumb on disk; invoke → exit code != 0; stderr contains "not found".
  - Unit: `test_increment_review_abort_rejects_upsert_combo` — `--increment-review-abort --upsert <cwd>` → exit 2.
  - Unit: `test_increment_review_abort_atomic` — invoke with env `_RECOVERY_TEST_DELAY_BEFORE_MV=1`; background; `kill -9 $!` after 0.5s. Assert resulting state_file is either pre-existing content or fully-incremented content, never partial. Deterministic injection — replaces unreliable race-based test.
  - Unit: `test_increment_review_abort_malformed_breadcrumb_exits_nonzero` — pre-write garbage; invoke `--increment-review-abort`; assert exit != 0 with stderr diagnostic about malformed JSON.
  - Checkpoint: `bats ~/.claude/tests/recovery/test_writer.bats --filter "increment_review_abort"`

---

#### Task 1.4 — `implement-next-triage.sh` classifier script
- [ ] **File**: `~/.claude/scripts/implement-next-triage.sh` (new)
- **Depends on**: Task 0.1 (CLAUDE.md `rm` carve-out for sentinel files), Task 1.1 (consumes v2 schema breadcrumbs written in tests)
- **Description**:
  - Bash script following the I/O contract in Architecture.
  - **Positional args**: `$1=cwd`, `$2=plan_path`, `$3=current_skill_variant`. Validate all three present and `$3 ∈ {"portable","cc"}`; otherwise exit 2.
  - **Output**: stdout `KEY=VALUE` lines + one `RECOVERY: ...` diagnostic line; stderr only on exit-1 cases. R-B's check-3 skip is now self-detected in Step 7 from the commit subject (no SKIP_CHECK3 variable emitted).
  - **Pre-checks** (before any breadcrumb logic):
    - **Canonicalize `cwd` to an absolute path**: `cwd=$(cd "$cwd" 2>/dev/null && pwd)` at the start of the script, before any other use of `$cwd`. If `cd` fails, exit 1 with stderr "cwd does not exist or is not accessible: $1". This guarantees all downstream uses (diagnostics, breadcrumb paths, anomalies log) are absolute regardless of caller.
    - `cwd` must be a directory; `plan_path` (from breadcrumb if present, else `$ARGUMENTS`) must exist when it's about to be consulted (the `plan file deleted between runs` case is exit 1).
    - `git -C "$cwd" rev-parse --git-dir` must succeed; otherwise exit 1.
    - `jq` must be in PATH; otherwise exit 1 with stderr naming the missing dep.
  - **`START_SHA` and `START_CHECKED`**:
    - `START_SHA = $(git -C "$cwd" rev-parse HEAD)` — emitted on every exit-0 path.
    - `START_CHECKED = $(awk '/^- \[[xX]\]/{c++} END{print c+0}' "$plan_path")` — emitted on every exit-0 path (computed against the on-disk plan).
  - **`NEXT_TASK_NAME` derivation** (compute once at the start, BEFORE dispatch): used both for the task_name-mismatch check AND for emitting `TASK_NAME` on R-Fresh paths:
    `NEXT_TASK_NAME=$(bash ~/.claude/scripts/plan-progress.sh "$plan_path" 2>/dev/null | grep '^NEXT_TASK_NAME=' | cut -d= -f2-)` (or fall back to `awk '/^- \[ \]/ {sub(/^- \[ \] /,""); print; exit}' "$plan_path"` if plan-progress.sh isn't available).

    On every exit-0 path:
    - R-A/R-B/R-AB/R-C: emit `TASK_NAME=<breadcrumb's task_name>`
    - R-Fresh: emit `TASK_NAME=$NEXT_TASK_NAME` (may be empty if plan has no unchecked tasks; the calling skill's Step 1 / plan-progress logic handles "all complete")
  - **Dispatch logic** (top-to-bottom; first match wins; see Architecture for full table).
    1. Read `review_abort_count` defensively: `review_abort_count=$(jq -r '.review_abort_count // 0' "$state_file" 2>/dev/null || echo 0)`. Validate integer before comparing: `if [[ "$review_abort_count" =~ ^[0-9]+$ ]] && [ "$review_abort_count" -ge 2 ]; then ...`. If the integer check fails (e.g., `null`, alpha string), proceed as if count were 0 — never crash bash. On R-Stuck → exit 1; stdout = only `RECOVERY:` line + `CASE=R-Stuck`; stderr diagnostic: `review failed twice for task '<task_name>' (sha_before=<X>); manual recovery required at <cwd>/.claude/implement-next-state.json. Either \`git checkout -- .\` to discard the review-touched files and delete <cwd>/.claude/implement-next-state.json, or commit manually and clear the breadcrumb with \`bash ~/.claude/scripts/implement-next-state-clear.sh <cwd>\`.` The diagnostic MUST include the absolute path to the breadcrumb file.
    2. No breadcrumb OR legacy (no `schema_version` + no v2 fields) → `R-Fresh`.
    3. `schema_version != 2` + one or more v2 fields present → `R-Fresh` (corrupt); diagnostic notes inconsistency. Treat `"schema_version": "2"` (string) as corrupt — the writer always emits integer; mismatch indicates external tampering or older writer.
    4. Malformed JSON → `R-Fresh`; diagnostic "Malformed JSON breadcrumb treated as absent.".
    5. `plan_path` from breadcrumb differs from `$2` (current) → `R-Fresh`; stale-plan diagnostic. Strings are compared literally; absolute vs relative paths that resolve to the same file are treated as mismatched (a known surface-only behavior).
    6. Breadcrumb's `task_name` is already committed-checked in `git -C "$cwd" show HEAD:$plan_path` (fixed-string `grep -F -- "- [x] $task_name"` OR `"- [X] $task_name"`) → delete stale breadcrumb (via `rm -f`); `R-Fresh`.
    7. Breadcrumb's `task_name` doesn't match `NEXT_TASK_NAME` (derived from `git -C "$cwd" show HEAD:$plan_path` via existing `plan-progress` logic OR plain re-extraction):
       - If `sha_before == HEAD` AND working tree clean → delete breadcrumb; `R-Fresh`; emit BOTH `RECOVERY:` line AND `WARNING: Auto-cleared stale breadcrumb for task '<task_name>' (next task per plan: '<NEXT_TASK_NAME>', no commits since breadcrumb, tree clean). If this was unexpected, check plan file integrity.`; append the WARNING line to `$cwd/.claude/recovery-anomalies.log` (create file if absent, append with `>>`). **On first append (the file did not exist immediately before this run)**, also emit `NOTE: Created .claude/recovery-anomalies.log. Add to your project's .gitignore to keep it out of version control.` on stderr.
       - Else → exit 1; stderr diagnostic naming plan editing / branch switch / prior crash.
    8. Breadcrumb's `branch_name` non-empty AND differs from current branch → emit warning naming both branches on stdout; continue dispatch as if branch matched. If `branch_name` is empty (writer was invoked in detached HEAD), skip the branch comparison entirely — never warn.
    9. Breadcrumb's `skill_variant` differs from `$3` → emit cross-variant warning; continue dispatch.
    10. Matched breadcrumb (passed all prior checks):
        - `HEAD == sha_before` + dirty → `R-A`; `REVIEW_RANGE=HEAD+worktree`; `STEP_2_RESUME=false`.
        - `HEAD != sha_before` + clean → `R-B`; `START_SHA=<sha_before>` (override); `REVIEW_RANGE=<sha_before>..HEAD`; `STEP_2_RESUME=false`. (Step 7's check 3 self-detects the R-B recovery commit from its subject prefix and skips itself; no SKIP_CHECK3 variable.)
        - `HEAD != sha_before` + dirty → `R-AB`; `REVIEW_RANGE=<sha_before>..HEAD+worktree`; `STEP_2_RESUME=false`; commit subject MUST begin with `recovery(R-AB): ` (no other prefix). Like R-B, the R-AB commit retroactively adds the plan checkoff for a partially-completed task and the audit script downgrades the VIOLATION to a WARNING.
        - `HEAD == sha_before` + clean → `R-C`; `REVIEW_RANGE=` (empty); `STEP_2_RESUME=true`.
  - **`recovery-anomalies.log` cap**: After any append, check line count. If > 10000, truncate via `tail -n 5000 "$log" > "$log.tmp" && mv "$log.tmp" "$log"`. This uses atomic `mv` (no `rm` involved); the log file is overwritten in place. The truncation operation does NOT require the CLAUDE.md `rm` carve-out.
  - **Observability stability contract**: the `RECOVERY: <case_name> detected. sha_before=<X>, head=<Y>, dirty=<bool>. <action_summary>.` line format is fixed; tests assert via regex.
  - Add `# RECOVERY_SCHEMA_V2` marker comment near the top.
  - Make script executable.
- **Releasable**: after this task, the classifier is callable in isolation and unit-tested. Skills still don't invoke it (added in Phase 2).
- **Tests (TDD)** — `~/.claude/tests/recovery/test_triage.bats`: implement all 15 rows from the Triage Unit Tests table in the brief. Each test:
  - Sets up `$BATS_TMPDIR/<fixture>/` with `git init`, a synthetic plan file with at least one unchecked task, and a crafted breadcrumb (or no breadcrumb) matching the row's "Pre" condition.
  - Invokes `bash ~/.claude/scripts/implement-next-triage.sh "$BATS_TMPDIR/<fixture>" "<plan>" "<variant>"`.
  - Asserts: exit code, `CASE=` line on stdout, ancillary `KEY=VALUE` lines per the "Other asserts" column.
  - Specific test names:
    - `test_no_breadcrumb_dispatches_r_fresh` (row 1)
    - `test_legacy_breadcrumb_dispatches_r_fresh` (row 2)
    - `test_corrupt_v2_field_without_version_dispatches_r_fresh` (row 3)
    - `test_committed_checked_breadcrumb_clears_and_r_fresh` (row 4)
    - `test_task_name_mismatch_clean_same_sha_r_fresh_with_warning` (row 5a)
    - `test_task_name_mismatch_dirty_or_moved_halt` (row 5b)
    - `test_matched_clean_same_sha_r_c` (row 6)
    - `test_matched_dirty_same_sha_r_a` (row 7)
    - `test_matched_clean_moved_r_b` (row 8)
    - `test_matched_dirty_moved_r_ab` (row 9)
    - `test_malformed_json_r_fresh` (row 11)
    - `test_branch_mismatch_warns_continues` (row 12)
    - `test_variant_mismatch_warns_continues` (row 13)
    - `test_plan_path_mismatch_r_fresh` (row 14)
    - `test_review_abort_count_two_r_stuck` (row 15)
  - Additional tests:
    - `test_plan_file_deleted_exit_1` — breadcrumb references nonexistent plan path → exit 1; stderr "plan file referenced by breadcrumb not found".
    - `test_recovery_line_format_regex` — for R-A case, stdout matches `^RECOVERY: R-A detected\. sha_before=[a-f0-9]+, head=[a-f0-9]+, dirty=true\. .*\.$`.
    - `test_anomalies_log_appended_on_auto_clear` — after row-5a scenario, `.claude/recovery-anomalies.log` exists with one WARNING line.
    - `test_anomalies_log_capped_at_10000_lines` — pre-populate with 10001 lines; trigger one more append; assert line count == 5001 (5000 from tail + 1 new).
    - `test_anomalies_log_first_creation_emits_gitignore_notice` — Trigger an auto-clear scenario with no pre-existing log; assert stderr contains the gitignore notice (`NOTE: Created .claude/recovery-anomalies.log`); assert log has exactly 1 line. Trigger AGAIN (different auto-clear scenario in same $TEST_CWD); assert stderr does NOT contain the notice; assert log has exactly 2 lines (one WARNING per trigger).
    - `test_legacy_breadcrumb_no_review_abort_count_no_r_stuck` — pre-write a v1 breadcrumb without `review_abort_count`; assert dispatch to R-Fresh (not R-Stuck), no bash error from the `[ ... -ge 2 ]` comparison.
    - `test_r_stuck_diagnostic_includes_absolute_breadcrumb_path` — trigger R-Stuck; assert stderr diagnostic contains the absolute path `<cwd>/.claude/implement-next-state.json`. Test variant: also invoke with relative `$cwd` (e.g., `cd /tmp && triage ./bats-XYZ ...`); assert the emitted path is still absolute.
    - `test_step7_check3_self_skip_on_recovery_commit` (in `test_step7_blocks_runnable.bats`) — set up repo with a `recovery(R-B):` commit at HEAD; run extracted Step 7 check 3; assert it emits "SKIPPED" and exits 0.
    - `test_detached_head_skips_branch_check` — set up tmp repo in detached HEAD; breadcrumb with `branch_name=""`; assert no branch warning emitted, dispatch proceeds normally.
    - `test_task_name_with_special_chars` — task name contains `*`, `[`, `]`; assert `grep -F` correctly handles it (no false positive/negative).
    - `test_plan_path_absolute_vs_relative_mismatch` — breadcrumb stores `/abs/path/plan.md`; current invocation passes `plan.md` (relative). Document the expected behavior (the plan currently says strings are compared literally → R-Fresh dispatch). Add the test asserting that exact behavior.
    - `test_schema_version_as_string_two_handled` — breadcrumb has `"schema_version": "2"` (string); treat as corrupt (R-Fresh) since the writer always emits integer; mismatch indicates external tampering or older writer.
    - `test_r_fresh_emits_task_name_from_plan` — invoke triage with no breadcrumb against a plan with one unchecked task; assert stdout has `TASK_NAME=<that task>` non-empty (derived from `NEXT_TASK_NAME`).
  - Checkpoint: `bats ~/.claude/tests/recovery/test_triage.bats`

---

#### Task 1.5 — `audit-plan-run.sh` recognizes `recovery(R-B):` marker + surfaces anomalies-log
- [ ] **File**: `~/.claude/scripts/audit-plan-run.sh`
- **Depends on**: Task 0.1 (CLAUDE.md `rm` carve-out for sentinel files)
- **Description**:
  - Add to the script after `commits` is counted (line ~89):
    - `recovery_commits=$(git rev-list --no-merges "${sha_start}..HEAD" --format='%s' | grep -cE '^recovery\((R-B|R-AB)\):' || true)` — count R-B AND R-AB markers. Note: `git rev-list --format='%s'` prefixes each subject with `commit <sha>\n` lines; use `git log --format='%s' --no-merges "${sha_start}..HEAD"` instead for cleaner output.
    - Replace usage with: `recovery_commits=$(git log --format='%s' --no-merges "${sha_start}..HEAD" 2>/dev/null | grep -cE '^recovery\((R-B|R-AB)\):' || true)`.
  - Change the final dispatch from `if [ "$commits" -eq "$completed" ]` to:
    - If `(commits - recovery_commits) == completed` AND `recovery_commits > 0` → `WARNING: Recovery commit(s) detected (count=$recovery_commits, types: $(git log --format='%s' --no-merges "${sha_start}..HEAD" | grep -oE '^recovery\(R-(B|AB)\):' | sort -u | tr '\n' ' '))`; PASS message; exit 0.
    - If `(commits - recovery_commits) == completed` AND `recovery_commits == 0` → existing PASS message; exit 0.
    - Else → existing VIOLATION message; exit 1.
  - **Anomalies-log surface**: after the audit verdict (regardless of pass/fail), check `$CWD/.claude/recovery-anomalies.log`. If it exists, append to stdout: `RECOVERY ANOMALIES LOG: $log_path (lines=$line_count)`. `$CWD` is `$(pwd)` since the audit runs at the repo root.
  - Add `# RECOVERY_SCHEMA_V2` marker comment.
  - Subject-line anchor enforcement: the regex `^recovery\((R-B|R-AB)\):` matches only at column 1 of the commit subject. Substring matches like `"This reverts recovery(R-B): foo"` are intentionally excluded (the existing `--no-merges` filter ignores merge commits).
  - **Recovery subject visibility**: when `recovery_commits > 0`, emit `git log --format='%h %s' --no-merges --grep='^recovery(R-\(B\|AB\)):' --extended-regexp` (or equivalent) output to stderr after the audit verdict for human review. Audit validates the marker by subject prefix only — the stderr listing lets a human eyeball the R-B and R-AB commit subjects.
- **Releasable**: after this task, R-B-marked commits don't cause spurious VIOLATIONs in the post-loop audit.
- **Tests (TDD)** — `~/.claude/tests/recovery/test_audit_marker.bats`:
  - Unit: `test_recovery_marker_downgrades_violation_to_warning` — covers BOTH `recovery(R-B):` and `recovery(R-AB):` markers. Setup repo with 3 commits, 2 tasks checked; one commit's subject is `recovery(R-B): foo`. Run audit → exit 0; stdout contains "WARNING: Recovery commit(s) detected (count=1". Variant: also test with `recovery(R-AB): foo` subject — same downgrade behavior.
  - Unit: `test_typo_marker_not_matched` — commit subject `recovery(R-X): foo` (typo) → counted as normal commit, VIOLATION reported as before.
  - Unit: `test_substring_match_not_counted` — commit subject `"This reverts recovery(R-B): foo"` (substring, not anchored) → NOT counted; VIOLATION if mismatch.
  - Unit: `test_recovery_commits_count_both_markers` — repo with 2 `recovery(R-B):` + 1 `recovery(R-AB):` + 1 normal commit + 1 task checked; assert `(4 - 3) == 1` → exit 0; "count=3" with both `R-B` and `R-AB` listed in the "types:" annotation.
  - Unit: `test_merge_commit_with_recovery_subject_ignored` — `git merge --no-ff` with subject `recovery(R-B): merge` → NOT counted (`--no-merges` filter).
  - Unit: `test_anomalies_log_existence_surfaced` — pre-create `.claude/recovery-anomalies.log` with 3 lines; run audit → stdout contains "RECOVERY ANOMALIES LOG: <path> (lines=3)".
  - Unit: `test_anomalies_log_absent_no_surface` — no log file → no "RECOVERY ANOMALIES LOG" line on stdout.
  - Unit: `test_no_recovery_markers_normal_pass` — 2 commits, 2 tasks checked, 0 R-B markers; assert exit 0; stdout contains "PASS"; stdout does NOT contain "WARNING".
  - Unit: `test_commit_count_and_recovery_count_use_consistent_filter` — Setup: create scratch repo; commit base; `git checkout -b tmp; git commit --allow-empty -m "recovery(R-B): merge-branch"; git checkout main`. Create 2 normal commits on main. Create 1 `recovery(R-B):` commit on main. `git merge --no-ff tmp` (creates a merge commit). Final state: 4 non-merge commits (1 base + 2 normal + 1 recovery), 1 merge commit, 1 recovery commit on the merged branch.
    Assertions: `git rev-list --count --no-merges base..HEAD` = 4 (merges excluded); `recovery_commits` count = 2 (one on main + one on the merged branch); audit's subtraction `(4 - 2) = 2` matches `completed = 2` tasks. Both counts MUST use `--no-merges`.
  - Checkpoint: `bats ~/.claude/tests/recovery/test_audit_marker.bats`

---

#### Task 1.6 — `implement-next-stop-gate.sh` bats coverage extension (no source change)
- [ ] **File**: `~/.claude/tests/recovery/test_hook_gate.bats` (new); no source changes to the gate script.
- **Depends on**: Task 1.1 (uses v2 breadcrumbs in fixtures)
- **Description**:
  - Pure-shell bats tests exercising `~/.claude/scripts/implement-next-stop-gate.sh` against three state scenarios. The hook gate's source is UNCHANGED — these tests lock in its behavior under the new state ecosystem (empty `expected_agent_id`, breadcrumb absence, mid-turn clear).
  - Each test crafts a hook input payload (JSON on stdin) and a state file on disk, invokes `bash ~/.claude/scripts/implement-next-stop-gate.sh`, asserts exit code + stdout content (block JSON or empty).
- **Releasable**: after this task, regressions in the hook gate's fail-open behavior are caught at test time.
- **Tests (TDD)** — `~/.claude/tests/recovery/test_hook_gate.bats`:
  - Unit: `test_hook_blocks_when_breadcrumb_present_agent_matches_no_commit` (fixture s) — v2 breadcrumb with `expected_agent_id="X"`, `sha_before == HEAD`; hook input payload has `agent_id="X"`, `cwd=$tmpdir`. Expected: exit 0; stdout JSON `{decision: "block", reason: ...}`.
  - Unit: `test_hook_passes_through_when_agent_mismatch` (fixture t) — breadcrumb `expected_agent_id="X"`; payload `agent_id="Y"`. Expected: exit 0; stdout empty.
  - Unit: `test_hook_passes_through_when_breadcrumb_absent` (fixture u) — no `.claude/implement-next-state.json`. Expected: exit 0; stdout empty.
  - Unit: `test_hook_passes_through_when_expected_agent_id_empty` — v2 breadcrumb with empty `expected_agent_id` (standalone child / portable parent case); any payload `agent_id`. Expected: exit 0; stdout empty (fail-open per `implement-next-stop-gate.sh:62-64`).
  - Unit: `test_hook_passes_through_when_new_commit_exists` — breadcrumb present, agent matches, but `HEAD != sha_before`; assert hook removes the breadcrumb AND exits 0 with no block JSON.
  - Unit: `test_hook_ttl_expired_removes_and_fails_open` — breadcrumb with `started_at` 5 hours ago → hook removes breadcrumb, exits 0.
  - Checkpoint: `bats ~/.claude/tests/recovery/test_hook_gate.bats`

---

#### Task 1.7 — `extract-bash-blocks.sh` helper

- [ ] **File**: `~/.claude/tests/recovery/extract-bash-blocks.sh` (new)
- **Depends on**: nothing
- **Description**: Tiny awk-based filter that reads markdown on stdin and prints the contents of all triple-backtick-fenced code blocks, EXCLUDING the fence lines themselves. Used by Step 7 block-mirror tests in Tasks 2.1/2.2.
  - Implementation: `awk 'BEGIN{inb=0} /^```/{inb=1-inb; next} inb{print}'`
  - Make script executable.
- **Releasable**: after this task, the diff command in Tasks 2.1/2.2 has a defined extractor.
- **Tests (TDD)** — new file `~/.claude/tests/recovery/test_extract_bash_blocks.bats`:
  - `test_extracts_single_fenced_block` — markdown with one ``` block → stdout matches the block content (no fences).
  - `test_extracts_multiple_blocks_concatenated` — markdown with three blocks → stdout is the three block contents concatenated, in order.
  - `test_no_blocks_yields_empty_output` — markdown with no fences → stdout empty.
  - `test_fence_lines_are_excluded` — a fence line containing ` ```bash ` is NOT in the output.
- **Checkpoint**: `bats ~/.claude/tests/recovery/test_extract_bash_blocks.bats`

---

### Phase 2 — Child skill integration
> **Releasable**: after Phase 2 + Phase 3 together. Child skills depend on parent breadcrumb writes (Phase 3) for the full recovery loop. Phase 2 alone allows standalone-child use; full parent-driven recovery requires Phase 3.

---

#### Task 2.1 — `implement-next.md` Step 0 triage + `START_SHA` / `START_CHECKED` capture move
- [ ] **File**: `~/.claude/commands/implement-next.md`
- **Depends on**: Task 1.4 (triage script must exist)
- **Description**:
  - Insert a new section between the frontmatter / "Using in Cursor" preamble and "Step 1: Show progress and identify the next task":

    ```
    ### Step 0: Triage prior state

    Before anything else, shell out to the triage classifier:

    \`\`\`
    bash ~/.claude/scripts/implement-next-triage.sh "$(pwd)" "$ARGUMENTS" "portable"
    \`\`\`

    Read the exit code FIRST.

    - **Non-zero exit**: print the `RECOVERY:` diagnostic line from stdout (and any stderr), then **exit your turn immediately**. Do NOT run Step 1 or any subsequent step.
    - **Exit 0**: parse `KEY=VALUE` lines from stdout. Record:
      - `CASE` (one of: `R-Fresh`, `R-A`, `R-B`, `R-AB`, `R-C`)
      - `START_SHA` (use this for Step 7's self-verification)
      - `START_CHECKED` (use this for Step 7's self-verification)
      - `SHA_BEFORE` (R-A/R-B/R-AB only)
      - `BRANCH_NAME` (informational; warnings already printed by triage)
      - `TASK_NAME` (next task to act on)
      - `REVIEW_RANGE` (passed to Step 3)
      - `STEP_2_RESUME` (R-C only)
      - `REVIEW_ABORT_COUNT` (informational)
    - Print the `RECOVERY:` diagnostic line verbatim so the user sees the case.

    **Dispatch on `CASE`:**

    - `R-Fresh` → proceed to Step 1 (existing flow).
    - `R-A` → SKIP Step 1 and Step 2; jump to Step 3 with `REVIEW_RANGE=HEAD+worktree`.
    - `R-B` → SKIP Step 1 and Step 2; the breadcrumb's `sha_before` already contains the orphan impl commit. Insert the plan-file checkoff for `TASK_NAME` into the working tree (do not commit yet). Jump to Step 3 with `REVIEW_RANGE=<sha_before>..HEAD`. Step 6's commit message MUST begin with `recovery(R-B): ` followed by a task-derived summary.
    - `R-AB` → SKIP Step 1 and Step 2; jump to Step 3 with `REVIEW_RANGE=<sha_before>..HEAD+worktree`. Step 6's commit message MUST begin with `recovery(R-AB): ` followed by a task-derived summary.
    - `R-C` → SKIP Step 1; resume Step 2 implementing ONLY the sub-items unchecked in `git show HEAD:$ARGUMENTS` (if `git show HEAD:$ARGUMENTS` fails — untracked plan or first-time commit — treat ALL sub-items as unchecked-in-HEAD).
    ```

  - In Step 1, REMOVE the line: `Record \`START_SHA = $(git rev-parse HEAD)\` and \`START_CHECKED = $(awk '/^- \[[xX]\]/{c++} END{print c+0}' "$ARGUMENTS")\`. These are used by the Step 7 self-verification.` (currently at `implement-next.md:25`). The triage now emits these; Step 1's job is solely to show progress and identify the next task.
  - In Step 3, add a sentence: "If `REVIEW_RANGE` was set by Step 0, use it; otherwise default to `git diff HEAD`." This routes R-A / R-B / R-AB to the correct review target.
  - **Step 7 check 3 self-contained R-B detection**: Replace the prior `SKIP_CHECK3`-driven approach with a self-contained R-B detection in bash. Check 3 (commit-diff includes both plan AND impl): wrap in a self-contained R-B detection — if the latest commit's subject begins with `recovery(R-B):`, the commit is plan-only by design; skip the check. Bash:
    ```
    if git log -1 --format='%s' HEAD | grep -q '^recovery(R-B):'; then
      echo "Step 7 check 3: SKIPPED (R-B recovery commit is plan-only by design)"
    else
      # existing check 3 logic
    fi
    ```
    This eliminates LLM-memory dependence on the Step 0 case.
  - In Step 3, replace the "Critical review" subsection's abort handling with:
    - "If the iterative-review (or critic) aborts mid-flow with unresolved findings, restart it ONCE."
    - "If the restart also aborts: run `bash ~/.claude/scripts/implement-next-state-write.sh --increment-review-abort "$(pwd)"`, then HALT — do NOT commit. Print the unresolved findings, leave the working tree as-is, end your turn with non-zero exit. The next invocation's triage will see `review_abort_count >= 2` and dispatch R-Stuck."
  - In Step 6, add: "If Step 0 dispatched R-B, the commit subject MUST begin with `recovery(R-B): ` (no other prefix). `audit-plan-run.sh` matches against this anchored prefix to downgrade VIOLATION to WARNING." Also add: "If Step 0 dispatched R-AB, the commit subject MUST begin with `recovery(R-AB): ` (audit downgrades VIOLATION to WARNING)."
  - Add `<!-- RECOVERY_SCHEMA_V2 -->` marker as an HTML comment near the top of the file.
- **Releasable**: after this task, the portable child skill triages on entry. Standalone-child mode works (no parent breadcrumb required for R-Fresh). Recovery cases still require Task 3.2's portable parent breadcrumb write to be useful.
- **Tests (TDD)** — manual integration scenarios from the brief's Catalog:
  - **Note**: this is an LLM-driven skill, not pure shell. Bats cannot intercept markdown consumed by an LLM. Validation happens manually in scratch-repo sessions per fixtures (a), (b), (c), (d), (h) of the Manual Integration Test Catalog.
  - Inline syntactic check: `grep -F "implement-next-triage.sh" ~/.claude/commands/implement-next.md` returns ≥ 1 line.
  - Inline check: `grep -F "RECOVERY_SCHEMA_V2" ~/.claude/commands/implement-next.md` returns ≥ 1 line.
  - Inline check: `grep -F "recovery(R-B):" ~/.claude/commands/implement-next.md` returns ≥ 1 line.
  - Inline check: the old `Record \`START_SHA = $(git rev-parse HEAD)\`` line is gone — `! grep -F "Record \`START_SHA" ~/.claude/commands/implement-next.md`.
  - Shell-extractable check (in addition to grep): extract the Step 7 bash blocks from the markdown via `sed -n '/^### Step 7/,/^### Step 8/p'` piped through `awk '/^```/,/^```$/'`; run each block against a synthetic repo in the new bats test `test_step7_blocks_runnable.bats`. Specifically test: `test_step7_check_task_commit_succeeds_after_commit`, `test_step7_checkoff_count_grows_after_check`, and `test_step7_blocks_expected_files_are_identical` — `diff -q ~/.claude/tests/recovery/step7-blocks-expected-portable.sh ~/.claude/tests/recovery/step7-blocks-expected-cc.sh` exits 0 (enforces the textual mirror invariant). This catches typos in the extracted bash that grep cannot detect.

    **Extractor + substitution mechanism**:
    The bats test does NOT `sed | awk | bash` the markdown verbatim. Instead:
    1. For each named check (check 1, check 2, check 3), the test file contains a HAND-WRITTEN bash block that mirrors the markdown's check exactly — kept in sync via a `RECOVERY_SCHEMA_V2` grep ascertaining the markdown text matches.
    2. The bats test executes these hand-written blocks against a synthetic repo with known SHAs, plan paths, and check counts.
    3. The bats test ALSO does a syntactic equivalence check: `diff <(sed -n '/^### Step 7/,/^### Step 8/p' ~/.claude/commands/implement-next.md | bash ~/.claude/tests/recovery/extract-bash-blocks.sh) <(cat ~/.claude/tests/recovery/step7-blocks-expected-portable.sh)` — this catches drift between the markdown and the hand-written test mirror. If Step 7 ever diverges between the two skills (e.g., cc gains an extra check), maintain two distinct expected files.

    This avoids the fragility of `sed + awk` extraction and runtime placeholder substitution while still catching markdown-side regressions.
  - Checkpoint: `grep -F "implement-next-triage.sh" ~/.claude/commands/implement-next.md && grep -F "RECOVERY_SCHEMA_V2" ~/.claude/commands/implement-next.md && ! grep -F "Record \`START_SHA" ~/.claude/commands/implement-next.md && echo OK`

---

#### Task 2.2 — `implement-next-cc.md` Step 0 triage + Step 7 self-verification + START capture move + parent-detect breadcrumb-write rule
- [ ] **File**: `~/.claude/commands/implement-next-cc.md`
- **Depends on**: Task 1.4 (triage script), Task 1.2 (`--upsert` mode for standalone child)
- **Description**:
  - Insert a new Step 0 between the frontmatter and "Step 1", mirroring Task 2.1's Step 0 but with `"cc"` as the third arg to triage:

    ```
    ### Step 0: Triage prior state

    \`\`\`
    bash ~/.claude/scripts/implement-next-triage.sh "$(pwd)" "$ARGUMENTS" "cc"
    \`\`\`

    [identical exit-code handling and CASE dispatch as in implement-next.md, including: R-B → Step 6's commit message MUST begin with `recovery(R-B): `; R-AB → Step 6's commit message MUST begin with `recovery(R-AB): `]
    ```

  - **Standalone-child breadcrumb write**: in Step 0, after triage emits `R-Fresh`, the child writes a breadcrumb via `--upsert` so the SubagentStop hook has something to look at AND so a subsequent interruption is recoverable:

    ```
    bash ~/.claude/scripts/implement-next-state-write.sh --upsert "$(pwd)" "$START_SHA" "$ARGUMENTS" "$TASK_NAME" "" "cc"
    ```

    Note: empty arg 5 (`expected_agent_id`) — child cannot reliably know its own agentId, hook fails open per `implement-next-stop-gate.sh:62-64`. Per the brief's Key Decisions: "on R-Fresh the child ALWAYS attempts a `--upsert` write" — `--upsert`'s read-merge means a parent-written breadcrumb (if any) is preserved verbatim; only the absent case results in the child writing its own.

  - **Add Step 7 self-verification** mirroring `implement-next.md:94-119`. Insert between the current Step 6 and the current Step 7 (Report):

    ```
    ### Step 7: Self-verification

    Before ending your turn, programmatically verify the work landed.

    Run these checks (with `START_SHA` and `START_CHECKED` from Step 0; for R-B, `START_SHA` is the breadcrumb's `sha_before`):

    1. **A new commit exists since the iteration started:**
       \`\`\`
       bash ~/.claude/scripts/check-task-commit.sh "$START_SHA"
       \`\`\`
       Exit 0 = at least one new commit. Exit 1 = zero.

    2. **The plan file's checked-task count grew by at least 1:**
       \`\`\`
       END_CHECKED=$(awk '/^- \[[xX]\]/{c++} END{print c+0}' "$ARGUMENTS")
       test $((END_CHECKED - START_CHECKED)) -ge 1
       \`\`\`

    3. **The new commit's diff includes both the plan file AND implementation files**. Wrap this in a self-contained R-B detection — if the latest commit's subject begins with `recovery(R-B):`, the commit is plan-only by design; skip the check. Bash:
       \`\`\`
       if git log -1 --format='%s' HEAD | grep -q '^recovery(R-B):'; then
         echo "Step 7 check 3: SKIPPED (R-B recovery commit is plan-only by design)"
       else
         # existing check 3 logic
       fi
       \`\`\`
       This eliminates LLM-memory dependence on the Step 0 case.

    On any check failure, do NOT end your turn. Diagnose and return to the appropriate step. If the same check fails twice in a row, report the specific failure and end with "task incomplete" status.

    On success, clear the breadcrumb:
    \`\`\`
    bash ~/.claude/scripts/implement-next-state-clear.sh "$(pwd)"
    \`\`\`
    ```

  - **Renumber existing "Report" step** to Step 8.

  - In Step 3 (DA review loop), mirror the same review-double-abort rule as Task 2.1: restart once; on second abort run `--increment-review-abort` and HALT.

  - In Step 6, add the same `recovery(R-B):` commit-message prefix requirement for R-B AND the `recovery(R-AB):` prefix requirement for R-AB (audit downgrades VIOLATION to WARNING for both).

  - Add `<!-- RECOVERY_SCHEMA_V2 -->` marker.

  - **Parent-detect rule**: at Step 0 (after triage's R-Fresh dispatch), the child's breadcrumb-write is unconditional via `--upsert`. If a parent already wrote a breadcrumb with a real `expected_agent_id`, the `--upsert` read-merge preserves it; if not, the child writes its own with empty `expected_agent_id`. The skill does NOT need to inspect parent identity — the writer's merge logic handles both cases. This is the brief's "pragmatic rule" decision.

- **Releasable**: after this task, the cc child triages on entry, performs Step 7 self-verification, and the standalone-child case is recoverable. Full `-cc` parent-driven recovery requires Task 3.1.
- **Tests (TDD)** — manual integration scenarios from the brief's Catalog (fixtures a, b, c, d, h, i, o, r1, r2 of the Manual Integration Test Catalog):
  - Inline syntactic checks:
    - `grep -F "implement-next-triage.sh" ~/.claude/commands/implement-next-cc.md` returns ≥ 1 line.
    - `grep -F "implement-next-state-write.sh --upsert" ~/.claude/commands/implement-next-cc.md` returns ≥ 1 line.
    - `grep -F "Step 7: Self-verification" ~/.claude/commands/implement-next-cc.md` returns ≥ 1 line.
    - `grep -F "Step 8: Report" ~/.claude/commands/implement-next-cc.md` returns ≥ 1 line.
    - `grep -F "RECOVERY_SCHEMA_V2" ~/.claude/commands/implement-next-cc.md` returns ≥ 1 line.
    - `grep -F "recovery(R-B):" ~/.claude/commands/implement-next-cc.md` returns ≥ 1 line.
    - `grep -F "implement-next-state-clear.sh" ~/.claude/commands/implement-next-cc.md` returns ≥ 1 line (for Step 7's success clear).
  - Shell-extractable check (in addition to grep): extract the Step 7 bash blocks from the markdown via `sed -n '/^### Step 7/,/^### Step 8/p'` piped through `awk '/^```/,/^```$/'`; run each block against a synthetic repo in the new bats test `test_step7_blocks_runnable.bats`. Specifically test: `test_step7_check_task_commit_succeeds_after_commit`, `test_step7_checkoff_count_grows_after_check`. This catches typos in the extracted bash that grep cannot detect.

    **Extractor + substitution mechanism**:
    The bats test does NOT `sed | awk | bash` the markdown verbatim. Instead:
    1. For each named check (check 1, check 2, check 3), the test file contains a HAND-WRITTEN bash block that mirrors the markdown's check exactly — kept in sync via a `RECOVERY_SCHEMA_V2` grep ascertaining the markdown text matches.
    2. The bats test executes these hand-written blocks against a synthetic repo with known SHAs, plan paths, and check counts.
    3. The bats test ALSO does a syntactic equivalence check: `diff <(sed -n '/^### Step 7/,/^### Step 8/p' ~/.claude/commands/implement-next-cc.md | bash ~/.claude/tests/recovery/extract-bash-blocks.sh) <(cat ~/.claude/tests/recovery/step7-blocks-expected-cc.sh)` — this catches drift between the markdown and the hand-written test mirror. If Step 7 ever diverges between the two skills (e.g., cc gains an extra check), maintain two distinct expected files.

    This avoids the fragility of `sed + awk` extraction and runtime placeholder substitution while still catching markdown-side regressions.
  - Checkpoint: combined `grep` chain returning OK.

---

#### Task 2.3 — `implement-next-cc-resume.md` clears breadcrumb after Step 2 commit
- [ ] **File**: `~/.claude/commands/implement-next-cc-resume.md`
- **Depends on**: nothing (uses existing `implement-next-state-clear.sh` signature)
- **Description**:
  - In Step 2, after the successful commit, add a final line (or insert a Step 2.5):
    ```
    After the commit succeeds, clear the breadcrumb so the parent's next-iteration check isn't poisoned:
    \`\`\`
    bash ~/.claude/scripts/implement-next-state-clear.sh "$(pwd)"
    \`\`\`
    ```
  - The clear is the last action on the success path. If the commit fails (Step 2 already says "report failure; parent will halt"), the parent's halt-path clear handles cleanup — this skill does NOT clear on commit failure.
  - Add `<!-- RECOVERY_SCHEMA_V2 -->` marker.
- **Releasable**: after this task, the Case-B rescue path leaves no stale breadcrumb behind on success — regression catcher for fixture (v).
- **Tests (TDD)** — manual scenario (v) of the Manual Integration Test Catalog (rescue-path breadcrumb clear).
  - Inline syntactic check: `grep -F "implement-next-state-clear.sh" ~/.claude/commands/implement-next-cc-resume.md` returns ≥ 1 line.
  - Inline check: `grep -F "RECOVERY_SCHEMA_V2" ~/.claude/commands/implement-next-cc-resume.md` returns ≥ 1 line.
  - Checkpoint: `grep -F "implement-next-state-clear.sh" ~/.claude/commands/implement-next-cc-resume.md && grep -F "RECOVERY_SCHEMA_V2" ~/.claude/commands/implement-next-cc-resume.md && echo OK`

---

### Phase 3 — Parent skill integration
> **Releasable**: after both 3.x tasks complete. Parent breadcrumb writes + halt-path clears, combined with Phase 2's children, make the recovery system end-to-end functional in real sessions.

---

#### Task 3.1 — `implement-all-cc.md` pre-spawn breadcrumb write + remove unconditional clear + halt-path clears
- [ ] **File**: `~/.claude/commands/implement-all-cc.md`
- **Depends on**: Task 1.1 (v2 schema + 6-arg signature)
- **Description**:
  - **Step 4 modification**: change the prose to specify ordering — the writer is called AFTER `Agent` returns the `agentId` and BEFORE the wait. Update the bash snippet:
    ```
    bash ~/.claude/scripts/implement-next-state-write.sh "<CWD>" "<START_SHA>" "<plan-path>" "<NEXT_TASK_NAME>" "<agentId-from-step-3>" "cc"
    ```
    Note the new 6th arg `"cc"`. Default mode (no `--upsert`) — the parent owns the breadcrumb and has a real agentId.
  - Update the surrounding prose to explicitly state: "Default-mode write (no `--upsert`). `expected_agent_id` is the agentId returned by `Agent` in Step 3."
  - **Step 6 modification**: REMOVE the unconditional `implement-next-state-clear.sh` invocation (currently around line 64-67, inside "Always clear the sentinel after this step regardless of outcome"). The child's Step 7 now clears on success; the parent only clears on halt paths.
  - **Halt-path clears**: add an explicit `bash ~/.claude/scripts/implement-next-state-clear.sh "<CWD>"` invocation at each halt:
    - Case B after-rescue-still-fails (current line ~82: "If still Case B after the rescue, halt with diagnostic.") — add clear before the halt.
    - Case C halt (current line ~84).
    - Case D halt (current line ~86).
    - Stuck-task guard halt (current line ~34).
    - Iteration-count exceeded halt (current line ~19).
  - **Final audit** (Step 8): add a clear AFTER the audit completes (line ~97) — defense-in-depth for clean runs.
  - Add `<!-- RECOVERY_SCHEMA_V2 -->` marker.
- **Releasable**: after this task, `-cc` parent writes the breadcrumb pre-spawn, child Step 0 finds it, recovery dispatches correctly. End-to-end recovery for `-cc` is functional.
- **Tests (TDD)** — manual scenarios (o), (p), (q) of the Manual Integration Test Catalog (`-cc` parent full lifecycle, convergence on Case-C, multi-iteration recovery).
  - Inline syntactic checks:
    - `grep -F "implement-next-state-write.sh" ~/.claude/commands/implement-all-cc.md` returns ≥ 1 line.
    - `grep -F '"cc"' ~/.claude/commands/implement-all-cc.md` returns ≥ 1 line (the new 6th arg).
    - Count of `implement-next-state-clear.sh` occurrences ≥ 4 (Case B after-rescue, Case C, Case D, final audit + stuck-task / iter-count).
    - `! grep -B2 -A2 "Always clear the sentinel after this step regardless of outcome" ~/.claude/commands/implement-all-cc.md | grep -F "implement-next-state-clear.sh"` (the unconditional clear is gone).
    - `grep -F "RECOVERY_SCHEMA_V2" ~/.claude/commands/implement-all-cc.md` returns ≥ 1 line.
  - Checkpoint: combined `grep` chain returning OK + a manual session run per fixture (o).

---

#### Task 3.2 — `implement-all.md` (portable parent) breadcrumb write + halt-path clears
- [ ] **File**: `~/.claude/commands/implement-all.md`
- **Depends on**: Task 1.2 (`--upsert` mode for empty `expected_agent_id`)
- **Description**:
  - **After Step 3's subagent spawn** (currently around line 53-55: "Wait for the subagent to return before continuing."), add a new step segment BEFORE the wait:
    ```
    Immediately after spawning the subagent, write the recovery breadcrumb (the portable variant has no SubagentStop hook to coordinate with, so use `--upsert` with empty `expected_agent_id`):

    \`\`\`
    bash ~/.claude/scripts/implement-next-state-write.sh --upsert "$CWD" "$START_SHA" "<plan-path>" "$NEXT_TASK_NAME" "" "portable"
    \`\`\`

    The `--upsert` flag is required because portable parents don't have an agentId; the hook fails open on empty `expected_agent_id`, but the child's breadcrumb-based recovery still works.

    Then wait for the subagent to return.
    ```
  - **Step 4 halt-path clears**: in each of the four cases (line 60-67), add `bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"` BEFORE the halt:
    - `END_SHA != START_SHA` + clean + NEXT_TASK_NAME unchanged → halt.
    - `END_SHA == START_SHA` + dirty → halt (portable doesn't auto-rescue).
    - `END_SHA == START_SHA` + clean → halt.
    - `END_SHA != START_SHA` + dirty → halt.
  - **Stuck-task guard** (line ~33) and **iteration-count exceeded** (line ~18): add clear before each halt.
  - **Step 5 final audit** (line 69-77): add clear AFTER the audit.
  - **Success continuation path** (`END_SHA != START_SHA` + clean + NEXT_TASK_NAME changed → continue): the child's Step 7 cleared the breadcrumb already, so no parent action needed; but as a defense-in-depth, before the next iteration's Step 2 capture, the parent's flow naturally re-writes via `--upsert` (which read-merges any leftover state correctly).
  - Add `<!-- RECOVERY_SCHEMA_V2 -->` marker.
- **Releasable**: after this task, the portable parent writes the breadcrumb pre-spawn. Recovery for `/implement-all` users matches `-cc` parity.
- **Tests (TDD)** — manual scenario (o-portable) of the Manual Integration Test Catalog.
  - Inline syntactic checks:
    - `grep -F "implement-next-state-write.sh --upsert" ~/.claude/commands/implement-all.md` returns ≥ 1 line.
    - `grep -F '"portable"' ~/.claude/commands/implement-all.md` returns ≥ 1 line (new 6th arg).
    - Count of `implement-next-state-clear.sh` occurrences ≥ 5 (4 Step 4 halts + final audit; or include stuck-task and iter-count for ≥ 7).
    - `grep -F "RECOVERY_SCHEMA_V2" ~/.claude/commands/implement-all.md` returns ≥ 1 line.
  - Checkpoint: combined `grep` chain returning OK + a manual session run per fixture (o-portable).

---

### Phase 4 — Installer, documentation, and final verification
> **Releasable**: after this phase, the feature is fully shipped: installer includes the new triage script, integrity check covers it, handout docs describe the recovery behavior, and the Manual Integration Test Catalog has been executed end-to-end.

---

#### Task 4.1 — `install.sh` manifest + integrity-check additions for `implement-next-triage.sh`
- [ ] **File**: `~/.claude/install.sh`
- **Depends on**: Task 1.4 (triage script must exist on disk)
- **Description**:
  - **First `files` array** (around `install.sh:177-182`): add `scripts/implement-next-triage.sh` in alphabetical-ish order alongside the other `scripts/implement-next-*` entries. Specifically: change the line `scripts/implement-next-state-clear.sh scripts/implement-next-state-write.sh` and the next line `scripts/implement-next-stop-gate.sh` to include `scripts/implement-next-triage.sh` (grouped with the implement-next family).
  - **Second `files` array** (around `install.sh:542-544`): identical addition.
  - **`check_cc_variant_integrity()`** (around `install.sh:483-497`): extend the `for f in ...` list to include `scripts/implement-next-triage.sh`. Both variants (`cc` and `portable`) require this script — there's no `check_portable_variant_integrity()` mirror currently, and the brief calls that out as a known limitation (line 357 of the brief).
  - **Add `check_portable_variant_integrity()` to `install.sh`**: mirror the cc check, listing `commands/implement-all.md`, `commands/implement-next.md`, and the shared `scripts/implement-next-triage.sh`. Without this, a portable-only install missing the triage script fails at Step 0 with a raw "bash: not found" and no diagnostic.
    Invoke `check_portable_variant_integrity()` from the same post-install block that calls `check_cc_variant_integrity()` (look for the existing `check_cc_variant_integrity` call site around `install.sh:~620` or wherever it's currently invoked). Both checks are invoked unconditionally (both variants share `scripts/implement-next-triage.sh`).
  - Add a comment at each insertion point: `# RECOVERY_SCHEMA_V2`.
  - Add the test directory exclusion remains as-is: `~/.claude/tests/recovery/` is NOT installed (matches existing convention — tests live in-repo only). No change needed in the installer for test fixtures.
- **Releasable**: after this task, a fresh `~/.claude/install.sh` install puts the triage script in place; the integrity check warns if it's missing.
- **Tests (TDD)** — extend existing `~/.claude/tests/test_install_copy.bats` or add a new `test_install_recovery.bats`:
  - Unit: `test_install_copies_triage_script` — run installer in dry-run mode; assert `scripts/implement-next-triage.sh` appears in the dry-run output.
  - Unit: `test_install_integrity_check_includes_triage` — install in a tmp DEST_DIR; remove `scripts/implement-next-triage.sh` from DEST_DIR; call `check_cc_variant_integrity` (or simulate it); assert the warning message contains `scripts/implement-next-triage.sh`.
  - Unit: `test_install_portable_integrity_check_includes_triage` — symmetric to the cc test; install in a tmp DEST_DIR; remove the triage script; call `check_portable_variant_integrity`; assert warning message contains `scripts/implement-next-triage.sh` for portable.
  - Unit: `test_install_calls_both_integrity_checks_end_to_end` — install.sh in a tmp DEST_DIR succeeds with all source files present. AFTER successful install, remove `${DEST_DIR}/scripts/implement-next-triage.sh`. Source install.sh functions (`. ${DEST_DIR}/install.sh` or `. ${SRC}/install.sh` depending on how functions are exported) and invoke both `check_cc_variant_integrity` and `check_portable_variant_integrity` directly against the modified DEST_DIR. Assert stderr from BOTH calls names `scripts/implement-next-triage.sh` in the warning. Fallback variant: post-install, remove triage script from DEST_DIR; re-run install.sh (it should detect existing DEST_DIR and skip copy step) and observe both integrity warnings on stderr.
  - Inline syntactic check: `grep -c "implement-next-triage" ~/.claude/install.sh` ≥ 4 (two files arrays + two integrity checks).
  - Checkpoint: `bats ~/.claude/tests/test_install_copy.bats` (or the new test file)

---

#### Task 4.2 — Handout HTML documentation updates (English + Hungarian)
- [ ] **File**: see list below (six pairs of HTML files)
- **Depends on**: Tasks 2.1, 2.2, 2.3, 3.1, 3.2 (the behavior must be settled before documenting it)
- **Description**:
  - **`~/.claude/handout/scripts-plan.html`** and **`~/.claude/handout/scripts-plan-hu.html`** — add `implement-next-triage.sh` to the script catalog with its purpose ("classifier with bounded state-hygiene side effects — reads breadcrumb + repo state, prints CASE= and ancillary vars"), I/O contract (positional args + stdout/stderr/exit codes), and a one-line example invocation.
  - **`~/.claude/handout/cmd-implement-all-cc.html`** and Hungarian counterpart — describe:
    - The pre-spawn breadcrumb write timing (after `Agent` returns `agentId`, before wait).
    - Removal of the unconditional `implement-next-state-clear.sh` invocation.
    - The new halt-path clear pattern (Cases B-after-rescue, C, D, stuck-task, iter-count).
  - **`~/.claude/handout/cmd-implement-next-cc.html`** and Hungarian counterpart — describe:
    - Step 0 triage classifier shell-out.
    - Step 7 self-verification (new — mirroring `implement-next.md`).
    - Step 8 Report (renumbered).
    - The standalone-child `--upsert` breadcrumb write at Step 0.
  - **`~/.claude/handout/cmd-implement-all.html`** and Hungarian counterpart (if these files exist; if not, list as TODO and create stubs):
    - Describe the portable parent's `--upsert` breadcrumb write.
    - Describe the halt-path clears.
  - **`~/.claude/handout/cmd-implement-next.html`** and Hungarian counterpart (if these files exist; if not, list as TODO):
    - Describe Step 0 triage classifier shell-out.
    - Note that `START_SHA` / `START_CHECKED` capture moved to Step 0.
  - **`~/.claude/handout/cmd-implement-next-cc-resume.html`** and Hungarian counterpart — describe the new breadcrumb-clear after Step 2's commit.
  - **Glossary update** (if a glossary HTML exists): add R-* case definitions (R-Fresh, R-A, R-B, R-AB, R-C, R-Halt, R-Stuck) and explain `recovery(R-B):` commit-marker semantics.
  - Per `~/.claude/CLAUDE.md` documentation-currency rule: this MUST happen in the same session as the code changes. No exceptions.
- **Releasable**: after this task, end-user-facing docs reflect the recovery behavior.
- **Tests (TDD)** — none (documentation; verified by inspection):
  - Inline check: `grep -l "implement-next-triage" ~/.claude/handout/scripts-plan*.html` returns ≥ 2 files (en + hu).
  - Inline check: `grep -l "Step 7" ~/.claude/handout/cmd-implement-next-cc*.html` returns ≥ 2 files.
  - Inline check: `grep -l "recovery(R-B)" ~/.claude/handout/cmd-implement-all-cc*.html` returns ≥ 2 files.
  - Inline check: `grep -l "implement-next-state-clear" ~/.claude/handout/cmd-implement-next-cc-resume*.html` returns ≥ 2 files.
  - If any of the bullet-listed HTML files don't yet exist (e.g., `cmd-implement-all.html`), create stub files following the conventions of existing siblings AND list them in `install.sh` manifest (folded back into Task 4.1's scope or noted here).
  - Checkpoint: chain of `grep -l` checks returning expected file counts.

---

#### Task 4.3 — Manual Integration Test Catalog execution
- [ ] **File**: `~/.claude/tests/recovery/MANUAL_TEST_RESULTS.md` (new)
- **Depends on**: All tasks 1.x–4.2 complete (everything must be in place before exercising end-to-end).
- **Description**:
  - Execute each scenario in the brief's Manual Integration Test Catalog (fixtures a, b, c, d, e/e.warn, f/f.write, g, h, i, k, l, m/m.write/m.corrupt/m.partial-v2, n, o, o-portable, p, q, r1, r2, s, t, u, v) in a scratch repo (separate clone or branch).
  - For each fixture, record in `MANUAL_TEST_RESULTS.md`:
    - Pre-state setup commands.
    - Action taken.
    - Observed Post-state (exit code, stdout regex matches, breadcrumb presence, commit log, plan-file state).
    - Pass / Fail verdict against the brief's expected Post.
    - For Fail verdicts: description of the gap and a referenced follow-up task.
  - **Required evidence per fixture**: for each fixture, the results file MUST include:
    1. **Setup transcript**: actual shell commands that constructed the pre-state, captured verbatim (e.g., `bash -x` output or `script(1)` recording).
    2. **Action transcript**: the full invocation (slash command or shell) and its observable output.
    3. **Post-state evidence**:
       - `git log --oneline -10` of the scratch repo
       - `git show <relevant-sha> --stat`
       - Final breadcrumb contents (or "absent" with `ls .claude/`)
       - Plan-file checked-task count
    4. **SHA of the scratch-repo HEAD** at the end of the test (for re-inspection).
  - Each fixture section MUST END with a standalone line containing ONLY the final SHA (no label, no prefix), e.g.:
    ```
    abc1234def5678
    ```
    This bare-SHA format is required by the checkpoint regex.
  - The file is committed for reproducibility; future regressions can re-run the catalog against the same scratch-repo recipes.
  - Pure-shell fixtures (s, t, u, and some sub-fixtures of e, f, m) are also covered by bats (Tasks 1.4, 1.6) — this task focuses on the LLM-driven end-to-end scenarios that bats cannot exercise.
- **Releasable**: after this task, the recovery system has been validated end-to-end against the brief's documented expectations; any gaps are captured as follow-up work.
- **Tests (TDD)** — N/A (this task IS the test execution; the deliverable is the results file).
  - Checkpoint: `test -f ~/.claude/tests/recovery/MANUAL_TEST_RESULTS.md && [ $(grep -A 200 '^### ' ~/.claude/tests/recovery/MANUAL_TEST_RESULTS.md | grep -cE '^[a-f0-9]{7,40}$') -ge 22 ]`

---

#### Task 4.3b — Shell-invocable end-to-end bats integration test

- [ ] **File**: `~/.claude/tests/recovery/test_integration.bats` (new)
- **Depends on**: Tasks 1.1–1.5 (the shell layer)
- **Description**: For fixtures that exercise ONLY the shell layer (state-write + triage + audit), automate the full pre→action→post sequence in bats. Specifically: e.warn, k, l, m, m.corrupt, m.partial-v2, r2 (the LLM is not needed because the action is "invoke triage" or "invoke writer", not "drive the skill"). Fixture `a` is EXCLUDED because it requires the full skill flow (commit) which is not bash-only. Fixture `r1`'s "first review double-abort" is EXCLUDED because it requires driving iterative-review which is not bash-only — replaced with `r2` only as the shell-invocable R-Stuck threshold test.
- For each such fixture: setup tmp repo, write the synthetic breadcrumb, invoke triage, assert exit code + stdout. This is NOT redundant with `test_triage.bats` because the integration test wires triage → writer → re-invocation, exercising the cross-script contract.
- **R-AB intermediate convergence note**: although `R-AB` is not in this fixture list, the R-B convergence walkthrough (Known Limitations) describes an R-B re-entry sub-window that dispatches as R-AB; that sub-window is already covered by `test_triage.bats`'s R-AB dispatch test, so the integration test does not need a duplicate fixture.
- **Releasable**: after this task, the shell-only subset of the catalog has automated regression coverage independent of the markdown file.
- **Tests**: the test_integration.bats file IS the test.
- **Checkpoint**: `bats ~/.claude/tests/recovery/test_integration.bats` returns all green.

---

#### Task 4.4 — Final verification & documentation update
- [ ] **File**: N/A (agent task)
- **Depends on**: Tasks 1.1–4.3 (all prior tasks)
- **Description**:
  - Spawn an agent to discover all documentation in `~/.claude/` (README, CLAUDE.md, handout HTML, in-script comments, skill SKILL.md files, scripts-plan handout, this plan's reverse-links) and update every file whose content is affected by the changes delivered in RECOVERY-001. The agent MUST NOT update unrelated docs.
  - Verify the acceptance criteria below all pass before marking this task complete.
  - Re-run the full bats suite under `~/.claude/tests/recovery/`; assert all green.
  - Re-run the existing test suite under `~/.claude/tests/` to ensure no regression.
  - Run the audit script against this plan after all commits land: `bash ~/.claude/scripts/audit-plan-run.sh ~/.claude/plans/RECOVERY-001-implement-next-recovery-flow.md <sha-at-Phase-0-start>`. Expected: exit 0; PASS message; commits = completed tasks; no R-B markers (this plan doesn't recover itself).
- **Releasable**: after this task, RECOVERY-001 is fully shipped, verified, and documented.
- **Acceptance criteria** (must all pass):

  **Shell-layer (bats-verified)**
  - [ ] `bash ~/.claude/scripts/implement-next-state-write.sh` (default mode, 6 args, valid `skill_variant`) writes a `schema_version: 2` (integer) breadcrumb atomically with all v2 fields populated.
  - [ ] `bash ~/.claude/scripts/implement-next-state-write.sh --upsert` accepts empty `expected_agent_id` and merges into any existing breadcrumb (non-empty fields preserved).
  - [ ] `bash ~/.claude/scripts/implement-next-state-write.sh --increment-review-abort <cwd>` bumps `review_abort_count` by 1 atomically and exits non-zero if breadcrumb absent.
  - [ ] `bash ~/.claude/scripts/implement-next-triage.sh <cwd> <plan> <variant>` dispatches correctly per all 15 rows of the Triage Unit Tests table.
  - [ ] `bash ~/.claude/scripts/audit-plan-run.sh <plan> <sha>` downgrades VIOLATION → WARNING when `recovery(R-B):`-prefixed commits explain the count delta; surfaces `.claude/recovery-anomalies.log` existence and line count.
  - [ ] `bash ~/.claude/scripts/implement-next-stop-gate.sh` (unchanged) passes new bats coverage for fixtures (s), (t), (u).
  - [ ] All four bats test files exist under `~/.claude/tests/recovery/` and pass: `test_writer.bats`, `test_triage.bats`, `test_audit_marker.bats`, `test_hook_gate.bats`.

  **Skill layer (manual catalog from Task 4.3)**
  - [ ] Fixture (a) R-A — uncommitted partial impl: re-invoke → exit 0; one new commit; plan checked; breadcrumb cleared; audit PASS.
  - [ ] Fixture (b) R-B — committed but plan not checked off: re-invoke → exit 0; new commit subject begins with `recovery(R-B):`; breadcrumb cleared; audit WARNING (not VIOLATION) due to `recovery(R-B):` marker; exit 0.
  - [ ] Fixture (c) R-AB — hybrid: re-invoke → exit 0; new commit subject begins with `recovery(R-AB):`; `REVIEW_RANGE=<sha_before>..HEAD+worktree`; breadcrumb cleared; audit WARNING (not VIOLATION) due to `recovery(R-AB):` marker; exit 0.
  - [ ] Fixture (d) R-C — pre-impl TDD-red state: re-invoke → `STEP_2_RESUME=true`; sub-items unchecked-in-HEAD only re-implemented; audit PASS.
  - [ ] Fixture (e) corrupt breadcrumb (mismatch + dirty/moved): triage exit 1; no commit; breadcrumb unchanged.
  - [ ] Fixture (e.warn) mismatch + clean + same SHA: R-Fresh; WARNING line on stdout AND in `.claude/recovery-anomalies.log`.
  - [ ] Fixture (f) wrong branch: triage warns, continues dispatch without halt.
  - [ ] Fixture (g) fully-checked-but-uncommitted plan: triage re-derives `NEXT_TASK_NAME` from `git show HEAD:$ARGUMENTS`.
  - [ ] Fixture (h) R-Fresh happy path: breadcrumb absent after success; re-run dispatches R-Fresh again.
  - [ ] Fixture (i) standalone child full lifecycle: `--upsert` write with empty `expected_agent_id`; hook fails open; Step 7 clears.
  - [ ] Fixture (k) malformed JSON: R-Fresh; diagnostic mentions "Malformed JSON".
  - [ ] Fixture (l) plan file deleted: triage exit 1; stderr "plan file not found".
  - [ ] Fixture (m) legacy schema-v1 breadcrumb: R-Fresh; diagnostic mentions "legacy".
  - [ ] Fixture (m.corrupt) v2 fields without `schema_version`: R-Fresh; diagnostic mentions "schema inconsistency".
  - [ ] Fixture (m.partial-v2) `schema_version=2` but missing `skill_variant`: R-Fresh with warning, NOT corrupt-flagged.
  - [ ] Fixture (n) TTL-expired breadcrumb: hook removes, fails open; next Step 0 → R-Fresh.
  - [ ] Fixture (o) `-cc` parent full lifecycle: parent writes with real `agentId`; child does NOT write; child Step 7 clears.
  - [ ] Fixture (o-portable) portable parent full lifecycle: parent writes with `--upsert` empty `expected_agent_id`; child does NOT write; child Step 7 clears.
  - [ ] Fixture (p) Case-C cascading interrupt convergence: parent halts; breadcrumb cleared on halt path.
  - [ ] Fixture (q) multi-iteration recovery: iteration 2 interrupted → re-invocation triages R-A/R-AB/R-B (not R-Fresh).
  - [ ] Fixture (r1) first review double-abort: exit non-zero; no commit; breadcrumb persists with `review_abort_count=1`.
  - [ ] Fixture (r2) R-Stuck on re-entry: triage exit 1; `CASE=R-Stuck`; no review/test/commit attempted.
  - [ ] Fixture (v) rescue-path breadcrumb clear: after `implement-next-cc-resume` Step 2 commit, breadcrumb absent.

  **Documentation currency (CLAUDE.md rule)**
  - [ ] `~/.claude/handout/scripts-plan.html` and `-hu.html` list `implement-next-triage.sh`.
  - [ ] `~/.claude/handout/cmd-implement-all-cc.html` and `-hu.html` describe pre-spawn write + halt-path clears.
  - [ ] `~/.claude/handout/cmd-implement-next-cc.html` and `-hu.html` describe Step 0 triage and Step 7 self-verification.
  - [ ] `~/.claude/handout/cmd-implement-all.html` (and `-hu.html`) describe portable parent breadcrumb write.
  - [ ] `~/.claude/handout/cmd-implement-next.html` (and `-hu.html`) describe Step 0 triage.
  - [ ] `~/.claude/handout/cmd-implement-next-cc-resume.html` and `-hu.html` describe Step 2's breadcrumb-clear.
  - [ ] `~/.claude/README.md` references the recovery feature in the relevant section (if it lists commands or skills).

  **Install integrity**
  - [ ] `~/.claude/install.sh` lists `scripts/implement-next-triage.sh` in both `files` arrays.
  - [ ] `check_cc_variant_integrity()` warns if `scripts/implement-next-triage.sh` is missing post-install.
  - [ ] Dry-run install (`DRY_RUN=1`) prints "Would install scripts/implement-next-triage.sh".

  **Audit script verification**
  - [ ] `bash ~/.claude/scripts/audit-plan-run.sh ~/.claude/plans/RECOVERY-001-implement-next-recovery-flow.md <sha-at-Phase-0-start>` exits 0 with PASS (no R-B markers expected — this plan implements recovery, doesn't recover itself).

- **Tests (TDD)**: N/A — this is a verification and documentation task.
- **Checkpoint**: manually confirm every acceptance criterion checkbox above is checked, AND run `bash ~/.claude/scripts/audit-plan-run.sh ~/.claude/plans/RECOVERY-001-implement-next-recovery-flow.md <sha-at-Phase-0-start>` returning exit 0.

---

## Notes for Implementers

- **Land atomically in a single PR.** Intermediate states between commits leave the breadcrumb cleared by un-updated callers — but the PR atom is what matters. Per-task commits within the PR are fine.
- Each modified skill/script includes a `RECOVERY_SCHEMA_V2` marker comment (HTML comment in markdown, `#`-comment in shell). Future version checks grep for this marker.
- Use `/implement-all-cc` to drive this plan (this work needs the hook-enforced commit gate). Each task's TDD cycle: write tests → run them → see them fail → implement → re-run → pass → check off → commit.
- The brief (`~/.claude/implement-next-recovery-brief.md`) is the authoritative reference for any ambiguity in this plan. The brief's Key Decisions, Edge Cases & Constraints, and Manual Integration Test Catalog sections contain the rationale this plan does not restate.
- **Audit independently after the run**: `bash ~/.claude/scripts/audit-plan-run.sh ~/.claude/plans/RECOVERY-001-implement-next-recovery-flow.md <sha-at-Phase-0-start>` — works for both portable and `-cc` variants per CLAUDE.md.
