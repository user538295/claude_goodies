---
name: commit-message
description: Write standardized Git commit messages in a direct, why-first style — Conventional Commits subject + a body of one or more `## H2` sections, each opening with a context paragraph then bullets. Use when the user asks to "write a commit message", "draft a commit message", "what should the commit message be", "make the commit message", "commit message for these changes", "commit the changes", or invokes /commit-message. Two modes: by default produces message text only and never mutates the repo; runs `git commit` (writing the message it just generated) ONLY when the request explicitly asks — pass the argument `commit` (deterministic trigger for agents) or use a commit verb such as "commit the changes". Safe to invoke as one step inside a larger task: it does its job, reports, and returns control without ever ending the agent's turn. Always applies this skill's standardized format — never inspects prior commits to "match local convention". Do NOT use for PR descriptions, tag annotations, or release notes — those have different voice constraints and live outside this skill.
---

# Commit Message

A voice and structure authority for Git commit messages. Reads the staged diff (or unstaged if nothing is staged) and produces a single commit message in the standardized format. Behaviour depends on the mode (see **Two modes** below): by default it only emits the message in a fenced block; when the request includes an explicit commit instruction it also runs `git commit` with that message and reports the new commit.

Message shape: Conventional Commits subject + body of `## H2` sections. 

---

## Operating contract — this skill is a subroutine, not a finish line

**Read this first if you are an agent invoking this skill as one step in a larger task.**

This skill does ONE small job — produce a commit message, and optionally commit it — and then **hands control straight back to you so you continue whatever you were doing.** It is a subroutine call, not the end of your work.

- **Never end your turn because of this skill.** Nothing in this file is an instruction to stop the agent, finish the session, or abandon the surrounding task. Words like "stop" / "done" below mean *"this skill has produced its output"* — they describe the skill returning, never you halting. After the skill returns, resume the next step of your task (run tests, move to the next item, etc.).
- **It is one step, not the last step.** If your task was "implement X, then commit," invoking this skill completes only the commit part. Carry on with the rest.
- **Failure is non-fatal — report and keep working.** If a `git commit` is rejected (pre-commit hook, nothing staged, lock file, etc.), the skill reports the error verbatim and returns. Do **not** retry blindly, work around a hook, or halt. Surface the error to the caller/user and continue with the rest of your task. The generated message stays available for a later retry.
- **Default is draft (no commit, no mutation).** A bare `/commit-message` only emits message text — it runs zero write commands and is always safe to call. The skill commits **only** when the invocation explicitly asks for it (see **Two modes**).
- **Never pushes, amends, or rewrites history.** Safe to invoke at any point in a workflow.

**What the skill returns in each mode** (in every row, control then returns to the caller):

| Mode | What the skill does | What the caller gets back |
|------|---------------------|----------------------|
| Draft | Reads diff, emits message | Fenced message block + one-line usage hint |
| Commit (success) | Reads diff, emits message, commits | Fenced message block + SHA + file list |
| Commit (failure) | Reads diff, emits message, attempts commit, commit rejected | Fenced message block + verbatim error; caller continues, message preserved |

---

## Two modes — draft (default) vs commit

This skill is invoked in one of two modes. **Decide the mode from the invocation phrasing, then state which mode you are in at the top of your response** (one short line, e.g. *"Commit mode: I will commit after generating the message."*).

**Draft mode (default).** The skill produces message text only and never mutates the repo. Triggered by:
- A bare `/commit-message` with no commit verb.
- "write / draft / make the commit message", "what should the commit message be?", "commit message for these changes".

**Commit mode.** The skill produces the message AND runs `git commit` with it, then reports the new commit. Triggered ONLY by an explicit commit instruction in the request, such as:
- The literal argument `commit` — `/commit-message commit`. This is the **deterministic trigger for agent callers**: pass `commit` as the argument and commit mode is guaranteed, with no reliance on phrasing.
- Natural-language commit verbs: "commit the changes", "commit it", "commit these", "go ahead and commit", "commit using /commit-message".

**The rule:** the `commit` argument, or an explicit commit *verb* directed at the repo → commit mode. Anything else, including a bare invocation, → draft mode. When genuinely ambiguous, default to **draft mode** (the non-destructive choice) and say so.

Mode selection only changes whether the skill commits. The message format, voice, and generation steps are identical in both modes.

**What gets committed (commit mode)** is decided from context, not from staging state alone: the changes produced during this conversation are the intended commit, whether they are staged, unstaged, or not yet tracked. Always reconcile that understanding against `git status` / the diff before committing — never commit from memory alone. When the intended set is **clear**, stage exactly those files and commit. When it is **ambiguous** — the working tree holds changes you did not make, several unrelated change-sets are present, or the session context isn't available to identify the set — **invoke the `/options` skill** to present the candidate change-sets and let the user choose; commit only what they select.

