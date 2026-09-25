#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SOURCE_ROOT="$PACKAGE_ROOT"
readonly VERSION="$(tr -d '[:space:]' < "$SOURCE_ROOT/VERSION")"
readonly HOME_ROOT="$(cd "${HOME:?HOME is required}" && pwd -P)"
readonly STORE="$HOME_ROOT/.local/share/universal-session-log"
readonly OWNERSHIP_MARKER="universal-session-log: managed"
readonly PACKAGE_MANIFEST=".universal-session-log.manifest"
readonly INSTALL_LOCK="$STORE/.install.lock"
INSTALL_LOCK_OWNER_START=""
INSTALL_STORE_CREATED=0

has_exact_ownership_marker() {
  local file="$1"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  awk -v marker="$OWNERSHIP_MARKER" '
    function is_marker(line) {
      return line == marker ||
        line == "# " marker ||
        line == "// " marker ||
        line == "<!-- " marker " -->"
    }
    NR == 1 {
      first = $0
      if (is_marker($0)) found = 1
      if ($0 == "---") in_frontmatter = 1
      next
    }
    NR == 2 && first ~ /^#!/ && is_marker($0) { found = 1 }
    in_frontmatter {
      if ($0 == "---") {
        in_frontmatter = 0
        marker_after_frontmatter = 1
      }
      next
    }
    marker_after_frontmatter {
      if (is_marker($0)) found = 1
      marker_after_frontmatter = 0
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

HARNESS_SELECTION=""
INSTALL_MODE=0
LOCAL_ARGUMENTS=""
LOCAL_ARGUMENTS_SET=0

fail() {
  printf 'universal-session-log: %s\n' "$1" >&2
  exit 1
}
canonical_path() {
  local path="$1" resolved
  if [[ -d "$path" ]]; then
    resolved="$(cd "$path" 2>/dev/null && pwd -P)" || return 1
    printf '%s\n' "$resolved"
  else
    printf '%s\n' "$path"
  fi
}

paths_equivalent() {
  local left right
  left="$(canonical_path "$1")" || return 1
  right="$(canonical_path "$2")" || return 1
  [[ "$left" == "$right" ]]
}


selected_harness() {
  [[ "$HARNESS_SELECTION" == all || "$HARNESS_SELECTION" == "$1" ]]
}

parse_args() {
  local arg
  while (($#)); do
    arg="$1"
    case "$arg" in
      --install)
        INSTALL_MODE=1
        shift
        ;;
      --harness)
        (($# >= 2)) || fail "--harness requires a value"
        [[ -z "$HARNESS_SELECTION" ]] || fail "only one --harness value is allowed"
        HARNESS_SELECTION="$2"
        shift 2
        ;;
      --harness=*)
        [[ -z "$HARNESS_SELECTION" ]] || fail "only one --harness value is allowed"
        HARNESS_SELECTION="${arg#*=}"
        shift
        ;;
      --arguments)
        (($# >= 2)) || fail "--arguments requires a value"
        [[ "$LOCAL_ARGUMENTS_SET" == 0 ]] || fail "only one --arguments value is allowed"
        LOCAL_ARGUMENTS="$2"
        LOCAL_ARGUMENTS_SET=1
        shift 2
        ;;
      --arguments=*)
        [[ "$LOCAL_ARGUMENTS_SET" == 0 ]] || fail "only one --arguments value is allowed"
        LOCAL_ARGUMENTS="${arg#*=}"
        LOCAL_ARGUMENTS_SET=1
        shift
        ;;
      --help|-h)
        printf 'Usage: install.sh --harness <claude|opencode|omp|all> [--arguments "<command and native args>"]\n'
        printf '       install.sh --install --harness <claude|opencode|omp|all>\n'
        exit 0
        ;;
      *)
        fail "unknown installer argument: $arg"
        ;;
    esac
  done
  [[ -n "$HARNESS_SELECTION" ]] || fail "--harness is required"
  case "$HARNESS_SELECTION" in
    claude|opencode|omp|all) ;;
    *) fail "unknown harness: $HARNESS_SELECTION (use claude, opencode, omp, or all)" ;;
  esac
  if ((INSTALL_MODE == 0)); then
    [[ "$LOCAL_ARGUMENTS_SET" == 1 ]] || LOCAL_ARGUMENTS="status"
  elif ((LOCAL_ARGUMENTS_SET)); then
    fail "--arguments cannot be used with --install"
  fi
}

ensure_safe_parent() {
  local path="$1" current component
  local -a components=()
  IFS='/' read -r -a components <<< "$(dirname "$path")"
  current=""
  for component in "${components[@]}"; do
    [[ -n "$component" ]] || continue
    current="$current/$component"
    [[ -L "$current" ]] && fail "refusing to follow symlinked parent: $current"
    [[ -e "$current" && ! -d "$current" ]] &&
      fail "refusing non-directory parent: $current"
  done
  return 0
}
ensure_private_directory() {
  local directory="$1"
  if ! SESSION_LOG_DIRECTORY="$directory" python3 - <<'PY'
import os
import stat

directory = os.environ["SESSION_LOG_DIRECTORY"]
flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
fd = os.open(os.sep, flags)
try:
    for part in directory.split(os.sep)[1:]:
        if not part or part == ".":
            continue
        if part == "..":
            raise SystemExit(f"refusing parent traversal: {directory}")
        try:
            next_fd = os.open(part, flags, dir_fd=fd)
        except FileNotFoundError:
            try:
                os.mkdir(part, 0o700, dir_fd=fd)
            except FileExistsError:
                pass
            next_fd = os.open(part, flags, dir_fd=fd)
        os.close(fd)
        fd = next_fd
    current = os.fstat(fd)
    if not stat.S_ISDIR(current.st_mode) or current.st_uid != os.getuid():
        raise SystemExit(f"refusing unsafe private directory: {directory}")
    os.fchmod(fd, 0o700)
finally:
    os.close(fd)
PY
  then
    fail "cannot safely prepare private directory: $directory"
  fi
}

safe_remove_path() {
  local path="$1"
  SESSION_LOG_REMOVE_PATH="$path" python3 - <<'PY'
import os
import stat

target = os.environ["SESSION_LOG_REMOVE_PATH"]
directory, name = os.path.split(os.path.abspath(target))
flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
parent_fd = os.open(os.sep, flags)
try:
    for part in directory.split(os.sep)[1:]:
        if not part or part == ".":
            continue
        if part == "..":
            raise RuntimeError("parent traversal")
        next_fd = os.open(part, flags, dir_fd=parent_fd)
        os.close(parent_fd)
        parent_fd = next_fd
    try:
        current = os.lstat(name, dir_fd=parent_fd)
    except FileNotFoundError:
        raise SystemExit(0)
    if stat.S_ISDIR(current.st_mode) and not stat.S_ISLNK(current.st_mode):
        os.rmdir(name, dir_fd=parent_fd)
    else:
        os.unlink(name, dir_fd=parent_fd)
finally:
    os.close(parent_fd)
PY
}

