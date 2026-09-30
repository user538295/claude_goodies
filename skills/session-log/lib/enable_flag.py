#!/usr/bin/env python3
# universal-session-log: managed
"""Locked create/remove of the session-log enable flag.

Extracted verbatim from bin/session-log so the flock dance and O_NOFOLLOW
walk are auditable and testable in one place. Reads the SESSION_LOG_ENABLE_*
env vars; the action ("on"/"off") comes from SESSION_LOG_ENABLE_ACTION.
"""
import fcntl
import os
import stat
import secrets
import pathsafe

lock_path = os.environ["SESSION_LOG_ENABLE_LOCK"]
flag_path = os.environ["SESSION_LOG_ENABLE_FLAG"]
action = os.environ["SESSION_LOG_ENABLE_ACTION"]
lock_flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
parent, name = os.path.split(flag_path)
lock_parent, lock_name = os.path.split(lock_path)
if lock_parent != parent:
    raise RuntimeError("session-log enable lock is outside the flag directory")
parent_fd = pathsafe.open_directory(parent, create=False)
lock_fd = os.open(lock_name, lock_flags, 0o600, dir_fd=parent_fd)
try:
    lock_stat = os.fstat(lock_fd)
    if (
        not stat.S_ISREG(lock_stat.st_mode)
        or lock_stat.st_nlink != 1
        or lock_stat.st_uid != os.getuid()
    ):
        raise RuntimeError("unsafe session-log enable lock")
    os.fchmod(lock_fd, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    try:
        try:
            current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            current = None
        if current is not None and (
            stat.S_ISLNK(current.st_mode)
            or not stat.S_ISREG(current.st_mode)
            or current.st_nlink != 1
            or current.st_uid != os.getuid()
        ):
            raise RuntimeError("unsafe session-log enable flag")
        if action == "on":
            if current is None:
                descriptor = os.open(
                    name,
                    os.O_WRONLY
                    | os.O_CREAT
                    | os.O_TRUNC
                    | getattr(os, "O_NOFOLLOW", 0),
                    0o600,
                    dir_fd=parent_fd,
                )
                try:
                    os.fchmod(descriptor, 0o600)
                    os.write(descriptor, f"enabled:{secrets.token_hex(16)}\n".encode())
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
            else:
                descriptor = os.open(
                    name,
                    os.O_RDWR | getattr(os, "O_NOFOLLOW", 0),
                    dir_fd=parent_fd,
                )
                try:
                    actual = os.fstat(descriptor)
                    if actual.st_dev != current.st_dev or actual.st_ino != current.st_ino:
                        raise RuntimeError("session-log enable flag changed during update")
                    os.fchmod(descriptor, 0o600)
                finally:
                    os.close(descriptor)
        elif action == "off":
            if current is not None:
                os.unlink(name, dir_fd=parent_fd)
        else:
            raise RuntimeError(f"unknown enable action: {action}")
    finally:
        os.close(parent_fd)
finally:
    fcntl.flock(lock_fd, fcntl.LOCK_UN)
    os.close(lock_fd)
