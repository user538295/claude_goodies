import json
import pytest
from pathlib import Path

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from watcher import ManifestEntry, ManifestStore


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
