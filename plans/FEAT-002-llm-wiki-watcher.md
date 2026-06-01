# FEAT-002 — llm-wiki Raw Folder Auto-Ingestion Watcher
**Purpose**: Eliminate the manual "did I forget to ingest?" burden when files are dropped into `llm-wiki/raw/` — a background watcher queues them, and Claude offers batch ingest at the start of any llm-wiki operation.
**Audience**: Developers and product teams actively maintaining an llm-wiki who periodically drop files into `raw/` subfolders. They are already in an interactive Claude session when they want the wiki updated.
**Status**: To Do

---

## Background

The Karpathy LLM Wiki pattern promises compounding knowledge, but the ingest step is manual. A user drops a PDF into `llm-wiki/raw/product-docs/` and forgets to tell Claude — the wiki silently falls out of sync. This feature closes that gap with a stdlib-only Python polling watcher that detects new/changed files and queues them for human-confirmed batch ingest. Claude retains full agency; the watcher is a detector only.

## Goal

A `watcher.py` script runs as a background OS process, survives Claude session termination, and persists a queue of stable new/changed files in `llm-wiki/.watcher/pending`. Before every llm-wiki operation, Claude runs a pre-flight check: if the queue is non-empty, it prompts the user to batch-ingest using the existing single-file Ingest operation. The watcher never calls Claude autonomously. No external dependencies are introduced.

---

## Scope

### In Scope
- `watcher.py` at `~/.claude/skills/llm-wiki/watcher.py` — stdlib-only (Python 3.10+)
- All state files under `llm-wiki/.watcher/`: `manifest.json`, `pending`, `pending.processing`, `pending.snoozed`, `watcher.pid`, `watcher.log`
- 4 new Claude operations added to `SKILL.md`: `start-watch`, `stop-watch`, `watch-status`, `check-pending`
- Pre-flight check section added to the top of the Operations section in `templates/schema.md`
- `start-watch` adds `llm-wiki/.watcher/` to `.gitignore` automatically
- Batch ingest: single user-confirmation prompt → sequential single-file Ingest calls (reuses existing Ingest operation)
- Log line format for watcher-queue ingests in `log.md`
- SKILL.md preamble update: automation boundary clarification

### Out of Scope
- `watchdog` library or any non-stdlib dependency
- Headless `claude -p` subprocess calls — watcher never invokes Claude
- Global multi-project watcher daemon
- Windows support
- Auto-start on system boot (launchd/systemd)
- Watching `wiki/` or `drafts/`
- External mapped source directories outside `llm-wiki/raw/`

---

## Acceptance criteria

> Acceptance criteria are verified in the final task. See [Task 4.1 — Final verification & documentation update].

---

## What does NOT change
- Existing Ingest operation — batch ingest reuses it per file, no modifications
- `manifest.json` — owned exclusively by watcher; Claude never reads or writes it
- `log.md` format — new log lines use the existing `## [YYYY-MM-DD] <verb> | <subject> | <objects>` format with a new `infra` sub-entry for watcher ingests
- All existing SKILL.md hard rules remain intact
- `schema.md` Operations section is not restructured — the pre-flight block is inserted at its top

---

## Known limitations / accepted trade-offs
- 30-second polling latency is acceptable; watchdog upgrade is a future iteration
- One watcher process per project; no global daemon
- Files modified during active ingest are intentionally re-queued for the next cycle (no dedup against `pending.processing`)
- SIGTERM wakes the watcher from sleep within 1 second (not 30) due to the 1-second-tick interruptible sleep pattern.
- Race window — `pending` rename: when Claude renames `pending` to `pending.processing`, the watcher may append a new path to `pending` between Claude's read and the rename. That path will be included in `pending.processing` (and ingested) even though it was not shown in the confirmation prompt. After renaming, Claude should re-read `pending.processing` to report the actual count of files to be ingested.
- Manifest tracks only currently-present files. Deleted files are removed from the manifest on the next poll cycle. They remain in `pending` until Claude's pre-flight clears the file — either by renaming to `pending.processing` (Yes) or by deleting after snoozing (No). PF-3 filters non-existent paths before presenting to the user.

---

## Architecture

### New files
- `~/.claude/skills/llm-wiki/watcher.py` — single-file stdlib Python script (~350 lines). Structured as module-level classes; no `__init__.py` required.
- `~/.claude/skills/llm-wiki/tests/test_watcher.py` — pytest test suite

