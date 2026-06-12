#!/usr/bin/env bash
# RECOVERY_SCHEMA_V2
#
# implement-next-triage.sh <cwd> <plan_path> <skill_variant>
#
# Classifier with bounded state-hygiene side effects. Reads the recovery
# breadcrumb (.claude/implement-next-state.json) plus repo state, then prints
# CASE= and ancillary KEY=VALUE lines on stdout, followed by a single
# human-readable RECOVERY: ... diagnostic line.
#
# Used as Step 0 of /implement-next and /implement-next-cc.
#
# Inputs (positional):
#   $1=cwd
#   $2=plan_path
#   $3=current_skill_variant   ("portable" | "cc")
#
# stdout (machine-readable):
#   KEY=VALUE lines, one per output variable. Always emits:
#     CASE, START_SHA, START_CHECKED, TASK_NAME
#   On matched-breadcrumb paths (R-A/R-B/R-AB/R-C):
#     SHA_BEFORE, BRANCH_NAME, REVIEW_RANGE, STEP_2_RESUME, REVIEW_ABORT_COUNT
#   Plus exactly one final line:
#     RECOVERY: <case_name> detected. sha_before=<X>, head=<Y>, dirty=<bool>. <action_summary>.
#
# Exit codes:
#   0 = dispatched (CASE=R-Fresh|R-A|R-B|R-AB|R-C)
#   1 = halt (corrupt breadcrumb in dirty tree, plan missing, R-Stuck, non-git cwd)
#   2 = usage error
#
# Side effects (bounded, documented):
#   - May delete $cwd/.claude/implement-next-state.json (machine-managed
#     sentinel; CLAUDE.md carve-out applies).
#   - May append to $cwd/.claude/recovery-anomalies.log (auto-clear row).
#     Capped at 10000 lines via atomic tail-and-mv truncation.
#   - On first creation of the anomalies log, emits a one-time stderr notice
#     prompting the user to .gitignore the path.

set -uo pipefail

USAGE="Usage: implement-next-triage.sh <cwd> <plan_path> <skill_variant>"

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [ $# -ne 3 ]; then
    echo "$USAGE" >&2
    exit 2
fi

raw_cwd="$1"
plan_path="$2"
current_variant="$3"

case "$current_variant" in
    portable|cc) ;;
    *)
        echo "ERROR: invalid skill_variant '$current_variant'; must be 'portable' or 'cc'" >&2
        exit 2
        ;;
esac

# Canonicalize cwd to an absolute path. If cd fails, exit 1.
cwd="$(cd "$raw_cwd" 2>/dev/null && pwd)" || {
    echo "ERROR: cwd does not exist or is not accessible: $raw_cwd" >&2
    exit 1
}

# jq dependency check.
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq not found in PATH (required by implement-next-triage.sh)" >&2
    exit 1
fi

# git repo check.
if ! git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: cwd is not a git repository: $cwd" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Capture START_SHA and plan-derived data
# ---------------------------------------------------------------------------
START_SHA="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo "")"

current_branch="$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo "")"

state_file="$cwd/.claude/implement-next-state.json"
anomalies_log="$cwd/.claude/recovery-anomalies.log"

# ---------------------------------------------------------------------------
# Plan-file existence check
# We need the plan file to exist (so we can compute START_CHECKED). If the
# breadcrumb references a plan_path but it's missing, this is exit 1 (plan
# file deleted between runs). Plain $plan_path missing too → exit 1.
# ---------------------------------------------------------------------------
if [ ! -f "$plan_path" ]; then
    echo "ERROR: plan file not found: $plan_path" >&2
    # Emit CASE=R-Halt for the calling skill to consume if it wants.
    echo "CASE=R-Halt"
    echo "RECOVERY: R-Halt detected. plan file not found at $plan_path."
    exit 1
fi

# START_CHECKED: count [x]/[X] lines in the on-disk plan.
START_CHECKED="$(awk '/^- \[[xX]\]/{c++} END{print c+0}' "$plan_path")"

