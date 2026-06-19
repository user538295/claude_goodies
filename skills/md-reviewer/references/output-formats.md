# Output Formats Reference

Templates and examples for each output format.

## Per-File Findings Format (Phase 3)

During Phase 3, findings are written per-file in both JSON and Markdown formats.

### Directory Structure

```
_review/findings/by-file/
├── docs__install.md.json          # JSON source of truth
├── docs__install.md.md            # Human-readable markdown
├── docs__api__auth.md.json
├── docs__api__auth.md.md
└── ...
```

**Filename convention**: Replace `/` with `__` in file paths.

### JSON Format (Source of Truth)

```json
{
  "file": "docs/install.md",
  "checked_at": "2025-01-15T10:35:00Z",
  "summary": {
    "critical": 2,
    "warning": 3,
    "info": 1
  },
  "findings": [
    {
      "id": "CC-001",
      "severity": "critical",
      "category": "content_consistency",
      "type": "value_mismatch",
      "line": 23,
      "column": null,
      "message": "Version mismatch: found '3.2.1', master has '3.4.0'",
      "context": "Install version 3.2.1 from npm",
      "follower_claim": {
        "subject": "version",
        "predicate": "equals",
        "object": "3.2.1"
      },
      "master_claim": {
        "subject": "version",
        "predicate": "equals",
        "object": "3.4.0"
      },
      "master_source": {
        "file": "README.md",
        "line": 15
      },
      "confidence": 0.95,
      "auto_fixable": true,
      "suggested_fix": "Replace '3.2.1' with '3.4.0'"
    },
    {
      "id": "CC-002",
      "severity": "critical",
      "category": "content_consistency",
      "type": "implicit_contradiction",
      "line": 45,
      "message": "Code implies MySQL but master specifies PostgreSQL",
      "context": "mysql -u root -p mydb",
      "source_type": "code_block",
      "follower_claim": {
        "subject": "database",
        "predicate": "uses",
        "object": "MySQL",
        "implicit": true
      },
      "master_claim": {
        "subject": "database",
        "predicate": "uses",
        "object": "PostgreSQL"
      },
      "master_source": {
        "file": "ARCHITECTURE.md",
        "line": 102
      },
      "confidence": 0.85,
      "auto_fixable": false
    }
    {
      "id": "SE-001",
      "severity": "warning", 
      "category": "scope_expansion",
      "type": "unmentioned_concept",
      "line": 45,
      "message": "Follower introduces concept not covered in masters",
      "follower_topic": "deployment",
      "follower_value": "on-premise installation",
      "master_coverage": "Masters only mention: cloud, AWS, hosted",
      "recommendation": "Verify if this is officially supported"
    }
  ]
}
```

### Markdown Format (Human-Readable)

```markdown
# Findings: docs/install.md

**Checked**: 2025-01-15T10:35:00Z  
**Summary**: 2 Critical, 3 Warning, 1 Info

---

## Critical (2)

### CC-001: Value Mismatch (L23) [95%]

**Category**: Content Consistency  
**Message**: Version mismatch: found '3.2.1', master has '3.4.0'

**Context**:
> Install version 3.2.1 from npm

**Master Reference**: README.md:15  
**Auto-fixable**: Yes  
**Suggested Fix**: Replace '3.2.1' with '3.4.0'

---

### CC-002: Implicit Contradiction (L45) [85%]

**Category**: Content Consistency  
**Message**: Code implies MySQL but master specifies PostgreSQL

**Context** (code block):
```
mysql -u root -p mydb
```

**Master Reference**: ARCHITECTURE.md:102  
**Auto-fixable**: No

---

## Warnings (3)

### TM-001: Terminology Variant (L67) [92%]
...

---

## Info (1)

### VT-001: Passive Voice (L102) [80%]
...
```

### ID Prefixes

| Prefix | Category |
|--------|----------|
| CC | Content Consistency |
| TM | Terminology |
| FM | Formatting |
| XR | Cross-Reference |
| VT | Voice & Tone |
| DP | Duplicate |

---

## 1. Console Output

Quick feedback format for terminal display.

