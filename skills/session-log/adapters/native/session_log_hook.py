#!/usr/bin/env python3
# universal-session-log: managed
import hashlib
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import time
from pathlib import Path

MAX_SESSION_ID_LENGTH = 128
WORKSPACE_NAME_LIMIT = 64
WORKSPACE_DIGEST_LENGTH = 12
SUPPORTED = {"cursor": ".cursor", "codex": ".codex"}
SAFE_ID = re.compile(rf"^[A-Za-z0-9._-]{{1,{MAX_SESSION_ID_LENGTH}}}$")
EVENTS = {
    "cursor": {"session-start", "user-prompt", "assistant-response", "subagent-stop", "stop"},
    "codex": {"session-start", "user-prompt", "subagent-stop", "stop"},
}


def fail(message):
    print(f"session-log: {message}", file=sys.stderr)
    raise SystemExit(1)


def ensure_directory(path):
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if current.is_symlink():
            fail(f"unsafe {HARNESS} path: {current}")
        if current.exists() and not current.is_dir():
            fail(f"non-directory {HARNESS} path: {current}")
        if not current.exists():
            current.mkdir(mode=0o700)
    return path


def safe_regular(path):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        fail(f"unsafe {HARNESS} file: {path}")


def atomic_private_json(path, value):
    ensure_directory(path.parent)
    safe_regular(path)
    temporary = path.parent / f".{path.name}.{os.getpid()}.{secrets.token_hex(6)}.tmp"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(temporary, flags, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def append_private(path, text):
    ensure_directory(path.parent)
    safe_regular(path)
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    try:
        current = os.fstat(descriptor)
        if not stat.S_ISREG(current.st_mode) or current.st_nlink != 1 or current.st_uid != os.getuid():
            fail(f"unsafe {HARNESS} log file: {path}")
        os.fchmod(descriptor, 0o600)
        os.write(descriptor, text.encode("utf-8"))
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def process_start(pid):
    try:
        output = subprocess.check_output(
            ["ps", "-p", str(pid), "-o", "lstart="],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return output.rstrip("\n").lstrip(" ")
    except (OSError, subprocess.SubprocessError):
        return ""


def session_id(payload):
    for key in ("session_id", "conversation_id"):
        value = payload.get(key)
        if isinstance(value, str) and SAFE_ID.fullmatch(value):
            return value
    return None


def workspace(payload):
    value = payload.get("cwd")
    if not isinstance(value, str):
        roots = payload.get("workspace_roots")
        value = roots[0] if isinstance(roots, list) and roots and isinstance(roots[0], str) else "unknown"
    canonical = os.path.realpath(value)
    name = re.sub(r"[^A-Za-z0-9._-]", "-", Path(canonical).name or "root")
    digest = hashlib.sha256(canonical.encode()).hexdigest()[:WORKSPACE_DIGEST_LENGTH]
    return f"{name[:WORKSPACE_NAME_LIMIT] or 'unknown'}-{digest}"


def event_text(payload):
    if EVENT == "user-prompt":
        value = payload.get("prompt")
        return ("prompt", value) if isinstance(value, str) and value else None
    if EVENT in ("assistant-response", "stop"):
        for key in ("text", "last_assistant_message", "response"):
            value = payload.get(key)
            if isinstance(value, str) and value:
                return ("response", value)
    if EVENT == "subagent-stop":
        value = payload.get("summary") or payload.get("last_assistant_message")
        if isinstance(value, str) and value:
            kind = payload.get("subagent_type") or payload.get("agent_type") or "subagent"
            return ("sub-agent finished", f"{kind}: {value}")
    return None


def respond():
    value = {"continue": True} if HARNESS == "cursor" and EVENT == "user-prompt" else {}
    print(json.dumps(value, separators=(",", ":")))


if len(sys.argv) != 3 or sys.argv[1] not in SUPPORTED:
    fail("native hook requires an explicit cursor or codex harness and lifecycle event")
HARNESS, EVENT = sys.argv[1:]
if EVENT not in EVENTS[HARNESS]:
    fail(f"unknown {HARNESS} lifecycle event: {EVENT}")
home = Path(os.path.realpath(os.environ.get("HOME", "")))
root = home / SUPPORTED[HARNESS]
state_dir = root / "session-log"
flag = root / "prompt-logs" / ".enabled"
runtime = state_dir / "runtime.json"
ensure_directory(root)
safe_regular(flag)
safe_regular(runtime)
if not flag.is_file():
    if runtime.exists():
        runtime.unlink()
    respond()
    raise SystemExit(0)
try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, UnicodeDecodeError):
    fail(f"invalid {HARNESS} hook payload")
if not isinstance(payload, dict):
    fail(f"invalid {HARNESS} hook payload")
sid = session_id(payload)
if sid is None:
    respond()
    raise SystemExit(0)
package_root = Path(__file__).resolve().parents[2]
version = (package_root / "VERSION").read_text(encoding="utf-8").strip()
pid = os.getppid()
atomic_private_json(runtime, {
    "harness": HARNESS,
    "version": version,
    "session_id": sid,
    "nonce": secrets.token_hex(16),
    "loaded_at": int(time.time()),
    "pid": pid,
    "process_start": process_start(pid),
})
content = event_text(payload)
if content:
    label, text = content
    log = root / "prompt-logs" / workspace(payload) / f"session_{sid}.md"
    append_private(log, f"\n### {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {label}\n\n{text}\n")
respond()