# ---------------------------------------------------------------------------
# NEXT_TASK_NAME: derive once at the start, used for task_name mismatch checks
# AND for R-Fresh's TASK_NAME emission.
# ---------------------------------------------------------------------------
NEXT_TASK_NAME="$(bash "$HOME/.claude/scripts/plan-progress.sh" "$plan_path" 2>/dev/null \
    | grep '^NEXT_TASK_NAME=' \
    | cut -d= -f2- \
    || echo "")"
if [ -z "$NEXT_TASK_NAME" ]; then
    # Fallback: extract first unchecked task directly.
    NEXT_TASK_NAME="$(awk '/^- \[ \]/ {sub(/^- \[ \] /,""); print; exit}' "$plan_path")"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Is the working tree dirty? Returns 0 (dirty) or 1 (clean).
# Excludes the machine-managed sentinel files (.claude/implement-next-state.json,
# .claude/recovery-anomalies.log) AND a `.claude/` line that only encloses them.
# These are state hygiene files written by this script's siblings; they must
# NOT participate in the dirty/clean classification.
is_dirty() {
    local status
    status="$(git -C "$cwd" status --porcelain 2>/dev/null)"
    if [ -z "$status" ]; then
        return 1
    fi
    # Filter out lines that refer to the sentinel files.
    # `git status --porcelain` reports `?? .claude/` when the entire .claude
    # directory is untracked. In that case, check whether the only contents
    # are the sentinel files — if so, treat as clean.
    # Compute the only-sentinels result OUTSIDE awk so paths with spaces or
    # shell metacharacters in $cwd do not break awk's command interpolation.
    local claude_only_sentinels=0
    if [ -d "$cwd/.claude" ]; then
        local extra
        extra="$(find "$cwd/.claude" -mindepth 1 -maxdepth 1 \
            ! -name 'implement-next-state.json' \
            ! -name 'recovery-anomalies.log' \
            ! -name 'implement-next-state.json.tmp' \
            ! -name 'recovery-anomalies.log.tmp' \
            -print 2>/dev/null | head -n 1)"
        if [ -z "$extra" ]; then
            claude_only_sentinels=1
        fi
    fi
    local filtered
    filtered="$(printf '%s\n' "$status" | awk -v only_sentinels="$claude_only_sentinels" '
        {
            # Strip 2-char status code + space prefix.
            path = substr($0, 4)
            # Drop trailing slash for directory entries.
            sub(/\/$/, "", path)
            if (path == ".claude/implement-next-state.json") next
            if (path == ".claude/recovery-anomalies.log") next
            if (path == ".claude/implement-next-state.json.tmp") next
            if (path == ".claude/recovery-anomalies.log.tmp") next
            if (path == ".claude" && only_sentinels == "1") next
            print
        }
    ')"
    [ -n "$filtered" ]
}

dirty_bool() {
    if is_dirty; then
        echo "true"
    else
        echo "false"
    fi
}

# Append a WARNING line to the anomalies log. Emits the gitignore notice on
# first creation (file did not exist immediately before this run).
# Cap policy: if the pre-existing log already exceeds 10000 lines, truncate
# to the last 5000 BEFORE appending so the post-append total settles at 5001.
append_anomaly() {
    local line="$1"
    mkdir -p "$cwd/.claude"
    local first_creation=0
    if [ ! -f "$anomalies_log" ]; then
        first_creation=1
    fi
    # Pre-append cap check (atomic tail-and-mv).
    if [ -f "$anomalies_log" ]; then
        local n
        n="$(wc -l < "$anomalies_log" | tr -d '[:space:]')"
        if [ -n "$n" ] && [ "$n" -gt 10000 ]; then
            tail -n 5000 "$anomalies_log" > "$anomalies_log.tmp" && mv "$anomalies_log.tmp" "$anomalies_log"
        fi
    fi
    printf '%s\n' "$line" >> "$anomalies_log"
    if [ "$first_creation" -eq 1 ]; then
        echo "NOTE: Created .claude/recovery-anomalies.log. Add this path to your project's .gitignore to keep it out of version control." >&2
    fi
}

