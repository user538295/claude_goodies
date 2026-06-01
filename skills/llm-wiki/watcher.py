from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import json
import os
import hashlib


@dataclass
class ManifestEntry:
    mtime: float
    size: int
    sha256: str | None


class ManifestStore:
    @staticmethod
    def load(path: Path) -> dict[str, ManifestEntry]:
        try:
            data = json.loads(path.read_text())
            return {
                k: ManifestEntry(
                    mtime=v["mtime"],
                    size=v["size"],
                    sha256=v["sha256"],
                )
                for k, v in data.items()
            }
        except Exception:
            return {}

    @staticmethod
    def save(path: Path, entries: dict[str, ManifestEntry]) -> None:
        data = {
            k: {"mtime": e.mtime, "size": e.size, "sha256": e.sha256}
            for k, e in entries.items()
        }
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data))
        tmp.rename(path)


class StabilityGate:
    def __init__(self) -> None:
        self._prev: dict[str, ManifestEntry] = {}

    def is_stable(self, path: str, current: ManifestEntry) -> bool:
        prev = self._prev.get(path)
        if prev is None:
            return False
        return prev.mtime == current.mtime and prev.size == current.size

    def advance(self, new_snapshot: dict[str, ManifestEntry]) -> None:
        self._prev = new_snapshot


_LARGE_FILE_THRESHOLD = 500 * 1024 * 1024  # 500 MB
_SCAN_CAP = 100


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


class FileScanner:
    def __init__(self, raw_dir: Path) -> None:
        self._raw_dir = raw_dir

    def scan(
        self,
        manifest: dict[str, ManifestEntry],
        gate: StabilityGate,
    ) -> tuple[list[str], dict[str, ManifestEntry]]:
        if not self._raw_dir.exists():
            return [], {}

        updated: dict[str, ManifestEntry] = {}
        candidates: list[str] = []

        for dirpath, _dirnames, filenames in os.walk(self._raw_dir, followlinks=False):
            for filename in filenames:
                path = os.path.join(dirpath, filename)
                try:
                    stat = os.stat(path)
                except OSError:
                    continue

                mtime = stat.st_mtime
                size = stat.st_size
                existing = manifest.get(path)

                if existing is not None and existing.mtime == mtime and existing.size == size:
                    # Unchanged — reuse existing entry, but still a candidate for stability check
                    new_entry = existing
                else:
                    # New or changed — compute hash if not too large
                    if size > _LARGE_FILE_THRESHOLD:
                        sha256 = None
                    else:
                        try:
                            sha256 = _hash_file(Path(path))
                        except OSError:
                            continue
                    new_entry = ManifestEntry(mtime=mtime, size=size, sha256=sha256)

                candidates.append(path)
                updated[path] = new_entry

        # Filter candidates by stability gate
        stable = [p for p in candidates if gate.is_stable(p, updated[p])]

        # Cap at 100, sorted alphabetically
        stable.sort()
        stable = stable[:_SCAN_CAP]

        return stable, updated


class PendingQueue:
    def __init__(self, watcher_dir: Path) -> None:
        self._pending = watcher_dir / "pending"
        self._snoozed = watcher_dir / "pending.snoozed"

    def load_sets(self) -> tuple[set[str], dict[str, tuple[float, int]]]:
        pending_set: set[str] = set()
        try:
            for line in self._pending.read_text().splitlines():
                line = line.strip()
                if line:
                    pending_set.add(line)
        except OSError:
            pass

        snoozed_dict: dict[str, tuple[float, int]] = {}
        try:
            for line in self._snoozed.read_text().splitlines():
                parts = line.split("\t")
                if len(parts) != 3:
                    continue
                path, mtime_str, size_str = parts
                try:
                    snoozed_dict[path] = (float(mtime_str), int(size_str))
                except ValueError:
                    continue
        except OSError:
            pass

        return pending_set, snoozed_dict

    def should_append(
        self,
        path: str,
        current_entry: ManifestEntry,
        pending_set: set[str],
        snoozed_dict: dict[str, tuple[float, int]],
    ) -> bool:
        if path in pending_set:
            return False
        if path in snoozed_dict:
            if snoozed_dict[path] == (current_entry.mtime, current_entry.size):
                return False
            return True
        return True

    def append(self, path: str) -> None:
        fd = os.open(str(self._pending), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
        try:
            os.write(fd, (path + "\n").encode())
            os.fsync(fd)
        finally:
            os.close(fd)


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