### Format

```
Reviewing <directory> (<N> files, <M> masters)...

<filepath>
  ✗ [CRITICAL] L<line>: <message>
  ⚠ [WARNING] L<line>: <message>
  ℹ [INFO] L<line>: <message>

<filepath>
  ✓ No issues found

...

═══════════════════════════════════════════════════════
Summary: <N> Critical, <M> Warnings, <K> Info in <F> files
═══════════════════════════════════════════════════════
```

### Example

```
Reviewing docs/ (47 files, 2 masters)...

docs/installation.md
  ✗ [CRITICAL] L23: Version "3.2.1" contradicts master README.md:15 (expected "3.4.0")
  ✗ [CRITICAL] L45: Broken link to "./setup.md" - file not found
  ⚠ [WARNING] L67: Term "REST API" differs from master terminology "API endpoint"
  ⚠ [WARNING] L89: Heading skip: H1 → H3 (missing H2)
  ℹ [INFO] L102: Passive voice: "is configured" → consider "configure"

docs/api/authentication.md
  ✗ [CRITICAL] L12: Contradicts master - says "API keys" but master says "JWT tokens"
  ⚠ [WARNING] L34: Informal tone: "pretty easy" in technical documentation

docs/quickstart.md
  ✓ No issues found

docs/contributing.md
  ℹ [INFO] L5-15: Near-duplicate of docs/README.md:20-30 (87% similar)

═══════════════════════════════════════════════════════
Summary: 4 Critical, 3 Warnings, 2 Info in 47 files
═══════════════════════════════════════════════════════
```

### Icons

```
✗  Critical (U+2717)
⚠  Warning (U+26A0)
ℹ  Info (U+2139)
✓  Success (U+2713)
```

---

## 2. Inline Comments

Comments inserted directly into the reviewed files.

### Format

```markdown
<!-- MD-REVIEW [SEVERITY]: <message> -->
<original line>
```

### Placement Rules

- Insert comment on line BEFORE the problematic line
- For multi-line issues, place before first line
- For structural issues (like heading hierarchy), place at the heading

### Example

Original file:
```markdown
# Installation Guide

## Quick Start

Install version 3.2.1 from npm:

```bash
npm install mypackage@3.2.1
```

Then configure your settings by editing the config file.
Its pretty easy to setup.
```

After inline comments added:
```markdown
# Installation Guide

<!-- MD-REVIEW [WARNING]: Heading skip - H1 directly to H3 in next section -->
## Quick Start

<!-- MD-REVIEW [CRITICAL]: Version "3.2.1" contradicts master (3.4.0 in README.md:15) -->
Install version 3.2.1 from npm:

<!-- MD-REVIEW [CRITICAL]: Version in code block also outdated -->
```bash
npm install mypackage@3.2.1
```

<!-- MD-REVIEW [INFO]: Passive voice - consider "Configure your settings by editing..." -->
Then configure your settings by editing the config file.
<!-- MD-REVIEW [WARNING]: Informal tone "pretty easy" + typo "setup" should be "set up" -->
Its pretty easy to setup.
```

### Comment Removal

When auto-fix runs, it should:
1. Process inline comments as fix instructions
2. Remove comments after applying fixes
3. Leave comments for issues that couldn't be auto-fixed

---

## 3. Structured Report

Full markdown report with organized findings.

### Template