---

## When to use

- The user asks to "write / draft / make the commit message".
- The user asks "what should the commit message be?"
- The user invokes `/commit-message` explicitly.
- The user has just finished a change and is about to commit.

## When NOT to use

- PR descriptions, release notes, tag annotations — different audience and shape.
- Code comments, docstrings, ADRs — different voice.

(Asking you to commit no longer excludes this skill — that is commit mode. See **Two modes**.)

---

## Output contract

Produce **one fenced block** containing the commit message. Nothing above it except the one-line mode declaration. Below it:
- **Draft mode:** one short sentence telling the user how to use it.
- **Commit mode:** the commit result — the new commit's short SHA and subject, and the list of files committed (see the commit step in the generation workflow).

````
```
<subject line>

## <Section heading>

<context paragraph: 2–3 wrapped lines explaining the problem this section solves>

- <concrete change>
- <concrete change>
```

Paste into `git commit -F-` or `git commit -e` to review.   ← draft-mode trailer; in commit mode this is replaced by the commit result (SHA + files).
````

Never:
- Run `git tag`, `git push`, `git rebase`, `git reset`, or any write command other than the `git add` / `git commit` that **commit mode** performs. In **draft mode**, run no write commands at all.
- Inspect prior commits via `git log` to "match local convention" — apply this skill's format regardless of project history.
- Wrap the message in extra prose, headers, or "here's the commit message:" preambles.
- Add a trailing `Generated-by:` or `Co-authored-by:` line unless the user asked.

---

## Subject line rules

Format: `<type>(<scope>?): <imperative description>`

**Type** — one of:
- `feat` — new user-visible capability.
- `fix` — bug fix in existing behaviour.
- `docs` — documentation, handouts, READMEs, inline comments only.
- `refactor` — code change with no behaviour change.
- `chore` — tooling, build, dependencies, repo housekeeping.
- `test` — adding or fixing tests only.
- `perf` — performance improvement with no other behaviour change.

If the diff straddles two types, pick the one that describes the **user-visible outcome**. A `feat` that includes its own tests is still `feat`, not `test`.

**Scope** — optional. Use when one word would meaningfully narrow the area: `docs(commands)`, `fix(install)`, `docs(demo)`. Skip the scope if the type alone is precise enough, or if the change touches too many areas to name one.

**Description**:
- Imperative mood: `add`, `fix`, `tighten`, `drop`, `improve`, `expand`, `harden`, `rewrite`. Never past tense (`added`) or gerund (`adding`).
- Lowercase first word after the colon.
- No trailing period.
- Aim for ≤ 72 chars. Hard ceiling at 80.
- One semicolon-joined subject is allowed when the commit genuinely has **two parallel concerns** that can't be summarised under one verb. Example: `feat: add CC orchestrator variant with hook gate; harden behavioral rules`. Three or more concerns → still one subject line (pick the dominant one), but use multiple `## H2` sections in the body to separate them.

---

## Body — `## H2` sections (the only shape)

Every commit message has a body. The body is one or more `## H2` sections. Each section follows the same internal structure:

1. **Heading** — `## <Title>` naming the area or concern.
2. **Context paragraph** — 2–3 wrapped lines explaining the *problem* this section addresses. Lead with WHY before WHAT. The context paragraph is not optional.
3. **Bullets** — concrete changes. One change per bullet. Sub-bullets only when a bullet's explanation itself contains a list.

If the commit really only touches one area, write **one** section. That section still gets a heading, a context paragraph, and bullets. The standard does not relax for small commits — that is the entire point of standardization.

**Ordering of sections**: primary change first, supporting changes next, `## Other` (housekeeping, README, `.gitignore`, lockfiles) last. Use `## Other` only when there is real housekeeping; do not invent an `## Other` section for visual symmetry.

The canonical example, from this repo's commit `5ae668d`:

