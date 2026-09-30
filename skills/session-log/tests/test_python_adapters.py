import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[3]
USAGE_PATH = REPO / "skills/session-log/adapters/codex/session_log_usage.py"
INSTALL_PATH = REPO / "skills/session-log/adapters/native/install_hooks.py"
HOOK_PATH = REPO / "skills/session-log/adapters/native/session_log_hook.py"
CLAUDE_SETTINGS_PATH = REPO / "skills/session-log/lib/claude_settings.py"

EMPTY_TOTALS = {
    "input_tokens": 0,
    "cached_input_tokens": 0,
    "output_tokens": 0,
    "reasoning_output_tokens": 0,
    "total_tokens": 0,
}


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _is_temp_swap_target(source_name, target_name, target_basename):
    return (
        target_name == target_basename
        and source_name.startswith(".")
        and not source_name.startswith(".session-log-backup.")
    )


class CodexUsageTests(unittest.TestCase):
    def test_codex_usage_import_has_no_io_side_effects(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory}), \
                patch("sys.stdout", new_callable=io.StringIO) as stdout, \
                patch("sys.stderr", new_callable=io.StringIO) as stderr:
            load_module(USAGE_PATH, "session_log_usage_under_test")
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "")
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_codex_usage_totals_are_per_invocation(self):
        usage = load_module(USAGE_PATH, "session_log_usage_per_invocation_test")
        first = io.StringIO(json.dumps({"type": "token_usage_record", "data": {"input_tokens": 3, "output_tokens": 4}}) + "\n")
        second = io.StringIO(json.dumps({"type": "token_usage_record", "data": {"input_tokens": 2, "output_tokens": 1}}) + "\n")
        records, first_totals = usage.aggregate_tokens(first)
        self.assertEqual(records, 1)
        records, second_totals = usage.aggregate_tokens(second)
        self.assertEqual(records, 1)
        self.assertEqual(first_totals["total_tokens"], 7)
        self.assertEqual(second_totals["total_tokens"], 3)

    def test_aggregate_tokens_ignores_empty_and_malformed_input(self):
        usage = load_module(USAGE_PATH, "session_log_usage_edge_test")
        records, totals = usage.aggregate_tokens(io.StringIO(""))
        self.assertEqual(records, 0)
        self.assertEqual(totals, EMPTY_TOTALS)
        malformed = io.StringIO(
            "not json\n"
            "[1, 2, 3]\n"
            "{}\n"
            + json.dumps({"type": "token_usage_record", "data": "oops"}) + "\n"
            + json.dumps({"type": "session_meta", "payload": {}}) + "\n"
        )
        records, totals = usage.aggregate_tokens(malformed)
        self.assertEqual(records, 0)
        self.assertEqual(totals, EMPTY_TOTALS)

    def test_aggregate_tokens_respects_native_total_and_rejects_invalid_numeric_fields(self):
        usage = load_module(USAGE_PATH, "session_log_usage_mixed_records_test")
        transcript = io.StringIO("\n".join(json.dumps(record) for record in (
            {"type": "token_usage_record", "data": {
                "input_tokens": 8, "cached_input_tokens": 3, "output_tokens": 2,
                "reasoning_output_tokens": 1, "total_tokens": 25,
            }},
            {"type": "token_usage_record", "payload": {"usage": {
                "input_tokens": 5, "cached_input_tokens": True, "output_tokens": 4,
                "reasoning_output_tokens": -1, "total_tokens": False,
            }}},
            {"type": "token_usage_record", "data": {
                "input_tokens": -3, "cached_input_tokens": "9", "output_tokens": 7,
                "reasoning_output_tokens": 2, "total_tokens": -1,
            }},
        )) + "\n")
        records, totals = usage.aggregate_tokens(transcript)
        self.assertEqual(records, 3)
        self.assertEqual(totals, {
            "input_tokens": 13,
            "cached_input_tokens": 3,
            "output_tokens": 13,
            "reasoning_output_tokens": 3,
            "total_tokens": 41,
        })

    def test_codex_usage_cli_keeps_report_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            transcript = Path(directory) / "usage.jsonl"
            transcript.write_text(json.dumps({"type": "token_usage_record", "data": {"input_tokens": 3, "output_tokens": 4}}) + "\n")
            result = subprocess.run([sys.executable, str(USAGE_PATH), str(transcript)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            f"session: {transcript}", "TOTAL", "input_tokens: 3", "cached_input_tokens: 0",
            "output_tokens: 4", "reasoning_output_tokens: 0", "total_tokens: 7",
        ])

    def test_codex_usage_cli_errors_when_no_token_records(self):
        with tempfile.TemporaryDirectory() as directory:
            transcript = Path(directory) / "empty.jsonl"
            transcript.write_text(json.dumps({"type": "session_meta", "payload": {}}) + "\n")
            result = subprocess.run([sys.executable, str(USAGE_PATH), str(transcript)], text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("no token_usage_record data", result.stderr)


class InstallerHooksTests(unittest.TestCase):
    def test_installer_import_has_no_io_side_effects(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory}), \
                patch("sys.stdout", new_callable=io.StringIO) as stdout, \
                patch("sys.stderr", new_callable=io.StringIO) as stderr:
            load_module(INSTALL_PATH, "install_hooks_under_test")
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "")
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_installer_cli_preserves_unmanaged_hooks(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory).resolve() / "hooks.json"
            hook = REPO / "skills/session-log/adapters/native/session_log_hook.py"
            config.write_text(json.dumps({"hooks": {"SessionStart": [{"command": "user-hook"}]}}))
            result = subprocess.run([sys.executable, str(INSTALL_PATH), "install", "codex", str(config), str(hook)], text=True, capture_output=True)
            updated = json.loads(config.read_text())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(updated["hooks"]["SessionStart"][0], {"command": "user-hook"})
        self.assertTrue(any("session_log_hook.py codex session-start" in item.get("command", "")
                            for entry in updated["hooks"]["SessionStart"]
                            for item in entry.get("hooks", [])))

    def test_installer_completes_partial_writes_before_replacing_hooks_file(self):
        installer = load_module(INSTALL_PATH, "install_hooks_partial_write_test")
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory).resolve() / "hooks.json"
            document = {"hooks": {"SessionStart": [{"command": "complete-value"}]}}
            native_write = installer.os.write

            def write_partial(descriptor, data):
                return native_write(descriptor, data[:3])

            with patch.object(installer.os, "write", side_effect=write_partial):
                installer.atomic_write(config, document)

            self.assertEqual(json.loads(config.read_text()), document)