### State file layout (under `<project-root>/llm-wiki/.watcher/`)
```
manifest.json         ← {path → {mtime, size, sha256|null}}; watcher-owned
pending               ← one path per line, append-only; watcher appends; Claude may also append during un-snooze (both use O_APPEND; no locking needed for line-atomic writes)
pending.processing    ← renamed from pending at ingest start; lines get #done: prefix; Claude manages
pending.snoozed       ← paths declined by user; tab-delimited format: <abs-path>\t<mtime_float>\t<size_int>; Claude writes (with mtime+size at time of snooze), watcher reads (dedup: skip if path found and current mtime+size match snoozed values); mtime is stored as a Python float (from `os.stat().st_mtime`) for sub-second precision matching with the watcher's manifest
watcher.pid           ← line 1: "<pid>:<nonce>", line 2: ISO 8601 UTC heartbeat timestamp
watcher.log           ← timestamped free-form log; watcher writes; rotated to 5000 lines on startup if >10000
```

### Key classes in `watcher.py`
```python
@dataclass
class ManifestEntry:
    mtime: float; size: int; sha256: str | None  # None for files >500MB

class ManifestStore:
    def load(path: Path) -> dict[str, ManifestEntry]: ...
    def save(path: Path, entries: dict[str, ManifestEntry]) -> None: ...

class StabilityGate:
    # tracks previous-poll entries; a path is stable when mtime+size match across two polls
    def is_stable(path: str, current: ManifestEntry) -> bool: ...

class FileScanner:
    # scans raw/ recursively; returns at most 100 stable changed paths (alphabetical)
    def scan(manifest: dict[str, ManifestEntry],
             gate: StabilityGate) -> tuple[list[str], dict[str, ManifestEntry]]: ...

class PendingQueue:
    def load_sets() -> tuple[set[str], dict[str, tuple[float, int]]]: ...  # called once per poll cycle
    def should_append(path: str, current_entry: ManifestEntry, pending_set: set[str], snoozed_dict: dict[str, tuple[float, int]]) -> bool: ...
    def append(path: str) -> None: ...  # O_APPEND + flush

class PIDFile:
    def write(pid: int, nonce: str) -> None: ...
    def update_heartbeat(pid: int, nonce: str) -> None: ...  # atomic tmp+rename
    def read() -> tuple[int, str, datetime] | None: ...

class WatcherLog:
    def write(msg: str) -> None: ...
    def rotate_if_needed() -> None: ...  # >10000 lines → keep last 5000
```

### CLI
```
python3 watcher.py start <project-root>   # starts poll loop (runs in foreground; caller uses nohup &)
```

### SKILL.md new operation structure
Four new operation stubs added between existing operations and the Hard Rules section:
- `start-watch`, `stop-watch`, `watch-status`, `check-pending`

### schema.md template change
A `## Pre-flight check` section is inserted at the very top of the `## Operations` heading (before `### Log line format`). This section is the single definition point — it applies to all operations without per-operation modification.

---

## Task breakdown

### Phase 1 — Core watcher script

> **Releasable**: after Task 1.7, `nohup python3 watcher.py start <project-root> &` can be invoked manually and will monitor `llm-wiki/raw/`, queue stable new/changed files in `pending`, write heartbeats every 30s, and exit cleanly on SIGTERM.

#### Task 1.1 — `ManifestEntry` + `ManifestStore`
- [x] **File**: `~/.claude/skills/llm-wiki/watcher.py`
- **Depends on**: nothing
- **Description**:
  - `@dataclass class ManifestEntry: mtime: float; size: int; sha256: str | None`
  - `sha256` is `None` for files > 500 MB (tracked by mtime+size only; never hashed)
  - `class ManifestStore` with two static methods:
    - `load(path: Path) -> dict[str, ManifestEntry]` — returns `{}` if file absent or JSON invalid
    - `save(path: Path, entries: dict[str, ManifestEntry]) -> None` — atomic write via tmp+rename
  - JSON schema: `{"<abs-path>": {"mtime": float, "size": int, "sha256": str|null}}`
  - `save` uses `path.with_suffix('.tmp')` → `rename` for crash-safety