cleanup() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  ensure_safe_parent "$path"
  if [[ -d "$path" && ! -L "$path" ]]; then
    safe_remove_path "$path" || fail "refusing to recursively remove non-empty directory: $path"
  elif [[ -e "$path" || -L "$path" ]]; then
    safe_remove_path "$path" || fail "refusing to remove path: $path"
  fi
}
_package_lock_operation() {
  local mode="$1"
  SESSION_LOG_LOCK_PATH="$INSTALL_LOCK" SESSION_LOG_LOCK_MODE="$mode" \
    SESSION_LOG_LOCK_PID="$$" SESSION_LOG_LOCK_START="$INSTALL_LOCK_OWNER_START" \
    python3 - "$mode" <<'PY'
import json
import os
import subprocess
import sys
import time

mode = sys.argv[1]
lock_path = os.environ["SESSION_LOG_LOCK_PATH"]
owner_pid = int(os.environ["SESSION_LOG_LOCK_PID"])
owner_start = os.environ["SESSION_LOG_LOCK_START"]
directory, name = os.path.split(lock_path)
flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)

def open_directory(path):
    fd = os.open(os.sep, flags)
    try:
        for component in path.split(os.sep)[1:]:
            if not component or component == ".":
                continue
            if component == "..":
                raise RuntimeError("parent traversal")
            try:
                next_fd = os.open(component, flags, dir_fd=fd)
            except FileNotFoundError:
                os.mkdir(component, 0o700, dir_fd=fd)
                next_fd = os.open(component, flags, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise

def read_owner(fd):
    descriptor = os.open("owner", os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=fd)
    try:
        return os.read(descriptor, 512).decode("utf-8").splitlines()
    finally:
        os.close(descriptor)

def owner_alive(lines):
    if len(lines) < 2 or not lines[0].isdigit() or not lines[1]:
        return None
    pid = int(lines[0])
    try:
        os.kill(pid, 0)
    except OSError as error:
        return getattr(error, "errno", None) != 3
    try:
        actual = subprocess.check_output(["ps", "-p", str(pid), "-o", "lstart="], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return True
    return actual == lines[1] if actual else True

parent_fd = open_directory(directory)
lock_fd = None
try:
    if mode == "acquire":
        while True:
            try:
                os.mkdir(name, 0o700, dir_fd=parent_fd)
                lock_fd = os.open(name, flags, dir_fd=parent_fd)
                descriptor = os.open("owner", os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600, dir_fd=lock_fd)
                try:
                    os.write(descriptor, ("%s\n%s\n" % (owner_pid, owner_start)).encode("utf-8"))
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
                break
            except FileExistsError:
                if lock_fd is not None:
                    os.close(lock_fd)
                    lock_fd = None
                lock_fd = os.open(name, flags, dir_fd=parent_fd)
                try:
                    lines = read_owner(lock_fd)
                except FileNotFoundError:
                    lines = []
                if owner_alive(lines):
                    raise SystemExit(1)
                age = time.time() - os.stat(name, dir_fd=parent_fd, follow_symlinks=False).st_mtime
                if age < 5:
                    raise SystemExit(1)
                try:
                    os.unlink("owner", dir_fd=lock_fd)
                except FileNotFoundError:
                    pass
                os.close(lock_fd)
                lock_fd = None
                os.rmdir(name, dir_fd=parent_fd)
    else:
        try:
            lock_fd = os.open(name, flags, dir_fd=parent_fd)
            lines = read_owner(lock_fd)
            if len(lines) >= 2 and lines[0] == str(owner_pid) and lines[1] == owner_start:
                os.unlink("owner", dir_fd=lock_fd)
                os.close(lock_fd)
                lock_fd = None
                os.rmdir(name, dir_fd=parent_fd)
        except (FileNotFoundError, NotADirectoryError):
            pass
finally:
    if lock_fd is not None:
        os.close(lock_fd)
    os.close(parent_fd)
PY
}
acquire_package_lock() {
  [[ ! -L "$STORE" ]] || fail "refusing symlinked package store: $STORE"
  [[ ! -e "$STORE" || -d "$STORE" ]] || fail "refusing non-directory package store: $STORE"
  if [[ ! -e "$STORE" ]]; then INSTALL_STORE_CREATED=1; fi
  ensure_private_directory "$STORE"
  INSTALL_LOCK_OWNER_START="$(ps -p "$$" -o lstart= 2>/dev/null | sed 's/^ *//; s/[[:space:]]*$//')"
  [[ -n "$INSTALL_LOCK_OWNER_START" ]] || fail "cannot determine package lock owner"
  _package_lock_operation acquire ||
    fail "universal session-log installation is already in progress"
}
release_package_lock() {
  _package_lock_operation release || true
  if ((INSTALL_STORE_CREATED)); then
    rmdir "$STORE" 2>/dev/null || true
  fi
}


sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    fail "missing dependency: shasum or sha256sum"
  fi
}

require_file() {
  [[ -f "$1" && ! -L "$1" ]] || fail "package source is incomplete: $1"
}

atomic_copy() {
  local source="$1" target="$2" preserve_mode="${3:-0}" manifest_owned="${4:-0}"
  require_file "$source"
  ensure_safe_parent "$target"
  if ! SESSION_LOG_SOURCE="$source" SESSION_LOG_TARGET="$target" SESSION_LOG_PRESERVE_MODE="$preserve_mode" \
    SESSION_LOG_MANIFEST_OWNED="$manifest_owned" python3 - <<'PY'
import os
import random
import stat

source = os.environ["SESSION_LOG_SOURCE"]
target = os.environ["SESSION_LOG_TARGET"]
preserve_mode = os.environ["SESSION_LOG_PRESERVE_MODE"] == "1"
manifest_owned = os.environ["SESSION_LOG_MANIFEST_OWNED"] == "1"
directory, name = os.path.split(target)
source_directory, source_name = os.path.realpath(os.path.dirname(source)), os.path.basename(source)
directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
file_flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)

def open_directory(path):
    if not os.path.isabs(path):
        fd = os.open(".", directory_flags)
        parts = path.split(os.sep)
    else:
        fd = os.open(os.sep, directory_flags)
        parts = path.split(os.sep)[1:]
    try:
        for part in parts:
            if not part or part == ".":
                continue
            if part == "..":
                raise SystemExit(f"refusing parent traversal: {path}")
            try:
                next_fd = os.open(part, directory_flags, dir_fd=fd)
            except FileNotFoundError:
                os.mkdir(part, 0o700, dir_fd=fd)
                next_fd = os.open(part, directory_flags, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise

def read_all(fd):
    chunks = []
    while True:
        chunk = os.read(fd, 1024 * 1024)
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)

