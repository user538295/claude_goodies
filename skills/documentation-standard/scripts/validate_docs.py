#!/usr/bin/env python3
"""
Documentation Structure Validator

This script validates that project documentation follows the documentation-standard
conventions including:
- Directory structure
- File naming conventions
- Metadata headers
- Review dates
"""

import re
import sys
from pathlib import Path
from datetime import datetime
from typing import List

class Colors:
    """Terminal colors for output"""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'
    BOLD = '\033[1m'

class DocumentationFileValidator:
    """Validates the content of individual documentation files."""

    def __init__(
        self,
        metadata_pattern: "re.Pattern[str]",
        errors: List[str],
        warnings: List[str],
    ):
        self._metadata_pattern = metadata_pattern
        self._errors = errors
        self._warnings = warnings

    def validate_markdown_file(self, filepath: Path):
        """Validate markdown file content"""
        try:
            content = filepath.read_text(encoding='utf-8')
        except Exception as e:
            self._errors.append(f"Cannot read file {filepath}: {e}")
            return

        if not self._metadata_pattern.search(content):
            self._errors.append(f"Missing or invalid metadata header: {filepath}")

        self.validate_review_dates(filepath, content)

        if not re.search(r'^# .+', content, re.MULTILINE):
            self._errors.append(f"Missing H1 heading: {filepath}")

    def validate_adr_structure(self, filepath: Path):
        """Validate ADR structure"""
        try:
            content = filepath.read_text(encoding='utf-8')
        except Exception as e:
            self._errors.append(f"Cannot read ADR {filepath}: {e}")
            return

        required_sections = [
            "Status:",
            "Date:",
            "Context",
            "Decision",
            "Consequences"
        ]

        for section in required_sections:
            if section not in content:
                self._errors.append(
                    f"ADR missing required section '{section}': {filepath}"
                )

    def validate_review_dates(self, filepath: Path, content: str):
        """Validate review dates in metadata"""
        last_review_match = re.search(
            r'\*\*Last reviewed\*\*:\s*(\d{4}-\d{2}-\d{2})',
            content
        )
        next_review_match = re.search(
            r'\*\*Next review\*\*:\s*(\d{4}-\d{2}-\d{2})',
            content
        )

        if not last_review_match or not next_review_match:
            return  # Already caught by metadata validation

        try:
            last_review = datetime.strptime(
                last_review_match.group(1), '%Y-%m-%d'
            )
            next_review = datetime.strptime(
                next_review_match.group(1), '%Y-%m-%d'
            )

            if next_review < datetime.now():
                self._warnings.append(
                    f"Documentation review overdue: {filepath} "
                    f"(next review: {next_review.date()})"
                )

            if next_review <= last_review:
                self._errors.append(
                    f"Next review date must be after last review: {filepath}"
                )
        except ValueError as e:
            self._errors.append(
                f"Invalid date format in {filepath}: {e}"
            )