- **Releasable**: after this task, manifest can be loaded and saved safely
- **Tests (TDD)** — `~/.claude/skills/llm-wiki/tests/test_watcher.py`:
  - [x] Unit: `test_manifest_load_missing_file` — returns `{}` when file does not exist
  - [x] Unit: `test_manifest_load_invalid_json` — returns `{}` rather than raising
  - [x] Unit: `test_manifest_roundtrip` — save then load returns identical entries
  - [x] Unit: `test_manifest_large_file_no_hash` — entry with `sha256=None` survives roundtrip
  - [x] Unit: `test_manifest_save_atomic` — tmp file does not persist after save
  - Checkpoint: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/test_watcher.py -k "manifest" -v`

#### Task 1.2 — `StabilityGate`
- [x] **File**: `~/.claude/skills/llm-wiki/watcher.py`
- **Depends on**: Task 1.1
- **Description**:
  - `class StabilityGate` — holds `_prev: dict[str, ManifestEntry]` (previous-poll snapshot)
  - `is_stable(path: str, current: ManifestEntry) -> bool` — returns `True` iff `path` is in `_prev` AND `_prev[path].mtime == current.mtime AND _prev[path].size == current.size`
  - `advance(new_snapshot: dict[str, ManifestEntry]) -> None` — replaces `_prev` entirely (called at end of each poll cycle with the freshly computed entries for all seen files)
  - A path absent from `_prev` always returns `is_stable = False` (first time seen)
  - A path whose mtime OR size changed between polls returns `is_stable = False`
  - **Note**: There is no `mark()` method. Gate state is updated exclusively via `advance()` at the end of each poll cycle.
- **Releasable**: after this task, two-consecutive-poll stability gate is callable
- **Tests (TDD)** — `tests/test_watcher.py`:
  - [x] Unit: `test_stability_first_poll_not_stable` — path not in prev → False
  - [x] Unit: `test_stability_unchanged_across_polls` — same mtime+size → True
  - [x] Unit: `test_stability_changed_mtime` — mtime changes → False
  - [x] Unit: `test_stability_changed_size` — size changes → False
  - [x] Unit: `test_stability_advance_replaces_state` — after `advance`, old entries are gone
  - [x] Unit: `test_stability_advance_empty_clears_all` — after calling `advance({})`, `is_stable()` returns False for any previously-known path
  - Checkpoint: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/test_watcher.py -k "stability" -v`

#### Task 1.3 — `FileScanner`
- [x] **File**: `~/.claude/skills/llm-wiki/watcher.py`
- **Depends on**: Task 1.1, Task 1.2
- **Description**:
  - `class FileScanner` — no instance state; takes `raw_dir: Path` as constructor argument
  - `scan(manifest: dict[str, ManifestEntry], gate: StabilityGate) -> tuple[list[str], dict[str, ManifestEntry]]`
    - Returns `(stable_changed_paths, updated_manifest_entries)`. The caller (poll loop) passes `updated_manifest_entries` to `gate.advance()` after scan.
    - `updated_manifest_entries` covers all currently-seen files
    - Walks `raw_dir` recursively via `os.walk(raw_dir, followlinks=False)` — symlinks are NOT followed to prevent cycles; skips directories; processes files only
    - For each file: read `os.stat`; compare mtime+size with manifest entry
    - If mtime+size match manifest: no hash needed (entry unchanged)
    - If mtime+size differ (or file is new): compute SHA256 unless file > 500MB; update manifest entry
    - A file is a "candidate" if its manifest entry changed (new or different mtime/size/hash vs stored)
    - From candidates, apply gate: `is_stable(path, new_entry)` must be `True` to be included in result
    - Note: `scan()` calls `gate.is_stable()` (read-only query); it does NOT call `gate.advance()` (mutation). The poll loop calls `gate.advance(updated_entries)` after scan returns.
    - Of stable candidates, take at most 100, sorted alphabetically by path; defer the rest (gate state for deferred files is preserved — they remain in `_prev` with their current entry)
    - Returns paths as absolute strings
  - SHA256 helper: `_hash_file(path: Path) -> str` — reads in 64KB chunks; returns hex digest