```markdown
# Documentation Review Report

**Generated**: <timestamp>  
**Workspace**: <path>  
**Files Reviewed**: <count>  
**Master Documents**: <list>

---

## Executive Summary

| Severity | Count |
|----------|-------|
| Critical | <n> |
| Warning | <n> |
| Info | <n> |

**Review Status**: <PASS/FAIL>

A review FAILS if there are any Critical issues.

---

## Critical Issues

Issues that must be resolved before documentation is considered accurate.

### Content Consistency Violations

| ID | Type | Follower | Line | Claim | Master Claim | Source | Confidence |
|----|------|----------|------|-------|--------------|--------|------------|
| CC-001 | Value Mismatch | <file> | <line> | <follower_claim> | <master_claim> | <master:line> | <n>% |
| CC-002 | Tool Conflict | <file> | <line> | <follower_claim> | <master_claim> | <master:line> | <n>% |
| CC-003 | Direct Contradiction | <file> | <line> | <follower_claim> | <master_claim> | <master:line> | <n>% |

### Implicit Contradictions

Code or examples that contradict explicit master claims.

| ID | Follower | Line | Source Type | Implicit Claim | Master Claim | Master Source |
|----|----------|------|-------------|----------------|--------------|---------------|
| IC-001 | <file> | <line> | code block | <inferred> | <master_claim> | <master:line> |

### Version Mismatches

| File | Line | Found | Expected | Master Reference |
|------|------|-------|----------|------------------|
| <path> | <line> | <found_version> | <expected_version> | <master:line> |

### Broken Cross-References

| File | Line | Link | Problem |
|------|------|------|---------|
| <path> | <line> | <link_text> | <file not found / anchor missing> |

---

## Warnings

Issues that should be addressed for documentation quality.

### Possible Content Conflicts (70-89% confidence)

| ID | Follower | Line | Issue | Master Reference | Confidence | Note |
|----|----------|------|-------|------------------|------------|------|
| PC-001 | <file> | <line> | <description> | <master:line> | <n>% | <clarification_needed> |

### Scope Ambiguities

Follower claims that may conflict depending on context (dev vs prod, version, etc.)

| Follower | Line | Follower Claim | Master Claim | Master Scope | Note |
|----------|------|----------------|--------------|--------------|------|
| <file> | <line> | <claim> | <master_claim> | <scope> | Verify intended scope |

### Terminology Inconsistencies

| File | Line | Found | Preferred | Master Source |
|------|------|-------|-----------|---------------|
| <path> | <line> | <variant> | <preferred> | <master:line> |

### Formatting Issues

| File | Line | Issue | Recommendation |
|------|------|-------|----------------|
| <path> | <line> | <description> | <fix> |

### Voice & Tone

| File | Line | Issue | Example |
|------|------|-------|---------|
| <path> | <line> | <description> | <text_sample> |

---

## Review Suggested (50-69% confidence)

Low-confidence findings that may warrant human review.

| ID | Follower | Line | Potential Issue | Related Master Claim | Confidence |
|----|----------|------|-----------------|---------------------|------------|
| RS-001 | <file> | <line> | <description> | <master:line> | <n>% |

---

## Informational

Observations and suggestions for improvement.

### Duplicate Content

| File A | Lines | File B | Lines | Similarity |
|--------|-------|--------|-------|------------|
| <path> | <range> | <path> | <range> | <percent>% |

### Style Suggestions

| File | Line | Suggestion |
|------|------|------------|
| <path> | <line> | <description> |

---

## Extracted Claims Summary

Overview of claims extracted from master documents.

| Category | Count | Example |
|----------|-------|---------|
| Tool/Technology | <n> | "uses PostgreSQL" |
| Version/Requirement | <n> | "requires Python 3.9+" |
| Configuration | <n> | "timeout: 30s" |
| Behavior | <n> | "returns JSON" |
| Architecture | <n> | "microservices" |
| Process/Procedure | <n> | "installation steps" |
| Recommendation | <n> | "recommended: X" |
| Limitation | <n> | "does not support Y" |

---

## Terminology Glossary

Terms extracted from master documents (preferred usage).

| Preferred Term | Definition/Context | Variants Found | Occurrences |
|----------------|-------------------|----------------|-------------|
| <term> | <context> | <variants> | <count> |

---

## Files Reviewed

### Masters
- [ ] <path> (analyzed as master)

### Followers
- [x] <path> - <n> issues
- [x] <path> - No issues
- [ ] <path> - Not reviewed (interrupted)

---

## Appendix: Check Configuration

| Check Type | Enabled | Severity |
|------------|---------|----------|
| Terminology | Yes | Warning |
| Formatting | Yes | Warning |
| Cross-references | Yes | Critical |
| Voice & Tone | Yes | Info |
| Technical Accuracy | Yes | Critical |
| Contradictions | Yes | Critical |
| Duplicates | Yes | Info |

---

*Report generated by md-reviewer skill*
```

