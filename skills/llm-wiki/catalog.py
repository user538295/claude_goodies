"""Ingest ledger for the LLM Wiki raw/ folder.

Records which raw files have been ingested into the wiki and their sha256 at
ingest time, so changed files can be flagged for re-ingest. This is the
*ingested*-hash authority; the current-hash is computed on demand by status().
Script-owned so the LLM never hand-edits the ledger.
"""

import argparse
import hashlib
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

READ_CHUNK_BYTES = 65536


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(READ_CHUNK_BYTES):
            h.update(chunk)
    return h.hexdigest()


@dataclass(frozen=True)
class CatalogEntry:
    sha256: str
    ingested_at: str


class CatalogStore:
    @staticmethod
    def load(path: Path) -> dict[str, CatalogEntry]:
        """Load the ledger. Missing file → empty ledger. A corrupt or
        wrong-shape file raises (JSONDecodeError/KeyError/TypeError) rather than
        silently reading as empty, which would trigger a full re-ingest."""
        if not path.exists():
            return {}
        data = json.loads(path.read_text())
        return {
            k: CatalogEntry(sha256=v["sha256"], ingested_at=v["ingested_at"])
            for k, v in data.items()
        }

    @staticmethod
    def save(path: Path, entries: dict[str, CatalogEntry]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        data = {
            k: {"sha256": e.sha256, "ingested_at": e.ingested_at}
            for k, e in entries.items()
        }
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=2, sort_keys=True))
        tmp.rename(path)


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")


def _raw_dir(project_root: Path) -> Path:
    return (Path(project_root) / "llm-wiki" / "raw").resolve()


def _catalog_path(project_root: Path) -> Path:
    # Committed (not under gitignored .watcher/) so a fresh clone keeps the
    # ingest history instead of re-ingesting the whole corpus.
    return Path(project_root) / "llm-wiki" / "catalog.json"


def _relkey(project_root: Path, raw_path: str, must_exist: bool = True) -> str:
    """Resolve raw_path to a POSIX key relative to raw/. Rejects anything that
    resolves outside raw/ (blocks `..` traversal). Tolerates the documented
    `raw/<file>` form (schema.md) as well as a bare `<file>`."""
    raw_dir = _raw_dir(project_root)
    p = Path(raw_path)
    # A leading `raw/` is the documented CLI form (schema.md); strip it.
    if not p.is_absolute() and len(p.parts) > 1 and p.parts[0] == "raw":
        p = Path(*p.parts[1:])
    p = p if p.is_absolute() else (raw_dir / p)
    # ponytail: normpath collapses .. without following symlinks, so
    # symlinked files/dirs in raw/ resolve to their link path, not target.
    p = Path(os.path.normpath(p))
    try:
        rel = p.relative_to(raw_dir)
    except ValueError:
        raise ValueError(f"path is not under {raw_dir}: {raw_path}")
    if must_exist and not p.is_file():
        raise ValueError(f"not an existing file under raw/: {raw_path}")
    return rel.as_posix()


def add(project_root: Path, paths: list[str]) -> None:
    """Record (upsert) each raw file's current sha256 and ingest time. Each path
    must be an existing file under raw/ (bare or `raw/`-prefixed); raises
    ValueError otherwise."""
    cat_path = _catalog_path(project_root)
    entries = CatalogStore.load(cat_path)
    raw_dir = _raw_dir(project_root)
    for raw_path in paths:
        key = _relkey(project_root, raw_path, must_exist=True)
        entries[key] = CatalogEntry(
            sha256=_hash_file(raw_dir / key),
            ingested_at=_now_iso(),
        )
    CatalogStore.save(cat_path, entries)


def remove(project_root: Path, paths: list[str]) -> None:
    """Drop each path's ledger entry. Idempotent: a path not in the ledger (or
    whose file was already deleted) is a no-op, not an error."""
    cat_path = _catalog_path(project_root)
    entries = CatalogStore.load(cat_path)
    for raw_path in paths:
        key = _relkey(project_root, raw_path, must_exist=False)
        entries.pop(key, None)
    CatalogStore.save(cat_path, entries)


def get(project_root: Path, raw_path: str) -> CatalogEntry | None:
    """Return the ledger entry for a raw path, or None if not catalogued."""
    entries = CatalogStore.load(_catalog_path(project_root))
    key = _relkey(project_root, raw_path, must_exist=False)
    return entries.get(key)


def status(project_root: Path) -> dict[str, list[str]]:
    """Diff raw/ against the catalog. new/changed/current re-hash each raw file
    (ponytail: O(total bytes) per call; add an mtime/size cache if corpora grow
    huge). missing = catalogued files no longer in raw/."""
    entries = CatalogStore.load(_catalog_path(project_root))
    raw_dir = _raw_dir(project_root)

    new, changed, current = [], [], []
    seen: set[str] = set()
    if raw_dir.exists():
        # ponytail: followlinks=True lets users symlink external corpora into raw/;
        # symlink loops are the user's problem — upgrade to cycle detection if needed.
        for dirpath, _dirnames, filenames in os.walk(raw_dir, followlinks=True):
            for filename in filenames:
                full = Path(dirpath) / filename
                if not full.is_file():
                    continue
                key = full.relative_to(raw_dir).as_posix()
                seen.add(key)
                entry = entries.get(key)
                if entry is None:
                    new.append(key)
                elif entry.sha256 == _hash_file(full):
                    current.append(key)
                else:
                    changed.append(key)

    missing = [k for k in entries if k not in seen]
    return {
        "new": sorted(new),
        "changed": sorted(changed),
        "current": sorted(current),
        "missing": sorted(missing),
    }


def main() -> None:
    parser = argparse.ArgumentParser(prog="catalog")
    sub = parser.add_subparsers(dest="command", required=True)

    for name in ("add", "remove"):
        p = sub.add_parser(name)
        p.add_argument("project_root", type=Path)
        p.add_argument("paths", nargs="+")

    p = sub.add_parser("get")
    p.add_argument("project_root", type=Path)
    p.add_argument("path")

    p = sub.add_parser("status")
    p.add_argument("project_root", type=Path)

    args = parser.parse_args()

    try:
        if args.command == "add":
            add(args.project_root, args.paths)
            print(json.dumps(status(args.project_root), indent=2))
        elif args.command == "remove":
            remove(args.project_root, args.paths)
            print(json.dumps(status(args.project_root), indent=2))
        elif args.command == "get":
            entry = get(args.project_root, args.path)
            print(json.dumps(
                None if entry is None
                else {"sha256": entry.sha256, "ingested_at": entry.ingested_at},
                indent=2,
            ))
        elif args.command == "status":
            print(json.dumps(status(args.project_root), indent=2))
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
