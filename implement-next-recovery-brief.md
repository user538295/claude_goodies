# Feature Brief: Recovery Flow for Interrupted `/implement-next` Runs

## Problem

When `/implement-next` or `/implement-next-cc` is interrupted mid-task (subagent killed, Ctrl-C, OOM, transport error, hook-bypass), the next invocation currently proceeds as if fresh — risking duplicate work, orphaned tests, contaminated diffs, or silent loss of partial implementation. The portable `/implement-next` has no entry-time recovery at all; the `-cc` variant has parent-level recovery via `/implement-all-cc`'s Case A/B/C/D, but standalone `/implement-next-cc` users are unprotected.

## Goal

When a previously-interrupted run left state behind (uncommitted impl, committed-but-unchecked impl, or tests-only-red), the next invocation of `/implement-next` or `/implement-next-cc` deterministically detects the interruption, recovers the in-flight task to a consistent state (implementation reviewed + tests green + plan checked off + committed), and reports any invariant violations it had to accept. No silent task loss. No duplicate commits without notice.

## Users & Context

- **Primary**: any user running `/implement-all` or `/implement-all-cc` whose iteration was interrupted (network, OOM, manual stop, transport error).
- **Secondary**: users invoking `/implement-next` or `/implement-next-cc` standalone after a prior crash.
- **State at moment of re-invocation**: working tree may be dirty, the prior task may be partially or fully committed without checkoff, or new tests may exist without impl. User typically does NOT know exactly which state — they re-run the skill and expect it to figure it out.

## Core Flow

1. User invokes `/implement-next <plan>` or `/implement-next-cc <plan>` (directly or via `/implement-all[-cc]`).
2. **Step 0: Triage prior state** — both skills shell out to `~/.claude/scripts/implement-next-triage.sh` (contract below). The script is a pure classifier: it READS state and PRINTS the dispatch case + variables. It never invokes review, tests, or commits. The skill consumes its output and runs the case-specific action sequence.
3. **Step 3 review**: if iterative-review aborts mid-flow, restart it once. If the restart also aborts, increment `review_abort_count` via `--increment-review-abort` and **HALT** — do NOT commit code two review passes could not stabilize. Print the unresolved findings, leave the working tree as-is, exit non-zero. On re-entry the triage sees `review_abort_count >= 2` and dispatches **R-Stuck** → HALT immediately with manual-recovery instructions (no re-execution of review). (See Key Decisions: commit-safety yields forward-progress; R-Stuck cap prevents infinite re-entry.)
4. Step 4–6 (tests → checkoff → commit) run as in the existing skill. R-B commits carry the recovery-commit prefix `recovery(R-B):` so `audit-plan-run.sh` recognizes them.
5. **Step 7 self-verification** (now present in BOTH variants — see In Scope). Confirms commit + plan progressed using `START_SHA`/`START_CHECKED` captured in Step 0.
6. Breadcrumb cleared on success by the child (Step 7) AND by `implement-next-cc-resume.md` after successful rescue. Parent clears on ALL halt paths (Cases B, C, D) so the next invocation isn't poisoned by a stale breadcrumb.

## In Scope