- **Releasable**: after this task, raw/ directory can be scanned for stable changes with capping
- **Tests (TDD)** — `tests/test_watcher.py`:
  - [x] Unit: `test_scanner_new_file_not_stable_first_poll` — new file not returned on first scan (not yet stable)
  - [x] Unit: `test_scanner_new_file_stable_second_poll` — same file returned on second scan after `gate.advance()`
  - [x] Unit: `test_scanner_changed_file_resets_stability` — file that changes mtime between polls is not stable
  - [x] Unit: `test_scanner_cap_100_files_alphabetical` — when 150 files are stable, returns first 100 alphabetically
  - [x] Unit: `test_scanner_large_file_no_hash` — file >500MB gets `sha256=None` in manifest entry
  - [x] Unit: `test_scanner_hash_helper_correct` — SHA256 of known content matches expected value
  - [x] Unit: `test_scanner_symlink_not_followed` — create a symlink in `raw/` pointing to a file outside; assert the symlink target is NOT in the scan results (symlinks are not followed; `followlinks=False`)
  - [x] Unit: `test_scanner_nonexistent_raw_dir` — call `scan()` with a nonexistent directory path; assert it returns `([], {})` without raising an exception. (The caller validates `raw_dir` at startup; the scanner must not crash if called with a missing directory.)
  - [x] Unit: `test_scanner_unreadable_subdirectory` — create a subdirectory in `raw/` with mode 000; call `scan()`; assert the scanner does NOT raise an exception and logs (or silently skips) the unreadable directory. **Note: skip this test if `os.getuid() == 0` (root bypasses file permissions; use `pytest.mark.skipif(os.getuid() == 0, reason='root bypasses permissions')`).**
  - [x] Unit: `test_scanner_empty_raw_dir` — call `scan()` with an existing but empty directory; assert returns `([], {})`
  - Checkpoint: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/test_watcher.py -k "scanner" -v`

#### Task 1.4 — `PendingQueue`
- [x] **File**: `~/.claude/skills/llm-wiki/watcher.py`
- **Depends on**: Task 1.1
- **Description**:
  - `class PendingQueue`:
    - `__init__(self, watcher_dir: Path)` — stores paths to `pending` and `pending.snoozed`
    - `load_sets(self) -> tuple[set[str], dict[str, tuple[float, int]]]` — reads `pending` (returns set of paths; bare paths only, no stripping) and `pending.snoozed` (returns dict of `{path: (mtime, size)}`; tab-delimited format; mtime is parsed as `float`, size as `int`). Returns both. Called ONCE per poll cycle before iterating stable paths. Malformed lines in `pending.snoozed` (wrong number of tab-delimited fields, non-numeric mtime or size) are silently skipped — the entire poll cycle must not crash due to a single corrupt line.
    - `should_append(self, path: str, current_entry: ManifestEntry, pending_set: set[str], snoozed_dict: dict[str, tuple[float, int]]) -> bool`:
      1. If `path` in `pending_set` → return `False` (already queued)
      2. If `path` in `snoozed_dict`:
         - If `snoozed_dict[path] == (current_entry.mtime, current_entry.size)` → return `False` (unchanged since snooze)
         - Else → return `True` (changed since snooze — override)
      3. Otherwise → return `True`
    - `append(self, path: str) -> None`:
      - Opens `pending` with `os.O_WRONLY | os.O_APPEND | os.O_CREAT`, writes `path + "\n"`, calls `os.fsync` — single syscall per line
      - Claude may also call a shell equivalent of this append for un-snooze operations — same O_APPEND pattern.
  - `pending` is plain text, one absolute path per line (append-only; NEVER contains `#done:` prefixes — that prefix only appears in `pending.processing`)
  - `pending.snoozed` is tab-delimited: `<abs-path>\t<mtime_float>\t<size_int>`
- **Releasable**: after this task, the dedup-safe append-only queue is callable
- **Tests (TDD)** — `tests/test_watcher.py`:
  - [x] Unit: `test_queue_append_not_in_pending` — path not in pending → appended
  - [x] Unit: `test_queue_dedup_already_in_pending` — path in pending → not appended again
  - [x] Unit: `test_queue_snoozed_unchanged` — path in snoozed (tab-delimited with mtime+size) and mtime+size unchanged → not appended
  - [x] Unit: `test_queue_snoozed_changed` — path in snoozed (tab-delimited with mtime+size) but mtime/size changed → appended
  - [x] Unit: `test_queue_append_creates_file` — append to non-existent pending creates it
  - [x] Unit: `test_queue_append_multiple_lines` — multiple appends produce multiple lines
  - [x] Unit: `test_queue_load_sets_malformed_snoozed_line` — write `pending.snoozed` with one valid tab-delimited line and one malformed line (e.g., path-only, no tabs); assert `load_sets()` returns only the valid entry without raising an exception.
  - Checkpoint: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/test_watcher.py -k "queue" -v`

#### Task 1.5 — `PIDFile`
- [x] **File**: `~/.claude/skills/llm-wiki/watcher.py`
- **Depends on**: nothing
- **Description**:
  - `class PIDFile`:
    - `__init__(self, watcher_dir: Path)`
    - `write(self, pid: int, nonce: str) -> None` — writes two lines: `<pid>:<nonce>` then ISO 8601 UTC timestamp (`datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")`). Use `from datetime import datetime, timezone` — `utcnow()` is deprecated since Python 3.12. **Note**: using `+00:00` suffix instead of `Z` for Python 3.10 compatibility (`fromisoformat()` supports `Z` only from Python 3.11+).
    - `update_heartbeat(self, pid: int, nonce: str) -> None` — atomically rewrites file (same two-line format) via tmp+rename, same as ManifestStore.save; pid and nonce are passed in from the running process
    - `read(self) -> tuple[int, str, datetime] | None` — returns `(pid, nonce, heartbeat_dt)` or `None` if file absent/malformed
  - Nonce is a 8-char hex string generated once at process start via `secrets.token_hex(4)`
