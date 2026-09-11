"""Background journal for the LLM Wiki raw/ folder.

Opt-in. The watcher only *observes*: every poll it records which files
appeared or changed in raw/ into watcher.log, and heartbeats a PID file so the
skill can report liveness. It never decides ingest and holds no ingest state —
catalog.py is the single authority for what needs ingesting (new/changed), and
the skill computes that on demand. The loop only stats files (no hashing), so
it stays cheap on large corpora.
"""

import argparse
import os
import signal
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path


class WatcherLog:
    def __init__(self, watcher_dir: Path) -> None:
        self._path = watcher_dir / "watcher.log"

    def write(self, msg: str) -> None:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        with open(self._path, "a") as f:
            f.write(f"[{ts}] {msg}\n")

    def rotate_if_needed(self) -> None:
        try:
            lines = self._path.read_text().splitlines(keepends=True)
        except OSError:
            return
        if len(lines) <= 10000:
            return
        n = len(lines)
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        rotation_line = f"[{ts}] rotated: kept last 5000 of {n} lines\n"
        tail = lines[-(4999):]
        output = [rotation_line] + tail
        tmp = self._path.with_suffix(".log.tmp")
        tmp.write_text("".join(output))
        tmp.rename(self._path)


class PIDFile:
    def __init__(self, watcher_dir: Path) -> None:
        self._path = watcher_dir / "watcher.pid"

    def _format_lines(self, pid: int, nonce: str) -> str:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        return f"{pid}:{nonce}\n{ts}\n"

    def write(self, pid: int, nonce: str) -> None:
        self._path.write_text(self._format_lines(pid, nonce))

    def update_heartbeat(self, pid: int, nonce: str) -> None:
        tmp = self._path.with_suffix(".pid.tmp")
        tmp.write_text(self._format_lines(pid, nonce))
        tmp.rename(self._path)

    def read(self) -> tuple[int, str, datetime] | None:
        try:
            lines = self._path.read_text().splitlines()
        except OSError:
            return None
        if len(lines) < 2:
            return None
        parts = lines[0].split(":", maxsplit=1)
        if len(parts) != 2:
            return None
        try:
            pid = int(parts[0])
        except ValueError:
            return None
        nonce = parts[1]
        try:
            heartbeat_dt = datetime.fromisoformat(lines[1])
        except ValueError:
            return None
        return (pid, nonce, heartbeat_dt)


_POLL_INTERVAL = 30
_stop_event = threading.Event()


def _sigterm_handler(signum, frame) -> None:
    _stop_event.set()


def _snapshot(raw_dir: Path) -> dict[str, tuple[float, int]]:
    """Cheap stat-only view of raw/: path -> (mtime, size). Symlinks not
    followed. Missing raw_dir yields an empty snapshot (deleted mid-run)."""
    snap: dict[str, tuple[float, int]] = {}
    for dirpath, _dirnames, filenames in os.walk(raw_dir, followlinks=False):
        for filename in filenames:
            path = os.path.join(dirpath, filename)
            if os.path.islink(path):  # match catalog.status(): raw/ ignores symlinks
                continue
            try:
                stat = os.stat(path)
            except OSError:
                continue
            snap[path] = (stat.st_mtime, stat.st_size)
    return snap


def main() -> None:
    _stop_event.clear()

    parser = argparse.ArgumentParser(prog="watcher")
    subparsers = parser.add_subparsers(dest="command")
    start_parser = subparsers.add_parser("start")
    start_parser.add_argument("project_root", type=Path)
    args = parser.parse_args()

    project_root: Path = args.project_root.resolve()
    raw_dir = project_root / "llm-wiki" / "raw"
    if not raw_dir.exists():
        print(f"error: {raw_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    watcher_dir = project_root / "llm-wiki" / ".watcher"
    watcher_dir.mkdir(parents=True, exist_ok=True)

    nonce = os.urandom(4).hex()

    log = WatcherLog(watcher_dir)
    log.rotate_if_needed()
    pid_file = PIDFile(watcher_dir)

    pid = os.getpid()
    pid_file.write(pid, nonce)

    signal.signal(signal.SIGTERM, _sigterm_handler)

    log.write(f"watcher started pid={pid} nonce={nonce} project={project_root}")

    prev: dict[str, tuple[float, int]] = {}
    while not _stop_event.is_set():
        cur = _snapshot(raw_dir)
        for path in sorted(set(cur) - set(prev)):
            log.write(f"appeared {path}")
        for path in sorted(k for k in cur if k in prev and cur[k] != prev[k]):
            log.write(f"modified {path}")
        prev = cur
        pid_file.update_heartbeat(pid, nonce)
        _stop_event.wait(timeout=_POLL_INTERVAL)

    log.write("watcher stopped")


if __name__ == "__main__":
    main()
