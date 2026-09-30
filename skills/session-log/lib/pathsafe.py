#!/usr/bin/env python3
# universal-session-log: managed
"""Safe filesystem primitives shared by the session-log bash entrypoints.

Every directory walk goes through :func:`open_directory`, which opens each path
component with ``O_NOFOLLOW`` so a symlink can never be traversed, and creates
missing components privately (mode 0o700) in a race-safe way. This module owns
the generic copy/link/write/remove primitives. The specialized locked writers
(``claude_settings.py``, ``enable_flag.py``, ``locking.py``) keep their own
minimal O_NOFOLLOW walkers because their traversals raise domain-specific errors
and hold flock/mkdir locks; each is small and audited in its own module.
"""
import os
import random
import stat
import sys

DIR_FLAGS = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
FILE_FLAGS = os.O_RDONLY | NOFOLLOW
PRIVATE_DIR_MODE = 0o700
PRIVATE_FILE_MODE = 0o600
MAX_TEMP_FILE_ATTEMPTS = 20


def open_directory(path, *, create):
    """Return an fd for ``path`` while refusing every symlinked component.

    When ``create`` is true, missing components are created 0o700 race-safely;
    otherwise a missing component raises ``FileNotFoundError``.
    """
    fd = os.open(os.sep, DIR_FLAGS)
    try:
        for part in path.split(os.sep):
            if not part or part == ".":
                continue
            if part == "..":
                raise SystemExit(f"refusing parent traversal: {path}")
            try:
                nxt = os.open(part, DIR_FLAGS, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    raise
                try:
                    os.mkdir(part, PRIVATE_DIR_MODE, dir_fd=fd)
                except FileExistsError:
                    pass
                nxt = os.open(part, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = nxt
        return fd
    except BaseException:
        os.close(fd)
        raise


def ensure_directory(directory):
    fd = open_directory(directory, create=True)
    try:
        info = os.fstat(fd)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise SystemExit(f"refusing unsafe private directory: {directory}")
        os.fchmod(fd, PRIVATE_DIR_MODE)
    finally:
        os.close(fd)


def write_file(path, content):
    directory, name = os.path.split(path)
    parent_fd = open_directory(directory, create=True)
    temporary = None
    try:
        os.fchmod(parent_fd, PRIVATE_DIR_MODE)
        try:
            existing = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            existing = None
        if existing is not None and (stat.S_ISLNK(existing.st_mode) or not stat.S_ISREG(existing.st_mode)):
            raise SystemExit(f"refusing to overwrite unsafe private file: {path}")
        for _ in range(MAX_TEMP_FILE_ATTEMPTS):
            candidate = f".session-log.{os.getpid()}.{random.randrange(1 << 30):08x}"
            try:
                descriptor = os.open(
                    candidate,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW,
                    PRIVATE_FILE_MODE,
                    dir_fd=parent_fd,
                )
                temporary = candidate
                break
            except FileExistsError:
                continue
        else:
            raise SystemExit(f"cannot create temporary file in: {directory}")
        try:
            data = (content + "\n").encode()
            offset = 0
            while offset < len(data):
                offset += os.write(descriptor, data[offset:])
            os.fchmod(descriptor, PRIVATE_FILE_MODE)
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        os.replace(temporary, name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        temporary = None
        os.fsync(parent_fd)
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary, dir_fd=parent_fd)
            except OSError:
                pass
        os.close(parent_fd)


def remove_path(target):
    directory, name = os.path.split(os.path.abspath(target))
    try:
        parent_fd = open_directory(directory, create=False)
    except FileNotFoundError:
        return
    try:
        try:
            current = os.lstat(name, dir_fd=parent_fd)
        except FileNotFoundError:
            return
        if stat.S_ISDIR(current.st_mode) and not stat.S_ISLNK(current.st_mode):
            os.rmdir(name, dir_fd=parent_fd)
        else:
            os.unlink(name, dir_fd=parent_fd)
    finally:
        os.close(parent_fd)


def _read_all(fd):
    chunks = []
    while True:
        chunk = os.read(fd, 1024 * 1024)
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)


def _classify(dir_fd, name, target):
    try:
        item = os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(item.st_mode):
        return ("link", os.readlink(name, dir_fd=dir_fd))
    if not stat.S_ISREG(item.st_mode):
        raise SystemExit(f"refusing to overwrite non-file adapter target: {target}")
    descriptor = os.open(name, FILE_FLAGS, dir_fd=dir_fd)
    try:
        return ("file", _read_all(descriptor))
    finally:
        os.close(descriptor)


def link_adapter(source, target, store):
    """Atomically point ``target`` at ``source`` via a symlink, refusing to
    clobber anything this package does not already own."""
    directory, name = os.path.split(target)
    source_directory, source_name = os.path.split(source)
    source_dir_fd = open_directory(source_directory, create=True)
    target_dir_fd = open_directory(directory, create=True)
    source_fd = None
    temporary_name = None
    backup_name = None
    backup_active = False
    try:
        source_fd = os.open(source_name, FILE_FLAGS, dir_fd=source_dir_fd)
        source_stat = os.fstat(source_fd)
        if not stat.S_ISREG(source_stat.st_mode) or source_stat.st_nlink != 1:
            raise SystemExit(f"adapter asset is not a safe regular file: {source}")
        source_data = _read_all(source_fd)
        initial = _classify(target_dir_fd, name, target)
        if initial is not None and initial[0] == "link":
            existing = initial[1]
            if existing == source:
                raise SystemExit(0)
            if not existing.startswith(f"{store}/releases/"):
                raise SystemExit(f"refusing to overwrite unowned adapter link: {target}")
        elif initial is not None:
            if initial[1] != source_data:
                raise SystemExit(f"refusing to overwrite unowned adapter file: {target}")
        for _ in range(MAX_TEMP_FILE_ATTEMPTS):
            candidate = f".session-log.{os.getpid()}.{random.randrange(1 << 30):08x}"
            try:
                os.symlink(source, candidate, dir_fd=target_dir_fd)
                temporary_name = candidate
                break
            except FileExistsError:
                continue
        else:
            raise SystemExit(f"cannot create temporary link in: {directory}")
        current = _classify(target_dir_fd, name, target)
        if current != initial:
            raise SystemExit(f"adapter target changed during update: {target}")
        if initial is None:
            os.unlink(temporary_name, dir_fd=target_dir_fd)
            temporary_name = None
            try:
                os.symlink(source, name, dir_fd=target_dir_fd)
            except FileExistsError:
                raise SystemExit(f"adapter target changed during update: {target}")
        else:
            for attempt in range(MAX_TEMP_FILE_ATTEMPTS):
                candidate = f".session-log-backup.{os.getpid()}.{random.randrange(1 << 30):08x}.{attempt}"
                try:
                    os.rename(name, candidate, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                    backup_name = candidate
                    backup_active = True
                    break
                except FileExistsError:
                    continue
            if not backup_active:
                raise SystemExit(f"cannot stage adapter target: {target}")
            if _classify(target_dir_fd, backup_name, target) != initial:
                os.rename(backup_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                backup_active = False
                raise SystemExit(f"adapter target changed during update: {target}")
            os.unlink(temporary_name, dir_fd=target_dir_fd)
            temporary_name = None
            try:
                os.symlink(source, name, dir_fd=target_dir_fd)
            except FileExistsError:
                conflict = f"{backup_name}.conflict"
                os.rename(name, conflict, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                os.rename(backup_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                backup_active = False
                raise SystemExit(f"adapter target changed during update: {target}")
            os.unlink(backup_name, dir_fd=target_dir_fd)
            backup_active = False
        os.fsync(target_dir_fd)
    finally:
        if source_fd is not None:
            os.close(source_fd)
        if temporary_name is not None:
            try:
                os.unlink(temporary_name, dir_fd=target_dir_fd)
            except OSError:
                pass
        if backup_active:
            try:
                os.stat(name, dir_fd=target_dir_fd, follow_symlinks=False)
            except FileNotFoundError:
                try:
                    os.rename(backup_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                except OSError:
                    pass
        os.close(source_dir_fd)
        os.close(target_dir_fd)


def rename_to_conflict(dir_fd, src_name, prefix, exhaust_message):
    for attempt in range(MAX_TEMP_FILE_ATTEMPTS):
        conflict = f"{prefix}.conflict.{attempt}"
        try:
            os.rename(src_name, conflict, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
            return conflict
        except FileExistsError:
            continue
    raise SystemExit(exhaust_message)


def copy_file(source, target, preserve_mode, manifest_owned):
    """Atomically copy ``source`` onto ``target``, refusing to clobber an
    unowned file and restoring the original on any mid-flight change."""
    directory, name = os.path.split(target)
    source_directory = os.path.realpath(os.path.dirname(source))
    source_name = os.path.basename(source)
    source_dir_fd = open_directory(source_directory, create=True)
    target_dir_fd = open_directory(directory, create=True)
    source_fd = None
    target_fd = None
    target_data = None
    temporary_name = None
    backup_name = None
    backup_active = False
    try:
        source_fd = os.open(source_name, FILE_FLAGS, dir_fd=source_dir_fd)
        source_stat = os.fstat(source_fd)
        if not stat.S_ISREG(source_stat.st_mode) or source_stat.st_nlink != 1:
            raise SystemExit(f"package source is not a safe regular file: {source}")
        source_data = _read_all(source_fd)
        try:
            target_stat = os.stat(name, dir_fd=target_dir_fd, follow_symlinks=False)
        except FileNotFoundError:
            target_stat = None
        if target_stat is not None:
            if stat.S_ISLNK(target_stat.st_mode):
                raise SystemExit(f"refusing to overwrite symlink: {target}")
            if not stat.S_ISREG(target_stat.st_mode):
                raise SystemExit(f"refusing to overwrite non-file: {target}")
            target_fd = os.open(name, FILE_FLAGS, dir_fd=target_dir_fd)
            target_data = _read_all(target_fd)
            if not manifest_owned and target_data != source_data:
                raise SystemExit(f"refusing to overwrite unowned file: {target}")
        for _ in range(MAX_TEMP_FILE_ATTEMPTS):
            candidate = f".session-log.{os.getpid()}.{random.randrange(1 << 30):08x}"
            try:
                temporary_fd = os.open(
                    candidate,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW,
                    PRIVATE_FILE_MODE,
                    dir_fd=target_dir_fd,
                )
                temporary_name = candidate
                break
            except FileExistsError:
                continue
        else:
            raise SystemExit(f"cannot create temporary copy in: {directory}")
        try:
            offset = 0
            while offset < len(source_data):
                offset += os.write(temporary_fd, source_data[offset:])
            os.fchmod(temporary_fd, stat.S_IMODE(source_stat.st_mode) if preserve_mode else PRIVATE_FILE_MODE)
            os.fsync(temporary_fd)
        finally:
            os.close(temporary_fd)
        if target_stat is None:
            try:
                os.link(temporary_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd, follow_symlinks=False)
            except FileExistsError:
                raise SystemExit(f"package target appeared during copy: {target}")
            os.unlink(temporary_name, dir_fd=target_dir_fd)
            temporary_name = None
        else:
            for attempt in range(MAX_TEMP_FILE_ATTEMPTS):
                candidate = f".session-log-backup.{os.getpid()}.{random.randrange(1 << 30):08x}.{attempt}"
                try:
                    os.rename(name, candidate, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                    backup_name = candidate
                    backup_active = True
                    break
                except FileExistsError:
                    continue
            if not backup_active:
                raise SystemExit(f"cannot stage package target: {target}")
            backup_stat = os.stat(backup_name, dir_fd=target_dir_fd, follow_symlinks=False)
            if (
                stat.S_ISLNK(backup_stat.st_mode)
                or not stat.S_ISREG(backup_stat.st_mode)
                or backup_stat.st_dev != target_stat.st_dev
                or backup_stat.st_ino != target_stat.st_ino
            ):
                os.rename(backup_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                backup_active = False
                raise SystemExit(f"package target changed during copy: {target}")
            os.lseek(target_fd, 0, os.SEEK_SET)
            if _read_all(target_fd) != target_data:
                os.rename(backup_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                backup_active = False
                raise SystemExit(f"package target changed during copy: {target}")
            try:
                os.link(temporary_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd, follow_symlinks=False)
            except FileExistsError:
                message = f"package target changed during copy: {target}"
                rename_to_conflict(target_dir_fd, name, backup_name, message)
                raise SystemExit(message)
            os.unlink(temporary_name, dir_fd=target_dir_fd)
            temporary_name = None
            os.lseek(target_fd, 0, os.SEEK_SET)
            if _read_all(target_fd) != target_data:
                message = f"package target changed during copy: {target}"
                rename_to_conflict(target_dir_fd, backup_name, backup_name, message)
                backup_active = False
                raise SystemExit(message)
            os.unlink(backup_name, dir_fd=target_dir_fd)
            backup_active = False
        os.fsync(target_dir_fd)
    finally:
        if target_fd is not None:
            os.close(target_fd)
        if source_fd is not None:
            os.close(source_fd)
        if temporary_name is not None:
            try:
                os.unlink(temporary_name, dir_fd=target_dir_fd)
            except OSError:
                pass
        if backup_active:
            try:
                os.stat(name, dir_fd=target_dir_fd, follow_symlinks=False)
            except FileNotFoundError:
                try:
                    os.rename(backup_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                except OSError:
                    pass
        os.close(source_dir_fd)
        os.close(target_dir_fd)


def main(argv):
    if not argv:
        raise SystemExit("pathsafe: missing operation")
    operation = argv[0]
    if operation == "ensure-dir":
        ensure_directory(os.environ["SESSION_LOG_DIRECTORY"])
    elif operation == "write-file":
        write_file(os.environ["SESSION_LOG_FILE"], os.environ["SESSION_LOG_CONTENT"])
    elif operation == "remove":
        remove_path(os.environ["SESSION_LOG_REMOVE_PATH"])
    elif operation == "link-adapter":
        link_adapter(
            os.environ["SESSION_LOG_SOURCE"],
            os.environ["SESSION_LOG_TARGET"],
            os.environ["SESSION_LOG_STORE"],
        )
    elif operation == "copy-file":
        copy_file(
            os.environ["SESSION_LOG_SOURCE"],
            os.environ["SESSION_LOG_TARGET"],
            os.environ["SESSION_LOG_PRESERVE_MODE"] == "1",
            os.environ["SESSION_LOG_MANIFEST_OWNED"] == "1",
        )
    else:
        raise SystemExit(f"pathsafe: unknown operation: {operation}")


if __name__ == "__main__":
    main(sys.argv[1:])