- **Releasable**: after this task, PID + heartbeat file management is callable
- **Tests (TDD)** — `tests/test_watcher.py`:
  - [x] Unit: `test_pidfile_write_then_read` — write pid/nonce, read back correct values
  - [x] Unit: `test_pidfile_missing_returns_none` — read on absent file returns None
  - [x] Unit: `test_pidfile_malformed_returns_none` — garbage content returns None
  - [x] Unit: `test_pidfile_update_heartbeat_preserves_pid_nonce` — heartbeat update keeps same pid:nonce (atomic tmp+rename)
  - [x] Unit: `test_pidfile_one_line_only_returns_none` — write a PID file with only line 1 (pid:nonce) and no line 2 (timestamp); assert `read()` returns `None`
  - Checkpoint: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/test_watcher.py -k "pidfile" -v`

#### Task 1.6 — `WatcherLog`
- [x] **File**: `~/.claude/skills/llm-wiki/watcher.py`
- **Depends on**: nothing
- **Description**:
  - `class WatcherLog`:
    - `__init__(self, watcher_dir: Path)`
    - `write(self, msg: str) -> None` — appends `[<ISO8601 UTC>] <msg>\n` using `datetime.now(timezone.utc)` (not `utcnow()`, deprecated since Python 3.12); opens in append mode each call (no persistent file handle; avoids rotation race)
    - `rotate_if_needed(self) -> None` — called once on startup:
      - Count lines in `watcher.log` (missing file → no-op)
      - If `> 10000` lines: read all lines, keep last 4999 tail lines (cut at line boundary; never mid-line), prepend `[<timestamp>] rotated: kept last 5000 of <N> lines` as the first of the 5000 retained lines, write all 5000 atomically (tmp + rename). Total output is 5000 lines.
- **Releasable**: after this task, structured log writing + startup rotation is callable
- **Tests (TDD)** — `tests/test_watcher.py`:
  - [x] Unit: `test_log_write_creates_file` — write to non-existent log creates it
  - [x] Unit: `test_log_write_includes_timestamp_and_message` — log line has ISO prefix
  - [x] Unit: `test_log_rotate_noop_under_threshold` — 9000-line file is not rotated
  - [x] Unit: `test_log_rotate_exactly_at_threshold` — 10001-line file is trimmed to 5000 lines
  - [x] Unit: `test_log_rotate_cuts_at_line_boundary` — no partial lines in rotated output
  - [x] Unit: `test_log_rotate_missing_file_noop` — no exception when file absent
  - [x] Unit: `test_log_rotate_exactly_at_boundary_no_rotation` — create a file with exactly 10000 lines; call `rotate_if_needed()`; assert the file is NOT modified (10000 lines exactly does NOT trigger rotation; threshold is strictly > 10000)
  - Checkpoint: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/test_watcher.py -k "log" -v`