source_dir_fd = open_directory(source_directory)
target_dir_fd = open_directory(directory)
source_fd = None
target_fd = None
target_data = None
temporary_name = None
backup_name = None
backup_active = False
try:
    source_fd = os.open(source_name, file_flags, dir_fd=source_dir_fd)
    source_stat = os.fstat(source_fd)
    if not stat.S_ISREG(source_stat.st_mode) or source_stat.st_nlink != 1:
        raise SystemExit(f"package source is not a safe regular file: {source}")
    source_data = read_all(source_fd)
    try:
        target_stat = os.stat(name, dir_fd=target_dir_fd, follow_symlinks=False)
    except FileNotFoundError:
        target_stat = None
    if target_stat is not None:
        if stat.S_ISLNK(target_stat.st_mode):
            raise SystemExit(f"refusing to overwrite symlink: {target}")
        if not stat.S_ISREG(target_stat.st_mode):
            raise SystemExit(f"refusing to overwrite non-file: {target}")
        target_fd = os.open(name, file_flags, dir_fd=target_dir_fd)
        target_data = read_all(target_fd)
        if not manifest_owned and target_data != source_data:
            raise SystemExit(f"refusing to overwrite unowned file: {target}")
    for attempt in range(20):
        candidate = f".session-log.{os.getpid()}.{random.randrange(1 << 30):08x}"
        try:
            temporary_fd = os.open(
                candidate,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                0o600,
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
        os.fchmod(temporary_fd, stat.S_IMODE(source_stat.st_mode) if preserve_mode else 0o600)
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
        for attempt in range(20):
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
        if read_all(target_fd) != target_data:
            os.rename(backup_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
            backup_active = False
            raise SystemExit(f"package target changed during copy: {target}")
        try:
            os.link(temporary_name, name, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd, follow_symlinks=False)
        except FileExistsError:
            for conflict_attempt in range(20):
                conflict = f"{backup_name}.conflict.{conflict_attempt}"
                try:
                    os.rename(name, conflict, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                    break
                except FileExistsError:
                    continue
            else:
                raise SystemExit(f"package target changed during copy: {target}")
            raise SystemExit(f"package target changed during copy: {target}")
        os.unlink(temporary_name, dir_fd=target_dir_fd)
        temporary_name = None
        os.lseek(target_fd, 0, os.SEEK_SET)
        if read_all(target_fd) != target_data:
            for conflict_attempt in range(20):
                conflict = f"{backup_name}.conflict.{conflict_attempt}"
                try:
                    os.rename(backup_name, conflict, src_dir_fd=target_dir_fd, dst_dir_fd=target_dir_fd)
                    break
                except FileExistsError:
                    continue
            else:
                raise SystemExit(f"package target changed during copy: {target}")
            backup_active = False
            raise SystemExit(f"package target changed during copy: {target}")
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
PY
  then
    fail "cannot safely copy package file: $target"
  fi
}
remove_known_path() {
  local path="$1" name
  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ -L "$path" ]]; then
    validate_managed_path "$path"
  elif [[ -f "$path" ]]; then
    name="${path##*/}"
    if ! has_exact_ownership_marker "$path"; then
      legacy_script_is_tracked "$name" "$path" ||
        fail "refusing to remove changed managed path: $path"
    fi
  else
    fail "refusing to remove changed managed path: $path"
  fi
  cleanup "$path"
}
legacy_omp_script_is_managed() {
  local child="$1"
  [[ "$child" == "$HOME_ROOT/.omp/agent/skills/session-log-omp/scripts/session_log_usage.ts" ]] &&
    has_exact_ownership_marker "$child"
}

