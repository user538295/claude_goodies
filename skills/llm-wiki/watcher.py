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