#### Task 1.7 — Main poll loop + CLI entrypoint
- [x] **File**: `~/.claude/skills/llm-wiki/watcher.py`
- **Depends on**: Task 1.1, 1.2, 1.3, 1.4, 1.5, 1.6
- **Description**:
  - `def main() -> None` — argparse with single subcommand `start <project-root>`
  - Startup sequence:
    1. Resolve and validate `<project-root>/llm-wiki/raw/` — if absent: print error and exit 1
    2. Create `<project-root>/llm-wiki/.watcher/` if absent
    3. Generate `nonce = secrets.token_hex(4)`
    4. Instantiate `WatcherLog`; call `log.rotate_if_needed()`
    5. Load manifest via `ManifestStore.load()`
    6. Instantiate `StabilityGate`, `FileScanner`, `PendingQueue`, `PIDFile`
    7. Write PID file: `pid_file.write(os.getpid(), nonce)`
    8. Register SIGTERM handler: sets `_stop = True`
    9. Log: `[timestamp] watcher started pid=<pid> nonce=<nonce> project=<project-root>`
  - Poll loop (`while not _stop`):
    1. `stable_paths, updated_entries = scanner.scan(manifest, gate)`
    2. `gate.advance(updated_entries)`
    2a. `pending_set, snoozed_dict = queue.load_sets()` — load dedup sets once per cycle (not per-path)
    3. For each path in `stable_paths`: if `queue.should_append(path, updated_entries[path], pending_set, snoozed_dict)`: `queue.append(path)` and log detection
    4. `manifest = updated_entries`; `ManifestStore.save(manifest_path, manifest)`. Note: `updated_entries` covers only files currently present in `raw/`. Files deleted from `raw/` are silently dropped from the manifest — this is intentional. They remain in `pending` until Claude processes them (PF-3 filters non-existent paths).
    5. `pid_file.update_heartbeat(os.getpid(), nonce)`
    6. Use an interruptible sleep: either loop `for _ in range(30): if _stop: break; time.sleep(1)` or use `threading.Event().wait(timeout=30)` with the SIGTERM handler calling `_stop_event.set()`. This is required because `time.sleep()` on Python 3.5+ (PEP 475) retries after EINTR and does NOT exit early on signal.
  - On SIGTERM / KeyboardInterrupt: log `[timestamp] watcher stopped`; exit 0
  - `if __name__ == "__main__": main()`
- **Releasable**: after this task, `nohup python3 watcher.py start <project-root> &` is fully functional
- **Tests (TDD)** — `tests/test_watcher.py`:
  - [x] Unit: `test_main_missing_llm_wiki_raw_exits_1` — no llm-wiki/raw/ → sys.exit(1) with clear message
  - [x] Unit: `test_main_creates_watcher_dir` — `.watcher/` created if absent
  - [x] Integration: `test_full_poll_cycle` — place a file in a tmp raw/, run two scan+gate cycles, verify path appears in pending after second cycle. Assertions: (a) `pending` contains exactly the path of the placed file (one line, no duplicates); (b) manifest reflects the file with correct mtime, size, sha256; (c) on first cycle file is NOT in pending; on second cycle it IS.
  - [x] Integration: `test_poll_cycle_cap_deferred` — 110 stable files → only 100 in pending after first qualifying cycle
  - [x] Integration: `test_sigterm_exits_cleanly` — send SIGTERM to a running watcher subprocess, verify it exits 0 and writes stop log line. Assertions: (a) process exit code is 0; (b) `watcher.log` contains a stop log line matching `watcher stopped`; (c) `manifest.json` is valid JSON (not corrupt from mid-write shutdown); (d) `watcher.pid` still exists (cleanup is optional — document expected state).
  - [x] Integration: `test_dedup_across_poll_cycles` — run two full poll cycles with the SAME file; assert `pending` contains exactly ONE entry for that path (not two)
  - [x] Integration: `test_raw_dir_deleted_mid_run` — start a watcher against a valid `raw/`; delete the directory; run one poll cycle; assert watcher logs an error, does NOT append to pending, and continues running (does not crash)
  - Checkpoint: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/test_watcher.py -k "main or poll or sigterm" -v`

---

### Phase 2 — SKILL.md watcher operations

> **Releasable**: after Task 2.5, a user can invoke any of the 4 watcher operations by name and Claude will know exactly what to do.

#### Task 2.1 — `start-watch` operation in SKILL.md
- [x] **File**: `~/.claude/skills/llm-wiki/SKILL.md`
- **Depends on**: Task 1.7
- **Description**:
  - Add `start-watch` under `## Step 2 — Operations` → operation names list, and add a new `### start-watch` subsection in the Operations section with the following procedure:
    1. Check `llm-wiki/` exists — if not, fail: "No llm-wiki/ directory found. Run setup first."
    2. Check for existing watcher: read `llm-wiki/.watcher/watcher.pid`; if exists, verify via `ps -p <pid> -o command=` that command contains `watcher.py`; if running, report status and offer restart (on restart: send SIGTERM, wait 2s, then proceed to start)
    3. Create `llm-wiki/.watcher/` if absent
    4. Add `llm-wiki/.watcher/` to `.gitignore` at project root if not already present (mandatory — append line if absent, never duplicate)
    5. Run: `nohup python3 ~/.claude/skills/llm-wiki/watcher.py start <project-root> > /dev/null &` (stderr is NOT redirected so startup errors are visible in the terminal before daemonizing)
    6. Wait 2 seconds, then read PID file to confirm watcher started; report PID to user. If PID file is absent, check terminal for startup errors.
    7. Log: `## [YYYY-MM-DD] infra | watcher started | llm-wiki/.watcher/`
  - `start-watch` checks the skill path via `ls ~/.claude/skills/llm-wiki/watcher.py` first; falls back to `<repo>/.claude/skills/llm-wiki/watcher.py`