validate_managed_path() {
  local path="$1" marker_path="${2:-$1}" target child scripts_dir=""
  [[ -e "$path" || -L "$path" ]] || return 0
  ensure_safe_parent "$path"
  if [[ -L "$path" ]]; then
    target="$(readlink "$path")"
    case "$path:$target" in
      "$HOME_ROOT/.config/opencode/plugins/session-log.js:$SOURCE_ROOT/adapters/opencode/session-log.js"|\
      "$HOME_ROOT/.config/opencode/plugins/session-log.js:$HOME_ROOT/.config/opencode/skills/session-log/adapters/opencode/session-log.js"|\
      "$HOME_ROOT/.config/opencode/plugins/session-log.js:$STORE/releases/"*/adapters/opencode/session-log.js|\
      "$HOME_ROOT/.config/opencode/plugins/session-log-omp.js:$SOURCE_ROOT/adapters/omp/session-log.js"|\
      "$HOME_ROOT/.config/opencode/plugins/session-log-omp.js:$HOME_ROOT/.omp/agent/skills/session-log/adapters/omp/session-log.js"|\
      "$HOME_ROOT/.config/opencode/plugins/session-log-omp.js:$STORE/releases/"*/adapters/omp/session-log.js|\
      "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh:$SOURCE_ROOT/adapters/opencode/session_log_usage.sh"|\
      "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh:$HOME_ROOT/.config/opencode/skills/session-log/adapters/opencode/session_log_usage.sh"|\
      "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh:$STORE/releases/"*/adapters/opencode/session_log_usage.sh|\
      "$HOME_ROOT/.omp/agent/extensions/session-log.js:$SOURCE_ROOT/adapters/omp/session-log.js"|\
      "$HOME_ROOT/.omp/agent/extensions/session-log.js:$HOME_ROOT/.omp/agent/skills/session-log/adapters/omp/session-log.js"|\
      "$HOME_ROOT/.omp/agent/extensions/session-log.js:$STORE/releases/"*/adapters/omp/session-log.js|\
      "$HOME_ROOT/.omp/agent/extensions/session-log-omp.js:$SOURCE_ROOT/adapters/omp/session-log.js"|\
      "$HOME_ROOT/.omp/agent/extensions/session-log-omp.js:$HOME_ROOT/.omp/agent/skills/session-log/adapters/omp/session-log.js"|\
      "$HOME_ROOT/.omp/agent/extensions/session-log-omp.js:$STORE/releases/"*/adapters/omp/session-log.js)
        return 0
        ;;
    esac
    fail "refusing to remove unowned legacy path: $path"
  fi
  [[ ! -d "$path" ]] ||
    { [[ "$marker_path" != "$path" && -f "$marker_path" ]] ||
      fail "refusing to remove unowned legacy path: $path"; }
  has_exact_ownership_marker "$marker_path" ||
    fail "refusing to remove unowned legacy path: $path"
  if [[ -d "$path" && ! -L "$path" ]]; then
    if [[ "$path" == "$HOME_ROOT/.omp/agent/skills/session-log-omp" &&
          -d "$path/scripts" && ! -L "$path/scripts" ]]; then
      scripts_dir="$path/scripts"
      for child in "$scripts_dir"/* "$scripts_dir"/.[!.]* "$scripts_dir"/..?*; do
        [[ -e "$child" || -L "$child" ]] || continue
        legacy_omp_script_is_managed "$child" && continue
        fail "refusing to remove managed directory containing user files: $scripts_dir"
      done
    fi
    for child in "$path"/* "$path"/.[!.]* "$path"/..?*; do
      [[ -e "$child" || -L "$child" ]] || continue
      [[ "$child" == "$marker_path" || "$child" == "$scripts_dir" ]] && continue
      fail "refusing to remove managed directory containing user files: $path"
    done
  fi
}

remove_managed_path() {
  local path="$1" marker_path="${2:-$1}" child scripts_dir=""
  validate_managed_path "$path" "$marker_path"
  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ -d "$path" && ! -L "$path" ]]; then
    if [[ "$path" == "$HOME_ROOT/.omp/agent/skills/session-log-omp" &&
          -d "$path/scripts" && ! -L "$path/scripts" ]]; then
      scripts_dir="$path/scripts"
      for child in "$scripts_dir"/* "$scripts_dir"/.[!.]* "$scripts_dir"/..?*; do
        [[ -e "$child" || -L "$child" ]] || continue
        if legacy_omp_script_is_managed "$child"; then
          remove_known_path "$child"
          continue
        fi
        fail "refusing to remove managed directory containing user files: $scripts_dir"
      done
    fi
    for child in "$path"/* "$path"/.[!.]* "$path"/..?*; do
      [[ -e "$child" || -L "$child" ]] || continue
      [[ "$child" == "$marker_path" || "$child" == "$scripts_dir" ]] && continue
      fail "refusing to remove managed directory containing user files: $path"
    done
    [[ -z "$scripts_dir" ]] || safe_remove_path "$scripts_dir" ||
      fail "refusing to remove managed directory containing user files: $scripts_dir"
    remove_known_path "$marker_path"
    safe_remove_path "$path" ||
      fail "refusing to remove managed directory containing user files: $path"
  else
    remove_known_path "$path"
  fi
}

remove_legacy_file() {
  remove_managed_path "$1"
}

check_default_roots() {
  if selected_harness claude; then
    [[ -z "${CLAUDE_CONFIG_DIR:-}" ]] ||
      paths_equivalent "$CLAUDE_CONFIG_DIR" "$HOME_ROOT/.claude" ||
      fail "CLAUDE_CONFIG_DIR is relocated; custom roots are unsupported; install this package explicitly for that location"
  fi
  if selected_harness opencode; then
    [[ -z "${OPENCODE_CONFIG_DIR:-}" ]] ||
      paths_equivalent "$OPENCODE_CONFIG_DIR" "$HOME_ROOT/.config/opencode" ||
      fail "OPENCODE_CONFIG_DIR is relocated; custom roots are unsupported; install this package explicitly for that location"
    [[ -z "${XDG_CONFIG_HOME:-}" ]] ||
      paths_equivalent "$XDG_CONFIG_HOME" "$HOME_ROOT/.config" ||
      fail "XDG_CONFIG_HOME is relocated; custom roots are unsupported; install this package explicitly for that location"
    [[ -z "${XDG_DATA_HOME:-}" ]] ||
      paths_equivalent "$XDG_DATA_HOME" "$HOME_ROOT/.local/share" ||
      fail "XDG_DATA_HOME is relocated; custom roots are unsupported; install this package explicitly for that location"
  fi
  if selected_harness omp; then
    [[ -z "${PI_CODING_AGENT_DIR:-}" ]] ||
      paths_equivalent "$PI_CODING_AGENT_DIR" "$HOME_ROOT/.omp/agent" ||
      fail "PI_CODING_AGENT_DIR is relocated; custom roots are unsupported; install this package explicitly for that location"
    [[ -z "${OMP_PROMPT_LOG_DIR:-}" ]] ||
      paths_equivalent "$OMP_PROMPT_LOG_DIR" "$HOME_ROOT/.omp/agent/prompt-logs" ||
      fail "OMP_PROMPT_LOG_DIR is relocated; custom roots are unsupported; install this package explicitly for that location"
  fi
}

validate_claude_settings() {
  local settings="$HOME_ROOT/.claude/settings.json"
  [[ -e "$settings" ]] || return 0
  ensure_safe_parent "$settings"
  [[ -L "$settings" ]] && fail "refusing to migrate symlinked Claude settings: $settings"
  SETTINGS_PATH="$settings" python3 - <<'PY'
import json
import os
import tempfile
settings_path = os.environ["SETTINGS_PATH"]
with open(settings_path, encoding="utf-8") as handle:
    document = json.load(handle)
if not isinstance(document, dict):
    raise SystemExit("cannot migrate Claude settings: root must be an object")
hooks = document.get("hooks")
if hooks is not None and not isinstance(hooks, dict):
    raise SystemExit("cannot migrate Claude settings: hooks must be an object")
if isinstance(hooks, dict):
    for event, entries in hooks.items():
        if not isinstance(entries, list):
            raise SystemExit(f"cannot migrate Claude settings: hooks.{event} must be an array")
parent = os.path.dirname(settings_path)
fd, temporary = tempfile.mkstemp(prefix=".session-log-check.", dir=parent, text=True)
os.close(fd)
os.unlink(temporary)
PY
}

legacy_script_is_tracked() {
  local name="$1" path="$2" hash
  [[ -f "$path" && ! -L "$path" ]] || return 1
  has_exact_ownership_marker "$path" && return 0
  hash="$(sha256_file "$path")"
  case "$name:$hash" in
    prompt_log_save.sh:81b0c9a3c1e5dc4a66387a61ef537634413b4a8a5aa51c2baba09d32f1f21c99|\
    prompt_log_new_session.sh:be3eab61ee895e97cdaa5ab624c707f00e188718efd23b4d1253f998350cba27|\
    prompt_log_stop.sh:43d402842f91c0a66dc6c3e0978eaac84a7288616a2e2816a3c5e6c5f577e91f|\
    prompt_log_subagent.sh:8b723c301764cdf858d629c60f194dcda6f0b52c2283d1014286e88a23c3661a|\
    prompt_log_lib.sh:921318ea4984f569d281916259f6e6cac0a199ea29d3ea9fadd56b8b514a8a45|\
    prompt_log_usage.sh:63fa36cfab6e6496a6ca06da2f1daa99013160145e2d62ab6ce5aecde33dd86a|\
    prompt_log_usage.jq:7a615cb3917c324d1638c4c0b7905681e5eb9eb14866f9b453415cb691f6ff1d|\
    prompt_log_prices.json:48aa786070d547d3d3a4552d13eeb403685660f0cf825b9797aaaee1bb15733d)
      return 0
      ;;
  esac
  return 1
}

validate_claude_legacy_scripts() {
  local name path
  for name in prompt_log_save.sh prompt_log_new_session.sh prompt_log_stop.sh prompt_log_subagent.sh prompt_log_lib.sh prompt_log_usage.sh prompt_log_usage.jq prompt_log_prices.json; do
    path="$HOME_ROOT/.claude/scripts/$name"
    [[ -e "$path" || -L "$path" ]] || continue
    legacy_script_is_tracked "$name" "$path" ||
      fail "refusing to remove unrecognized legacy Claude script: $path"
  done
}

remove_claude_legacy_scripts() {
  local name path
  validate_claude_legacy_scripts
  for name in prompt_log_save.sh prompt_log_new_session.sh prompt_log_stop.sh prompt_log_subagent.sh prompt_log_lib.sh prompt_log_usage.sh prompt_log_usage.jq prompt_log_prices.json; do
    path="$HOME_ROOT/.claude/scripts/$name"
    [[ -e "$path" || -L "$path" ]] || continue
    remove_known_path "$path"
  done
}

current_adapter_link() {
  local path="$1" target
  [[ -L "$path" ]] || return 1
  target="$(readlink "$path")"
  case "$path:$target" in
    "$HOME_ROOT/.config/opencode/plugins/session-log.js:$SOURCE_ROOT/adapters/opencode/session-log.js"|\
    "$HOME_ROOT/.config/opencode/plugins/session-log.js:$HOME_ROOT/.config/opencode/skills/session-log/adapters/opencode/session-log.js"|\
    "$HOME_ROOT/.config/opencode/plugins/session-log.js:$STORE/releases/"*/adapters/opencode/session-log.js|\
    "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh:$SOURCE_ROOT/adapters/opencode/session_log_usage.sh"|\
    "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh:$HOME_ROOT/.config/opencode/skills/session-log/adapters/opencode/session_log_usage.sh"|\
    "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh:$STORE/releases/"*/adapters/opencode/session_log_usage.sh|\
    "$HOME_ROOT/.omp/agent/extensions/session-log.js:$SOURCE_ROOT/adapters/omp/session-log.js"|\
    "$HOME_ROOT/.omp/agent/extensions/session-log.js:$HOME_ROOT/.omp/agent/skills/session-log/adapters/omp/session-log.js"|\
    "$HOME_ROOT/.omp/agent/extensions/session-log.js:$STORE/releases/"*/adapters/omp/session-log.js)
      return 0
      ;;
  esac
  return 1
}

