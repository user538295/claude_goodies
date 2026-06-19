#!/usr/bin/env python3
"""
Initialize MD-Reviewer workspace.

Creates the _review/ directory structure with progress tracking,
glossary, findings folders, and configuration.

Usage:
    python3 init_review.py --workspace <path> --masters <file1,file2> --output <format> [options]

Arguments:
    --workspace             Where to create _review/ folder
    --masters               Comma-separated list of master document paths
    --output                Output format: console, inline, report, auto-fix
    --scope                 Directory to scan for .md files (default: workspace)
    --on-master-conflict    How to handle master conflicts: ask, warn, first-wins (default: warn)
    --priority              Comma-separated list of priority files to check first
    --language              Report language (default: auto-detect from user input)
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path


def find_markdown_files(directory: str, exclude_dirs: set = None) -> list:
    """Recursively find all .md files in directory."""
    if exclude_dirs is None:
        exclude_dirs = {'node_modules', '.git', '_review', 'venv', '__pycache__', '.venv'}
    
    md_files = []
    for root, dirs, files in os.walk(directory):
        # Filter out excluded directories
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        
        for file in files:
            if file.endswith('.md'):
                full_path = os.path.join(root, file)
                md_files.append(os.path.relpath(full_path, directory))
    
    return sorted(md_files)


def create_config_file(masters: list, output_format: str, on_master_conflict: str,
                       priority_files: list, language: str) -> dict:
    """Create the config.json structure."""
    return {
        "version": "1.0",
        "created_at": datetime.now().isoformat(),
        "masters": masters,
        "output_format": output_format,
        "on_master_conflict": on_master_conflict,
        "priority_files": priority_files or [],
        "language": language,
        "confidence_thresholds": {
            "report": 0.90,
            "possible": 0.70,
            "review_suggested": 0.50
        }
    }


def create_progress_file(masters: list, all_files: list, priority_files: list,
                         output_format: str, on_master_conflict: str) -> str:
    """Create the progress.md tracking file."""
    now = datetime.now().isoformat()
    
    # Separate masters and followers
    master_set = set(masters)
    followers = [f for f in all_files if f not in master_set]
    
    # Reorder followers: priority first, then alphabetical
    priority_set = set(priority_files or [])
    priority_followers = [f for f in followers if f in priority_set]
    other_followers = [f for f in followers if f not in priority_set]
    ordered_followers = priority_followers + other_followers
    
    content = f"""# Review Progress

## Configuration
- Masters: {', '.join(masters)}
- Output: {output_format}
- On master conflict: {on_master_conflict}
- Started: {now}
- Total files: {len(all_files)} ({len(masters)} masters, {len(followers)} followers)

## Phase Status
- [x] Phase 1: Setup
- [ ] Phase 2a: Master Extraction (0/{len(masters)})
- [ ] Phase 2b: Master Consolidation
- [ ] Phase 3: Follower Validation (0/{len(followers)})
- [ ] Phase 4: Cross-Document Analysis
- [ ] Phase 5: Output Generation

## Statistics
- Claims extracted: 0
- Glossary terms: 0
- Master conflicts: 0
- Critical findings: 0
- Warning findings: 0
- Info findings: 0

## Master Documents
"""
    
    for master in masters:
        content += f"- [ ] {master} | claims: - | terms: - | anchors: -\n"
    
    content += "\n## Follower Documents\n"
    
    for follower in ordered_followers:
        priority_marker = " (priority)" if follower in priority_set else ""
        content += f"- [ ] {follower}{priority_marker} | critical: - | warning: - | info: -\n"
    
    content += f"""
## Checkpoints
| Timestamp | Phase | File | Action |
|-----------|-------|------|--------|
| {now} | 1 | - | Setup complete |
"""
    
    return content


def create_glossary_file() -> str:
    """Create the initial glossary.md file."""
    return """# Terminology Glossary

Built from master documents during Phase 2. Preferred terms and their variants.

## Preferred Terms

| Term | Definition/Context | Source | Line |
|------|-------------------|--------|------|
<!-- Populated during Phase 2a: Master Extraction -->

## Discovered Variants

| Variant | Preferred Term | Found In | Line |
|---------|---------------|----------|------|
<!-- Populated during Phase 3: Follower Validation -->
"""


def create_master_facts_file() -> str:
    """Create the initial master_facts.md file."""
    return """# Master Document Facts

Authoritative claims extracted from master documents during Phase 2.

## Extraction Summary

| Master | Claims | Terms | Anchors | Extracted At |
|--------|--------|-------|---------|--------------|
<!-- Populated during Phase 2a -->