# Read a string field from the breadcrumb. Returns empty on error.
read_field() {
    local field="$1"
    jq -r --arg f "$field" '.[$f] // ""' "$state_file" 2>/dev/null || echo ""
}

# Emit the standard ancillary lines for a matched dispatch (R-A/R-B/R-AB/R-C).
emit_matched_lines() {
    local case_name="$1"
    local review_range="$2"
    local step2_resume="$3"
    local override_start_sha="${4:-}"  # for R-B
    local sha_before
    sha_before="$(read_field sha_before)"
    local branch_name
    branch_name="$(read_field branch_name)"
    local task_name
    task_name="$(read_field task_name)"
    local review_abort_count
    review_abort_count="$(jq -r '.review_abort_count // 0' "$state_file" 2>/dev/null || echo 0)"

    echo "CASE=$case_name"
    if [ -n "$override_start_sha" ]; then
        echo "START_SHA=$override_start_sha"
    else
        echo "START_SHA=$START_SHA"
    fi
    echo "START_CHECKED=$START_CHECKED"
    echo "SHA_BEFORE=$sha_before"
    echo "BRANCH_NAME=$branch_name"
    echo "TASK_NAME=$task_name"
    echo "REVIEW_RANGE=$review_range"
    echo "STEP_2_RESUME=$step2_resume"
    echo "REVIEW_ABORT_COUNT=$review_abort_count"
}

# Emit RECOVERY: <case> diagnostic line.
recovery_line() {
    local case_name="$1"
    local action="$2"
    local sha_before
    sha_before="$(read_field sha_before 2>/dev/null || echo "")"
    local head
    head="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo "")"
    local dirty
    dirty="$(dirty_bool)"
    echo "RECOVERY: $case_name detected. sha_before=$sha_before, head=$head, dirty=$dirty. $action."
}

# Emit R-Fresh and its diagnostic, then exit 0.
emit_r_fresh() {
    local action="$1"
    echo "CASE=R-Fresh"
    echo "START_SHA=$START_SHA"
    echo "START_CHECKED=$START_CHECKED"
    echo "TASK_NAME=$NEXT_TASK_NAME"
    local head
    head="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo "")"
    local dirty
    dirty="$(dirty_bool)"
    echo "RECOVERY: R-Fresh detected. sha_before=, head=$head, dirty=$dirty. $action."
    exit 0
}

# ---------------------------------------------------------------------------
# Dispatch (top-to-bottom; first match wins)
# ---------------------------------------------------------------------------

# Row 0: no breadcrumb → R-Fresh
if [ ! -f "$state_file" ]; then
    emit_r_fresh "No prior breadcrumb; proceeding to Step 1"
fi

# Row 0a: malformed JSON → R-Fresh
if ! jq -e . "$state_file" >/dev/null 2>&1; then
    emit_r_fresh "Malformed JSON breadcrumb treated as absent"
fi

# Inspect breadcrumb fields once (each read is a jq call; cache).
bc_schema_version="$(jq -r '.schema_version // ""' "$state_file" 2>/dev/null || echo "")"
bc_sha_before="$(read_field sha_before)"
bc_plan_path="$(read_field plan_path)"
bc_task_name="$(read_field task_name)"
bc_branch_name="$(read_field branch_name)"
bc_skill_variant="$(read_field skill_variant)"

