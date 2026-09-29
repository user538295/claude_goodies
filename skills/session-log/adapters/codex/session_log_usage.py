#!/usr/bin/env python3
# universal-session-log: managed
import json
import os
import re
import sys
from pathlib import Path

def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def rollout_files(root):
    return [path for path in root.glob("**/*.jsonl") if path.is_file() and not path.is_symlink()]


def session_metadata(path):
    try:
        with path.open(encoding="utf-8") as handle:
            for index, line in enumerate(handle):
                if index >= 64:
                    break
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if not isinstance(record, dict) or record.get("type") != "session_meta":
                    continue
                value = record.get("payload")
                if not isinstance(value, dict):
                    value = record.get("data")
                return value if isinstance(value, dict) else {}
    except OSError:
        return {}
    return {}


def same_directory(left, right):
    return os.path.realpath(left) == os.path.realpath(right)


def latest_rollout(root):
    files = []
    for path in rollout_files(root):
        cwd = session_metadata(path).get("cwd")
        if isinstance(cwd, str) and same_directory(cwd, os.getcwd()):
            files.append(path)
    return max(files, key=lambda path: path.stat().st_mtime) if files else None


def rollout_for_session(root, session_id):
    if not re.fullmatch(r"[A-Za-z0-9._-]+", session_id):
        fail(f"invalid Codex session id: {session_id}")
    files = [
        path
        for path in rollout_files(root)
        if session_metadata(path).get("id") == session_id
        or path.stem == session_id
        or path.stem.endswith(f"-{session_id}")
    ]
    return max(files, key=lambda path: path.stat().st_mtime) if files else None


def usage_data(record):
    if record.get("type") != "token_usage_record":
        return None
    value = record.get("data")
    if not isinstance(value, dict):
        value = record.get("payload")
    if isinstance(value, dict) and isinstance(value.get("usage"), dict):
        value = value["usage"]
    return value if isinstance(value, dict) else None


def integer(value):
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else 0


args = sys.argv[1:] or ["--latest"]
if len(args) != 1:
    fail("usage accepts exactly one rollout target")
sessions_root = Path.home() / ".codex" / "sessions"
target = args[0]
if target == "--latest":
    transcript = latest_rollout(sessions_root)
    if transcript is None:
        fail("no Codex rollout transcript found for the current project")
else:
    candidate = Path(target).expanduser()
    if candidate.is_file() and not candidate.is_symlink():
        transcript = candidate
    elif "/" in target or target.endswith(".jsonl"):
        fail(f"Codex rollout transcript does not exist: {candidate}")
    else:
        transcript = rollout_for_session(sessions_root, target)
        if transcript is None:
            fail(f"Codex session does not exist: {target}")
totals = {
    "input_tokens": 0,
    "cached_input_tokens": 0,
    "output_tokens": 0,
    "reasoning_output_tokens": 0,
    "total_tokens": 0,
}
records = 0
try:
    with transcript.open(encoding="utf-8") as handle:
        for line in handle:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(record, dict):
                continue
            data = usage_data(record)
            if data is None:
                continue
            records += 1
            for key in ("input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens"):
                totals[key] += integer(data.get(key))
            native_total = data.get("total_tokens")
            if isinstance(native_total, int) and not isinstance(native_total, bool) and native_total >= 0:
                totals["total_tokens"] += native_total
            else:
                totals["total_tokens"] += integer(data.get("input_tokens")) + integer(data.get("output_tokens"))
except OSError as error:
    fail(f"cannot read Codex rollout transcript: {error}")
if not records:
    fail("Codex rollout contains no token_usage_record data")
print(f"session: {transcript}")
print("TOTAL")
for key, value in totals.items():
    print(f"{key}: {value}")