## Claims by Category

### Tool/Technology
| ID | Subject | Predicate | Object | Scope | Source | Line |
|----|---------|-----------|--------|-------|--------|------|
<!-- Populated during Phase 2a -->

### Version/Requirement
| ID | Subject | Predicate | Object | Scope | Source | Line |
|----|---------|-----------|--------|-------|--------|------|

### Configuration
| ID | Subject | Predicate | Object | Scope | Source | Line |
|----|---------|-----------|--------|-------|--------|------|

### Behavior
| ID | Subject | Predicate | Object | Scope | Source | Line |
|----|---------|-----------|--------|-------|--------|------|

### Architecture
| ID | Subject | Predicate | Object | Scope | Source | Line |
|----|---------|-----------|--------|-------|--------|------|

### Process/Procedure
| ID | Subject | Steps | Scope | Source | Lines |
|----|---------|-------|-------|--------|-------|

### Recommendation
| ID | Subject | Predicate | Object | Scope | Source | Line |
|----|---------|-----------|--------|-------|--------|------|

### Limitation
| ID | Subject | Predicate | Object | Scope | Source | Line |
|----|---------|-----------|--------|-------|--------|------|

## Anchors

| Document | Anchor | Heading Text |
|----------|--------|--------------|
<!-- Populated during Phase 2a -->
"""


def create_cross_refs_file() -> str:
    """Create the initial cross_refs.md file."""
    return """# Cross-Reference Map

Link and anchor mapping across all documents. Built during Phase 4.

## Internal Links

| Source File | Line | Link Target | Resolved To | Status |
|-------------|------|-------------|-------------|--------|
<!-- Populated during Phase 4 -->

## Image References

| Source File | Line | Image Path | Status |
|-------------|------|------------|--------|
<!-- Populated during Phase 4 -->

## External Links

| Source File | Line | URL | Notes |
|-------------|------|-----|-------|
<!-- Logged for reference -->
"""


def create_master_conflicts_file() -> str:
    """Create the master-conflicts.md file."""
    return """# Master Document Conflicts

Internal conflicts detected between master documents during Phase 2b.

## Conflicts

| ID | Master A | Line | Claim A | Master B | Line | Claim B | Resolution |
|----|----------|------|---------|----------|------|---------|------------|
<!-- Populated during Phase 2b: Master Consolidation -->

## Notes

Conflict handling mode: (set in config.json)
- `ask`: Prompts user to resolve
- `warn`: Logs here and continues (default)
- `first-wins`: First master takes precedence
"""


def create_findings_file(severity: str) -> str:
    """Create a consolidated findings file for a specific severity level."""
    titles = {
        "critical": "Critical Issues",
        "warnings": "Warnings", 
        "info": "Informational"
    }
    
    descriptions = {
        "critical": "Must be resolved. Factual errors, contradictions, or broken references.",
        "warnings": "Should be addressed. Style issues, potential confusion, or quality concerns.",
        "info": "For consideration. Suggestions and observations for improvement."
    }
    
    return f"""# {titles[severity]}

{descriptions[severity]}

**Note**: This file is consolidated from per-file findings during Phase 5.
Individual findings are in `findings/by-file/`.

## Summary

| File | Count | Categories |
|------|-------|------------|
<!-- Populated during Phase 5 -->

## All Issues

