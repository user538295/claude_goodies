import hashlib
import json
import re
import sys
from pathlib import Path

_ISO_UTC = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+00:00$")

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from catalog import (
    CatalogEntry,
    CatalogStore,
    _catalog_path,
    _relkey,
    add,
    get,
    main,
    remove,
    status,
)


# --- helpers ---

def _mk_raw(tmp_path: Path) -> Path:
    raw = tmp_path / "llm-wiki" / "raw"
    raw.mkdir(parents=True)
    return raw


def _sha(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


# --- CatalogStore tests ---

def test_store_load_missing_file(tmp_path):
    assert CatalogStore.load(tmp_path / "nope.json") == {}


def test_store_load_invalid_json_raises(tmp_path):
    bad = tmp_path / "catalog.json"
    bad.write_text("not json{{{")
    with pytest.raises(json.JSONDecodeError):
        CatalogStore.load(bad)


def test_store_load_wrong_shape_raises(tmp_path):
    # Valid JSON, wrong shape: must fail loud, not silently wipe the ledger.
    bad = tmp_path / "catalog.json"
    bad.write_text('{"a.md": "not-an-entry"}')
    with pytest.raises((KeyError, TypeError)):
        CatalogStore.load(bad)


def test_store_roundtrip(tmp_path):
    path = tmp_path / "catalog.json"
    entries = {
        "a.md": CatalogEntry(sha256="abc", ingested_at="2026-01-01T00:00:00+00:00"),
        "sub/b.md": CatalogEntry(sha256="def", ingested_at="2026-02-02T00:00:00+00:00"),
    }
    CatalogStore.save(path, entries)
    assert CatalogStore.load(path) == entries


def test_store_save_atomic_no_tmp_left(tmp_path):
    path = tmp_path / "catalog.json"
    CatalogStore.save(path, {"a.md": CatalogEntry(sha256="x", ingested_at="t")})
    assert not path.with_suffix(".tmp").exists()


def test_store_save_creates_parent_dir(tmp_path):
    path = tmp_path / ".watcher" / "catalog.json"
    CatalogStore.save(path, {"a.md": CatalogEntry(sha256="x", ingested_at="t")})
    assert path.exists()


# --- _relkey tests ---

def test_relkey_relative_to_raw(tmp_path):
    raw = _mk_raw(tmp_path)
    (raw / "doc.md").write_text("x")
    assert _relkey(tmp_path, "doc.md") == "doc.md"


def test_relkey_tolerates_documented_raw_prefix(tmp_path):
    # Docs (schema.md) instruct `add <root> raw/<file>`; that form must resolve.
    raw = _mk_raw(tmp_path)
    (raw / "doc.md").write_text("x")
    assert _relkey(tmp_path, "raw/doc.md") == "doc.md"


def test_relkey_absolute_under_raw(tmp_path):
    raw = _mk_raw(tmp_path)
    f = raw / "sub" / "doc.md"
    f.parent.mkdir()
    f.write_text("x")
    assert _relkey(tmp_path, str(f)) == "sub/doc.md"


def test_relkey_rejects_path_outside_raw(tmp_path):
    _mk_raw(tmp_path)
    outside = tmp_path / "llm-wiki" / "wiki" / "page.md"
    outside.parent.mkdir(parents=True)
    outside.write_text("x")
    with pytest.raises(ValueError):
        _relkey(tmp_path, str(outside))


def test_relkey_rejects_traversal(tmp_path):
    _mk_raw(tmp_path)
    with pytest.raises(ValueError):
        _relkey(tmp_path, "../secret.md", must_exist=False)


def test_relkey_add_requires_existing_file(tmp_path):
    _mk_raw(tmp_path)
    with pytest.raises(ValueError):
        _relkey(tmp_path, "ghost.md", must_exist=True)


# --- add tests ---

def test_add_new_file_records_hash_and_timestamp(tmp_path):
    raw = _mk_raw(tmp_path)
    content = b"hello world"
    (raw / "doc.md").write_bytes(content)

    add(tmp_path, ["doc.md"])

    entries = CatalogStore.load(_catalog_path(tmp_path))
    assert entries["doc.md"].sha256 == _sha(content)
    assert _ISO_UTC.match(entries["doc.md"].ingested_at)


def test_add_upsert_on_reingest_updates_hash(tmp_path):
    raw = _mk_raw(tmp_path)
    f = raw / "doc.md"
    f.write_bytes(b"v1")
    add(tmp_path, ["doc.md"])

    f.write_bytes(b"v2-changed")
    add(tmp_path, ["doc.md"])

    entries = CatalogStore.load(_catalog_path(tmp_path))
    assert entries["doc.md"].sha256 == _sha(b"v2-changed")
    assert _ISO_UTC.match(entries["doc.md"].ingested_at)
    assert len(entries) == 1


def test_add_multiple_files(tmp_path):
    raw = _mk_raw(tmp_path)
    (raw / "a.md").write_bytes(b"a")
    (raw / "b.md").write_bytes(b"b")
    add(tmp_path, ["a.md", "b.md"])
    entries = CatalogStore.load(_catalog_path(tmp_path))
    assert set(entries) == {"a.md", "b.md"}


def test_add_outside_raw_raises(tmp_path):
    _mk_raw(tmp_path)
    outside = tmp_path / "elsewhere.md"
    outside.write_text("x")
    with pytest.raises(ValueError):
        add(tmp_path, [str(outside)])


def test_add_nonexistent_raises(tmp_path):
    _mk_raw(tmp_path)
    with pytest.raises(ValueError):
        add(tmp_path, ["ghost.md"])


# --- get tests ---

def test_get_existing(tmp_path):
    raw = _mk_raw(tmp_path)
    (raw / "doc.md").write_bytes(b"hi")
    add(tmp_path, ["doc.md"])
    entry = get(tmp_path, "doc.md")
    assert entry is not None
    assert entry.sha256 == _sha(b"hi")


def test_get_missing_returns_none(tmp_path):
    _mk_raw(tmp_path)
    assert get(tmp_path, "doc.md") is None


# --- remove tests ---

def test_remove_existing(tmp_path):
    raw = _mk_raw(tmp_path)
    (raw / "a.md").write_bytes(b"a")
    (raw / "b.md").write_bytes(b"b")
    add(tmp_path, ["a.md", "b.md"])
    remove(tmp_path, ["a.md"])
    entries = CatalogStore.load(_catalog_path(tmp_path))
    assert set(entries) == {"b.md"}


def test_remove_missing_is_idempotent(tmp_path):
    _mk_raw(tmp_path)
    remove(tmp_path, ["ghost.md"])  # must not raise
    assert CatalogStore.load(_catalog_path(tmp_path)) == {}


def test_remove_accepts_deleted_file(tmp_path):
    raw = _mk_raw(tmp_path)
    f = raw / "a.md"
    f.write_bytes(b"a")
    add(tmp_path, ["a.md"])
    f.unlink()
    remove(tmp_path, ["a.md"])  # file gone, entry must still be removable
    assert CatalogStore.load(_catalog_path(tmp_path)) == {}


# --- status tests ---

def test_status_new_changed_current_missing(tmp_path):
    raw = _mk_raw(tmp_path)

    # current: ingested, unchanged
    (raw / "current.md").write_bytes(b"same")
    add(tmp_path, ["current.md"])

    # changed: ingested then edited
    changed = raw / "changed.md"
    changed.write_bytes(b"v1")
    add(tmp_path, ["changed.md"])
    changed.write_bytes(b"v2")

    # missing: ingested then file deleted
    gone = raw / "gone.md"
    gone.write_bytes(b"x")
    add(tmp_path, ["gone.md"])
    gone.unlink()

    # new: never ingested
    (raw / "new.md").write_bytes(b"fresh")

    result = status(tmp_path)
    assert result["new"] == ["new.md"]
    assert result["changed"] == ["changed.md"]
    assert result["current"] == ["current.md"]
    assert result["missing"] == ["gone.md"]


def test_status_empty_catalog_all_new(tmp_path):
    raw = _mk_raw(tmp_path)
    (raw / "a.md").write_bytes(b"a")
    (raw / "b.md").write_bytes(b"b")
    result = status(tmp_path)
    assert result["new"] == ["a.md", "b.md"]
    assert result["changed"] == []
    assert result["current"] == []
    assert result["missing"] == []


def test_status_empty_raw(tmp_path):
    _mk_raw(tmp_path)
    result = status(tmp_path)
    assert result == {"new": [], "changed": [], "current": [], "missing": []}


def test_status_symlink_not_followed(tmp_path):
    raw = _mk_raw(tmp_path)
    outside = tmp_path / "outside.md"
    outside.write_text("secret")
    (raw / "link").symlink_to(outside)
    result = status(tmp_path)
    assert result["new"] == []


def test_status_lists_sorted(tmp_path):
    raw = _mk_raw(tmp_path)
    for name in ("z.md", "a.md", "m.md"):
        (raw / name).write_bytes(b"x")
    result = status(tmp_path)
    assert result["new"] == ["a.md", "m.md", "z.md"]


# --- CLI (main) tests ---

def test_cli_status_prints_json(tmp_path, capsys):
    raw = _mk_raw(tmp_path)
    (raw / "a.md").write_bytes(b"a")
    with pytest.MonkeyPatch().context() as mp:
        mp.setattr(sys, "argv", ["catalog.py", "status", str(tmp_path)])
        main()
    out = json.loads(capsys.readouterr().out)
    assert out["new"] == ["a.md"]


def test_cli_add_then_get(tmp_path, capsys):
    raw = _mk_raw(tmp_path)
    (raw / "a.md").write_bytes(b"a")
    with pytest.MonkeyPatch().context() as mp:
        mp.setattr(sys, "argv", ["catalog.py", "add", str(tmp_path), "a.md"])
        main()
    capsys.readouterr()
    with pytest.MonkeyPatch().context() as mp:
        mp.setattr(sys, "argv", ["catalog.py", "get", str(tmp_path), "a.md"])
        main()
    out = json.loads(capsys.readouterr().out)
    assert out["sha256"] == _sha(b"a")


def test_cli_add_with_documented_raw_prefix(tmp_path, capsys):
    # schema.md documents `add <root> raw/<file>`; it must record, not crash.
    raw = _mk_raw(tmp_path)
    (raw / "a.md").write_bytes(b"a")
    with pytest.MonkeyPatch().context() as mp:
        mp.setattr(sys, "argv", ["catalog.py", "add", str(tmp_path), "raw/a.md"])
        main()
    out = json.loads(capsys.readouterr().out)
    assert out["current"] == ["a.md"]
    assert get(tmp_path, "a.md") is not None


def test_cli_get_missing_prints_null(tmp_path, capsys):
    _mk_raw(tmp_path)
    with pytest.MonkeyPatch().context() as mp:
        mp.setattr(sys, "argv", ["catalog.py", "get", str(tmp_path), "a.md"])
        main()
    assert json.loads(capsys.readouterr().out) is None


def test_cli_add_outside_raw_exits_nonzero(tmp_path):
    _mk_raw(tmp_path)
    outside = tmp_path / "x.md"
    outside.write_text("x")
    with pytest.MonkeyPatch().context() as mp:
        mp.setattr(sys, "argv", ["catalog.py", "add", str(tmp_path), str(outside)])
        with pytest.raises(SystemExit) as exc:
            main()
    assert exc.value.code != 0
