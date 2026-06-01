from dataclasses import dataclass
from pathlib import Path
import json


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
