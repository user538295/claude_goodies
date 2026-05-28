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

import os
import re
import sys
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Tuple

class Colors:
    """Terminal colors for output"""
    RED = '\033[91m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'
    BOLD = '\033[1m'

class DocumentationValidator:
    """Validates documentation structure and content"""
    
    def __init__(self, docs_path: str = "Documentation"):
        self.docs_path = Path(docs_path)
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.info: List[str] = []
        
        # Expected directory structure
        self.expected_dirs = {
            "Architecture",
            "ADRs",
            "Backlog",
            "Completed",
            "UserManual"
        }
        
        # Metadata pattern
        self.metadata_pattern = re.compile(
            r'\*\*Purpose\*\*:.*\n'
            r'\*\*Audience\*\*:.*\n'
            r'\*\*Status\*\*:.*\n'
            r'\*\*Last reviewed\*\*:.*\n'
            r'\*\*Next review\*\*:.*',
            re.MULTILINE
        )
        
    def validate(self) -> bool:
        """Run all validations"""
        print(f"{Colors.BOLD}Validating documentation structure...{Colors.END}\n")
        
        if not self.docs_path.exists():
            self.errors.append(f"Documentation directory not found: {self.docs_path}")
            return False
        
        self.validate_directory_structure()
        self.validate_root_files()
        self.validate_architecture_files()
        self.validate_adr_files()
        self.validate_all_markdown_files()
        
        return self.print_results()
    
    def validate_directory_structure(self):
        """Validate that expected directories exist"""
        print(f"{Colors.BLUE}Checking directory structure...{Colors.END}")
        
        existing_dirs = {d.name for d in self.docs_path.iterdir() if d.is_dir()}
        missing_dirs = self.expected_dirs - existing_dirs
        
        if missing_dirs:
            self.warnings.append(
                f"Missing expected directories: {', '.join(missing_dirs)}"
            )
        else:
            self.info.append("All expected directories present")
    
    def validate_root_files(self):
        """Validate root-level documentation files"""
        print(f"{Colors.BLUE}Checking root files...{Colors.END}")
        
        root = Path(".")
        expected_files = ["readme.md", "contributing.md"]
        
        for filename in expected_files:
            filepath = root / filename
            if not filepath.exists():
                self.warnings.append(f"Missing root file: {filename}")
    
    def validate_architecture_files(self):
        """Validate Architecture directory files"""
        arch_dir = self.docs_path / "Architecture"
        if not arch_dir.exists():
            return
        
        print(f"{Colors.BLUE}Checking Architecture files...{Colors.END}")
        
        for filepath in arch_dir.glob("*.md"):
            # Check naming convention: NNN_snake_case.md
            if not re.match(r'^\d{3}_[a-z0-9_]+\.md$', filepath.name):
                self.errors.append(
                    f"Architecture file has invalid naming: {filepath.name}. "
                    f"Expected format: NNN_snake_case.md"
                )
            
            self.validate_markdown_file(filepath)
    
    def validate_adr_files(self):
        """Validate ADR directory files"""
        adr_dir = self.docs_path / "ADRs"
        if not adr_dir.exists():
            return
        
        print(f"{Colors.BLUE}Checking ADR files...{Colors.END}")
        
        for filepath in adr_dir.glob("*.md"):
            # Check naming convention: NN_descriptive_name.md
            if not re.match(r'^\d{2}_[a-z0-9_-]+\.md$', filepath.name):
                self.errors.append(
                    f"ADR file has invalid naming: {filepath.name}. "
                    f"Expected format: NN_descriptive_name.md"
                )
            
            self.validate_adr_structure(filepath)
    
    def validate_markdown_file(self, filepath: Path):
        """Validate markdown file content"""
        try:
            content = filepath.read_text(encoding='utf-8')
        except Exception as e:
            self.errors.append(f"Cannot read file {filepath}: {e}")
            return
        
        # Check for metadata header
        if not self.metadata_pattern.search(content):
            self.errors.append(f"Missing or invalid metadata header: {filepath}")
        
        # Check review dates
        self.validate_review_dates(filepath, content)
        
        # Check for H1 heading
        if not re.search(r'^# .+', content, re.MULTILINE):
            self.errors.append(f"Missing H1 heading: {filepath}")
    
    def validate_adr_structure(self, filepath: Path):
        """Validate ADR structure"""
        try:
            content = filepath.read_text(encoding='utf-8')
        except Exception as e:
            self.errors.append(f"Cannot read ADR {filepath}: {e}")
            return
        
        # Check for required ADR sections
        required_sections = [
            "Status:",
            "Date:",
            "Context",
            "Decision",
            "Consequences"
        ]
        
        for section in required_sections:
            if section not in content:
                self.errors.append(
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
            
            # Check if review is overdue
            if next_review < datetime.now():
                self.warnings.append(
                    f"Documentation review overdue: {filepath} "
                    f"(next review: {next_review.date()})"
                )
            
            # Check if next review is before last review
            if next_review <= last_review:
                self.errors.append(
                    f"Next review date must be after last review: {filepath}"
                )
        except ValueError as e:
            self.errors.append(
                f"Invalid date format in {filepath}: {e}"
            )
    
    def validate_all_markdown_files(self):
        """Validate all markdown files for common issues"""
        print(f"{Colors.BLUE}Checking all markdown files...{Colors.END}")
        
        for filepath in self.docs_path.rglob("*.md"):
            try:
                content = filepath.read_text(encoding='utf-8')
                
                # Check for trailing whitespace
                if re.search(r' +$', content, re.MULTILINE):
                    self.warnings.append(
                        f"File contains trailing whitespace: {filepath}"
                    )
                
                # Check for multiple blank lines
                if re.search(r'\n\n\n+', content):
                    self.warnings.append(
                        f"File contains multiple consecutive blank lines: {filepath}"
                    )
                
                # Check for tabs
                if '\t' in content:
                    self.warnings.append(
                        f"File contains tabs (use spaces): {filepath}"
                    )
            except Exception as e:
                self.errors.append(f"Cannot validate {filepath}: {e}")
    
    def print_results(self) -> bool:
        """Print validation results"""
        print(f"\n{Colors.BOLD}Validation Results:{Colors.END}\n")
        
        if self.info:
            print(f"{Colors.GREEN}✓ Info:{Colors.END}")
            for msg in self.info:
                print(f"  {msg}")
            print()
        
        if self.warnings:
            print(f"{Colors.YELLOW}⚠ Warnings ({len(self.warnings)}):{Colors.END}")
            for msg in self.warnings:
                print(f"  {msg}")
            print()
        
        if self.errors:
            print(f"{Colors.RED}✗ Errors ({len(self.errors)}):{Colors.END}")
            for msg in self.errors:
                print(f"  {msg}")
            print()
        
        # Summary
        total_issues = len(self.errors) + len(self.warnings)
        if self.errors:
            print(f"{Colors.RED}{Colors.BOLD}Validation FAILED{Colors.END}")
            print(f"Found {len(self.errors)} error(s) and {len(self.warnings)} warning(s)")
            return False
        elif self.warnings:
            print(f"{Colors.YELLOW}{Colors.BOLD}Validation PASSED with warnings{Colors.END}")
            print(f"Found {len(self.warnings)} warning(s)")
            return True
        else:
            print(f"{Colors.GREEN}{Colors.BOLD}Validation PASSED{Colors.END}")
            print("No issues found!")
            return True


def main():
    """Main entry point"""
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
    success = validator.validate()
    
    if args.strict and validator.warnings:
        print(f"\n{Colors.YELLOW}Running in strict mode: treating warnings as errors{Colors.END}")
        success = False
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
