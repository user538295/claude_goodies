#!/usr/bin/env python3
# universal-session-log: managed
import json
import os
import random
import shlex
import stat
import sys
from pathlib import Path

EVENTS = {
    "cursor": {
        "sessionStart": "session-start",
        "beforeSubmitPrompt": "user-prompt",
        "afterAgentResponse": "assistant-response",
        "subagentStop": "subagent-stop",
        "stop": "stop",
    },
    "codex": {
        "SessionStart": "session-start",
        "UserPromptSubmit": "user-prompt",
        "Stop": "stop",
        "SubagentStop": "subagent-stop",
    },
}


def fail(message):
    print(f"session-log: {message}", file=sys.stderr)
    raise SystemExit(1)


def command(harness, hook, lifecycle):
    return f"python3 {shlex.quote(str(hook))} {harness} {lifecycle}"


def managed_command(value, harness, lifecycle):
    if not isinstance(value, str):
        return False
    try:
        words = shlex.split(value)
    except ValueError:
        return False
    return (
        len(words) == 4
        and words[0] == "python3"
        and words[1].endswith("/skills/session-log/adapters/native/session_log_hook.py")
        and words[2:] == [harness, lifecycle]
    )


def expected_cursor(harness, hook, lifecycle):
    return {"command": command(harness, hook, lifecycle), "timeout": 30}


def expected_codex(harness, hook, lifecycle):
    return {"hooks": [{"type": "command", "command": command(harness, hook, lifecycle)}]}


def is_current(document, harness, hook):
    hooks = document.get("hooks")
    if not isinstance(hooks, dict):
        return False
    for event, lifecycle in EVENTS[harness].items():
        entries = hooks.get(event)
        if not isinstance(entries, list):
            return False
        expected = expected_cursor(harness, hook, lifecycle) if harness == "cursor" else expected_codex(harness, hook, lifecycle)
        if expected not in entries:
            return False
    return True


def update(document, harness, hook):
    hooks = document.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        fail(f"{harness} hooks must be an object")
    if harness == "cursor":
        version = document.get("version", 1)
        if version != 1:
            fail("Cursor hooks version must be 1")
        document["version"] = 1
    for event, lifecycle in EVENTS[harness].items():
        entries = hooks.setdefault(event, [])
        if not isinstance(entries, list):
            fail(f"{harness} hooks.{event} must be an array")
        kept = []
        for entry in entries:
            remove = False
            if harness == "cursor" and isinstance(entry, dict):
                remove = managed_command(entry.get("command"), harness, lifecycle)
            elif harness == "codex" and isinstance(entry, dict) and isinstance(entry.get("hooks"), list):
                items = entry["hooks"]
                remove = len(items) == 1 and isinstance(items[0], dict) and managed_command(
                    items[0].get("command"), harness, lifecycle
                )
            if not remove:
                kept.append(entry)
        expected = expected_cursor(harness, hook, lifecycle) if harness == "cursor" else expected_codex(harness, hook, lifecycle)
        hooks[event] = kept + [expected]
    return document


def safe_parent(path):
    current = Path(path.anchor)
    for part in path.parts[1:-1]:
        current /= part
        if current.is_symlink():
            fail(f"refusing to follow symlinked hooks parent: {current}")
        if current.exists() and not current.is_dir():
            fail(f"refusing non-directory hooks parent: {current}")
        if not current.exists():
            current.mkdir(mode=0o700)


def load(path):
    safe_parent(path)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        fail(f"refusing to update unsafe hooks file: {path}")
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read hooks file: {error}")
    if not isinstance(value, dict):
        fail("hooks root must be an object")
    return value


def atomic_write(path, document):
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    data = (json.dumps(document, indent=2) + "\n").encode()
    for _ in range(20):
        temporary = path.parent / f".{path.name}.{os.getpid()}.{random.randrange(1 << 30):08x}"
        try:
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
            break
        except FileExistsError:
            continue
    else:
        fail("cannot create temporary hooks file")
    try:
        os.fchmod(descriptor, mode)
        os.write(descriptor, data)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = None
        if path.is_symlink() or (path.exists() and not path.is_file()):
            fail(f"refusing to replace unsafe hooks file: {path}")
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if descriptor is not None:
            os.close(descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


if len(sys.argv) != 5 or sys.argv[1] not in ("check", "install") or sys.argv[2] not in EVENTS:
    fail("hooks configurator requires check|install, cursor|codex, config path, and hook path")
mode, harness, config_path, hook_path = sys.argv[1:]
config = Path(config_path)
hook = Path(hook_path)
if not hook.is_file() or hook.is_symlink():
    fail(f"native lifecycle adapter is missing: {hook}")
document = load(config)
if mode == "check":
    raise SystemExit(0 if is_current(document, harness, hook) else 1)
atomic_write(config, update(document, harness, hook))