- **Releasable**: after this task, Claude can start the watcher on user request
- **Tests (TDD)**: N/A — SKILL.md is instruction text; verified manually in Task 4.1
- **Checkpoint**: manually read SKILL.md and verify `start-watch` section is present and complete

#### Task 2.2 — `stop-watch` operation in SKILL.md
- [x] **File**: `~/.claude/skills/llm-wiki/SKILL.md`
- **Depends on**: Task 2.1
- **Description**:
  - Add `stop-watch` to operation names list and add `### stop-watch` subsection:
    1. Read `llm-wiki/.watcher/watcher.pid` — if absent: report "watcher is not running (no PID file)"
    2. Parse `<pid>:<nonce>` from line 1
    3. Verify via `ps -p <pid> -o command=` that the output contains `watcher.py` — if not: report "stale PID file, watcher not running"; delete the stale PID file
    4. Send SIGTERM: `kill -TERM <pid>`
    5. Wait up to 5s for process to exit (poll `ps -p <pid>` every 1s)
    6. Report success or timeout
    7. Log: `## [YYYY-MM-DD] infra | watcher stopped | llm-wiki/.watcher/`
- **Releasable**: after this task, Claude can stop the watcher on user request
- **Tests (TDD)**: N/A — verified manually in Task 4.1
- **Checkpoint**: manually read SKILL.md and verify `stop-watch` section is present and complete

#### Task 2.3 — `watch-status` operation in SKILL.md
- [x] **File**: `~/.claude/skills/llm-wiki/SKILL.md`
- **Depends on**: Task 2.2
- **Description**:
  - Add `watch-status` to operation names list and add `### watch-status` subsection:
    1. Read `watcher.pid` — if absent: report "not running (no PID file)"
    2. Parse `<pid>:<nonce>` and heartbeat timestamp (line 2)
    3. Verify PID via `ps -p <pid> -o command=` (contains `watcher.py`)
    4. Compute heartbeat age = `now - heartbeat_dt`
    5. Report:
       - Age < 90s → "running (last heartbeat: Xs ago)"
       - Age 90s–300s → "stale/hung — heartbeat Xs ago; watcher may be hung. Consider stop-watch + start-watch."
       - Age > 300s or PID not found → "not running — run start-watch to resume monitoring"
    6. Also report: pending queue size (line count of `pending` if file exists)
- **Releasable**: after this task, Claude can report watcher health on user request
- **Tests (TDD)**: N/A — verified manually in Task 4.1
- **Checkpoint**: manually read SKILL.md and verify `watch-status` section is present and complete

#### Task 2.4 — `check-pending` operation in SKILL.md
- [x] **File**: `~/.claude/skills/llm-wiki/SKILL.md`
- **Depends on**: Task 2.3
- **Description**:
  - Add `check-pending` to operation names list and add `### check-pending` subsection:
    1. Read `llm-wiki/.watcher/pending` — list all pending paths (missing file = empty)
    2. Read `llm-wiki/.watcher/pending.snoozed` — list all snoozed paths (tab-delimited format: `<path>\t<mtime>\t<size>`)
    3. Cross-reference: if any path appears in both pending and snoozed, remove it from snoozed (the watcher only re-adds a snoozed path to pending when it detects the file has changed — the snooze is therefore stale). Write any modifications to `pending.snoozed` via `pending.snoozed.tmp` first, then atomically rename to `pending.snoozed`.
    4. Present two lists to user:
       - **Pending** (N files): list of paths — offer standard ingest prompt (proceeds to ingest flow)
       - **Snoozed** (N files): list of paths — for each, offer: (a) un-snooze (move back to pending), (b) dismiss permanently (delete from snoozed), (c) keep snoozed
    5. User can act on pending, snoozed, or both in one operation
- **Releasable**: after this task, Claude can review and manage the pending/snoozed queues on user request
- **Tests (TDD)**: N/A — verified manually in Task 4.1
- **Checkpoint**: manually read SKILL.md and verify `check-pending` section is present and complete

