#!/usr/bin/env python3
# universal-session-log: managed
"""Claude settings.json hook management (install + legacy migration).

Extracted verbatim from bin/session-log (``install``) and install.sh
(``migrate``) so the flock + JSON-merge + atomic-replace dances live in one
auditable, testable module instead of two large shell here-documents.

Usage:
    python3 claude_settings.py install   # SETTINGS_PATH, HOOK_PATH, SESSION_LOG_OWNER_MARKER
    python3 claude_settings.py migrate   # SETTINGS_PATH, CLAUDE_SCRIPTS_DIR
"""
import fcntl
import json
import os
import random
import shlex
import stat
import sys

import pathsafe

NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
FILE_FLAGS = os.O_RDONLY | NOFOLLOW
BACKUP_ATTEMPTS = 20
TEMP_ATTEMPTS = 100

EVENTS = {
    "SessionStart": ("startup|resume", "session-start"),
    "UserPromptSubmit": (None, "user-prompt"),
    "Stop": (None, "stop"),
    "SubagentStop": (None, "subagent-stop"),
}

LEGACY_NAMES = {
    "prompt_log_save.sh",
    "prompt_log_new_session.sh",
    "prompt_log_stop.sh",
    "prompt_log_subagent.sh",
    "prompt_log_lib.sh",
    "prompt_log_usage.sh",
    "prompt_log_usage.jq",
    "prompt_log_prices.json",
}


def _read_all(fd):
    chunks = []
    while True:
        chunk = os.read(fd, 1024 * 1024)
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)


def _read_fd(fd):
    os.lseek(fd, 0, os.SEEK_SET)
    return _read_all(fd)


def _read_named(parent_fd, name):
    descriptor = os.open(name, FILE_FLAGS, dir_fd=parent_fd)
    try:
        info = os.fstat(descriptor)
        os.lseek(descriptor, 0, os.SEEK_SET)
        return info, _read_all(descriptor)
    finally:
        os.close(descriptor)


def _key5(value):
    return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def _key4(value):
    return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns)


def _signature(value):
    return (
        value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns,
        value.st_mode, value.st_nlink, value.st_uid, value.st_gid,
    )


def _identity_after_rename(value):
    return (
        value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns,
        value.st_mode, value.st_nlink, value.st_uid, value.st_gid,
    )


def _create_temp(parent_fd, mode, candidates, exhaust_message):
    for candidate in candidates:
        try:
            fd = os.open(
                candidate,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW,
                mode,
                dir_fd=parent_fd,
            )
            return candidate, fd
        except FileExistsError:
            continue
    raise SystemExit(exhaust_message)