```
feat: add CC orchestrator variant with hook gate; harden behavioral rules

## CC orchestrator variant (/implement-all-cc family)

The portable /implement-all variant relies on prompt-only enforcement
to make subagents commit. Some subagents skip the commit step under
OOM, transport, or quota pressure. The CC variant adds deterministic
runtime enforcement on top of the same flow.

- New commands: `commands/implement-all-cc.md`,
  `commands/implement-next-cc.md`,
  `commands/implement-next-cc-resume.md` (rescue-only, not called
  directly)
- New hook scripts:
  - `implement-next-stop-gate.sh` — SubagentStop hook; refuses to let
    the spawned /implement-next-cc subagent end its turn until a new
    commit lands. Filters on agentId so devil's-advocate and fix
    sub-sub-agents pass through.
  - `implement-next-state-write.sh` / `implement-next-state-clear.sh`
    — write and clean up the sentinel at
    `<cwd>/.claude/implement-next-state.json`.

## Behavioral rules (CLAUDE.md)

Three top-level rules placed in the section that owns each concept,
no soft restatements left elsewhere:

- Section 1 "Think Before Coding" header:
  "Don't assume" → "You mustn't make assumptions"
- Communication: new "Never soften findings" with a concrete test
  (no "probably," "might be worth," "it could be argued" unless real
  uncertainty exists) so it's enforceable, not a slogan

## Other

- README.md: two-variants block under the orchestration commands.
- `.gitignore` added with the claude-sync sentinel block.
```

Things to notice in the example:

- **Subject uses a semicolon** because there are two genuinely parallel concerns: adding a new variant AND hardening rules.
- **Each `## Section` opens with a context paragraph** explaining the *problem* that section addresses, then bullets for the concrete changes.
- **Sub-bullets** appear under "New hook scripts" because each script needs its own one-line explanation — that's the trigger for nesting, not stylistic preference.
- **`## Other` section last** absorbs the housekeeping (README, `.gitignore`) that doesn't deserve its own top-level section but shouldn't be omitted.
- **Glob shorthand**: `cmd-implement-all{,-hu}.html` style for paired files (saves a line, signals "the same change in both").

---

## Body conventions

These rules govern the prose inside every section.

### 1. Wrap at 72 characters

Every body line — paragraph or bullet — wraps at column 72. Continuation lines of a bullet align under the text that follows the `- ` prefix.

### 2. Lead with WHY before WHAT

Context paragraphs name the *problem*, then introduce the *solution*. Example: *"The portable /implement-all variant relies on prompt-only enforcement to make subagents commit. Some subagents skip the commit step under OOM, transport, or quota pressure. The CC variant adds deterministic runtime enforcement on top of the same flow."* Even a small section gets a context paragraph — never skip it.

### 3. Backticks for code, paths, commands, config keys

Anything a reader could grep for goes in backticks: `commands/implement-all-cc.md`, `SubagentStop`, `git commit -F-`, `settings.json`. Plain English words do not.

### 4. Em-dashes for inline explanations

Use `—` (real em-dash, not `--`) for the beat where a comma is too quiet and a period is too loud. *"`implement-next-stop-gate.sh` — SubagentStop hook; refuses to let..."* Spaces around the em-dash are fine — match the surrounding prose.

### 5. Glob shorthand for paired files

When the same change applies to a `.html` and its `-hu.html` sibling (or `.ts` / `.test.ts`), use brace expansion: `cmd-implement-all{,-hu}.html`, `handout/agentic-workflow-{en,hu}.html`. Saves a line, signals "the same change in both."

### 6. Concrete language only

Name files, line numbers, function names, behaviour changes. Forbidden: *probably, might, perhaps, somewhat, slightly, could be*. The diff is concrete; the prose should match.

### 7. Sub-bullets only when needed

A bullet whose explanation runs longer than ~2 wrapped lines, or that itself contains a list of items, gets sub-bullets indented 2 spaces. Don't sub-bullet for visual variety.

### 8. No marketing, no trailers

Forbidden vocabulary: *robust, comprehensive, elegant, clean, polish, improvement, enhanced, optimised, streamlined, refined*. Forbidden trailers: *"Generated with Claude Code", "Co-authored-by: Claude", "This commit was made by an AI"*. Only add a `Co-authored-by:` line if the user typed a real human collaborator's email.

---

## Generation workflow

When invoked, follow these steps **in order**. Do not skip steps. **First determine the mode** (draft vs commit — see **Two modes**) and declare it on the first line of your response. Then:

1. **Inspect what will be committed.** Run:
   - `git diff --staged --stat` — file-level summary of staged changes.
   - `git diff --staged` — actual diff (read it; don't just summarize from filenames).
   - `git status --short` — flag unstaged changes the user may have meant to stage.

   Do **NOT** run `git log` to "match local conventions". The skill's format is the format, regardless of what the project has used in the past. Run `git log` only if the user explicitly asks you to consult prior commits.

2. **If nothing is staged**, inspect unstaged changes the same way (`git diff`, `git status`) and build the message from those. In **draft mode**, add **one sentence below the fenced block** noting that nothing is staged yet. In **commit mode**, the commit step (step 8) decides what to stage.

3. **Decide the type and scope** from the diff:
   - Pure docs/handouts/READMEs → `docs`.
   - New user-visible capability → `feat`.
   - Behaviour change that fixes a bug → `fix`.
   - Same behaviour, different code → `refactor`.
   - Build/tooling/deps → `chore`.

4. **Group the diff into sections.** Walk the changed files and cluster them by concern (a feature area, a subsystem, a rule set). Each cluster becomes one `## H2` section. Housekeeping (`README.md`, `.gitignore`, lockfiles) goes under `## Other` at the end. Even a single-cluster commit gets one `## H2` section — do not skip the heading.

5. **Draft the subject** in imperative mood, ≤72 chars, lowercase after colon, no trailing period. Semicolon only if two genuinely parallel concerns.

6. **Draft each section**: heading, then 2–3 line context paragraph (WHY), then bullets (WHAT). Wrap at 72. Backticks for code/paths. Forbidden-vocabulary check before output.

7. **Emit** the message inside a fenced block per the Output Contract.
   - **Draft mode:** add one sentence after the block telling the user how to use it (`git commit -F-` or `git commit -e`). **Do not commit.** The skill is finished — return control to the caller. (This does not end your turn: if you are mid-task, resume the next step.)
   - **Commit mode:** proceed to step 8.

8. **Commit (commit mode only).** Commit the exact message you just emitted:
   - **Decide what to commit (context first, not staging state).** The intended commit is the set of changes produced during this conversation — staged, unstaged, or untracked alike. Cross-check that against `git status --short` and the diff; **never commit from memory alone.**
     - **Clear set** → `git add <those exact paths>` (or accept an existing deliberate staged set that already matches) and commit. Do **not** sweep in unrelated changes with `git add -A`.
     - **Ambiguous** — the working tree holds changes you did not make, several unrelated change-sets are present, or the session context isn't available to identify the set → **invoke the `/options` skill** (via the Skill tool), presenting the candidate change-sets with a recommendation. Commit only the set the user picks, and respect a "don't commit / I'll stage it myself" choice.
   - **Commit via stdin** so the message is preserved verbatim (quoted heredoc — no shell expansion of backticks):
     ```
     git commit -F- <<'COMMIT_EOF'
     <the message exactly as emitted>
     COMMIT_EOF
     ```
   - **Only this one commit.** Never `git push`, never `git commit --amend`, never touch history.
   - **Report the result** below the fenced block: state the new short SHA and subject (`git log -1 --oneline`) and the files committed (`git show --stat --oneline HEAD`). If the commit fails (nothing to commit, a pre-commit hook rejects it, etc.), report the error verbatim — do not retry blindly or work around the hook. Either way (success or failure), **the skill is finished and returns control to the caller**: if you are mid-task, resume the next step; do not end your turn because of this skill.

---

## Anti-patterns — do not produce

- `feat: added new feature` — past tense (`added`) and no specifics.
- `fix: bug fixes` — non-specific subject, plural noun, no scope.
- `Update README.md` — capitalised, no type prefix, describes the file not the change.
- `feat: comprehensive refactor of the auth subsystem to improve robustness` — marketing vocabulary (`comprehensive`, `robustness`), and `refactor` should be the type, not part of the description.
- **A commit with no body** — every commit gets at least one `## H2` section with context paragraph + bullets. No exceptions for "small" commits.
- **A `## H2` section with no bullets**, or a context paragraph that just restates the heading — if you can't write at least one concrete bullet under the heading, the section doesn't earn its place; merge it elsewhere.
- An `## Other` section invented to make the message "feel bigger" — only use it when there is real housekeeping.
- Any trailer of the form `🤖 Generated with Claude Code` or `Co-authored-by: Claude <noreply@anthropic.com>`.

---

## What this skill does NOT do

- **No commit in draft mode.** Draft mode generates message text only; the user runs `git commit -F-` (or `-e`). Commit mode commits the generated message itself (see **Two modes**), and does no further git work — it never pushes, amends, or touches history. (Doing no further git work ≠ ending the agent's turn; control returns to the caller.)
- **No staging in draft mode.** Draft mode will not run `git add`; if the user has unstaged changes they meant to include, it flags them but does not act. Commit mode stages the specific files belonging to the change being committed (`git add <paths>`) — never a blind `git add -A` — and asks via the `/options` skill when the set is ambiguous.
- **No history-matching.** Does not inspect prior commits to mimic an inconsistent past format. Applies this skill's standardized format regardless of project history.
- **No PR descriptions, release notes, or tag annotations.** Different audience, different voice.
- **No translation.** If the project commits in a non-English language, follow the project's existing convention — never translate the subject prefixes (`feat`, `fix`, etc.) since those are tooling-adjacent.
- **No template-filling.** This skill writes the message from the diff. It does not maintain a template file the user fills in.