class DocumentationValidator:
    """Validates documentation structure and content"""

    def __init__(self, docs_path: str = "Documentation"):
        self._docs_path = Path(docs_path)
        self._errors: List[str] = []
        self._warnings: List[str] = []
        self._info: List[str] = []
        self._expected_dirs = {
            "Architecture",
            "ADRs",
            "Backlog",
            "Completed",
            "UserManual"
        }

        self._metadata_pattern = re.compile(
            r'\*\*Purpose\*\*:.*\n'
            r'\*\*Audience\*\*:.*\n'
            r'\*\*Status\*\*:.*\n'
            r'\*\*Last reviewed\*\*:.*\n'
            r'\*\*Next review\*\*:.*',
            re.MULTILINE
        )
        self._file_validator = DocumentationFileValidator(
            self._metadata_pattern, self._errors, self._warnings
        )

    def validate(self):
        """Run all validations and collect findings."""
        self._errors.clear()
        self._warnings.clear()
        self._info.clear()
        if not self._docs_path.exists():
            self._errors.append(
                f"Documentation directory not found: {self._docs_path}"
            )
            return

        self.validate_directory_structure()
        self.validate_root_files()
        self.validate_architecture_files()
        self.validate_adr_files()
        self.validate_all_markdown_files()

    def has_warnings(self) -> bool:
        """Return whether validation found warnings."""
        return bool(self._warnings)

    def is_successful(self) -> bool:
        """Return whether validation passed with no errors."""
        return not self._errors

    def is_strictly_successful(self) -> bool:
        """Return whether validation passed with no errors or warnings."""
        return not self._errors and not self._warnings

    @property
    def errors(self) -> tuple[str, ...]:
        return tuple(self._errors)

    @property
    def warnings(self) -> tuple[str, ...]:
        return tuple(self._warnings)

    @property
    def info(self) -> tuple[str, ...]:
        return tuple(self._info)

    def validate_directory_structure(self):
        """Validate that expected directories exist."""
        existing_dirs = {
            directory.name
            for directory in self._docs_path.iterdir()
            if directory.is_dir()
        }
        missing_dirs = self._expected_dirs - existing_dirs

        if missing_dirs:
            self._warnings.append(
                f"Missing expected directories: {', '.join(missing_dirs)}"
            )
        else:
            self._info.append("All expected directories present")

    def validate_root_files(self):
        """Validate root-level documentation files."""
        root = Path(".")
        expected_files = ["readme.md", "contributing.md"]

        for filename in expected_files:
            filepath = root / filename
            if not filepath.exists():
                self._warnings.append(f"Missing root file: {filename}")

    def validate_architecture_files(self):
        """Validate Architecture directory files."""
        arch_dir = self._docs_path / "Architecture"
        if not arch_dir.exists():
            return

        for filepath in arch_dir.glob("*.md"):
            if not re.match(r'^\d{3}_[a-z0-9_]+\.md$', filepath.name):
                self._errors.append(
                    f"Architecture file has invalid naming: {filepath.name}. "
                    f"Expected format: NNN_snake_case.md"
                )

            self._file_validator.validate_markdown_file(filepath)

    def validate_adr_files(self):
        """Validate ADR directory files"""
        adr_dir = self._docs_path / "ADRs"
        if not adr_dir.exists():
            return

        for filepath in adr_dir.glob("*.md"):
            if not re.match(r'^\d{2}_[a-z0-9_-]+\.md$', filepath.name):
                self._errors.append(
                    f"ADR file has invalid naming: {filepath.name}. "
                    f"Expected format: NN_descriptive_name.md"
                )

            self._file_validator.validate_adr_structure(filepath)

    def validate_all_markdown_files(self):
        """Validate all markdown files for common issues"""
        for filepath in self._docs_path.rglob("*.md"):
            try:
                content = filepath.read_text(encoding='utf-8')

                # Check for trailing whitespace
                if re.search(r' +$', content, re.MULTILINE):
                    self._warnings.append(
                        f"File contains trailing whitespace: {filepath}"
                    )

                # Check for multiple blank lines
                if re.search(r'\n\n\n+', content):
                    self._warnings.append(
                        f"File contains multiple consecutive blank lines: {filepath}"
                    )

                # Check for tabs
                if '\t' in content:
                    self._warnings.append(
                        f"File contains tabs (use spaces): {filepath}"
                    )
            except Exception as e:
                self._errors.append(f"Cannot validate {filepath}: {e}")
    
def print_results(validator: DocumentationValidator):
    """Print collected validation findings."""
    errors = validator.errors
    warnings = validator.warnings
    info = validator.info
    print(f"\n{Colors.BOLD}Validation Results:{Colors.END}\n")

    if info:
        print(f"{Colors.GREEN}✓ Info:{Colors.END}")
        for msg in info:
            print(f"  {msg}")
        print()

    if warnings:
        print(f"{Colors.YELLOW}⚠ Warnings ({len(warnings)}):{Colors.END}")
        for msg in warnings:
            print(f"  {msg}")
        print()

    if errors:
        print(f"{Colors.RED}✗ Errors ({len(errors)}):{Colors.END}")
        for msg in errors:
            print(f"  {msg}")
        print()

    if errors:
        print(f"{Colors.RED}{Colors.BOLD}Validation FAILED{Colors.END}")
        print(
            f"Found {len(errors)} error(s) and "
            f"{len(warnings)} warning(s)"
        )
    elif warnings:
        print(f"{Colors.YELLOW}{Colors.BOLD}Validation PASSED with warnings{Colors.END}")
        print(f"Found {len(warnings)} warning(s)")
    else:
        print(f"{Colors.GREEN}{Colors.BOLD}Validation PASSED{Colors.END}")
        print("No issues found!")


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description='Validate documentation structure and content'
    )
    parser.add_argument(
        '--path',
        default='Documentation',
        help='Path to documentation directory (default: Documentation)'
    )
    parser.add_argument(
        '--strict',
        action='store_true',
        help='Treat warnings as errors'
    )

    args = parser.parse_args()

    validator = DocumentationValidator(args.path)
    print(f"{Colors.BOLD}Validating documentation structure...{Colors.END}\n")
    if Path(args.path).exists():
        print(f"{Colors.BLUE}Checking directory structure...{Colors.END}")
        print(f"{Colors.BLUE}Checking root files...{Colors.END}")
        if (Path(args.path) / "Architecture").exists():
            print(f"{Colors.BLUE}Checking Architecture files...{Colors.END}")
        if (Path(args.path) / "ADRs").exists():
            print(f"{Colors.BLUE}Checking ADR files...{Colors.END}")
        print(f"{Colors.BLUE}Checking all markdown files...{Colors.END}")

    validator.validate()
    if Path(args.path).exists():
        print_results(validator)

    if args.strict and validator.has_warnings():
        print(f"\n{Colors.YELLOW}Running in strict mode: treating warnings as errors{Colors.END}")

    if args.strict:
        success = validator.is_strictly_successful()
    else:
        success = validator.is_successful()
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