remove_standalone_adapter_files() {
  if selected_harness opencode; then
    current_adapter_link "$HOME_ROOT/.config/opencode/plugins/session-log.js" ||
      remove_legacy_file "$HOME_ROOT/.config/opencode/plugins/session-log.js"
    current_adapter_link "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh" ||
      remove_legacy_file "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh"
  fi
  if selected_harness omp; then
    current_adapter_link "$HOME_ROOT/.omp/agent/extensions/session-log.js" ||
      remove_legacy_file "$HOME_ROOT/.omp/agent/extensions/session-log.js"
  fi
}

remove_legacy_entrypoints() {
  local path
  for path in \
    "$HOME_ROOT/.claude/skills/session-log/SKILL.md" \
    "$HOME_ROOT/.config/opencode/skills/session-log/SKILL.md" \
    "$HOME_ROOT/.config/opencode/commands/session-log.md" \
    "$HOME_ROOT/.omp/agent/skills/session-log/SKILL.md"; do
    case "$path" in
      "$HOME_ROOT/.claude/"*) selected_harness claude || continue ;;
      "$HOME_ROOT/.config/opencode/"*) selected_harness opencode || continue ;;
      "$HOME_ROOT/.omp/"*) selected_harness omp || continue ;;
    esac
    case "$path" in
      "$HOME_ROOT/.claude/skills/session-log/SKILL.md"|\
      "$HOME_ROOT/.config/opencode/skills/session-log/SKILL.md"|\
      "$HOME_ROOT/.config/opencode/commands/session-log.md"|\
      "$HOME_ROOT/.omp/agent/skills/session-log/SKILL.md")
      continue
      ;;
    esac
    if [[ -f "$path" && ! -L "$path" ]] && has_exact_ownership_marker "$path"; then
      remove_managed_path "$path"
    fi
  done
}



validate_legacy_entrypoints() {
  local path
  for path in \
    "$HOME_ROOT/.claude/skills/session-log/SKILL.md" \
    "$HOME_ROOT/.config/opencode/skills/session-log/SKILL.md" \
    "$HOME_ROOT/.config/opencode/commands/session-log.md" \
    "$HOME_ROOT/.omp/agent/skills/session-log/SKILL.md"; do
    case "$path" in
      "$HOME_ROOT/.claude/"*) selected_harness claude || continue ;;
      "$HOME_ROOT/.config/opencode/"*) selected_harness opencode || continue ;;
      "$HOME_ROOT/.omp/"*) selected_harness omp || continue ;;
    esac
    if [[ -f "$path" && ! -L "$path" ]] && has_exact_ownership_marker "$path"; then
      validate_managed_path "$path"
    fi
  done
}

validate_migration() {
  selected_harness claude && {
    validate_claude_settings
    validate_claude_legacy_scripts
  }
  validate_legacy_entrypoints
  if selected_harness opencode; then
    validate_managed_path "$HOME_ROOT/.config/opencode/plugins/session-log.js"
    validate_managed_path "$HOME_ROOT/.config/opencode/scripts/session_log_usage.sh"
    validate_managed_path "$HOME_ROOT/.config/opencode/commands/session-log-omp.md"
    validate_managed_path "$HOME_ROOT/.config/opencode/plugins/session-log-omp.js"
  fi
  if selected_harness omp; then
    validate_managed_path "$HOME_ROOT/.omp/agent/extensions/session-log.js"
    validate_managed_path "$HOME_ROOT/.omp/agent/skills/session-log-omp" \
      "$HOME_ROOT/.omp/agent/skills/session-log-omp/SKILL.md"
    validate_managed_path "$HOME_ROOT/.omp/agent/extensions/session-log-omp.js"
  fi
}