### Example Report

```markdown
# Documentation Review Report

**Generated**: 2025-01-15T14:30:00Z  
**Workspace**: /project/docs/_review  
**Files Reviewed**: 47  
**Master Documents**: README.md, docs/ARCHITECTURE.md

---

## Executive Summary

| Severity | Count |
|----------|-------|
| Critical | 4 |
| Warning | 12 |
| Info | 8 |

**Review Status**: FAIL

---

## Critical Issues

### Contradictions

| File | Line | Issue | Master Reference |
|------|------|-------|------------------|
| docs/api/auth.md | 23 | States "API keys" for auth | ARCHITECTURE.md:45 says "JWT tokens" |
| docs/deploy.md | 67 | "MySQL database" | ARCHITECTURE.md:102 says "PostgreSQL" |

### Version Mismatches

| File | Line | Found | Expected | Master Reference |
|------|------|-------|----------|------------------|
| docs/install.md | 15 | 3.2.1 | 3.4.0 | README.md:8 |
| docs/install.md | 34 | Python 3.7+ | Python 3.9+ | README.md:12 |

### Broken Cross-References

| File | Line | Link | Problem |
|------|------|------|---------|
| docs/guide.md | 89 | [Setup](./setup.md) | File not found |
| docs/api.md | 156 | [Auth section](#authentication) | Anchor missing |

...
```

---

## 4. Auto-Fix Mode

Applies fixes directly to files with change tracking.

### Process

1. Read current file content
2. Apply fixable changes
3. Generate diff for confirmation (if interactive)
4. Write updated file
5. Log changes to `_review/fixes_applied.md`

### Fixes Applied Log Template

```markdown
# Fixes Applied

**Run**: <timestamp>  
**Mode**: <interactive/automatic>

## Summary

| Fix Type | Count |
|----------|-------|
| Terminology normalized | <n> |
| Headings adjusted | <n> |
| Code blocks standardized | <n> |
| Lists formatted | <n> |

---

## Detailed Changes

### <filepath>

**Terminology (3 changes)**
- L23: "REST API" → "API endpoint"
- L45: "config" → "configuration"
- L67: "Javascript" → "JavaScript"

**Formatting (1 change)**
- L12: Heading level adjusted H3 → H2

### <filepath>

**Code Blocks (2 changes)**
- L34: Added language specifier `python`
- L56: Converted indented code to fenced block

---

## Unfixable Issues

These require manual intervention:

| File | Line | Issue | Reason |
|------|------|-------|--------|
| docs/api.md | 89 | Broken link | Destination unknown |
| docs/guide.md | 23 | Contradiction | Semantic decision needed |

---

*Auto-fix completed at <timestamp>*
```

### Interactive Confirmation

For critical changes (like version updates), prompt for confirmation:

```
docs/install.md:15
  Current:  Install version 3.2.1
  Proposed: Install version 3.4.0
  Master:   README.md:8 defines version as 3.4.0

  Apply this fix? [y/N/all/skip-type]:
```

Options:
- `y` - Apply this fix
- `n` - Skip this fix
- `all` - Apply all remaining fixes of this type
- `skip-type` - Skip all fixes of this type

---

## Language Adaptation

All output formats adapt to user's instruction language.

### English Example
```
✗ [CRITICAL] L23: Version "3.2.1" contradicts master (expected "3.4.0")
```

### Hungarian Example
```
✗ [KRITIKUS] L23: "3.2.1" verzió ellentmond a masternek (elvárt: "3.4.0")
```

### Key Phrases by Language

| English | Hungarian | German |
|---------|-----------|--------|
| Critical | Kritikus | Kritisch |
| Warning | Figyelmeztetés | Warnung |
| Info | Információ | Info |
| contradicts master | ellentmond a masternek | widerspricht Master |
| not found | nem található | nicht gefunden |
| expected | elvárt | erwartet |
| Summary | Összefoglalás | Zusammenfassung |
| Files Reviewed | Ellenőrzött fájlok | Überprüfte Dateien |