#### Task 2.5 — SKILL.md preamble update (automation boundary)
- [ ] **File**: `~/.claude/skills/llm-wiki/SKILL.md`
- **Depends on**: Task 2.4
- **Description**:
  - In the opening paragraph of SKILL.md (the paragraph beginning "The pattern stays minimal. **No automation...**"), update the sentence to read:
    > "No automation of wiki content. File change detection is permitted as infrastructure — the watcher detects but never acts; all ingest decisions remain with the human."
  - Add `start-watch`, `stop-watch`, `watch-status`, `check-pending` to the operation names list in `## Step 2 — Operations`
  - Update the SKILL.md sentence(s) that state "All operation procedures live in `llm-wiki/schema.md`" to distinguish between content operations (procedures in schema.md) and infrastructure/watcher operations (procedures in SKILL.md). The updated text should read approximately: "Content operation procedures live in `llm-wiki/schema.md`. Infrastructure and watcher operations (`start-watch`, `stop-watch`, `watch-status`, `check-pending`) are defined in this file below."
- **Releasable**: after this task, the automation boundary is clearly documented
- **Tests (TDD)**: N/A — verified manually in Task 4.1
- **Checkpoint**: manually read SKILL.md preamble and verify automation boundary sentence is updated

---

### Phase 3 — schema.md template pre-flight section

> **Releasable**: after Task 3.1, every new llm-wiki setup gets the pre-flight check in its `schema.md`, and existing wikis can have it added manually.

#### Task 3.1 — Pre-flight check section in `templates/schema.md`
- [ ] **File**: `~/.claude/skills/llm-wiki/templates/schema.md`
- **Depends on**: Task 2.5
- **Description**:
  - Insert a new `## Pre-flight check` section at the very top of the `## Operations` section (immediately after the `## Operations` heading, before `### Log line format`)
  - This section applies to ALL operations — it is defined once here, not per-operation
  - Content (exact markdown to insert):

    ```markdown
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
    ```

- **Releasable**: after this task, all new llm-wiki setups include the pre-flight check in `schema.md`
- **Tests (TDD)**: N/A — template text; verified manually in Task 4.1
- **Checkpoint**: read `templates/schema.md` and confirm `## Pre-flight check` appears at the top of `## Operations`

---

### Final Phase — Verification & Documentation

#### Task 4.1 — Final verification & documentation update
- [ ] **File**: N/A (agent task)
- **Depends on**: all prior tasks
- **Description**:
  - Run the complete test suite and verify all pass
  - Manually verify each acceptance criterion below
  - Spawn an agent to discover all documentation in the project (SKILL.md, templates/schema.md, reference files) and update every file whose content is affected by the changes delivered in this plan. The agent must not update docs that are unrelated.
  - Specifically check: does SKILL.md's operation list include all 4 new operations? Does `templates/schema.md` have the pre-flight section at the correct position? Is the automation boundary sentence updated?
- **Releasable**: after this task, the feature is fully verified and all documentation reflects the delivered implementation.
- **Acceptance criteria** (must all pass):
  - `python3 ~/.claude/skills/llm-wiki/watcher.py start /tmp/test-project` fails with clear error when `llm-wiki/raw/` is absent
  - `watcher.py start` runs successfully against a project with `llm-wiki/raw/`, creates `.watcher/` and `watcher.pid`, and writes a heartbeat within 35 seconds
  - After dropping a file in `llm-wiki/raw/` and waiting 65 seconds (two poll cycles), the file path appears in `llm-wiki/.watcher/pending`
  - `stop-watch` sends SIGTERM, watcher exits 0, and `watcher.log` contains a stop entry
  - `watch-status` correctly classifies running / stale / not-running based on heartbeat age
  - `check-pending` lists pending and snoozed files; un-snooze moves path back to pending
  - Pre-flight section appears at the top of `## Operations` in `templates/schema.md`
  - All Python tests pass: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/ -v`
  - `watcher.py` imports no third-party modules (stdlib only)
  - `.gitignore` is updated by `start-watch` when `.watcher/` is not already listed
  - Log rotation: a `watcher.log` with 11000 lines is trimmed to 5000 lines on watcher startup
  - Dedup: dropping the same file twice does not produce duplicate lines in `pending`
  - Snoozed file that is subsequently modified reappears in `pending` on next stable detection
  - After declining files in PF-3 ('No'), the same unchanged files do NOT appear in the next pre-flight prompt (snooze persists across pre-flight cycles when file is unmodified)
- **Tests (TDD)**: N/A — this is a verification and documentation task.
- **Checkpoint**: `cd ~/.claude/skills/llm-wiki && python -m pytest tests/ -v` — all green; manually confirm every acceptance criterion above is checked.