- New Step 0 in BOTH `~/.claude/commands/implement-next.md` AND `~/.claude/commands/implement-next-cc.md`, implemented as a call to `~/.claude/scripts/implement-next-triage.sh` (contract below).
- New `~/.claude/scripts/implement-next-triage.sh` per the contract.
- Add a new **Step 7 self-verification** to `~/.claude/commands/implement-next-cc.md` (mirroring `implement-next.md:25` + `implement-next.md:94-119`), and renumber the existing Report step to Step 8. Capture `START_SHA`/`START_CHECKED` at Step 0 (not Step 1) so recovery paths that skip Step 1 still have them bound.
- Modify `~/.claude/scripts/implement-next-state-write.sh`:
  - Atomic write: render JSON to a `.tmp` sibling, then `mv` (POSIX-atomic on same filesystem). Both modes use this.
  - Add `--upsert` flag (a misnomer retained for brevity; the flag's actual effect is to skip the empty-`expected_agent_id` guard, permitting portable parents and standalone children to write without an agentId). In `--upsert` the existing `[ -z "$5" ] && exit 2` guard at `implement-next-state-write.sh:17-20` is skipped, so the caller can write with empty `expected_agent_id`. Default (non-`--upsert`) mode keeps the guard for back-compat with current `/implement-all-cc` Step 4 callers, which pass a real agentId. Both the standalone child AND the portable parent (no hook to coordinate with) call with `--upsert`; the `-cc` parent does not.
  - Add `schema_version: 2`, `branch_name`, `skill_variant`, and `review_abort_count: 0` fields to the written JSON. `branch_name = $(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo "")` (the `-C "$cwd"` is mandatory when the writer is invoked from a parent's working directory). `skill_variant ∈ {"portable", "cc"}`, passed as a new positional arg. New arg order: `<cwd> <sha_before> <plan_path> <task_name> <expected_agent_id> <skill_variant>`. Flags `--upsert` and `--increment-review-abort` precede positional args. The 6-arg requirement is incompatible with the current 5-arg call site in `implement-all-cc.md:55` — that caller must be updated in lockstep.
  - Add `--increment-review-abort` mode: read the existing breadcrumb, increment `review_abort_count` by 1, atomic FILE write via tempfile + `mv`. No other fields touched. Used by Step 3 review double-abort path (NCR3). Atomicity is per-file only — does NOT protect against concurrent read-modify-write from parallel invocations (concurrent invocations are explicitly unsupported; see Edge Cases).
- Modify `~/.claude/commands/implement-all-cc.md`:
  - Step 4 (line 53-56): write the FULL breadcrumb pre-spawn (with the captured `agentId` already present — call the writer AFTER the `Agent` tool returns the id but BEFORE waiting for the agent to complete). Default truncate-and-write mode; no `--upsert`.
  - Step 6 (line 64): REMOVE the unconditional `implement-next-state-clear.sh` invocation. Child's Step 7 clears on success. Parent clears explicitly on ALL halt paths (Cases B-after-rescue-fails, C, D) and at final audit (line 96).
- Modify `~/.claude/commands/implement-all.md` (portable parent — NEW SCOPE addition):
  - Mirror the `-cc` parent's breadcrumb-write pattern. After Step 3's subagent spawn, write the full breadcrumb via `--upsert` with empty `expected_agent_id` (the portable parent has no hook to coordinate with, so the empty-agentId-permitted mode is required). Without this, users running `/implement-all` lose half the recovery benefit (child's Step 0 finds no breadcrumb → R-Fresh on every invocation, even when the prior run was interrupted mid-task).
  - Clear the breadcrumb on ALL Step 4 halt paths (mirroring `-cc` parent's clear-on-halt).
- Modify `~/.claude/commands/implement-next-cc-resume.md`: after Step 2's commit succeeds, run exactly `bash ~/.claude/scripts/implement-next-state-clear.sh "$CWD"` (insert as a new Step 2.5 or as the final line of Step 2). Mirrors the child's Step 7 clear locus.
- Modify `~/.claude/scripts/audit-plan-run.sh`: recognize R-B recovery commits via `git log --format=%s --no-merges` matched against subject-line regex `^recovery\(R-B\):` (anchored at start; substring matches do NOT count; merge commits ignored). Future R-* cases (R-A, R-AB, R-C) do NOT use the prefix — they don't violate the commit-count invariant. **Formula**: let `recovery_commits` = count of commits in `$sha_start..HEAD` whose subject matches `^recovery\(R-B\):`. If `(commits - recovery_commits) == completed`, exit 0 with stdout containing `WARNING: R-B recovery commit(s) detected (count=$recovery_commits)`. Else exit 1 with VIOLATION as before.
- Add bats unit tests under `~/.claude/tests/recovery/` for the shell-layer components (triage, writer, audit-marker, hook gate). See Test Harness Architecture for scope.
- Add `.claude/recovery-anomalies.log` to `.gitignore`; `audit-plan-run.sh` reports its existence + line count at loop end.
- A user-visible report when R-B is detected, including the out-of-order commit SHA, plan path, and an acknowledgment that `audit-plan-run.sh` downgrades the violation to a WARNING.

### Triage Script Contract

`~/.claude/scripts/implement-next-triage.sh` is a pure classifier.

- **Inputs (positional)**: `$1 = CWD`, `$2 = plan_path` (the `$ARGUMENTS` value), `$3 = current_skill_variant` (`"portable"` or `"cc"`, required for the cross-variant warning in the Dispatch Table).
- **Outputs (stdout, machine-parseable `KEY=VALUE`, one per line)**:
  - `CASE=R-Fresh|R-A|R-B|R-AB|R-C|R-Halt|R-Stuck`
  - `START_SHA=<sha>` (HEAD at triage time)
  - `START_CHECKED=<int>` (on-disk checked-task count)
  - `SHA_BEFORE=<sha>` (from breadcrumb; empty for R-Fresh)
  - `BRANCH_NAME=<name>` (from breadcrumb; empty if absent or detached)
  - `TASK_NAME=<name>` (next task to act on)
  - `REVIEW_RANGE=<spec>` (e.g., `HEAD+worktree`, `<sha_before>..HEAD`, `<sha_before>..HEAD+worktree`; empty for R-Fresh/R-C)
  - `STEP_2_RESUME=true|false` (R-C sets `true`; others `false`)
  - `REVIEW_ABORT_COUNT=<int>` (from breadcrumb; 0 if absent)
  - PLUS one human-readable diagnostic line:
    `RECOVERY: <case_name> detected. sha_before=<X>, head=<Y>, dirty=<bool>. <action_summary>.`
- **Exit codes**:
  - `0` = dispatched successfully. Read stdout for the case + variables.
  - `1` = halt (corrupt breadcrumb in dirty tree, plan file missing, etc.). Diagnostic on stderr.
  - `2` = usage error.
- **Error semantics**:
  - Malformed breadcrumb JSON → exit 0, dispatch to R-Fresh, diagnostic line notes "malformed JSON, treated as no breadcrumb."
  - Plan file missing (referenced by breadcrumb but not on disk) → exit 1, stderr diagnostic.
  - Internal-dependency failure (jq not found, git unresponsive, breadcrumb file unreadable) → exit 1 with stderr naming the missing/broken dependency.
  - **Exit-1 stdout contract**: on exit 1, stdout contains ONLY the `RECOVERY:` diagnostic line and `CASE=R-Halt` (or `CASE=R-Stuck` for the cap case). No other `KEY=VALUE` pairs. The calling skill MUST check exit code BEFORE parsing stdout and MUST exit immediately on non-zero; no subsequent step runs. `R-Halt` and `R-Stuck` are sentinel cases.
- **Dispatch order**: conditions are evaluated TOP-TO-BOTTOM in the order listed in the Dispatch Table; the FIRST matching condition determines the case. Conditions are NOT assumed disjoint — overlapping conditions resolve by listed order.
- **Role**: pure classifier. Triage READS state (and may DELETE a stale breadcrumb on the auto-clear arm); the skill EXECUTES the case-specific actions (review/test/commit). This separation makes the script unit-testable in isolation.

### Dispatch Table (consumed from triage stdout `CASE=...`)

- **Breadcrumb's `review_abort_count >= 2`** → **R-Stuck**: exit 1 immediately with diagnostic including the interrupted `task_name` and `sha_before` values: "review failed twice for task '<task_name>' (sha_before=<X>); manual recovery required. Either `git checkout -- .` to discard the review-touched files and delete `.claude/implement-next-state.json`, or commit manually and clear the breadcrumb." No review/test/commit attempted. Evaluated FIRST so a stuck breadcrumb cannot fall through to R-A/R-B/R-AB.
- **No breadcrumb** OR **`schema_version != 2` AND no other v2 fields present (legacy)** → **R-Fresh**. Proceed to existing Step 1.
- **`schema_version != 2` AND one or more v2 fields present (`branch_name`, `skill_variant`, etc.)** → treat as corrupt; dispatch to R-Fresh with a diagnostic noting the inconsistency. (Distinct from clean legacy.)
- **Breadcrumb's `task_name` does not match `NEXT_TASK_NAME` AND `sha_before == HEAD` AND working tree clean** → auto-clear the breadcrumb and dispatch to **R-Fresh**, emitting BOTH the normal `RECOVERY:` line AND an additional warning: `WARNING: Auto-cleared stale breadcrumb for task '<task_name>' (next task per plan: '<NEXT_TASK_NAME>', no commits since breadcrumb, tree clean). If this was unexpected, check plan file integrity.` Additionally append the WARNING line to `$CWD/.claude/recovery-anomalies.log` so overnight runs surface anomalies in the final audit step (audit reports the file's existence).
- **Breadcrumb's `task_name` does not match `NEXT_TASK_NAME` (any other combination: dirty tree or HEAD moved)** → halt (exit 1) with diagnostic; mention plan editing, branch switch, or prior crash as likely causes.
- **Breadcrumb's `task_name` is already committed-checked in `git show HEAD:$ARGUMENTS`** (committed-but-uncleared breadcrumb, e.g., parent loop terminated mid-Step-6) → delete stale breadcrumb, dispatch to **R-Fresh**. Match uses fixed-string: `grep -F -- "- [x] $task_name" <(git show HEAD:$ARGUMENTS) || grep -F -- "- [X] $task_name" <(git show HEAD:$ARGUMENTS)`. Task names containing newlines or NUL bytes are unsupported.
- **Breadcrumb's `branch_name` non-empty AND differs from current branch** → warn (do not halt); list both branches; continue dispatch as if `branch_name` matched. If `branch_name` is empty (detached HEAD at write time), skip the comparison entirely.
- **Breadcrumb's `skill_variant` differs from current skill's variant** → warn (do not halt) and continue dispatch.
- **Breadcrumb matches AND `HEAD == sha_before` AND working tree dirty** → **R-A**: uncommitted partial impl. Skip Step 2. Review target = `HEAD+worktree`. Run tests. Check off. Commit.
- **Breadcrumb matches AND `HEAD != sha_before` AND working tree clean** → **R-B**: committed but plan not checked off. Set `START_SHA = sha_before`. Report the violation. Add plan checkoff to working tree. Review target = `<sha_before>..HEAD`. Run tests. Commit with `recovery(R-B):` message prefix.
- **Breadcrumb matches AND `HEAD != sha_before` AND working tree dirty** → **R-AB**: hybrid. Review target = `<sha_before>..HEAD+worktree`. Commit.
- **Breadcrumb matches AND `HEAD == sha_before` AND working tree clean** → **R-C**: pre-impl resume. Resume Step 2 from "implement to green" using sub-item delta against `git show HEAD:$ARGUMENTS`.

## Out of Scope

- **Auto-amending the prior commit in R-B** (silent index contamination; conflicts with "prefer new commits over amends").
- **Heuristic file-relatedness detection.** Replaced entirely by deterministic breadcrumb lookup.
- **Branch-switch HARD halt** beyond a warning. The user may legitimately have moved between branches.
- **Stash-based rollback on review abort.** Rejected: HALT is the new default (see Key Decisions).
- **Modifying `iterative-review.md`.** Recovery uses the existing review skill unchanged.
- **Extracting per-case action steps (review/test/commit) into shared scripts.** Only Step 0 triage is shared; the per-case action sequences legitimately differ between variants (`-cc` uses parallel DA; portable uses one critic). Sharing more would force a synthetic convergence. (See Key Decisions: this duplication is an accepted maintenance cost.)
- **`/implement-next --force` for committing review-unstable code.** Future iteration.

## Key Decisions

- **Detection = deterministic breadcrumb, not LLM heuristic.** Why: 3 Critical + 4 Major findings in the prior DA review all stemmed from the "does this dirty tree relate to the current task?" heuristic. The breadcrumb already exists, is already tested.
- **The breadcrumb is the authority on interruption, not `plan-progress.sh`.** Why: a plan file fully checked but uncommitted (Step 5 ran, Step 6 didn't) makes `plan-progress.sh` skip the task. Step 0 reads the breadcrumb first; when its `task_name` is already committed-checked in `git show HEAD:$ARGUMENTS`, that's the stale-breadcrumb signal (replaces the original "task precedes NEXT_TASK_NAME" rule — no plan-ordering parser needed).
- **R-B `START_SHA` = `sha_before` from the breadcrumb.** Why: the out-of-order impl commit lies between `sha_before` and `HEAD`; using `sha_before` makes `check-task-commit.sh` see >= 1 commits. Cost: `audit-plan-run.sh` would report VIOLATION — addressed by the R-B commit-message marker (see below).
- **R-B is treated as R-A (forward progress) with explicit violation reporting AND audit-script marker recognition.** Why: user values forward progress; audit script downgrades the marked R-B commits from VIOLATION to WARNING so a clean R-B run still exits 0.
- **R-B commit-message marker `recovery(R-B):`** is the recognition signal for `audit-plan-run.sh`. Cheaper than parsing breadcrumb history. Only R-B uses a marker (it's the only case that violates the one-task-one-commit invariant).
- **R-B review fixes co-mingle with the checkoff commit, NOT the impl commit.** Cost: `git bisect` blames the impl commit but the fix lands in the checkoff commit; `git revert` of the impl commit leaves the fix orphaned. This is the documented cost of R-B's forward-progress design.
- **Review double-abort: HALT, increment `review_abort_count`; R-Stuck caps re-entry.** Committing code two review passes could not stabilize is silent-loss-by-default. Without a cap, the next invocation would re-dispatch R-A/R-AB → re-run review → re-abort → re-HALT (infinite loop). Cap: `review_abort_count >= 2` → R-Stuck → exit 1 with manual-recovery instructions. Opt-in `--force` deferred.
- **`review_abort_count` is CUMULATIVE across re-invocations for the same task.** Cleared by Step 7's breadcrumb-delete on successful task completion. No automatic per-run reset — two total double-aborts trigger R-Stuck regardless of intervening successes within the same task scope (success deletes the breadcrumb so the counter starts fresh on the next task). To manually reset, delete `.claude/implement-next-state.json`.
- **9-step skill sits at the LLM-reliability boundary.** The 7.6% failure rate cited in `implement-all.md:81` is for prompt-only multi-step flows; longer skills are MORE prone to missing-step errors. Mitigation: Step 0 is a single shell-out and Step 7 is exit-code-driven, so LLM-driven steps stay at 5. Net effect: this recovery feature increases per-task failure probability (more steps to miss) but each failure is now recoverable rather than silent. Empirically validate after deploy.
- **Step 7 self-verification is the in-flow primary gate; the SubagentStop hook is the fallback.** When both are active (`-cc` variant), Step 7 runs first and checks a superset of conditions (commit + plan checkoff + non-empty diff); the hook is the fallback for cases where Step 7 never executes (OOM, transport error). They do not conflict: the hook passes once any commit since `sha_before` exists.
- **Parent writes the FULL breadcrumb pre-spawn; child NEVER writes when a parent is detected.** Eliminates the parent/child write race (no overlapping update window). The `-cc` parent writes default mode (real agentId, post-`Agent`-return, pre-wait, per `implement-all-cc.md` Step 4 prose). The portable parent and STANDALONE child both write via `--upsert` (empty-agentId-permitted); hook fails open on empty `expected_agent_id` per `implement-next-stop-gate.sh:62-64`. Mutually exclusive paths: parent writes XOR standalone child writes.
- **Child-parent detection is enforced by writer logic, not skill code.** A child running inside a subagent cannot reliably inspect its parent's identity. **Pragmatic rule**: on R-Fresh the child ALWAYS attempts a `--upsert` write. The `--upsert` mode's read-merge semantics mean that if a parent breadcrumb already exists (race window), the writer preserves all non-empty fields — so a parent-written `expected_agent_id` is never clobbered by a child's empty value. Fixtures (i) and (o) assert this via the resulting breadcrumb contents.
- **Atomic writes via tempfile + `mv`.** Why: even though the parent/child race is now eliminated, `mv` rules out half-written JSON from being read by a concurrent triage or hook invocation (relevant for standalone + the unlikely concurrent-terminal case below).
- **Breadcrumb schema is versioned (`schema_version: 2`).** Why: lets the triage dispatcher distinguish recovery-aware breadcrumbs from old-style hook-only sentinels.
- **Schema versioning policy.** Additive (backward-compatible) field additions: same `schema_version`, default missing fields to empty/false, do not corrupt-flag (fixture m.partial-v2). BREAKING changes (field removal, semantics change): bump `schema_version` to 3. The triage tolerates missing additive fields within v2.
- **`recovery(R-B):` marker is a soft convention.** The audit script trusts the prefix; a developer manually using it for unrelated commits would silently bypass the commit-count check. Acceptable for single-developer usage; multi-developer teams should consider a sidecar marker file (deferred).
- **Legacy vs corrupt distinction.** A breadcrumb missing `schema_version` AND missing all other v2 fields (`branch_name`, `skill_variant`) is LEGACY → R-Fresh. A breadcrumb missing `schema_version` BUT carrying one or more v2 fields is CORRUPT → R-Fresh + diagnostic noting the inconsistency.
- **`branch_name` capture.** `branch_name = $(git symbolic-ref --short HEAD 2>/dev/null || echo "")`. When empty (detached HEAD at write time), the triage's branch-mismatch check is skipped entirely — cannot compare what was never known.
- **`skill_variant` field (`"portable" | "cc"`).** Triage warns (does NOT halt) on cross-variant contamination — e.g., a breadcrumb written by `/implement-next` consumed by `/implement-next-cc`.
- **`START_SHA` / `START_CHECKED` are captured at Step 0, before case dispatch.** Why: moved from Step 1 (`implement-next.md:25`) because R-A/R-B/R-AB paths skip Step 1; without the move, Step 7's self-verification would reference unbound variables.
- **Sub-item resume = committed-state delta.** Diff on-disk plan vs `git show HEAD:$ARGUMENTS`; Step 2 (R-C) implements only the sub-items unchecked in HEAD. If `git show HEAD:$ARGUMENTS` fails (untracked plan or first-time commit), treat ALL sub-items as unchecked-in-HEAD (safe default).
- **No separate "current iteration SHA" file in `/implement-all`.** Why: the breadcrumb's `sha_before` IS the current-iteration SHA. The durable *first*-iteration SHA file (`implement-all-start-sha-$PLAN_HASH`) stays because it serves the post-loop audit — a different consumer.
- **`/implement-all` (portable parent) is in scope.** Why: without modifying the portable parent, users running `/implement-all` lose half the recovery benefit. Both parents now write the breadcrumb; only `-cc` enforces the hook (portable's `expected_agent_id` is empty — hook fails open, but the child's breadcrumb-based recovery still works).
- **Per-case action duplication across portable and `-cc` skills is accepted.** Why: the iterative-review skill IS the variant-specific divergence point (parallel DA vs single critic); the surrounding R-* sequences are otherwise substantially identical (SHA override, violation report, plan-checkoff insert). Extracting them into a shared script would force a synthetic convergence. **Maintenance note**: when changing R-* action semantics, audit BOTH skill files. (Potential future extraction is deferred.)
- **Worst-case cascading commit count.** Lower bound: `commits ≥ 2 * tasks`. R-AB stacking on R-B for the same task can produce 3+ commits per task in pathological cascading. The audit-script marker handles the typical case; the worst case still surfaces in commit-count delta.
- **Observability log line on every dispatch.** Step 0 emits `RECOVERY: <case_name> detected. sha_before=<X>, head=<Y>, dirty=<bool>. <action_summary>.` Format is a **stability contract**: any future change requires a major-version bump of the recovery system. Fixtures assert via regex against the full format.
- **Case labels live in their own namespace (`R-*`)** to avoid collision with `implement-all-cc.md:71-86` Cases A/B/C/D at the parent layer.
- **Pre-ship validation = bash fixture scripts** (bats-core, `.bats` files) under `~/.claude/tests/recovery/`, matching the existing test suite convention.

## Edge Cases & Constraints

- **Stale breadcrumb from a different plan file.** Breadcrumb's `plan_path` doesn't match `$ARGUMENTS` → treat as no breadcrumb (R-Fresh); optionally warn.
- **Sub-items partially checked on disk but not committed.** Step 0 diffs on-disk plan vs `git show HEAD:$ARGUMENTS` to confirm sub-item state and not re-implement completed sub-items.
- **Untracked plan or first-time commit (`git show HEAD:$ARGUMENTS` fails).** Sub-item delta treats ALL sub-items as unchecked-in-HEAD. Safe default — overcounts work but never silently skips it. R-C on a first-run untracked plan behaves identically to R-Fresh; by the second run the plan is tracked and R-C works normally.
- **Plan file fully checked but uncommitted (Step 5 ran, Step 6 didn't).** `plan-progress.sh` against on-disk plan would skip the task entirely. Step 0 reads the breadcrumb first; the "task already committed-checked" rule (above) deletes the stale breadcrumb and falls through to R-Fresh.
- **Plan file deleted between runs.** Breadcrumb references a plan path that no longer exists → exit 1 with clear error. (See fixture (l).)
- **Branch switched between interruption and recovery.** Breadcrumb's `branch_name` differs → warn, list both branches, let user choose. (See fixture (f).)
- **Detached HEAD at breadcrumb write.** `branch_name = ""` → branch-mismatch check skipped on recovery.
- **Task-name mismatch with clean tree at same SHA.** Auto-clear + WARNING log line. (Mitigates the narrow corruption-window: e.g., a partial Step 5 that corrupted a checkmark. Warning surfaces the unexpected case.)
- **Cascading R-B recoveries.** `commits ≥ 2 * tasks` lower bound. R-AB stacking on R-B can push to 3+ commits per task. Audit script downgrades VIOLATION → WARNING when commit count = N + matching `recovery(R-B):` commits.
- **Multiple consecutive interruptions on the same task.** Defense is `implement-all-cc.md` Step 6 Case-C halt (subagent did nothing visible). Cite the correct mechanism in fixture (p).
- **TTL-expired breadcrumb (> 4 hours).** `implement-next-stop-gate.sh:53` fails open and removes the breadcrumb. Next Step 0 sees no breadcrumb → R-Fresh.
- **Malformed breadcrumb JSON.** Triage exit 0, dispatch to R-Fresh, diagnostic notes malformed JSON. (Fixture (k).)
- **Legacy (schema_version=1) breadcrumb.** R-Fresh. (Fixture (m).)
- **Concurrent invocations** (two terminals on the same plan). The breadcrumb is a single file with no lock. Recommended: do not run concurrent `/implement-next` invocations on the same plan. Future Iterations may add `flock`-based advisory locking.
- **`recovery-anomalies.log` lifecycle.** `.claude/recovery-anomalies.log` is gitignored, append-only, capped at 10000 lines (truncated to last 5000 on overflow), and surfaced by `audit-plan-run.sh` at loop end (existence check + line count).
- **Constraints**: one-task-one-commit (R-B violates by design; marker tolerates); no `--no-verify` (recovery commits go through hooks); Step 7 self-verification in both variants (`START_SHA`/`START_CHECKED` captured at Step 0).
- **`rm` carve-out**: per project policy, ephemeral state files (`.claude/implement-next-state.json`, `.claude/recovery-anomalies.log`) are exempt from the `trash`-instead-of-`rm` rule — they are machine-managed sentinels, not user files.

## Test Harness Architecture

Bats covers ONLY the pure-shell layer. LLM-driven skill execution (Steps 1-8 as run by an LLM) cannot be intercepted via shell env vars — markdown is consumed by the model, not the shell. Honest scoping:

**In bats scope (pre-ship gates, `~/.claude/tests/recovery/*.bats`):**
- `implement-next-triage.sh` — all dispatch branches per the Triage Unit Tests table.
- `implement-next-state-write.sh` — default mode, `--upsert`, `--increment-review-abort`, atomic write, all new fields.
- `audit-plan-run.sh` — `recovery(R-B):` marker recognition and anomalies-log consumption.
- `implement-next-stop-gate.sh` — block/pass-through behavior under the various breadcrumb/agentId states (fixtures s, t, u).

**Out of bats scope (validated manually or via integration harness):**
- End-to-end skill flow (Step 0 through Step 8 as executed by an LLM-driven `/implement-next[-cc]`).
- Parent loop (`/implement-all[-cc]`) full iteration.
- `implement-next-cc-resume.md` execution path.

These require actual Claude Code session invocation, are expensive, and are not pre-ship gates. Setup (bats only): `setup_file()` creates shared helpers; per-fixture `setup()` creates a fresh `$BATS_TMPDIR/<fixture>/` with `git init` + synthetic plan. Mock boundary: real `git`, `jq`, `bash` — shell-layer tests exercise scripts directly with crafted breadcrumb/repo state, no stubs.

## Manual / Integration Test Catalog

Each scenario below is a manual or integration-harness check, NOT a bats fixture. Drive against a real `/implement-next[-cc]` session in a scratch repo. Filenames use the `R-*` label (or scenario letter).

### (a) R-A — uncommitted partial impl
- **Pre**: breadcrumb present with `task_name=T`, `sha_before==HEAD`, `schema_version=2`, working tree has uncommitted impl (no plan checkmark yet).
- **Action**: invoke `/implement-next`.
- **Post**: exit 0; `git rev-list --count <sha_before>..HEAD` == 1; plan-checked-count for T += 1; breadcrumb absent; stdout matches `^RECOVERY: R-A detected\. sha_before=[a-f0-9]+, head=[a-f0-9]+, dirty=true\. .*\.$`. After completion: `audit-plan-run.sh <plan> <sha_before>` exit 0 (no false-positive VIOLATION).
- **Negative**: Step 2 not invoked; no duplicate test files; no second commit.

### (b) R-B — committed but plan not checked off
- **Pre**: breadcrumb with `task_name=T`, `sha_before` is one commit behind `HEAD`, `schema_version=2`, working tree clean.
- **Action**: re-invoke `/implement-next`.
- **Post**: exit 0; `git rev-list --count <sha_before>..HEAD` == 2; plan-checked-count for T += 1; new commit's message begins with `recovery(R-B):`; breadcrumb absent; stdout matches the R-B recovery-line regex with `dirty=false`; `audit-plan-run.sh <plan> <sha_before>` exit 0 with stdout containing `WARNING: R-B recovery commit(s) detected`.
- **Negative**: no `--amend`; no plan-only commit.

### (c) R-AB — out-of-order commit + further uncommitted work
- **Pre**: breadcrumb with `sha_before != HEAD` AND working tree dirty.
- **Action**: re-invoke `/implement-next`.
- **Post**: exit 0; triage stdout includes `REVIEW_RANGE=<sha_before>..HEAD+worktree`; exactly one new commit since prior `HEAD`; stdout matches R-AB recovery-line regex. `audit-plan-run.sh <plan> <start_sha>` exit 0 with NO VIOLATION and NO WARNING (R-AB doesn't violate commit-count).
- **Negative**: triage stdout does NOT include unrelated history before `sha_before`.

### (d) R-C — TDD-red state, tests only
- **Pre**: breadcrumb with `task_name=T`, `sha_before==HEAD`, working tree clean, NEW test files committed for T but no impl.
- **Action**: re-invoke `/implement-next`.
- **Post**: triage stdout includes `STEP_2_RESUME=true`; sub-items unchecked-in-HEAD only are targeted; stdout matches R-C recovery-line regex. `audit-plan-run.sh <plan> <start_sha>` exit 0 with NO VIOLATION and NO WARNING.
- **Negative**: no duplicate test files; existing test files unmodified except to make them pass.

### (e) Corrupt breadcrumb — task_name mismatch with dirty tree or moved HEAD
- **Pre**: breadcrumb's `task_name` doesn't match any task in the plan AND (dirty tree OR HEAD moved since `sha_before`).
- **Action**: re-invoke `/implement-next`.
- **Post**: triage exit 1; stderr diagnostic mentions plan editing, branch switch, or prior crash; breadcrumb unchanged on disk.
- **Negative**: no commits, no plan-file edits, no Step 2 invocation.
- **Sub-fixture (e.warn)**: task-name mismatch + clean tree + HEAD==sha_before → triage exit 0, R-Fresh, WARNING on stdout AND a line appended to `.claude/recovery-anomalies.log`.

### (f) Wrong branch — `branch_name` differs from current branch
- **Pre**: breadcrumb's `branch_name` is `feature/foo`; current branch is `main`.
- **Action**: re-invoke `/implement-next`.
- **Post**: stdout contains a warning mentioning both branches; dispatch proceeds as if `branch_name` matched.
- **Negative**: no unilateral halt.
- **Sub-fixture (f.write)**: invoke `implement-next-state-write.sh` on a feature branch → assert JSON `branch_name` equals branch. Invoke in detached-HEAD state → assert `branch_name: ""` AND downstream branch-mismatch check is skipped.

### (g) Fully-checked-but-uncommitted plan
- **Pre**: breadcrumb's `task_name=T`; on-disk plan has T checked; `git show HEAD:$ARGUMENTS` shows T unchecked.
- **Action**: re-invoke `/implement-next`.
- **Post**: triage re-derives `NEXT_TASK_NAME` from `git show HEAD:$ARGUMENTS`; dispatches based on tree/sha state for T.
- **Negative**: on-disk `plan-progress.sh` is NOT the authoritative source.

### (h) Fresh-run breadcrumb lifecycle (happy path)
- **Pre**: no breadcrumb. Plan has an unchecked task.
- **Action**: invoke `/implement-next`, run to completion.
- **Post**: Step 0 dispatches to **R-Fresh**; after completion, breadcrumb absent (cleared by child's Step 7). Re-run dispatches to R-Fresh again.
- **Negative**: breadcrumb NOT lingering between iterations.

### (i) Standalone child full lifecycle (no parent, `--upsert`)
- **Pre**: no breadcrumb; no parent loop; user invokes `/implement-next-cc` directly.
- **Action**: child Step 0 writes breadcrumb via `--upsert` with empty `expected_agent_id`, completes Steps 2-7.
- **Post**: breadcrumb present mid-run with `expected_agent_id` empty; SubagentStop hook fires (`implement-next-stop-gate.sh:62-64`) → fails open; Step 7 clears the breadcrumb on success; re-invoke and assert R-Fresh.
- **Negative**: hook does NOT block the standalone subagent; breadcrumb does NOT linger after a successful run.

> Fixture (j) is reserved/unused — letters skip (j) because the original (j) was removed in Cycle 2 when the parent/child clobber concern became moot.

### (k) Malformed breadcrumb JSON
- **Pre**: `.claude/implement-next-state.json` contains garbled JSON (truncated mid-write).
- **Action**: invoke `/implement-next`.
- **Post**: triage exit 0; stdout `RECOVERY: R-Fresh detected. sha_before=, head=<Y>, dirty=<bool>. Malformed JSON breadcrumb treated as absent.`; no stack trace; no partial commit.
- **Negative**: no R-A/R-B/R-AB/R-C dispatch on malformed JSON.

### (l) Plan file deleted between runs
- **Pre**: breadcrumb references a plan path that no longer exists.
- **Action**: invoke `/implement-next`.
- **Post**: triage exit 1; stderr `plan file referenced by breadcrumb not found: <path>`.
- **Negative**: no silent fall-through; no `plan-progress.sh` invocation on the missing file.

### (m) Schema-version-1 (legacy) breadcrumb
- **Pre**: breadcrumb on disk has no `schema_version` field AND no other v2 fields (`branch_name`, `skill_variant`).
- **Action**: invoke `/implement-next`.
- **Post**: triage exit 0, dispatch R-Fresh; stdout includes a note about legacy schema.
- **Sub-fixture (m.write)** — bats in `~/.claude/tests/recovery/test_writer.bats`: (1) invoke the writer; assert the written JSON contains `schema_version: 2` (integer, not string) AND `review_abort_count: 0`. (2) `--increment-review-abort` on a breadcrumb with `review_abort_count: 0` → result is 1; other fields unchanged. (3) starting at 1 → 2. (4) `--increment-review-abort` on missing breadcrumb → exit non-zero with diagnostic.
- **Sub-fixture (m.corrupt)**: breadcrumb missing `schema_version` BUT has `branch_name` set → triage dispatches R-Fresh AND diagnostic mentions the schema inconsistency. (Distinct from clean legacy.)
- **Sub-fixture (m.partial-v2)**: breadcrumb has `schema_version: 2` but lacks `skill_variant` (Cycle-1-era breadcrumb consumed by Cycle-2 dispatcher) → triage treats it as valid-but-incomplete (per Key Decisions: intra-version additions), warns about partial schema, continues dispatch normally. NO corrupt-flag.
- **Negative**: no R-A/R-B/R-AB/R-C dispatch on legacy or corrupt-schema input.

### (n) TTL-expired breadcrumb
- **Pre**: breadcrumb's `started_at` > 4 hours ago.
- **Action**: invoke `/implement-next` AND/OR fire a SubagentStop event.
- **Post**: `implement-next-stop-gate.sh:53` removes the breadcrumb and fails open; next Step 0 sees no breadcrumb → R-Fresh.
- **Negative**: TTL-expired breadcrumb does NOT block turn-end.

### (o) `-cc` parent-spawn full lifecycle — MANUAL
- **Pre**: clean repo, no breadcrumb, plan with one unchecked task.
- **Action**: run one `/implement-all-cc` iteration in a real session.
- **Post (state-level)**: (a) writer is called by the parent with `expected_agent_id=<real agentId>` (default mode, no `--upsert`); (b) child does NOT invoke the writer in the parent-present scenario; (c) child's Step 7 deletes the breadcrumb; (d) breadcrumb absent after success. Temporal ordering between `Agent` return and the writer call is enforced by `implement-all-cc.md` Step 4 ordering prose.

### (o-portable) Portable parent full lifecycle — MANUAL
- **Pre**: clean repo, no breadcrumb, plan with one unchecked task.
- **Action**: run one `/implement-all` iteration in a real session.
- **Post**: (a) writer called by the parent with `--upsert` and empty `expected_agent_id`; (b) breadcrumb contains `schema_version=2`, `skill_variant="portable"`, `review_abort_count=0`; (c) child does NOT invoke the writer; (d) child's Step 7 deletes the breadcrumb; (e) parent's pre-next-iteration check sees no breadcrumb.

### (p) Convergence on cascading interrupt
- **Pre**: simulate a subagent that returns without changing HEAD or working tree (Case-C nothing-visible).
- **Action**: parent `/implement-all-cc` runs one iteration.
- **Post**: parent halts with the Case-C diagnostic; parent clears the breadcrumb on the halt path (per MO4 / Key Decisions); re-running does not loop.
- **Negative**: breadcrumb does NOT persist past a Case-C halt.

### (q) Multi-iteration `/implement-all-cc` recovery — MANUAL
- **Pre**: plan with three unchecked tasks.
- **Action**: run `/implement-all-cc` for two iterations in a real session; interrupt iteration 2 during Step 2 (after test files exist, before commit) via Ctrl-C or process kill — producing R-A state on re-entry; re-invoke `/implement-all-cc`.
- **Post**: (a) after interrupting iteration 2, breadcrumb EXISTS (not cleared); (b) re-invocation's triage emits `CASE=R-A` (or R-AB / R-B per interruption point), NOT `R-Fresh`; (c) third iteration recovers and completes.
- **Negative**: a regression that re-adds the unconditional `implement-next-state-clear.sh` call at Step 6 would clear the breadcrumb mid-loop — assertion (b) catches it.

### (r1) R-B with first review double-abort (HALT, count=1) — MANUAL
- **Pre**: pre R-B state; manually drive `/iterative-review` to abort on both invocations within the same session.
- **Action**: re-invoke `/implement-next`.
- **Post**: exit non-zero; no new commit; stdout/stderr surfaces unresolved review findings; breadcrumb on disk, `review_abort_count == 1`.
- **Negative**: no `recovery(R-B):` commit lands when review aborts twice.

### (r2) R-Stuck on re-entry after prior double-abort
- **Pre**: breadcrumb from (r1) with `review_abort_count == 2` (simulate two consecutive interrupted runs).
- **Action**: re-invoke `/implement-next`.
- **Post**: triage exit 1, `CASE=R-Stuck`; stderr contains "review failed twice; manual recovery required"; no review/test/commit attempted; breadcrumb unchanged.
- **Negative**: no infinite re-entry — Step 3 review is NOT invoked.

### (s) Hook with valid breadcrumb + matching agentId → blocks
- **Pre**: breadcrumb on disk with `expected_agent_id=X`; SubagentStop hook receives payload with `agent_id=X`; HEAD == `sha_before`.
- **Action**: hook runs.
- **Post**: hook emits `{decision: "block", reason: ...}` on stdout; exit 0.

### (t) Hook with valid breadcrumb + mismatched agentId → passes through
- **Pre**: breadcrumb with `expected_agent_id=X`; hook receives `agent_id=Y` (nested sub-sub-agent).
- **Action**: hook runs.
- **Post**: hook exits 0 with no block JSON.

### (u) Hook with breadcrumb cleared mid-turn → passes through
- **Pre**: hook fires; `.claude/implement-next-state.json` was just removed by the child's Step 7.
- **Action**: hook runs.
- **Post**: hook exits 0 (no sentinel → not an implement-next subagent → pass through).

### (v) Rescue-path breadcrumb clear (`implement-next-cc-resume`)
- **Pre**: breadcrumb present AND dirty tree with committed work — simulates Case-B rescue entry.
- **Action**: invoke `implement-next-cc-resume` skill (Step 2 commits).
- **Post**: breadcrumb absent after the resume skill returns (independent of any parent halt-path clear); regression catcher for the new rescue-path clear in `implement-next-cc-resume.md`.

### Triage Unit Tests (`~/.claude/tests/recovery/test_triage.bats`)

Pre-ship bats gate (separate from the manual catalog above). Crafts breadcrumb/repo state directly; asserts the printed `CASE=...`, exit code, and downstream variables.

| # | Branch | Pre | Exit | `CASE=` | Other asserts |
|---|--------|-----|------|---------|---------------|
| 1 | No breadcrumb | absent | 0 | R-Fresh | `START_SHA=<sha>`, no `SHA_BEFORE=` |
| 2 | Legacy (no v2 fields) | no `schema_version` and no `branch_name`/`skill_variant` | 0 | R-Fresh | stdout contains "legacy" |
| 3 | Corrupt (v2 fields without version) | `branch_name` present but no `schema_version` | 0 | R-Fresh | stdout contains "schema inconsistency" |
| 4 | Stale (committed-checked) | `task_name` already in `git show HEAD:` | 0 | R-Fresh | breadcrumb file absent after run |
| 5a | Mismatch + clean + same SHA | `task_name != NEXT_TASK_NAME`, HEAD==sha_before, clean | 0 | R-Fresh | stdout contains "WARNING: Auto-cleared" |
| 5b | Mismatch + dirty OR moved | mismatch + (dirty OR HEAD moved) | 1 | R-Halt | stderr mentions plan editing/branch switch |
| 6 | Matched + clean + same SHA | matched, HEAD==sha_before, clean | 0 | R-C | `STEP_2_RESUME=true`, `REVIEW_RANGE=` empty |
| 7 | Matched + dirty + same SHA | matched, HEAD==sha_before, dirty | 0 | R-A | `REVIEW_RANGE=HEAD+worktree` |
| 8 | Matched + clean + moved | matched, HEAD!=sha_before, clean | 0 | R-B | `START_SHA=<sha_before>`, `REVIEW_RANGE=<sha_before>..HEAD` |
| 9 | Matched + dirty + moved | matched, HEAD!=sha_before, dirty | 0 | R-AB | `REVIEW_RANGE=<sha_before>..HEAD+worktree` |
| 11 | Malformed JSON | unparseable breadcrumb | 0 | R-Fresh | stdout contains "malformed JSON" |
| 12 | Branch mismatch | `branch_name` differs from HEAD branch | 0 | R-A/B/AB/C | stdout contains warning naming both branches |
| 13 | Variant mismatch | `skill_variant` differs from current variant | 0 | R-A/B/AB/C | stdout contains cross-variant warning |
| 14 | Plan-path mismatch | breadcrumb's `plan_path` != `$ARGUMENTS` | 0 | R-Fresh | stale-breadcrumb diagnostic |
| 15 | R-Stuck on re-entry | `review_abort_count >= 2` | 1 | R-Stuck | stderr contains "review failed twice; manual recovery required" |

## Documentation Impact

Per CLAUDE.md's documentation-currency rule, the following docs update **in the same session** as the code changes:

- `handout/scripts-plan.html` and `handout/scripts-plan-hu.html` — add `implement-next-triage.sh` to the script catalog.
- `handout/cmd-implement-all-cc.html` and Hungarian counterpart — describe the new pre-spawn breadcrumb-write timing + removal of unconditional clear.
- `handout/cmd-implement-next-cc.html` and Hungarian counterpart — describe Step 0 triage + Step 7 self-verification.
- `handout/cmd-implement-all.html` / `cmd-implement-next.html` (and Hungarian) — describe Step 0 triage for the portable variant. (If any HTML file does not yet exist, list as TODO in the implementation plan.)
- `handout/cmd-implement-next-cc-resume.html` and Hungarian counterpart — describe the new breadcrumb-clear after Step 2's commit.

## Notes for Implementers

**Land atomically in a single PR** — intermediate states leave the breadcrumb cleared by un-updated callers. Each modified skill/script includes a `RECOVERY_SCHEMA_V2` marker comment for future version-checks. Order within the PR:

1. **`implement-next-state-write.sh`**: add atomic write, `--upsert` flag (empty-agentId-permitted; used by portable parent + standalone child), `--increment-review-abort` flag (read-modify-write to bump `review_abort_count` only), `schema_version: 2`, `branch_name` (via `git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo ""`), `skill_variant`, `review_abort_count` (default 0) fields. Default mode keeps the existing `expected_agent_id` guard. Add `RECOVERY_SCHEMA_V2` marker comment.
2. **`implement-next-triage.sh` (new)**: shared classifier per the contract above. Add `RECOVERY_SCHEMA_V2` marker.
3. **`audit-plan-run.sh`**: recognize `recovery(R-B):` commit-message prefix; downgrade matching VIOLATION to WARNING (exit 0). Add `RECOVERY_SCHEMA_V2` marker.
4. **`implement-next-cc-resume.md`**: clear the breadcrumb after Step 2's successful commit. Add `RECOVERY_SCHEMA_V2` marker.
5. **`implement-next-cc.md`**: add Step 7 self-verification (mirroring `implement-next.md:94-119`); renumber existing Report to Step 8; move `START_SHA`/`START_CHECKED` capture to Step 0; call `implement-next-triage.sh` in Step 0; child does NOT write breadcrumb when a parent breadcrumb is present. Add `RECOVERY_SCHEMA_V2` marker.
6. **`implement-next.md`**: move `START_SHA`/`START_CHECKED` capture from line 25 to Step 0; call `implement-next-triage.sh` in Step 0. Add `RECOVERY_SCHEMA_V2` marker.
7. **`implement-all-cc.md`**: write the full breadcrumb at Step 4 AFTER `Agent` returns the `agentId` and BEFORE waiting; remove the unconditional `implement-next-state-clear.sh` at Step 6 (line 64); clear explicitly on Case B-after-rescue-fails, Case C, Case D, and at final audit. Add `RECOVERY_SCHEMA_V2` marker.
8. **`implement-all.md` (portable parent)**: write the full breadcrumb at Step 3 after subagent spawn (empty `expected_agent_id` — portable has no hook to coordinate with); clear on all Step 4 halt paths. Add `RECOVERY_SCHEMA_V2` marker.
9. **`install.sh`**: (a) add `scripts/implement-next-triage.sh` to both `files` arrays at `install.sh:177-182` AND `install.sh:542-544`. (b) add `scripts/implement-next-triage.sh` to `check_cc_variant_integrity()` at `install.sh:483-497`; both variants need the script — known limitation that no `check_portable_variant_integrity()` mirror exists. (c) test fixtures under `~/.claude/tests/recovery/` are NOT installed (matches existing convention — tests live in-repo only).
10. **Tests** (bats, shell-layer only — see Test Harness Architecture):
    - `~/.claude/tests/recovery/test_triage.bats` — unit tests per the table in "Triage Unit Tests".
    - `~/.claude/tests/recovery/test_writer.bats` — `--upsert`, `--increment-review-abort`, atomic write, all new fields per sub-fixture (m.write).
    - `~/.claude/tests/recovery/test_audit_marker.bats` — covers: (a) positive `recovery(R-B):` commit → VIOLATION→WARNING; (b) typo `recovery(R-X):` → not matched, normal violation; (c) substring `"This reverts recovery(R-B): foo"` → not matched (subject-anchored); (d) three R-B commits → all three counted; (e) merge commit with `recovery(R-B):` subject → ignored (`--no-merges`); (f) anomalies-log existence/line-count surfaced at loop end.
    - `~/.claude/tests/recovery/test_hook_gate.bats` — fixtures (s), (t), (u) block/pass-through assertions (these are pure-shell hook invocations).
    - End-to-end scenarios (fixtures a–v) are MANUAL — see Manual / Integration Test Catalog.
11. **Documentation**: update the handout HTML files listed under Documentation Impact above.

## Open Questions

_None remaining. All Cycle 2 findings resolved into Key Decisions, In Scope additions, or fixtures above._

## Future Iterations

**Committed follow-up**: (none yet).
**Potential enhancements** (no commitment): opt-in `/implement-next --force` for committing review-unstable code; `audit-plan-run.sh` awareness of R-A/R-AB/R-C (currently only R-B); recovery telemetry; per-case sentinel for other skills; `flock`-based advisory locking for concurrent invocations; sidecar marker file for multi-developer `recovery(R-B):` integrity; extraction of shared R-* action sequences across the portable and `-cc` skill files.

## Recommendation

Build it — but with eyes open about the scope. The interruption failure class is real (`implement-all.md:81` cites ~7.6% of `/implement-next` subagents historically failing to commit), and that justifies the cost. Honestly this is a coordinated 20+ file change touching both parent variants (`-cc` and portable), both child variants, the rescue command, two helper scripts (`implement-next-state-write.sh`, `audit-plan-run.sh`), one new script (`implement-next-triage.sh`), the installer manifest, and a new `~/.claude/tests/recovery/` directory. Atomic landing is required — partial states leave the breadcrumb cleared by un-updated callers. Plan for a multi-PR review unit, not a quick fix. **Pre-ship gates are bats-tested shell-layer only**; end-to-end LLM-driven recovery flow is validated manually against a real session (acknowledged limitation — markdown consumed by an LLM cannot be intercepted via shell stubs). Hardest sub-problems: (a) eliminating the parent/child breadcrumb-write race (parent writes full, child reads-only); (b) `START_SHA`/`START_CHECKED` capture surviving skipped-Step-1 paths; (c) audit-script marker confined to R-B; (d) R-Stuck cap preventing re-entry loops. Do not compromise on deterministic breadcrumb-first detection — the LLM-heuristic version was wrong in 7 of 9 prior DA findings.