# Detect v2 field presence: branch_name, skill_variant, review_abort_count.
# `jq -e .field` returns 0 if the field exists (even if null/empty); 1 otherwise.
has_v2_field=0
for v2_field in branch_name skill_variant review_abort_count; do
    if jq -e ". | has(\"$v2_field\")" "$state_file" >/dev/null 2>&1; then
        if [ "$(jq -r ". | has(\"$v2_field\")" "$state_file")" = "true" ]; then
            has_v2_field=1
            break
        fi
    fi
done

# Detect legacy: no schema_version AND no v2 fields → legacy v1.
# We accept jq's emit "null" for missing as empty already (// "").
if [ -z "$bc_schema_version" ] && [ "$has_v2_field" -eq 0 ]; then
    emit_r_fresh "Legacy v1 breadcrumb (no schema_version, no v2 fields); treating as absent"
fi

# Schema mismatch: schema_version not "2" (integer) but one or more v2 fields present → corrupt.
# bc_schema_version is the raw string representation; the writer emits an INTEGER 2,
# which jq -r prints as "2". A string "2" stored as schema_version would also yield "2".
# To distinguish, ask jq for the TYPE.
if [ "$has_v2_field" -eq 1 ]; then
    schema_type="$(jq -r '.schema_version | type' "$state_file" 2>/dev/null || echo "null")"
    # Acceptable: number == 2.
    accepted=0
    if [ "$schema_type" = "number" ] && [ "$bc_schema_version" = "2" ]; then
        accepted=1
    fi
    if [ "$accepted" -eq 0 ]; then
        emit_r_fresh "Schema inconsistency: schema_version not integer 2 but v2 fields present; corrupt breadcrumb treated as absent"
    fi
fi

# Row 1: review_abort_count >= 2 → R-Stuck
# Read defensively. Validate integer before comparing.
review_abort_count_raw="$(jq -r '.review_abort_count // 0' "$state_file" 2>/dev/null || echo 0)"
if [[ "$review_abort_count_raw" =~ ^[0-9]+$ ]] && [ "$review_abort_count_raw" -ge 2 ]; then
    # R-Stuck: halt with manual-recovery diagnostic on stderr.
    echo "CASE=R-Stuck"
    echo "RECOVERY: R-Stuck detected. sha_before=$bc_sha_before, head=$START_SHA, dirty=$(dirty_bool). review failed twice; manual recovery required."
    cat >&2 <<EOF
review failed twice for task '$bc_task_name' (sha_before=$bc_sha_before); manual recovery required at $state_file. Either \`git checkout -- .\` to discard the review-touched files and delete $state_file, or commit manually and clear the breadcrumb with \`bash ~/.claude/scripts/implement-next-state-clear.sh $cwd\`.
EOF
    exit 1
fi

# Row 2: plan_path differs from current plan path → R-Fresh (stale-plan)
if [ -n "$bc_plan_path" ] && [ "$bc_plan_path" != "$plan_path" ]; then
    emit_r_fresh "Stale-plan: breadcrumb plan_path='$bc_plan_path' differs from current '$plan_path'"
fi

# Row 3: breadcrumb's task_name is already committed-checked in git show HEAD:$plan_path
# Determine repo-relative path for git show.
repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "")"
plan_rel=""
if [ -n "$repo_root" ]; then
    # If absolute path starts with repo_root/, strip it; otherwise leave as-is.
    case "$plan_path" in
        "$repo_root"/*) plan_rel="${plan_path#"$repo_root/"}" ;;
        *) plan_rel="$plan_path" ;;
    esac
fi

if [ -n "$plan_rel" ] && [ -n "$bc_task_name" ]; then
    if head_plan_content="$(git -C "$cwd" show "HEAD:$plan_rel" 2>/dev/null)"; then
        # Use fixed-string grep so task names with regex metachars don't false-trigger.
        if printf '%s\n' "$head_plan_content" | grep -F -- "- [x] $bc_task_name" >/dev/null 2>&1 \
            || printf '%s\n' "$head_plan_content" | grep -F -- "- [X] $bc_task_name" >/dev/null 2>&1; then
            # Delete stale breadcrumb and dispatch R-Fresh.
            rm -f "$state_file"
            emit_r_fresh "Breadcrumb's task '$bc_task_name' already committed-checked in HEAD; clearing stale breadcrumb"
        fi
    fi
fi

# Row 4: task_name doesn't match NEXT_TASK_NAME (the next unchecked task)
# Note: NEXT_TASK_NAME may be empty if the plan has no unchecked tasks.
if [ -n "$bc_task_name" ] && [ "$bc_task_name" != "$NEXT_TASK_NAME" ]; then
    # Sub-row 4a: clean + HEAD == sha_before → auto-clear + WARNING + R-Fresh
    head_sha="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo "")"
    if ! is_dirty && [ "$head_sha" = "$bc_sha_before" ]; then
        warn_line="WARNING: Auto-cleared stale breadcrumb for task '$bc_task_name' (next task per plan: '$NEXT_TASK_NAME', no commits since breadcrumb, tree clean). If this was unexpected, check plan file integrity."
        echo "$warn_line"
        append_anomaly "$warn_line"
        rm -f "$state_file"
        emit_r_fresh "Auto-cleared stale breadcrumb; tree clean and no commits since breadcrumb"
    else
        # Sub-row 4b: dirty OR HEAD moved → exit 1 (potential plan editing / branch switch / crash)
        echo "CASE=R-Halt"
        echo "RECOVERY: R-Halt detected. sha_before=$bc_sha_before, head=$head_sha, dirty=$(dirty_bool). Breadcrumb task '$bc_task_name' mismatches plan's next task '$NEXT_TASK_NAME' AND tree is dirty or HEAD has moved; manual investigation required."
        echo "ERROR: breadcrumb's task_name '$bc_task_name' does not match plan's next task '$NEXT_TASK_NAME', and either the working tree is dirty or HEAD has moved. This indicates plan editing, branch switch, or a prior crash. Investigate manually." >&2
        exit 1
    fi
fi

# Row 5: branch_name non-empty and differs → warn and continue
if [ -n "$bc_branch_name" ] && [ -n "$current_branch" ] && [ "$bc_branch_name" != "$current_branch" ]; then
    echo "WARNING: branch mismatch — breadcrumb branch='$bc_branch_name', current branch='$current_branch'. Continuing dispatch; verify this was intentional."
fi

# Row 6: skill_variant differs → warn and continue
if [ -n "$bc_skill_variant" ] && [ "$bc_skill_variant" != "$current_variant" ]; then
    echo "WARNING: skill variant mismatch — breadcrumb variant='$bc_skill_variant', current variant='$current_variant'. Continuing dispatch."
fi

# ---------------------------------------------------------------------------
# Final matched dispatch (passed all prior checks)
# ---------------------------------------------------------------------------
head_sha="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || echo "")"
dirty_now=0
if is_dirty; then dirty_now=1; fi

if [ "$head_sha" = "$bc_sha_before" ] && [ "$dirty_now" -eq 1 ]; then
    # R-A: HEAD == sha_before + dirty → review HEAD+worktree
    emit_matched_lines "R-A" "HEAD+worktree" "false"
    recovery_line "R-A" "Resuming with uncommitted partial impl; skip Steps 1-2, review HEAD+worktree, run tests, check off, commit"
    exit 0
fi

if [ "$head_sha" != "$bc_sha_before" ] && [ "$dirty_now" -eq 0 ]; then
    # R-B: HEAD != sha_before + clean → orphan impl commit; insert plan checkoff, review <sha_before>..HEAD
    emit_matched_lines "R-B" "${bc_sha_before}..HEAD" "false" "$bc_sha_before"
    recovery_line "R-B" "Orphan impl commit detected; insert plan checkoff into WT, review ${bc_sha_before}..HEAD, commit with recovery(R-B): prefix"
    exit 0
fi

if [ "$head_sha" != "$bc_sha_before" ] && [ "$dirty_now" -eq 1 ]; then
    # R-AB: HEAD != sha_before + dirty → hybrid
    emit_matched_lines "R-AB" "${bc_sha_before}..HEAD+worktree" "false"
    recovery_line "R-AB" "Hybrid: orphan impl commit AND dirty tree; review ${bc_sha_before}..HEAD+worktree, commit with recovery(R-AB): prefix"
    exit 0
fi

# Default: HEAD == sha_before + clean → R-C
emit_matched_lines "R-C" "" "true"
recovery_line "R-C" "Pre-impl TDD-red state; resume Step 2 implementing only sub-items unchecked in HEAD's plan"
exit 0