class AtomicSwapRaceTests(unittest.TestCase):
    def test_atomic_writers_preserve_targets_created_during_install(self):
        installer = load_module(INSTALL_PATH, "install_hooks_race_test")
        hook = load_module(HOOK_PATH, "session_log_hook_race_test")
        pathsafe = installer.pathsafe
        native_move = pathsafe.move_no_replace
        writers = (
            ("pathsafe", lambda path: pathsafe.write_file(str(path), "new value")),
            ("installer", lambda path: installer.atomic_write(path, {"value": "new"})),
            (
                "hook",
                lambda path: hook.atomic_private_json(path, {"value": "new"}, "codex"),
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            for name, writer in writers:
                target = Path(directory).resolve() / f"{name}.json"

                def create_racing_target(dir_fd, source_name, target_name):
                    if target_name == target.name:
                        descriptor = os.open(
                            target_name,
                            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                            0o600,
                            dir_fd=dir_fd,
                        )
                        os.write(descriptor, b"raced\n")
                        os.close(descriptor)
                    return native_move(dir_fd, source_name, target_name)

                with patch.object(
                    pathsafe, "move_no_replace", side_effect=create_racing_target
                ):
                    with self.assertRaises(FileExistsError):
                        writer(target)
                self.assertEqual(target.read_text(), "raced\n")

    def test_atomic_writers_quarantine_swapped_temp_for_absent_targets(self):
        installer = load_module(INSTALL_PATH, "install_hooks_absent_swap_test")
        hook = load_module(HOOK_PATH, "session_log_hook_absent_swap_test")
        pathsafe = installer.pathsafe
        native_move = pathsafe.move_no_replace
        writers = (
            ("pathsafe", lambda path: pathsafe.write_file(str(path), "intended")),
            ("installer", lambda path: installer.atomic_write(path, {"value": "new"})),
            ("hook", lambda path: hook.atomic_private_json(path, {"value": "new"}, "codex")),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for name, writer in writers:
                target = root / f"{name}.json"
                conflicts_before = set(root.glob(".*.conflict.*"))

                def swap_temporary(dir_fd, source_name, target_name):
                    if _is_temp_swap_target(source_name, target_name, target.name):
                        os.unlink(source_name, dir_fd=dir_fd)
                        descriptor = os.open(
                            source_name,
                            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                            0o600,
                            dir_fd=dir_fd,
                        )
                        os.write(descriptor, b"raced replacement\n")
                        os.close(descriptor)
                    return native_move(dir_fd, source_name, target_name)

                with patch.object(
                    pathsafe, "move_no_replace", side_effect=swap_temporary
                ):
                    with self.assertRaises(OSError):
                        writer(target)

                self.assertFalse(target.exists())
                conflicts = set(root.glob(".*.conflict.*")) - conflicts_before
                self.assertEqual(len(conflicts), 1)
                self.assertEqual(next(iter(conflicts)).read_bytes(), b"raced replacement\n")

    def test_atomic_writers_quarantine_entries_swapped_after_install(self):
        installer = load_module(INSTALL_PATH, "install_hooks_post_rename_test")
        hook = load_module(HOOK_PATH, "session_log_hook_post_rename_test")
        pathsafe = installer.pathsafe
        native_move = pathsafe.move_no_replace
        installer_document = {"value": "new"}
        writers = (
            ("pathsafe", lambda path: pathsafe.write_file(str(path), "intended"), b"intended\n"),
            (
                "installer",
                lambda path: installer.atomic_write(path, installer_document),
                (json.dumps(installer_document, indent=2) + "\n").encode(),
            ),
            (
                "hook",
                lambda path: hook.atomic_private_json(path, installer_document, "codex"),
                (json.dumps(installer_document, separators=(",", ":")) + "\n").encode(),
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for name, writer, expected_content in writers:
                target = root / f"{name}.json"
                displaced = f"{target.name}.displaced"
                conflicts_before = set(root.glob(".*.conflict.*"))

                occupied_conflicts = set()

                def swap_after_install(dir_fd, source_name, target_name):
                    result = native_move(dir_fd, source_name, target_name)
                    if target_name == target.name:
                        for attempt in range(pathsafe.MAX_TEMP_FILE_ATTEMPTS):
                            conflict = f"{source_name}.conflict.{attempt}"
                            descriptor = os.open(
                                conflict,
                                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                                0o600,
                                dir_fd=dir_fd,
                            )
                            os.write(descriptor, b"occupied conflict\n")
                            os.close(descriptor)
                            occupied_conflicts.add(conflict)
                        os.rename(
                            target_name,
                            displaced,
                            src_dir_fd=dir_fd,
                            dst_dir_fd=dir_fd,
                        )
                        descriptor = os.open(
                            target_name,
                            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                            0o600,
                            dir_fd=dir_fd,
                        )
                        os.write(descriptor, b"raced after rename\n")
                        os.close(descriptor)
                    return result

                with patch.object(
                    pathsafe, "move_no_replace", side_effect=swap_after_install
                ):
                    with self.assertRaises(OSError):
                        writer(target)

                self.assertFalse(target.exists())
                self.assertEqual((root / displaced).read_bytes(), expected_content)
                new_conflicts = set(root.glob(".*.conflict.*")) - conflicts_before
                raced_conflicts = [
                    conflict
                    for conflict in new_conflicts
                    if conflict.read_bytes() == b"raced after rename\n"
                ]
                self.assertEqual(len(occupied_conflicts), pathsafe.MAX_TEMP_FILE_ATTEMPTS)
                self.assertTrue(
                    all(
                        (root / conflict).read_bytes() == b"occupied conflict\n"
                        for conflict in occupied_conflicts
                    )
                )
                self.assertEqual(len(raced_conflicts), 1)
                self.assertNotIn(raced_conflicts[0].name, occupied_conflicts)

    def test_atomic_replacement_preserves_target_when_temp_path_is_swapped(self):
        installer = load_module(INSTALL_PATH, "install_hooks_temp_swap_test")
        hook = load_module(HOOK_PATH, "session_log_hook_temp_swap_test")
        pathsafe = installer.pathsafe
        native_move = pathsafe.move_no_replace
        writers = (
            ("pathsafe", lambda path: pathsafe.write_file(str(path), "intended replacement")),
            ("installer", lambda path: installer.atomic_write(path, {"value": "new"})),
            ("hook", lambda path: hook.atomic_private_json(path, {"value": "new"}, "codex")),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for name, writer in writers:
                target = root / f"{name}.json"
                conflicts_before = set(root.glob(".session-log-backup.*.conflict.*"))
                target.write_bytes(b"original\n")

                def swap_temporary(dir_fd, source_name, target_name):
                    if _is_temp_swap_target(source_name, target_name, target.name):
                        os.unlink(source_name, dir_fd=dir_fd)
                        descriptor = os.open(
                            source_name,
                            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                            0o600,
                            dir_fd=dir_fd,
                        )
                        os.write(descriptor, b"raced replacement\n")
                        os.close(descriptor)
                    return native_move(dir_fd, source_name, target_name)

                with patch.object(
                    pathsafe, "move_no_replace", side_effect=swap_temporary
                ):
                    with self.assertRaises(OSError):
                        writer(target)

                self.assertEqual(target.read_bytes(), b"original\n")
                conflicts = set(target.parent.glob(".session-log-backup.*.conflict.*")) - conflicts_before
                self.assertEqual(len(conflicts), 1)
                self.assertEqual(next(iter(conflicts)).read_bytes(), b"raced replacement\n")

    def test_atomic_writer_cleanup_preserves_swapped_temp_source(self):
        installer = load_module(INSTALL_PATH, "install_hooks_temp_cleanup_test")
        hook = load_module(HOOK_PATH, "session_log_hook_temp_cleanup_test")
        pathsafe = installer.pathsafe
        native_replace = pathsafe.replace_file_no_replace
        writers = (
            ("pathsafe", lambda path: pathsafe.write_file(str(path), "new value")),
            ("installer", lambda path: installer.atomic_write(path, {"value": "new"})),
            ("hook", lambda path: hook.atomic_private_json(path, {"value": "new"}, "codex")),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for name, writer in writers:
                target = root / f"{name}.json"
                target.write_bytes(b"original\n")
                cleanups_before = set(root.glob(".session-log-cleanup.*"))

                def swap_before_validation(request):
                    os.unlink(request.source_name, dir_fd=request.dir_fd)
                    descriptor = os.open(
                        request.source_name,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                        0o600,
                        dir_fd=request.dir_fd,
                    )
                    os.write(descriptor, b"raced temp source\n")
                    os.close(descriptor)
                    return native_replace(request)

                with patch.object(
                    pathsafe, "replace_file_no_replace", side_effect=swap_before_validation
                ):
                    with self.assertRaises(OSError):
                        writer(target)

                self.assertEqual(target.read_bytes(), b"original\n")
                cleanups = set(root.glob(".session-log-cleanup.*")) - cleanups_before
                self.assertEqual(len(cleanups), 1)
                self.assertEqual(next(iter(cleanups)).read_bytes(), b"raced temp source\n")

    def test_cleanup_retains_temp_in_nonsticky_shared_directory(self):
        installer = load_module(INSTALL_PATH, "install_hooks_shared_cleanup_test")
        pathsafe = installer.pathsafe
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            root.chmod(0o777)
            directory_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY)
            try:
                descriptor = os.open(
                    "temporary",
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                    dir_fd=directory_fd,
                )
                os.write(descriptor, b"keep this file\n")
                expected = os.fstat(descriptor)
                os.close(descriptor)
                pathsafe.unlink_if_same_file(directory_fd, "temporary", expected)
            finally:
                os.close(directory_fd)

            self.assertEqual((root / "temporary").read_bytes(), b"keep this file\n")


class DirectoryLifecycleTests(unittest.TestCase):
    def test_copy_closes_source_directory_when_target_cannot_open(self):
        installer = load_module(INSTALL_PATH, "install_hooks_directory_test")
        pathsafe = installer.pathsafe
        native_open = pathsafe.open_directory
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.write_bytes(b"source\n")
            source_descriptor = None

            def open_then_fail(path, *, create):
                nonlocal source_descriptor
                if source_descriptor is None:
                    source_descriptor = native_open(path, create=create)
                    return source_descriptor
                raise PermissionError("target directory unavailable")

            with patch.object(pathsafe, "open_directory", side_effect=open_then_fail):
                with self.assertRaises(PermissionError):
                    pathsafe.copy_file(pathsafe.CopyFileOptions(
                        str(source), str(Path(directory) / "target"),
                        preserve_mode=False, manifest_owned=False,
                    ))
            with self.assertRaises(OSError):
                os.fstat(source_descriptor)

    def test_settings_closes_directory_when_lock_open_fails(self):
        with patch.object(sys, "path", [str(CLAUDE_SETTINGS_PATH.parent), *sys.path]):
            settings = load_module(CLAUDE_SETTINGS_PATH, "claude_settings_directory_test")
        native_open = settings.os.open
        native_directory_open = settings.pathsafe.open_directory
        with tempfile.TemporaryDirectory() as directory:
            settings_path = str(Path(directory).resolve() / "settings.json")
            for operation in ("install", "migrate"):
                with self.subTest(operation=operation):
                    opened = []

                    def record_directory(path, *, create):
                        fd = native_directory_open(path, create=create)
                        opened.append(fd)
                        return fd

                    def reject_lock(path, *args, **kwargs):
                        if path == "settings.json.session-log.lock":
                            raise PermissionError("lock unavailable")
                        return native_open(path, *args, **kwargs)

                    with patch.dict(os.environ, {
                        "SETTINGS_PATH": settings_path,
                        "HOOK_PATH": "/unused/hook.sh",
                        "SESSION_LOG_OWNER_MARKER": "test-owner",
                        "CLAUDE_SCRIPTS_DIR": str(Path(directory).resolve() / "scripts"),
                    }), patch.object(settings.pathsafe, "open_directory", side_effect=record_directory), \
                            patch.object(settings.os, "open", side_effect=reject_lock):
                        with self.assertRaises(PermissionError):
                            settings.main([operation])
                    self.assertEqual(len(opened), 1)
                    with self.assertRaises(OSError):
                        os.fstat(opened[0])



class NativeHookTests(unittest.TestCase):
    def test_native_hook_import_has_no_io_side_effects(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"HOME": directory}), \
                patch("sys.stdout", new_callable=io.StringIO) as stdout, \
                patch("sys.stderr", new_callable=io.StringIO) as stderr:
            load_module(HOOK_PATH, "session_log_hook_import_test")
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "")
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_native_hook_processing_writes_injected_clock_and_nonce(self):
        hook = load_module(HOOK_PATH, "session_log_hook_under_test")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve() / ".codex"
            (root / "prompt-logs").mkdir(parents=True)
            (root / "prompt-logs" / ".enabled").touch()
            with patch("sys.stdout", new_callable=io.StringIO) as stdout:
                hook.process_payload(
                    hook.HookRequest(
                        "codex", "user-prompt",
                        {"session_id": "session-1", "cwd": directory, "prompt": "hello"},
                        root,
                    ),
                    hook.RuntimeHooks(
                        now=lambda: 1_700_000_000,
                        nonce_factory=lambda: "fixed-nonce",
                        process_start_lookup=lambda _pid: "started",
                    ),
                )
            self.assertEqual(stdout.getvalue(), "{}\n")
            runtime = json.loads((root / "session-log" / "runtime.json").read_text())
            self.assertEqual(runtime["nonce"], "fixed-nonce")
            self.assertEqual(runtime["loaded_at"], 1_700_000_000)
            log_files = list((root / "prompt-logs").glob("*/session_session-1.md"))
            self.assertEqual(len(log_files), 1)
            self.assertIn("2023-11-14T22:13:20Z prompt", log_files[0].read_text())
            self.assertIn("\nhello\n", log_files[0].read_text())

    def test_native_hook_reports_process_lookup_failure_in_runtime_and_keeps_response(self):
        hook = load_module(HOOK_PATH, "session_log_hook_failure_under_test")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve() / ".codex"
            (root / "prompt-logs").mkdir(parents=True)
            (root / "prompt-logs" / ".enabled").touch()
            with patch("sys.stdout", new_callable=io.StringIO) as stdout:
                hook.process_payload(
                    hook.HookRequest("codex", "session-start", {"session_id": "session-2"}, root),
                    hook.RuntimeHooks(
                        now=lambda: 10,
                        nonce_factory=lambda: "nonce",
                        process_start_lookup=lambda _pid: None,
                    ),
                )
            runtime = json.loads((root / "session-log" / "runtime.json").read_text())
        self.assertEqual(stdout.getvalue(), "{}\n")
        self.assertIsNone(runtime["process_start"])


if __name__ == "__main__":
    unittest.main()
