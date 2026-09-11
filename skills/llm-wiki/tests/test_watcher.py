import os
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from watcher import PIDFile, WatcherLog, _snapshot, main


# --- _snapshot tests ---

def test_snapshot_lists_files_with_mtime_size(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    f = raw / "file.md"
    f.write_text("hello")
    snap = _snapshot(raw)
    stat = f.stat()
    assert snap == {str(f): (stat.st_mtime, stat.st_size)}


def test_snapshot_symlink_not_followed(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    outside = tmp_path / "outside.txt"
    outside.write_text("outside")
    (raw / "link").symlink_to(outside)
    snap = _snapshot(raw)
    # The symlink itself must be skipped, matching catalog.status()'s raw/ view.
    assert str(raw / "link") not in snap
    assert snap == {}


def test_snapshot_nonexistent_dir(tmp_path):
    assert _snapshot(tmp_path / "does_not_exist") == {}


def test_snapshot_empty_dir(tmp_path):
    raw = tmp_path / "raw"
    raw.mkdir()
    assert _snapshot(raw) == {}


def test_snapshot_nested_files(tmp_path):
    raw = tmp_path / "raw"
    (raw / "sub").mkdir(parents=True)
    (raw / "sub" / "a.md").write_text("a")
    (raw / "b.md").write_text("b")
    snap = _snapshot(raw)
    assert set(snap) == {str(raw / "sub" / "a.md"), str(raw / "b.md")}


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
    for line in lines[:-1]:
        assert line.endswith("\n"), f"Line does not end with newline: {line!r}"


def test_log_rotate_missing_file_noop(tmp_path):
    wl = WatcherLog(tmp_path)
    wl.rotate_if_needed()


def test_log_rotate_exactly_at_boundary_no_rotation(tmp_path):
    wl = WatcherLog(tmp_path)
    log_file = tmp_path / "watcher.log"
    log_file.write_text("".join(f"line {i}\n" for i in range(10000)))
    wl.rotate_if_needed()
    lines = log_file.read_text().splitlines()
    assert len(lines) == 10000


# --- main() unit tests ---

def test_main_missing_llm_wiki_raw_exits_1(tmp_path):
    with patch("sys.argv", ["watcher.py", "start", str(tmp_path)]):
        with pytest.raises(SystemExit) as exc_info:
            main()
    assert exc_info.value.code == 1


def test_main_creates_watcher_dir(tmp_path):
    raw_dir = tmp_path / "llm-wiki" / "raw"
    raw_dir.mkdir(parents=True)
    watcher_dir = tmp_path / "llm-wiki" / ".watcher"
    assert not watcher_dir.exists()

    mock_event = MagicMock()
    mock_event.is_set.return_value = True

    with patch("sys.argv", ["watcher.py", "start", str(tmp_path)]):
        with patch("watcher._stop_event", mock_event):
            main()

    assert watcher_dir.exists()
    assert (watcher_dir / "watcher.pid").exists()


# --- Integration test ---

def test_watcher_process_journals_and_exits_cleanly(tmp_path):
    import subprocess
    import time
    import signal as sig_mod

    project_root = tmp_path
    raw_dir = project_root / "llm-wiki" / "raw"
    raw_dir.mkdir(parents=True)
    (raw_dir / "note.md").write_text("hello")

    watcher_py = Path(__file__).parent.parent / "watcher.py"
    proc = subprocess.Popen(
        ["python3", str(watcher_py), "start", str(project_root)],
        cwd=str(watcher_py.parent),
    )
    time.sleep(2)
    proc.send_signal(sig_mod.SIGTERM)
    proc.wait(timeout=5)

    assert proc.returncode == 0

    watcher_dir = project_root / "llm-wiki" / ".watcher"
    log_file = watcher_dir / "watcher.log"
    pid_file = watcher_dir / "watcher.pid"

    assert pid_file.exists()
    assert log_file.exists()
    log_text = log_file.read_text()
    assert "watcher stopped" in log_text
    assert "appeared" in log_text  # the pre-existing note.md must be journaled
