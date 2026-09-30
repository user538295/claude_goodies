import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from validate_docs import DocumentationValidator, print_results

class DocumentationValidatorTests(unittest.TestCase):
    def test_validation_collects_findings_without_printing(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            docs_path = Path(temp_dir) / "docs"
            docs_path.mkdir()
            validator = DocumentationValidator(str(docs_path))
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                validator.validate()

            self.assertEqual(output.getvalue(), "")
            self.assertTrue(validator.has_warnings())
            self.assertTrue(validator.is_successful())
            self.assertFalse(validator.is_strictly_successful())


    def test_revalidation_replaces_previous_findings(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            docs_path = Path(temp_dir) / "docs"
            docs_path.mkdir()
            validator = DocumentationValidator(str(docs_path))

            validator.validate()
            first_result = (validator.errors, validator.warnings, validator.info)
            validator.validate()

            self.assertEqual(
                (validator.errors, validator.warnings, validator.info),
                first_result,
            )
    def test_result_presentation_preserves_warning_summary(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            docs_path = Path(temp_dir) / "docs"
            docs_path.mkdir()
            validator = DocumentationValidator(str(docs_path))
            validator.validate()
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                print_results(validator)

            self.assertIn("Validation PASSED with warnings", output.getvalue())
            self.assertIn("Missing expected directories:", output.getvalue())

    def test_cli_preserves_warning_and_strict_exit_codes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            docs_path = Path(temp_dir) / "docs"
            docs_path.mkdir()
            script_path = Path(__file__).resolve().parents[1] / "scripts" / "validate_docs.py"

            regular = subprocess.run(
                [sys.executable, str(script_path), "--path", str(docs_path)],
                cwd=temp_dir,
                capture_output=True,
                text=True,
                check=False,
            )
            strict = subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    "--path",
                    str(docs_path),
                    "--strict",
                ],
                cwd=temp_dir,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(regular.returncode, 0)
            self.assertIn("Validation PASSED with warnings", regular.stdout)
            self.assertEqual(strict.returncode, 1)
            self.assertIn("Validation PASSED with warnings", strict.stdout)
            self.assertIn("strict mode", strict.stdout)

    def test_missing_documentation_directory_fails_without_result_output(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            validator = DocumentationValidator(str(Path(temp_dir) / "missing"))
            output = io.StringIO()

            with contextlib.redirect_stdout(output):
                validator.validate()

            self.assertEqual(output.getvalue(), "")
            self.assertFalse(validator.is_successful())


if __name__ == "__main__":
    unittest.main()
