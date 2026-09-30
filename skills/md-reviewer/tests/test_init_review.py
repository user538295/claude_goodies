import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "init_review.py"
SPEC = importlib.util.spec_from_file_location("init_review", SCRIPT)
init_review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(init_review)


class InitializeReviewWorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.workspace = Path(self.temp_dir.name).resolve() / "docs"
        self.workspace.mkdir()
        (self.workspace / "README.md").write_text("# Master\n")
        (self.workspace / "guide.md").write_text("# Guide\n")

    def run_cli(self, *arguments):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--workspace", str(self.workspace), *arguments],
            capture_output=True,
            text=True,
        )

    def test_cli_creates_expected_workspace_files_and_preserves_contents(self):
        result = self.run_cli(
            "--masters", "README.md", "--output", "report", "--priority", "guide.md"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("✅ Review workspace initialized:", result.stdout)
        self.assertIn("Files created: 10", result.stdout)
        review = self.workspace / "_review"
        expected = {
            "config.json",
            "progress.md",
            "glossary.md",
            "master_facts.md",
            "cross_refs.md",
            "findings/master-conflicts.md",
            "findings/critical.md",
            "findings/warnings.md",
            "findings/info.md",
            "findings/by-file/.gitkeep",
        }
        self.assertEqual(
            {str(path.relative_to(review)) for path in review.rglob("*") if path.is_file()},
            expected,
        )
        config = json.loads((review / "config.json").read_text())
        self.assertEqual(config["masters"], ["README.md"])
        self.assertEqual(config["output_format"], "report")
        self.assertEqual(config["on_master_conflict"], "warn")
        self.assertEqual(config["priority_files"], ["guide.md"])
        progress = (review / "progress.md").read_text()
        self.assertIn("- [ ] guide.md (priority)", progress)
        self.assertIn("- [ ] README.md | claims:", progress)

    def test_cli_reports_missing_master_without_creating_workspace(self):
        result = self.run_cli("--masters", "missing.md", "--output", "report")

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("❌ Error: Master documents not found: missing.md", result.stderr)
        self.assertFalse((self.workspace / "_review").exists())

    def test_cli_reports_missing_priority_file_without_creating_workspace(self):
        result = self.run_cli(
            "--masters", "README.md", "--output", "report", "--priority", "missing.md"
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("❌ Error: Priority files not found: missing.md", result.stderr)
        self.assertFalse((self.workspace / "_review").exists())

    def test_cli_refuses_existing_workspace_without_overwriting_user_files(self):
        review = self.workspace / "_review"
        review.mkdir()
        config = review / "config.json"
        user_content = b"user-authored settings\n"
        config.write_bytes(user_content)

        result = self.run_cli("--masters", "README.md", "--output", "report")

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn(
            f"❌ Error: Review workspace already exists: {review}", result.stderr
        )
        self.assertEqual(config.read_bytes(), user_content)

    def test_cli_reports_empty_markdown_scope_without_creating_workspace(self):
        (self.workspace / "README.md").unlink()
        (self.workspace / "guide.md").unlink()
        (self.workspace / "README.txt").write_text("Master\n")
        result = self.run_cli("--masters", "README.txt", "--output", "report")

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("❌ Error: No .md files found in ", result.stderr)
        self.assertFalse((self.workspace / "_review").exists())

    def test_summary_query_is_side_effect_free_and_initializer_creates_workspace(self):
        options = init_review.WorkspaceOptions(
            workspace=str(self.workspace), masters=["README.md"], output_format="report"
        )

        summary = init_review.summarize_workspace(options)

        self.assertTrue(summary["success"])
        self.assertEqual(summary["total_files"], 2)
        self.assertFalse((self.workspace / "_review").exists())
        self.assertIsNone(init_review.initialize_workspace(options, summary))
        self.assertTrue((self.workspace / "_review" / "config.json").is_file())


if __name__ == "__main__":
    unittest.main()