<!-- Consolidated from by-file findings during Phase 5 -->
"""


def init_workspace(workspace: str, masters: list, output_format: str, 
                   scope: str = None, on_master_conflict: str = "warn",
                   priority_files: list = None, language: str = "en") -> dict:
    """Initialize the review workspace."""
    
    # Resolve paths
    workspace_path = Path(workspace).resolve()
    review_path = workspace_path / "_review"
    findings_path = review_path / "findings"
    by_file_path = findings_path / "by-file"
    
    # Determine scope
    if scope:
        scope_path = Path(scope).resolve()
    else:
        scope_path = workspace_path
    
    # Check masters exist
    missing_masters = []
    for master in masters:
        master_path = scope_path / master
        if not master_path.exists():
            missing_masters.append(master)
    
    if missing_masters:
        return {
            "success": False,
            "error": f"Master documents not found: {', '.join(missing_masters)}"
        }
    
    # Find all markdown files
    all_files = find_markdown_files(str(scope_path))
    
    if not all_files:
        return {
            "success": False,
            "error": f"No .md files found in {scope_path}"
        }
    
    # Validate priority files exist
    if priority_files:
        missing_priority = [f for f in priority_files if f not in all_files]
        if missing_priority:
            return {
                "success": False,
                "error": f"Priority files not found: {', '.join(missing_priority)}"
            }
    
    # Create directory structure
    review_path.mkdir(exist_ok=True)
    findings_path.mkdir(exist_ok=True)
    by_file_path.mkdir(exist_ok=True)
    
    # Create files
    files_created = []
    
    # Config file (JSON)
    config = create_config_file(masters, output_format, on_master_conflict, 
                                priority_files, language)
    (review_path / "config.json").write_text(json.dumps(config, indent=2))
    files_created.append("config.json")
    
    # Progress file
    progress_content = create_progress_file(
        masters, all_files, priority_files, output_format, on_master_conflict
    )
    (review_path / "progress.md").write_text(progress_content)
    files_created.append("progress.md")
    
    # Glossary file
    (review_path / "glossary.md").write_text(create_glossary_file())
    files_created.append("glossary.md")
    
    # Master facts file
    (review_path / "master_facts.md").write_text(create_master_facts_file())
    files_created.append("master_facts.md")
    
    # Cross-refs file
    (review_path / "cross_refs.md").write_text(create_cross_refs_file())
    files_created.append("cross_refs.md")
    
    # Master conflicts file
    (findings_path / "master-conflicts.md").write_text(create_master_conflicts_file())
    files_created.append("findings/master-conflicts.md")
    
    # Consolidated findings files (populated in Phase 5)
    for severity in ["critical", "warnings", "info"]:
        (findings_path / f"{severity}.md").write_text(create_findings_file(severity))
        files_created.append(f"findings/{severity}.md")
    
    # Create empty by-file directory marker
    (by_file_path / ".gitkeep").write_text("# Per-file findings will be stored here\n")
    files_created.append("findings/by-file/.gitkeep")
    
    return {
        "success": True,
        "workspace": str(review_path),
        "files_created": files_created,
        "total_files": len(all_files),
        "masters": len(masters),
        "followers": len(all_files) - len(masters),
        "priority_files": len(priority_files) if priority_files else 0
    }


def main():
    parser = argparse.ArgumentParser(
        description="Initialize MD-Reviewer workspace",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Basic usage
    python3 init_review.py --workspace ./docs --masters README.md,ARCHITECTURE.md --output report
    
    # With all options
    python3 init_review.py \\
        --workspace ./docs \\
        --masters README.md,docs/ARCHITECTURE.md \\
        --output report \\
        --on-master-conflict warn \\
        --priority docs/install.md,docs/quickstart.md
        """
    )
    
    parser.add_argument(
        "--workspace", "-w",
        required=True,
        help="Where to create _review/ folder"
    )
    
    parser.add_argument(
        "--masters", "-m",
        required=True,
        help="Comma-separated list of master document paths (relative to scope)"
    )
    
    parser.add_argument(
        "--output", "-o",
        required=True,
        choices=["console", "inline", "report", "auto-fix"],
        help="Output format"
    )
    
    parser.add_argument(
        "--scope", "-s",
        help="Directory to scan for .md files (default: workspace)"
    )
    
    parser.add_argument(
        "--on-master-conflict",
        choices=["ask", "warn", "first-wins"],
        default="warn",
        help="How to handle conflicts between masters (default: warn)"
    )
    
    parser.add_argument(
        "--priority", "-p",
        help="Comma-separated list of priority files to check first"
    )
    
    parser.add_argument(
        "--language", "-l",
        default="en",
        help="Report language (default: en)"
    )
    
    args = parser.parse_args()
    
    # Parse comma-separated lists
    masters = [m.strip() for m in args.masters.split(",")]
    priority_files = [p.strip() for p in args.priority.split(",")] if args.priority else None
    
    # Initialize
    result = init_workspace(
        workspace=args.workspace,
        masters=masters,
        output_format=args.output,
        scope=args.scope,
        on_master_conflict=args.on_master_conflict,
        priority_files=priority_files,
        language=args.language
    )
    
    if result["success"]:
        print(f"✅ Review workspace initialized: {result['workspace']}")
        print(f"   Files created: {len(result['files_created'])}")
        print(f"   Total documents: {result['total_files']}")
        print(f"   Masters: {result['masters']}")
        print(f"   Followers: {result['followers']}")
        if result['priority_files']:
            print(f"   Priority files: {result['priority_files']}")
        print(f"\n   Next: Begin Phase 2a (Master Extraction)")
        print(f"   Process each master ONE AT A TIME.")
    else:
        print(f"❌ Error: {result['error']}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