migrate_legacy_files() {
  local settings="$HOME_ROOT/.claude/settings.json"
  if selected_harness claude && [[ -f "$settings" ]]; then
    SETTINGS_PATH="$settings" CLAUDE_SCRIPTS_DIR="$HOME_ROOT/.claude/scripts" python3 - <<'PY'
import fcntl
import json
import os
import shlex
import stat

settings_path = os.environ["SETTINGS_PATH"]
legacy_scripts_dir = os.environ["CLAUDE_SCRIPTS_DIR"]
lock_path = settings_path + ".session-log.lock"
lock_fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
os.fchmod(lock_fd, 0o600)
fcntl.flock(lock_fd, fcntl.LOCK_EX)
legacy_names = {
    "prompt_log_save.sh",
    "prompt_log_new_session.sh",
    "prompt_log_stop.sh",
    "prompt_log_subagent.sh",
    "prompt_log_lib.sh",
    "prompt_log_usage.sh",
    "prompt_log_usage.jq",
    "prompt_log_prices.json",
}
legacy_paths = {os.path.join(legacy_scripts_dir, name) for name in legacy_names}

def normalized_legacy_path(token):
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
            if name in legacy_names:
                return os.path.join(legacy_scripts_dir, name)
    return token

def is_managed_legacy_command(command):
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    if len(tokens) != 2 or tokens[0] not in {"bash", "/bin/bash"}:
        return False
    return normalized_legacy_path(tokens[1]) in legacy_paths
settings_fd = os.open(settings_path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
before_stat = os.fstat(settings_fd)
if not stat.S_ISREG(before_stat.st_mode):
    os.close(settings_fd)
    raise SystemExit("Claude settings is not a regular file")
def read_settings():
    os.lseek(settings_fd, 0, os.SEEK_SET)
    chunks = []
    while True:
        chunk = os.read(settings_fd, 1024 * 1024)
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
original_settings = read_settings()
document = json.loads(original_settings.decode("utf-8"))
hooks = document.get("hooks")
changed = False
if isinstance(hooks, dict):
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
                    and is_managed_legacy_command(command)
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

if not changed:
    os.close(settings_fd)
    raise SystemExit(0)
parent = os.path.dirname(settings_path)
current_stat = os.fstat(settings_fd)
current_path_stat = os.lstat(settings_path)
if (
    (current_stat.st_dev, current_stat.st_ino, current_stat.st_size, current_stat.st_mtime_ns, current_stat.st_ctime_ns)
    != (before_stat.st_dev, before_stat.st_ino, before_stat.st_size, before_stat.st_mtime_ns, before_stat.st_ctime_ns)
    or
    (current_path_stat.st_dev, current_path_stat.st_ino, current_path_stat.st_size, current_path_stat.st_mtime_ns, current_path_stat.st_ctime_ns)
    != (before_stat.st_dev, before_stat.st_ino, before_stat.st_size, before_stat.st_mtime_ns, before_stat.st_ctime_ns)
):
    os.close(settings_fd)
    raise SystemExit("Claude settings changed during migration; retry installation")
if read_settings() != original_settings:
    os.close(settings_fd)
    raise SystemExit("Claude settings changed during migration; retry installation")
mode = stat.S_IMODE(before_stat.st_mode)
parent_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
parent_fd = None
temporary_fd = None
temporary = None
backup_name = None
backup_active = False
try:
    parent_fd = os.open(parent, parent_flags)
    parent_stat = os.fstat(parent_fd)
    path_parent_stat = os.stat(parent, follow_symlinks=False)
    if (parent_stat.st_dev, parent_stat.st_ino) != (path_parent_stat.st_dev, path_parent_stat.st_ino):
        raise SystemExit("Claude settings parent changed during migration; retry installation")
    for attempt in range(100):
        candidate = f".session-log-migrate.{os.getpid()}.{attempt}"
        try:
            temporary_fd = os.open(
                candidate,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                mode & 0o777,
                dir_fd=parent_fd,
            )
            temporary = candidate
            break
        except FileExistsError:
            continue
    if temporary_fd is None or temporary is None:
        raise SystemExit("cannot allocate temporary Claude settings file")
    os.fchmod(temporary_fd, mode & 0o777)
    with os.fdopen(temporary_fd, "w", encoding="utf-8") as handle:
        temporary_fd = None
        json.dump(document, handle, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    settings_name = os.path.basename(settings_path)
    final_stat = os.fstat(settings_fd)
    final_path_stat = os.stat(settings_name, dir_fd=parent_fd, follow_symlinks=False)
    os.lseek(settings_fd, 0, os.SEEK_SET)
    final_settings = read_settings()
    if (
        (final_stat.st_dev, final_stat.st_ino, final_stat.st_size, final_stat.st_mtime_ns, final_stat.st_ctime_ns)
        != (before_stat.st_dev, before_stat.st_ino, before_stat.st_size, before_stat.st_mtime_ns, before_stat.st_ctime_ns)
        or
        (final_path_stat.st_dev, final_path_stat.st_ino, final_path_stat.st_size, final_path_stat.st_mtime_ns, final_path_stat.st_ctime_ns)
        != (before_stat.st_dev, before_stat.st_ino, before_stat.st_size, before_stat.st_mtime_ns, before_stat.st_ctime_ns)
        or final_settings != original_settings
    ):
        raise SystemExit("Claude settings changed during migration; retry installation")
    for attempt in range(20):
        candidate = f".session-log-backup.{os.getpid()}.{attempt}"
        try:
            os.rename(settings_name, candidate, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            backup_name = candidate
            backup_active = True
            break
        except FileExistsError:
            continue
    if not backup_active:
        raise SystemExit("cannot stage Claude settings migration")
    backup_fd = os.open(backup_name, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=parent_fd)
    try:
        backup_stat = os.fstat(backup_fd)
        os.lseek(backup_fd, 0, os.SEEK_SET)
        chunks = []
        while True:
            chunk = os.read(backup_fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        backup_settings = b"".join(chunks)
    finally:
        os.close(backup_fd)
    if (
        (backup_stat.st_dev, backup_stat.st_ino, backup_stat.st_size, backup_stat.st_mtime_ns)
        != (before_stat.st_dev, before_stat.st_ino, before_stat.st_size, before_stat.st_mtime_ns)
        or backup_settings != original_settings
    ):
        os.rename(backup_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        backup_active = False
        raise SystemExit("Claude settings changed during migration; retry installation")
    try:
        os.link(temporary, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd, follow_symlinks=False)
    except FileExistsError:
        for conflict_attempt in range(20):
            conflict = f"{backup_name}.conflict.{conflict_attempt}"
            try:
                os.rename(settings_name, conflict, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                break
            except FileExistsError:
                continue
        else:
            raise SystemExit("Claude settings changed during migration; retry installation")
        os.rename(backup_name, settings_name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        backup_active = False
        raise SystemExit("Claude settings changed during migration; retry installation")
    os.unlink(temporary, dir_fd=parent_fd)
    temporary = None
    backup_fd = os.open(backup_name, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=parent_fd)
    try:
        backup_stat = os.fstat(backup_fd)
        os.lseek(backup_fd, 0, os.SEEK_SET)
        chunks = []
        while True:
            chunk = os.read(backup_fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        backup_settings = b"".join(chunks)
    finally:
        os.close(backup_fd)
    if (
        (backup_stat.st_dev, backup_stat.st_ino, backup_stat.st_size, backup_stat.st_mtime_ns)
        != (before_stat.st_dev, before_stat.st_ino, before_stat.st_size, before_stat.st_mtime_ns)
        or backup_settings != original_settings
    ):
        conflict = f"{backup_name}.conflict.0"
        for conflict_attempt in range(20):
            conflict = f"{backup_name}.conflict.{conflict_attempt}"
            try:
                os.rename(backup_name, conflict, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                break
            except FileExistsError:
                continue
        backup_active = False
        raise SystemExit("Claude settings changed during migration; retry installation")
    os.unlink(backup_name, dir_fd=parent_fd)
    backup_active = False
    os.fsync(parent_fd)
finally:
    if temporary_fd is not None:
        os.close(temporary_fd)
    if temporary is not None and parent_fd is not None:
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
    if parent_fd is not None:
        os.close(parent_fd)
    os.close(settings_fd)
PY
  fi
  selected_harness claude && validate_claude_settings
  remove_legacy_entrypoints
  selected_harness claude && remove_claude_legacy_scripts
  remove_standalone_adapter_files
  if selected_harness omp; then
    remove_managed_path "$HOME_ROOT/.omp/agent/skills/session-log-omp" \
      "$HOME_ROOT/.omp/agent/skills/session-log-omp/SKILL.md"
    remove_managed_path "$HOME_ROOT/.omp/agent/extensions/session-log-omp.js"
  fi
  if selected_harness opencode; then
    remove_managed_path "$HOME_ROOT/.config/opencode/commands/session-log-omp.md"
    remove_managed_path "$HOME_ROOT/.config/opencode/plugins/session-log-omp.js"
  fi

}

package_files() {
  cat <<'EOF'
SKILL.md
VERSION
install.sh
bin/session-log
adapters/claude/claude_hook.sh
adapters/claude/scripts/prompt_log_lib.sh
adapters/claude/scripts/prompt_log_new_session.sh
adapters/claude/scripts/prompt_log_prices.json
adapters/claude/scripts/prompt_log_save.sh
adapters/claude/scripts/prompt_log_stop.sh
adapters/claude/scripts/prompt_log_subagent.sh
adapters/claude/scripts/prompt_log_usage.jq
adapters/claude/scripts/prompt_log_usage.sh
adapters/opencode/session-log.js
adapters/opencode/session_log_usage.sh
adapters/omp/session-log.js
adapters/omp/session_log_usage.ts
templates/opencode/SKILL.md
templates/opencode/command.md
templates/omp/SKILL.md
EOF
}

package_manifest_hash() {
  local manifest="$1" relative="$2"
  awk -v wanted="asset=$relative" '
    $0 == wanted {
      if (getline && $0 ~ /^sha256=[0-9a-f]{64}$/) {
        sub(/^sha256=/, "")
        print
        exit
      }
    }
  ' "$manifest" 2>/dev/null
}

validate_package_manifest() {
  local target="$1" skill_source="$2" manifest="$target/$PACKAGE_MANIFEST"
  local relative expected source_hash target_hash manifest_version
  [[ -e "$manifest" || -L "$manifest" ]] || return 0
  [[ -f "$manifest" && ! -L "$manifest" ]] ||
    fail "refusing to use invalid package ownership manifest: $manifest"
  if ! SESSION_LOG_MANIFEST="$manifest" SESSION_LOG_PACKAGE_ASSETS="$(package_files)" python3 - <<'PY'
import os
import re

manifest = os.environ["SESSION_LOG_MANIFEST"]
allowed = set(os.environ["SESSION_LOG_PACKAGE_ASSETS"].splitlines())
with open(manifest, encoding="utf-8") as handle:
    lines = [line.rstrip("\n") for line in handle]
if len(lines) < 5 or lines[0] != "format=1" or lines[1] != "owner=universal-session-log":
    raise SystemExit(1)
if not re.fullmatch(r"version=[0-9]+\.[0-9]+\.[0-9]+", lines[2]):
    raise SystemExit(1)
seen = set()
if (len(lines) - 3) % 2:
    raise SystemExit(1)
for index in range(3, len(lines), 2):
    asset = lines[index][len("asset="):] if lines[index].startswith("asset=") else ""
    digest = lines[index + 1]
    if not asset or asset not in allowed or asset in seen:
        raise SystemExit(1)
    if not re.fullmatch(r"sha256=[0-9a-f]{64}", digest):
        raise SystemExit(1)
    seen.add(asset)
PY
  then
    fail "refusing to use invalid package ownership manifest: $manifest"
  fi
  while IFS= read -r relative; do
    [[ "$relative" == "SKILL.md" ]] && continue
    expected="$(package_manifest_hash "$manifest" "$relative")"
    [[ -z "$expected" ]] && continue
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] ||
      fail "refusing to use invalid package ownership manifest: $manifest"
    [[ -f "$target/$relative" && ! -L "$target/$relative" ]] ||
      fail "managed package asset is missing: $target/$relative"
    target_hash="$(sha256_file "$target/$relative")"
    source_hash="$(sha256_file "$SOURCE_ROOT/$relative")"
    [[ "$target_hash" == "$expected" || "$target_hash" == "$source_hash" ]] ||
      fail "managed package asset was modified: $target/$relative"
  done < <(package_files)
  expected="$(package_manifest_hash "$manifest" SKILL.md)"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] ||
    fail "refusing to use invalid package ownership manifest: $manifest"
  [[ -f "$target/SKILL.md" && ! -L "$target/SKILL.md" ]] ||
    fail "managed package asset is missing: $target/SKILL.md"
  target_hash="$(sha256_file "$target/SKILL.md")"
  source_hash="$(sha256_file "$skill_source")"
  [[ "$target_hash" == "$expected" || "$target_hash" == "$source_hash" ]] ||
    fail "managed package asset was modified: $target/SKILL.md"
}

package_manifest_owns() {
  local target="$1" relative="$2" expected
  [[ -f "$target/$PACKAGE_MANIFEST" && ! -L "$target/$PACKAGE_MANIFEST" ]] || return 1
  expected="$(package_manifest_hash "$target/$PACKAGE_MANIFEST" "$relative")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ -f "$target/$relative" && ! -L "$target/$relative" ]] || return 1
  [[ "$(sha256_file "$target/$relative")" == "$expected" ]]
}
package_skill_owned() {
  local target="$1"
  package_manifest_owns "$target" SKILL.md
}
manifestless_package_owned() {
  local target="$1" version
  [[ ! -e "$target/$PACKAGE_MANIFEST" && ! -L "$target/$PACKAGE_MANIFEST" ]] || return 1
  [[ -f "$target/SKILL.md" && ! -L "$target/SKILL.md" ]] || return 1
  has_exact_ownership_marker "$target/SKILL.md" || return 1
  [[ -f "$target/VERSION" && ! -L "$target/VERSION" ]] || return 1
  version="$(cat "$target/VERSION")" || return 1
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ -f "$target/install.sh" && ! -L "$target/install.sh" ]] || return 1
  [[ -f "$target/bin/session-log" && ! -L "$target/bin/session-log" ]] || return 1
}

write_package_manifest() {
  local target="$1" manifest="$1/$PACKAGE_MANIFEST" temp relative
  ensure_safe_parent "$manifest"
  [[ ! -L "$target" && -d "$target" ]] || fail "invalid package target: $target"
  [[ ! -L "$manifest" && ! -d "$manifest" ]] ||
    fail "refusing to overwrite package ownership manifest: $manifest"
  temp="$(mktemp "${TMPDIR:-/tmp}/session-log-manifest.XXXXXX")" ||
    fail "cannot create package manifest temporary file"
  chmod 600 "$temp"
  {
    printf 'format=1\n'
    printf 'owner=universal-session-log\n'
    printf 'version=%s\n' "$VERSION"
    while IFS= read -r relative; do
      [[ "$relative" == "SKILL.md" ]] && continue
      printf 'asset=%s\nsha256=%s\n' "$relative" "$(sha256_file "$target/$relative")"
    done < <(package_files)
    printf 'asset=SKILL.md\nsha256=%s\n' "$(sha256_file "$target/SKILL.md")"
  } > "$temp"
  if ! atomic_copy "$temp" "$manifest" 0 1; then
    unlink "$temp"
    fail "cannot safely write package ownership manifest: $manifest"
  fi
  unlink "$temp"
}

is_known_entrypoint_target() {
  case "$1" in
    "$HOME_ROOT/.claude/skills/session-log/SKILL.md"|\
    "$HOME_ROOT/.config/opencode/skills/session-log/SKILL.md"|\
    "$HOME_ROOT/.config/opencode/commands/session-log.md"|\
    "$HOME_ROOT/.omp/agent/skills/session-log/SKILL.md") return 0 ;;
  esac
  return 1
}

validate_copy_target() {
  local source="$1" target="$2" allow_legacy_marker="${3:-0}" manifest_owned="${4:-0}"
  require_file "$source"
  ensure_safe_parent "$target"
  [[ ! -L "$target" ]] || fail "refusing to overwrite symlink: $target"
  [[ ! -d "$target" ]] || fail "refusing to overwrite directory: $target"
  if [[ -e "$target" ]]; then
    [[ -f "$target" && ! -L "$target" ]] ||
      fail "refusing to overwrite non-file: $target"
    if ! cmp -s "$source" "$target"; then
      if ((manifest_owned)); then
        :
      elif ((allow_legacy_marker)) && has_exact_ownership_marker "$target"; then
        :
      else
        fail "refusing to overwrite unowned file: $target"
      fi
    fi
  fi
}
validate_package_targets() {
  local target="$1" skill_source="$2" relative allow_legacy_marker=0 manifest_owned=0 legacy_owned=0
  validate_package_manifest "$target" "$skill_source"
  if manifestless_package_owned "$target"; then
    legacy_owned=1
  fi
  while IFS= read -r relative; do
    [[ "$relative" == "SKILL.md" ]] && continue
    manifest_owned=$legacy_owned
    if [[ -e "$target/$relative" ]] && package_manifest_owns "$target" "$relative"; then
      if cmp -s "$SOURCE_ROOT/$relative" "$target/$relative"; then
        continue
      fi
      manifest_owned=1
    fi
    validate_copy_target "$SOURCE_ROOT/$relative" "$target/$relative" 0 "$manifest_owned"
  done < <(package_files)
  manifest_owned=$legacy_owned
  if package_skill_owned "$target"; then
    if cmp -s "$skill_source" "$target/SKILL.md"; then
      return 0
    fi
    manifest_owned=1
  fi
  is_known_entrypoint_target "$target/SKILL.md" && allow_legacy_marker=1
  validate_copy_target "$skill_source" "$target/SKILL.md" "$allow_legacy_marker" "$manifest_owned"
}

copy_package() {
  local target="$1" skill_source="$2" relative
  validate_package_targets "$target" "$skill_source"
  while IFS= read -r relative; do
    [[ "$relative" == "SKILL.md" ]] && continue
    if [[ -e "$target/$relative" ]] &&
      package_manifest_owns "$target" "$relative" &&
      cmp -s "$SOURCE_ROOT/$relative" "$target/$relative"; then
      continue
    fi
    atomic_copy "$SOURCE_ROOT/$relative" "$target/$relative" 1 1
  done < <(package_files)
  if ! package_skill_owned "$target" ||
    ! cmp -s "$skill_source" "$target/SKILL.md"; then
    atomic_copy "$skill_source" "$target/SKILL.md" 1 1
  fi
  write_package_manifest "$target"
}

validate_seed_entrypoints() {
  local command_target="$HOME_ROOT/.config/opencode/commands/session-log.md"
  local command_allow_legacy_marker=0
  if selected_harness claude; then
    validate_package_targets "$HOME_ROOT/.claude/skills/session-log" "$SOURCE_ROOT/SKILL.md"
  fi
  if selected_harness opencode; then
    validate_package_targets "$HOME_ROOT/.config/opencode/skills/session-log" \
      "$SOURCE_ROOT/templates/opencode/SKILL.md"
    is_known_entrypoint_target "$command_target" && command_allow_legacy_marker=1
    validate_copy_target "$SOURCE_ROOT/templates/opencode/command.md" \
      "$command_target" "$command_allow_legacy_marker"
  fi
  if selected_harness omp; then
    validate_package_targets "$HOME_ROOT/.omp/agent/skills/session-log" \
      "$SOURCE_ROOT/templates/omp/SKILL.md"
  fi
}

seed_entrypoints() {
  local command_target="$HOME_ROOT/.config/opencode/commands/session-log.md"
  if selected_harness claude; then
    copy_package "$HOME_ROOT/.claude/skills/session-log" "$SOURCE_ROOT/SKILL.md"
  fi
  if selected_harness opencode; then
    copy_package "$HOME_ROOT/.config/opencode/skills/session-log" "$SOURCE_ROOT/templates/opencode/SKILL.md"
    atomic_copy "$SOURCE_ROOT/templates/opencode/command.md" "$command_target" 1 1
  fi
  if selected_harness omp; then
    copy_package "$HOME_ROOT/.omp/agent/skills/session-log" "$SOURCE_ROOT/templates/omp/SKILL.md"
  fi
}


validate_package() {
  local relative
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    fail "package source is invalid: $SOURCE_ROOT/VERSION"
  while IFS= read -r relative; do
    case "$relative" in
      ""|/*|../*|*/../*) fail "invalid package asset path: $relative" ;;
    esac
    require_file "$SOURCE_ROOT/$relative"
  done < <(package_files)
  if [[ -e "$SOURCE_ROOT/$PACKAGE_MANIFEST" || -L "$SOURCE_ROOT/$PACKAGE_MANIFEST" ]]; then
    validate_package_manifest "$SOURCE_ROOT" "$SOURCE_ROOT/SKILL.md"
  fi
}

main() {
  parse_args "$@"
  validate_package
  if ((INSTALL_MODE == 0)); then
    [[ "$HARNESS_SELECTION" != all ]] || fail "--harness all requires --install"
    exec "$SOURCE_ROOT/bin/session-log" \
      --entrypoint "$HARNESS_SELECTION" \
      --harness "$HARNESS_SELECTION" \
      --arguments "$LOCAL_ARGUMENTS"
  fi

  command -v python3 >/dev/null 2>&1 || fail "missing dependency: python3"
  check_default_roots
  acquire_package_lock
  trap release_package_lock EXIT
  validate_migration
  validate_seed_entrypoints
  seed_entrypoints
  migrate_legacy_files
  release_package_lock
  trap - EXIT

  printf 'Universal session-log installed for %s.\n' \
    "$([[ "$HARNESS_SELECTION" == all ]] && printf 'Claude Code, OpenCode, and OMP' || printf '%s' "$HARNESS_SELECTION")"
  printf 'Run /session-log on in the current harness; restart it when activation requires it.\n'
  printf 'Logging remains off until explicitly enabled per harness.\n'
}

main "$@"