def _stage_backup(parent_fd, settings_name, candidates, exhaust_message):
    for candidate in candidates:
        try:
            os.rename(settings_name, candidate, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            return candidate
        except FileExistsError:
            continue
    raise SystemExit(exhaust_message)


def _restore_after_conflict(parent_fd, settings_name, backup_name, message):
    pathsafe.rename_to_conflict(parent_fd, settings_name, backup_name, message)
    os.rename(backup_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)


def _filter_managed_hooks(entries, expected_command):
    filtered = []
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
            filtered.append(entry)
            continue
        kept_hooks = []
        removed_owned = False
        for item in entry["hooks"]:
            command = item.get("command", "") if isinstance(item, dict) else ""
            if (
                isinstance(item, dict)
                and item.get("type") == "command"
                and command == expected_command
            ):
                removed_owned = True
            else:
                kept_hooks.append(item)
        if removed_owned and kept_hooks:
            replacement = dict(entry)
            replacement["hooks"] = kept_hooks
            filtered.append(replacement)
        elif not removed_owned:
            filtered.append(entry)
    return filtered


def _load_install_settings(parent_fd, settings_name):
    original_stat = None
    original_settings = None
    try:
        descriptor = os.open(settings_name, FILE_FLAGS, dir_fd=parent_fd)
        try:
            original_stat = os.fstat(descriptor)
            original_settings = _read_all(descriptor)
        finally:
            os.close(descriptor)
        document = json.loads(original_settings.decode("utf-8"))
    except FileNotFoundError:
        document = {}
    except (json.JSONDecodeError, OSError) as error:
        raise SystemExit(f"cannot update Claude settings: {error}")
    if not isinstance(document, dict):
        raise SystemExit("cannot update Claude settings: root must be an object")
    return document, original_stat, original_settings


def _inject_managed_hooks(document, hook_path, owner):
    hooks = document.get("hooks")
    if hooks is None:
        hooks = {}
    elif not isinstance(hooks, dict):
        raise SystemExit("cannot update Claude settings: hooks must be an object")
    document["hooks"] = hooks
    for event, (matcher, name) in EVENTS.items():
        entries = hooks.setdefault(event, [])
        if not isinstance(entries, list):
            raise SystemExit(f"cannot update Claude settings: hooks.{event} must be an array")
        command = f"SESSION_LOG_OWNER={shlex.quote(owner)} bash {shlex.quote(hook_path)} {name}"
        filtered = _filter_managed_hooks(entries, command)
        entry = {"hooks": [{"type": "command", "command": command}]}
        if matcher is not None:
            entry["matcher"] = matcher
        filtered.append(entry)
        hooks[event] = filtered


def _assert_install_unchanged(parent_fd, settings_name, original_stat, original_settings):
    try:
        descriptor = os.open(settings_name, FILE_FLAGS, dir_fd=parent_fd)
    except FileNotFoundError:
        if original_stat is None:
            return
        raise SystemExit("Claude settings changed during update; retry installation")
    try:
        current_stat = os.fstat(descriptor)
        current_settings = _read_all(descriptor)
    finally:
        os.close(descriptor)
    if (
        original_stat is None
        or _signature(current_stat) != _signature(original_stat)
        or current_settings != original_settings
    ):
        raise SystemExit("Claude settings changed during update; retry installation")


CHANGED_UPDATE = "Claude settings changed during update; retry installation"
CHANGED_MIGRATE = "Claude settings changed during migration; retry installation"


def _write_install_settings(parent_fd, settings_name, document, original_stat, original_settings):
    mode = stat.S_IMODE(original_stat.st_mode) if original_stat is not None else 0o600
    _assert_install_unchanged(parent_fd, settings_name, original_stat, original_settings)
    temp_candidates = (f".session-log.{os.getpid()}.{random.randrange(1 << 30):08x}" for _ in range(20))
    temporary_name, temporary_fd = _create_temp(
        parent_fd, 0o600, temp_candidates, "cannot create temporary Claude settings file"
    )
    os.fchmod(temporary_fd, mode & 0o777)
    backup_name = None
    backup_active = False
    try:
        with os.fdopen(temporary_fd, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        _assert_install_unchanged(parent_fd, settings_name, original_stat, original_settings)
        if original_stat is None:
            try:
                os.link(temporary_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd, follow_symlinks=False)
            except FileExistsError:
                raise SystemExit(CHANGED_UPDATE)
            os.unlink(temporary_name, dir_fd=parent_fd)
            temporary_name = None
        else:
            backups = (f".session-log-backup.{os.getpid()}.{random.randrange(1 << 30):08x}.{attempt}" for attempt in range(20))
            backup_name = _stage_backup(parent_fd, settings_name, backups, "cannot stage Claude settings update")
            backup_active = True
            backup_stat, backup_settings = _read_named(parent_fd, backup_name)
            if _identity_after_rename(backup_stat) != _identity_after_rename(original_stat) or backup_settings != original_settings:
                os.rename(backup_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                backup_active = False
                raise SystemExit(CHANGED_UPDATE)
            try:
                os.link(temporary_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd, follow_symlinks=False)
            except FileExistsError:
                _restore_after_conflict(parent_fd, settings_name, backup_name, CHANGED_UPDATE)
                backup_active = False
                raise SystemExit(CHANGED_UPDATE)
            os.unlink(temporary_name, dir_fd=parent_fd)
            temporary_name = None
            os.unlink(backup_name, dir_fd=parent_fd)
            backup_active = False
        os.fsync(parent_fd)
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name, dir_fd=parent_fd)
            except OSError:
                pass
        if backup_active:
            try:
                os.stat(settings_name, dir_fd=parent_fd, follow_symlinks=False)
            except FileNotFoundError:
                try:
                    os.rename(backup_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                except OSError:
                    pass


def install():
    settings_path = os.environ["SETTINGS_PATH"]
    hook_path = os.environ["HOOK_PATH"]
    owner = os.environ["SESSION_LOG_OWNER_MARKER"]
    directory, settings_name = os.path.split(settings_path)
    parent_fd = pathsafe.open_directory(directory, create=True)
    lock_fd = os.open(settings_name + ".session-log.lock", os.O_RDWR | os.O_CREAT | NOFOLLOW, 0o600, dir_fd=parent_fd)
    os.fchmod(lock_fd, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    try:
        document, original_stat, original_settings = _load_install_settings(parent_fd, settings_name)
        _inject_managed_hooks(document, hook_path, owner)
        _write_install_settings(parent_fd, settings_name, document, original_stat, original_settings)
    finally:
        os.close(lock_fd)
        os.close(parent_fd)


def _normalized_legacy_path(token, legacy_scripts_dir):
    raw_home_scripts = os.path.join(os.environ["HOME"], ".claude", "scripts")
    prefixes = (
        legacy_scripts_dir,
        raw_home_scripts,
        "$HOME/.claude/scripts",
        "${HOME}/.claude/scripts",
        "~/.claude/scripts",
    )
    for prefix in prefixes:
        if token.startswith(prefix + "/"):
            name = token[len(prefix) + 1:]
            if name in LEGACY_NAMES:
                return os.path.join(legacy_scripts_dir, name)
    return token


def _is_managed_legacy_command(command, legacy_scripts_dir, legacy_paths):
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    if len(tokens) != 2 or tokens[0] not in {"bash", "/bin/bash"}:
        return False
    return _normalized_legacy_path(tokens[1], legacy_scripts_dir) in legacy_paths


def _strip_legacy_hooks(document, legacy_scripts_dir):
    legacy_paths = {os.path.join(legacy_scripts_dir, name) for name in LEGACY_NAMES}
    hooks = document.get("hooks")
    changed = False
    if not isinstance(hooks, dict):
        return changed
    for event, entries in list(hooks.items()):
        kept = []
        event_changed = False
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
                kept.append(entry)
                continue
            filtered = []
            entry_changed = False
            for item in entry["hooks"]:
                command = item.get("command", "") if isinstance(item, dict) else ""
                if (
                    isinstance(item, dict)
                    and item.get("type") == "command"
                    and isinstance(command, str)
                    and _is_managed_legacy_command(command, legacy_scripts_dir, legacy_paths)
                ):
                    entry_changed = True
                    continue
                filtered.append(item)
            if entry_changed:
                changed = True
                event_changed = True
                if filtered:
                    replacement = dict(entry)
                    replacement["hooks"] = filtered
                    kept.append(replacement)
            else:
                kept.append(entry)
        if event_changed:
            if kept:
                hooks[event] = kept
            else:
                del hooks[event]
    if changed and not hooks:
        document.pop("hooks", None)
    return changed


def _reverify_unchanged_early(parent_fd, settings_name, settings_fd, before_stat, original_settings):
    current_stat = os.fstat(settings_fd)
    current_path_stat = os.stat(settings_name, dir_fd=parent_fd, follow_symlinks=False)
    before = _key5(before_stat)
    if _key5(current_stat) != before or _key5(current_path_stat) != before:
        raise SystemExit(CHANGED_MIGRATE)
    if _read_fd(settings_fd) != original_settings:
        raise SystemExit(CHANGED_MIGRATE)


def _write_migrate_settings(parent_fd, settings_name, settings_fd, document, before_stat, original_settings):
    mode = stat.S_IMODE(before_stat.st_mode)
    temporary = None
    backup_name = None
    backup_active = False
    try:
        temp_candidates = (f".session-log-migrate.{os.getpid()}.{attempt}" for attempt in range(TEMP_ATTEMPTS))
        temporary, temporary_fd = _create_temp(
            parent_fd, mode & 0o777, temp_candidates, "cannot allocate temporary Claude settings file"
        )
        os.fchmod(temporary_fd, mode & 0o777)
        with os.fdopen(temporary_fd, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        final_stat = os.fstat(settings_fd)
        final_path_stat = os.stat(settings_name, dir_fd=parent_fd, follow_symlinks=False)
        final_settings = _read_fd(settings_fd)
        if (
            _key5(final_stat) != _key5(before_stat)
            or _key5(final_path_stat) != _key5(before_stat)
            or final_settings != original_settings
        ):
            raise SystemExit(CHANGED_MIGRATE)
        backups = (f".session-log-backup.{os.getpid()}.{attempt}" for attempt in range(BACKUP_ATTEMPTS))
        backup_name = _stage_backup(parent_fd, settings_name, backups, "cannot stage Claude settings migration")
        backup_active = True
        backup_stat, backup_settings = _read_named(parent_fd, backup_name)
        if _key4(backup_stat) != _key4(before_stat) or backup_settings != original_settings:
            os.rename(backup_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            backup_active = False
            raise SystemExit(CHANGED_MIGRATE)
        try:
            os.link(temporary, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd, follow_symlinks=False)
        except FileExistsError:
            _restore_after_conflict(parent_fd, settings_name, backup_name, CHANGED_MIGRATE)
            backup_active = False
            raise SystemExit(CHANGED_MIGRATE)
        os.unlink(temporary, dir_fd=parent_fd)
        temporary = None
        backup_stat, backup_settings = _read_named(parent_fd, backup_name)
        if _key4(backup_stat) != _key4(before_stat) or backup_settings != original_settings:
            pathsafe.rename_to_conflict(parent_fd, backup_name, backup_name, CHANGED_MIGRATE)
            backup_active = False
            raise SystemExit(CHANGED_MIGRATE)
        os.unlink(backup_name, dir_fd=parent_fd)
        backup_active = False
        os.fsync(parent_fd)
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
        if backup_active:
            try:
                os.stat(settings_name, dir_fd=parent_fd, follow_symlinks=False)
            except FileNotFoundError:
                try:
                    os.rename(backup_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                except OSError:
                    pass


def migrate():
    settings_path = os.environ["SETTINGS_PATH"]
    legacy_scripts_dir = os.environ["CLAUDE_SCRIPTS_DIR"]
    directory, settings_name = os.path.split(settings_path)
    parent_fd = pathsafe.open_directory(directory, create=False)
    lock_fd = os.open(settings_name + ".session-log.lock", os.O_RDWR | os.O_CREAT | NOFOLLOW, 0o600, dir_fd=parent_fd)
    os.fchmod(lock_fd, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    settings_fd = os.open(settings_name, FILE_FLAGS, dir_fd=parent_fd)
    try:
        before_stat = os.fstat(settings_fd)
        if not stat.S_ISREG(before_stat.st_mode):
            raise SystemExit("Claude settings is not a regular file")
        original_settings = _read_fd(settings_fd)
        try:
            document = json.loads(original_settings.decode("utf-8"))
        except json.JSONDecodeError as error:
            raise SystemExit(f"cannot update Claude settings: {error}")
        if not _strip_legacy_hooks(document, legacy_scripts_dir):
            raise SystemExit(0)
        _reverify_unchanged_early(parent_fd, settings_name, settings_fd, before_stat, original_settings)
        _write_migrate_settings(parent_fd, settings_name, settings_fd, document, before_stat, original_settings)
    finally:
        os.close(settings_fd)
        os.close(parent_fd)
        os.close(lock_fd)


def main(argv):
    if not argv:
        raise SystemExit("claude_settings: missing operation")
    operation = argv[0]
    if operation == "install":
        install()
    elif operation == "migrate":
        migrate()
    else:
        raise SystemExit(f"claude_settings: unknown operation: {operation}")


if __name__ == "__main__":
    main(sys.argv[1:])
