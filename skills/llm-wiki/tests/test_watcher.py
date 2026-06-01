import json
import os
import hashlib
import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from watcher import ManifestEntry, ManifestStore, StabilityGate, FileScanner, PendingQueue, PIDFile, WatcherLog, _hash_file


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


# --- FileScanner tests ---

def test_scanner_new_file_not_stable_first_poll(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    (raw / "file.md").write_text("hello")
    scanner = FileScanner(raw)
    gate = StabilityGate()
    stable, updated = scanner.scan({}, gate)
    assert stable == []
    assert len(updated) == 1


def test_scanner_new_file_stable_second_poll(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    (raw / "file.md").write_text("hello")
    scanner = FileScanner(raw)
    gate = StabilityGate()
    _, updated = scanner.scan({}, gate)
    gate.advance(updated)
    stable, _ = scanner.scan(updated, gate)
    assert len(stable) == 1
    assert stable[0] == str(raw / "file.md")


def test_scanner_changed_file_resets_stability(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    f = raw / "file.md"
    f.write_text("hello")
    scanner = FileScanner(raw)
    gate = StabilityGate()
    _, updated = scanner.scan({}, gate)
    gate.advance(updated)
    # Modify the file to change mtime/size
    f.write_text("hello world changed")
    stable, _ = scanner.scan(updated, gate)
    assert stable == []


def test_scanner_cap_100_files_alphabetical(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    for i in range(150):
        (raw / f"file_{i:04d}.md").write_text(f"content {i}")
    scanner = FileScanner(raw)
    gate = StabilityGate()
    # First scan: advance so all files are stable on second scan
    _, updated = scanner.scan({}, gate)
    gate.advance(updated)
    stable, _ = scanner.scan(updated, gate)
    assert len(stable) == 100
    assert stable == sorted(stable)


def test_scanner_large_file_no_hash(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    f = raw / "bigfile.bin"
    f.write_bytes(b"x")  # small actual file
    fake_stat = MagicMock()
    fake_stat.st_mtime = 1000.0
    fake_stat.st_size = 500 * 1024 * 1024 + 1  # > 500MB
    scanner = FileScanner(raw)
    gate = StabilityGate()
    with patch("os.stat", return_value=fake_stat):
        _, updated = scanner.scan({}, gate)
    assert updated[str(f)].sha256 is None
    assert updated[str(f)].size == 500 * 1024 * 1024 + 1


def test_scanner_hash_helper_correct(tmp_path):
    f = tmp_path / "test.txt"
    content = b"hello world"
    f.write_bytes(content)
    expected = hashlib.sha256(content).hexdigest()
    assert _hash_file(f) == expected


def test_scanner_symlink_not_followed(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    outside = tmp_path / "outside_file.txt"
    outside.write_text("outside content")
    link = raw / "link"
    link.symlink_to(outside)
    scanner = FileScanner(raw)
    gate = StabilityGate()
    _, updated = scanner.scan({}, gate)
    gate.advance(updated)
    stable, _ = scanner.scan(updated, gate)
    assert str(outside) not in stable


def test_scanner_nonexistent_raw_dir(tmp_path):
    scanner = FileScanner(tmp_path / "does_not_exist")
    gate = StabilityGate()
    stable, updated = scanner.scan({}, gate)
    assert stable == []
    assert updated == {}


@pytest.mark.skipif(os.getuid() == 0, reason="root bypasses permissions")
def test_scanner_unreadable_subdirectory(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    locked = raw / "locked"
    locked.mkdir()
    (locked / "hidden.md").write_text("secret")
    locked.chmod(0o000)
    try:
        scanner = FileScanner(raw)
        gate = StabilityGate()
        scanner.scan({}, gate)  # must not raise
    finally:
        locked.chmod(0o755)  # restore for cleanup


def test_scanner_empty_raw_dir(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    scanner = FileScanner(raw)
    gate = StabilityGate()
    stable, updated = scanner.scan({}, gate)
    assert stable == []
    assert updated == {}


# --- PendingQueue tests ---

def test_queue_append_not_in_pending(tmp_path):
    queue = PendingQueue(tmp_path)
    entry = ManifestEntry(mtime=1.0, size=100, sha256=None)
    pending_set, snoozed_dict = queue.load_sets()
    assert queue.should_append("/some/file.md", entry, pending_set, snoozed_dict) is True


def test_queue_dedup_already_in_pending(tmp_path):
    queue = PendingQueue(tmp_path)
    (tmp_path / "pending").write_text("/some/file.md\n")
    entry = ManifestEntry(mtime=1.0, size=100, sha256=None)
    pending_set, snoozed_dict = queue.load_sets()
    assert queue.should_append("/some/file.md", entry, pending_set, snoozed_dict) is False


def test_queue_snoozed_unchanged(tmp_path):
    queue = PendingQueue(tmp_path)
    (tmp_path / "pending.snoozed").write_text("/some/file.md\t1.0\t100\n")
    entry = ManifestEntry(mtime=1.0, size=100, sha256=None)
    pending_set, snoozed_dict = queue.load_sets()
    assert queue.should_append("/some/file.md", entry, pending_set, snoozed_dict) is False


def test_queue_snoozed_changed(tmp_path):
    queue = PendingQueue(tmp_path)
    (tmp_path / "pending.snoozed").write_text("/some/file.md\t1.0\t100\n")
    entry = ManifestEntry(mtime=2.0, size=200, sha256=None)
    pending_set, snoozed_dict = queue.load_sets()
    assert queue.should_append("/some/file.md", entry, pending_set, snoozed_dict) is True


def test_queue_append_creates_file(tmp_path):
    queue = PendingQueue(tmp_path)
    queue.append("/some/file.md")
    assert (tmp_path / "pending").exists()
    assert (tmp_path / "pending").read_text() == "/some/file.md\n"


def test_queue_append_multiple_lines(tmp_path):
    queue = PendingQueue(tmp_path)
    queue.append("/a.md")
    queue.append("/b.md")
    lines = (tmp_path / "pending").read_text().splitlines()
    assert lines == ["/a.md", "/b.md"]


def test_queue_load_sets_malformed_snoozed_line(tmp_path):
    queue = PendingQueue(tmp_path)
    (tmp_path / "pending.snoozed").write_text("/valid/file.md\t1.0\t100\n/malformed-no-tabs\n")
    pending_set, snoozed_dict = queue.load_sets()
    assert "/valid/file.md" in snoozed_dict
    assert snoozed_dict["/valid/file.md"] == (1.0, 100)
    assert "/malformed-no-tabs" not in snoozed_dict


# --- PIDFile tests ---

def test_pidfile_write_then_read(tmp_path):
    pf = PIDFile(tmp_path)
    pf.write(12345, "abcd1234")
    result = pf.read()
    assert result is not None
    pid, nonce, heartbeat_dt = result
    assert pid == 12345
    assert nonce == "abcd1234"
    assert heartbeat_dt.tzinfo is not None


def test_pidfile_missing_returns_none(tmp_path):
    pf = PIDFile(tmp_path)
    assert pf.read() is None


def test_pidfile_malformed_returns_none(tmp_path):
    pid_file = tmp_path / "watcher.pid"
    pid_file.write_text("not-valid-content\n")
    pf = PIDFile(tmp_path)
    assert pf.read() is None


def test_pidfile_update_heartbeat_preserves_pid_nonce(tmp_path):
    pf = PIDFile(tmp_path)
    pf.write(99, "nonce99")
    pf.update_heartbeat(99, "nonce99")
    result = pf.read()
    assert result is not None
    pid, nonce, _ = result
    assert pid == 99
    assert nonce == "nonce99"
    assert not (tmp_path / "watcher.pid.tmp").exists()


def test_pidfile_one_line_only_returns_none(tmp_path):
    pid_file = tmp_path / "watcher.pid"
    pid_file.write_text("42:mynonce\n")
    pf = PIDFile(tmp_path)
    assert pf.read() is None


# --- WatcherLog tests ---

def test_log_write_creates_file(tmp_path):
    wl = WatcherLog(tmp_path)
    wl.write("hello")
    assert (tmp_path / "watcher.log").exists()


def test_log_write_includes_timestamp_and_message(tmp_path):
    import re
    wl = WatcherLog(tmp_path)
    wl.write("test message")
    content = (tmp_path / "watcher.log").read_text()
    pattern = r"^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+00:00\] test message\n$"
    assert re.match(pattern, content), f"Line did not match pattern: {content!r}"


def test_log_rotate_noop_under_threshold(tmp_path):
    wl = WatcherLog(tmp_path)
    log_file = tmp_path / "watcher.log"
    log_file.write_text("".join(f"line {i}\n" for i in range(9000)))
    wl.rotate_if_needed()
    lines = log_file.read_text().splitlines()
    assert len(lines) == 9000


def test_log_rotate_exactly_at_threshold(tmp_path):
    wl = WatcherLog(tmp_path)
    log_file = tmp_path / "watcher.log"
    log_file.write_text("".join(f"line {i}\n" for i in range(10001)))
    wl.rotate_if_needed()
    lines = log_file.read_text().splitlines()
    assert len(lines) == 5000


def test_log_rotate_cuts_at_line_boundary(tmp_path):
    wl = WatcherLog(tmp_path)
    log_file = tmp_path / "watcher.log"
    log_file.write_text("".join(f"line {i}\n" for i in range(10001)))
    wl.rotate_if_needed()
    content = log_file.read_text()
    lines = content.splitlines(keepends=True)
    # Every line except possibly the last should end with \n
    for line in lines[:-1]:
        assert line.endswith("\n"), f"Line does not end with newline: {line!r}"


def test_log_rotate_missing_file_noop(tmp_path):
    wl = WatcherLog(tmp_path)
    # Should not raise even if file is absent
    wl.rotate_if_needed()


def test_log_rotate_exactly_at_boundary_no_rotation(tmp_path):
    wl = WatcherLog(tmp_path)
    log_file = tmp_path / "watcher.log"
    log_file.write_text("".join(f"line {i}\n" for i in range(10000)))
    wl.rotate_if_needed()
    lines = log_file.read_text().splitlines()
    assert len(lines) == 10000
