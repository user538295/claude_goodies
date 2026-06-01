import json
import pytest
from pathlib import Path

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from watcher import ManifestEntry, ManifestStore, StabilityGate


def test_manifest_load_missing_file(tmp_path):
    result = ManifestStore.load(tmp_path / "nonexistent.json")
    assert result == {}


def test_manifest_load_invalid_json(tmp_path):
    bad = tmp_path / "manifest.json"
    bad.write_text("not valid json{{{")
    result = ManifestStore.load(bad)
    assert result == {}


def test_manifest_roundtrip(tmp_path):
    path = tmp_path / "manifest.json"
    entries = {
        "/some/file.md": ManifestEntry(mtime=1234567890.0, size=1024, sha256="abc123"),
        "/other/file.txt": ManifestEntry(mtime=9876543210.5, size=512, sha256="def456"),
    }
    ManifestStore.save(path, entries)
    loaded = ManifestStore.load(path)
    assert loaded == entries


def test_manifest_large_file_no_hash(tmp_path):
    path = tmp_path / "manifest.json"
    entries = {
        "/huge/video.mp4": ManifestEntry(mtime=111111.0, size=600 * 1024 * 1024, sha256=None),
    }
    ManifestStore.save(path, entries)
    loaded = ManifestStore.load(path)
    assert loaded == entries
    assert loaded["/huge/video.mp4"].sha256 is None


def test_manifest_save_atomic(tmp_path):
    path = tmp_path / "manifest.json"
    entries = {"/a/b.md": ManifestEntry(mtime=1.0, size=10, sha256="aaa")}
    ManifestStore.save(path, entries)
    tmp_file = path.with_suffix(".tmp")
    assert not tmp_file.exists()


# --- StabilityGate tests ---

def test_stability_first_poll_not_stable():
    gate = StabilityGate()
    entry = ManifestEntry(mtime=1.0, size=100, sha256=None)
    assert gate.is_stable("/some/file.md", entry) is False


def test_stability_unchanged_across_polls():
    gate = StabilityGate()
    entry = ManifestEntry(mtime=1.0, size=100, sha256=None)
    gate.advance({"/some/file.md": entry})
    assert gate.is_stable("/some/file.md", entry) is True


def test_stability_changed_mtime():
    gate = StabilityGate()
    old = ManifestEntry(mtime=1.0, size=100, sha256=None)
    new = ManifestEntry(mtime=2.0, size=100, sha256=None)
    gate.advance({"/some/file.md": old})
    assert gate.is_stable("/some/file.md", new) is False


def test_stability_changed_size():
    gate = StabilityGate()
    old = ManifestEntry(mtime=1.0, size=100, sha256=None)
    new = ManifestEntry(mtime=1.0, size=200, sha256=None)
    gate.advance({"/some/file.md": old})
    assert gate.is_stable("/some/file.md", new) is False


def test_stability_advance_replaces_state():
    gate = StabilityGate()
    entry_a = ManifestEntry(mtime=1.0, size=100, sha256=None)
    entry_b = ManifestEntry(mtime=2.0, size=200, sha256=None)
    gate.advance({"/a.md": entry_a})
    gate.advance({"/b.md": entry_b})
    # /a.md is no longer in prev — should be unstable
    assert gate.is_stable("/a.md", entry_a) is False
    # /b.md is now in prev with matching values — should be stable
    assert gate.is_stable("/b.md", entry_b) is True


def test_stability_advance_empty_clears_all():
    gate = StabilityGate()
    entry = ManifestEntry(mtime=1.0, size=100, sha256=None)
    gate.advance({"/some/file.md": entry})
    gate.advance({})
    assert gate.is_stable("/some/file.md", entry) is False
