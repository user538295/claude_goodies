# Markdown Quality Standards

This reference defines markdown linting rules and quality standards for documentation.

## Table of Contents
1. [Linting Rules](#linting-rules)
2. [Style Guide](#style-guide)
3. [Quality Checklist](#quality-checklist)
4. [Common Issues and Fixes](#common-issues-and-fixes)

## Linting Rules

### Recommended Tools
- **markdownlint**: Primary linting tool
- **markdownlint-cli**: Command-line interface
- **VS Code Extension**: markdownlint by David Anson

### Configuration

Create `.markdownlint.json` in project root:

```json
{
  "default": true,
  "MD001": true,
  "MD003": { "style": "atx" },
  "MD004": { "style": "dash" },
  "MD007": { "indent": 2 },
  "MD013": false,
  "MD024": { "siblings_only": true },
  "MD025": true,
  "MD033": { "allowed_elements": ["antml:cite", "antml:document", "details", "summary"] },
  "MD034": false,
  "MD041": true
}
```

### Key Rules Explained

#### MD001 - Heading Levels
**Rule**: Heading levels should only increment by one level at a time

**Bad**:
```markdown
# Heading 1
### Heading 3 (skipped level 2)
```

**Good**:
```markdown
# Heading 1
## Heading 2
### Heading 3
```

#### MD003 - Heading Style
**Rule**: Use ATX-style headings (with #)

**Bad**:
```markdown
Heading 1
=========
```

**Good**:
```markdown
# Heading 1
```

#### MD004 - List Style
**Rule**: Use consistent list markers (prefer dash -)

**Bad**:
```markdown
- Item 1
* Item 2
+ Item 3
```

**Good**:
```markdown
- Item 1
- Item 2
- Item 3
```

#### MD007 - List Indentation
**Rule**: Lists should be indented with 2 spaces

**Bad**:
```markdown
- Item 1
    - Nested item (4 spaces)
```

**Good**:
```markdown
- Item 1
  - Nested item (2 spaces)
```

#### MD009 - Trailing Spaces
**Rule**: No trailing spaces at end of lines

**Fix**: Configure editor to remove trailing spaces on save

#### MD010 - Hard Tabs
**Rule**: Use spaces, not tabs

**Fix**: Configure editor to use spaces for indentation

#### MD012 - Multiple Blank Lines
**Rule**: No multiple consecutive blank lines

**Bad**:
```markdown
Paragraph 1


Paragraph 2 (two blank lines)
```

**Good**:
```markdown
Paragraph 1

Paragraph 2 (one blank line)
```

#### MD013 - Line Length
**Rule**: Disabled (lines can be any length)

**Rationale**: Modern editors handle line wrapping well, and strict line limits can harm readability

#### MD022/MD023/MD032 - Blank Lines Around Headings/Lists
**Rule**: Blank lines should surround headings and lists

**Bad**:
```markdown
# Heading
Paragraph immediately after heading
- List item
```

**Good**:
```markdown
# Heading

Paragraph with blank line after heading

- List item
```

#### MD024 - Duplicate Headings
**Rule**: Duplicate headings are allowed if they're not siblings

**Good** (different sections):
```markdown
# Section 1
## Configuration

# Section 2
## Configuration
```

#### MD025 - Single H1
**Rule**: Only one top-level heading per document

**Bad**:
```markdown
# First Heading
Content
# Second Heading
```

**Good**:
```markdown
# Main Heading
## Subheading 1
## Subheading 2
```

#### MD033 - Inline HTML
**Rule**: HTML is restricted but some elements are allowed

**Allowed**: `<details>`, `<summary>`, ``, `<document>`

#### MD041 - First Line Should Be H1
**Rule**: Document should start with a top-level heading

**Exception**: Metadata header comes before H1 in our standard

## Style Guide

### Headings

```markdown
# Top-Level Heading (H1)
## Second-Level Heading (H2)
### Third-Level Heading (H3)
#### Fourth-Level Heading (H4)
```

**Best Practices**:
- Use sentence case ("Authentication flow" not "Authentication Flow")
- Keep headings concise (under 60 characters)
- Make headings descriptive and scannable
- Avoid ending with punctuation
- Don't skip heading levels

### Lists

#### Unordered Lists
```markdown
- First item
- Second item
  - Nested item
  - Another nested item
- Third item
```

#### Ordered Lists
```markdown
1. First step
2. Second step
   1. Sub-step
   2. Another sub-step
3. Third step
```

#### Task Lists
```markdown
- [ ] Incomplete task
- [x] Complete task
- [ ] Another incomplete task
```

**Best Practices**:
- Use parallel structure (all items same grammatical form)
- Keep items concise (1-2 lines preferred)
- Add blank line before and after list
- Use ordered lists for sequences, unordered for sets

### Code Blocks

#### Fenced Code Blocks
````markdown
```python
def hello_world():
    print("Hello, World!")
```
````

#### Inline Code
```markdown
Use the `pip install` command to install packages.
```

**Best Practices**:
- Always specify language for syntax highlighting
- Keep code examples under 30 lines
- Add comments for non-obvious logic
- Test code examples before documenting
- Use inline code for commands, variables, file names

### Links

#### Inline Links
```markdown
[Link text](https://example.com)
```

#### Reference Links
```markdown
[Link text][ref]

[ref]: https://example.com
```

#### Internal Links
```markdown
[Architecture Overview](./Architecture/100_system_architecture_overview.md)
[Section Link](#heading-name)
```

**Best Practices**:
- Use descriptive link text (not "click here")
- Prefer relative paths for internal links
- Check all links periodically for rot
- Use reference style for repeated links

### Tables

```markdown
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Value 1  | Value 2  | Value 3  |
| Value 4  | Value 5  | Value 6  |
```

**Alignment**:
```markdown
| Left-aligned | Center-aligned | Right-aligned |
|:-------------|:--------------:|--------------:|
| Text         | Text           | Text          |
```

**Best Practices**:
- Use tables for structured data only
- Keep tables simple (max 5 columns)
- Use headers for all columns
- Align columns for readability in source
- Consider lists for simple key-value pairs

### Emphasis

```markdown
**Bold text** for strong emphasis
*Italic text* for mild emphasis
~~Strikethrough~~ for deprecated content
`Code text` for technical terms
```

**Best Practices**:
- Don't overuse bold (reduce impact)
- Use italic sparingly
- Prefer code formatting for technical terms
- Avoid underlining (reserved for links)

### Block Quotes

```markdown
> This is a quote
> spanning multiple lines
```

**Use for**:
- Quotes from sources
- Important callouts
- Extracted content references

### Horizontal Rules

```markdown
---
```

**Use sparingly** - usually indicates document should be split

## Quality Checklist

### Structure
- [ ] Document starts with metadata header
- [ ] Single H1 heading after metadata
- [ ] Logical heading hierarchy (no skipped levels)
- [ ] Table of contents for docs over 200 lines
- [ ] Sections are well-organized and scannable

### Content
- [ ] Purpose is clear from first paragraph
- [ ] Principles stated before details
- [ ] Examples follow explanations
- [ ] Technical terms defined on first use
- [ ] Assumptions explicitly stated
- [ ] Cross-references to related docs

### Formatting
- [ ] Passes markdownlint validation
- [ ] Consistent list styles throughout
- [ ] Code blocks have language specified
- [ ] Tables are properly formatted
- [ ] Links are descriptive and working
- [ ] Images have alt text
- [ ] No trailing whitespace

### Technical Accuracy
- [ ] Code examples are tested
- [ ] Commands are correct and current
- [ ] Version numbers are accurate
- [ ] Links point to correct resources
- [ ] Diagrams match current architecture

### Maintainability
- [ ] Review date is set
- [ ] No duplicated content
- [ ] Information is in correct document
- [ ] File follows naming convention
- [ ] Document is in correct directory

### Accessibility
- [ ] Headings provide document structure
- [ ] Lists use proper markup
- [ ] Images have descriptive alt text
- [ ] Links are descriptive (not "click here")
- [ ] Tables have headers
- [ ] Color is not only means of conveying info

## Common Issues and Fixes

### Issue: Heading Hierarchy Broken

**Problem**:
```markdown
# Main Heading
### Subheading (skipped H2)
```

**Fix**:
```markdown
# Main Heading
## Subheading
```

### Issue: Inconsistent List Markers

**Problem**:
```markdown
* Item 1
- Item 2
+ Item 3
```

**Fix**:
```markdown
- Item 1
- Item 2
- Item 3
```

### Issue: No Blank Lines Around Elements

**Problem**:
```markdown
# Heading
Paragraph
- List item
```

**Fix**:
```markdown
# Heading

Paragraph

- List item
```

### Issue: Long Lines Without Breaks

**Problem**: Single paragraph with 500+ character line

**Fix**: Use semantic line breaks (break at sentence or clause boundaries):
```markdown
This is the first sentence.
This is the second sentence.
This is the third sentence.
```

### Issue: Bare URLs Instead of Links

**Problem**:
```markdown
See https://example.com for more info
```

**Fix**:
```markdown
See [the documentation](https://example.com) for more info
```

### Issue: Missing Code Language

**Problem**:
````markdown
```
function example() {}
```
````

**Fix**:
````markdown
```javascript
function example() {}
```
````

### Issue: Tables Not Aligned

**Problem**:
```markdown
| Column | Value |
|---|---|
| A | 1 |
| B | 2 |
```

**Fix**:
```markdown
| Column | Value |
|--------|-------|
| A      | 1     |
| B      | 2     |
```

### Issue: Multiple H1 Headings

**Problem**:
```markdown
# Introduction
Content
# Architecture
Content
```

**Fix**:
```markdown
# Document Title

## Introduction
Content

## Architecture
Content
```

## Automation

### Pre-commit Hook

Create `.git/hooks/pre-commit`:
```bash
#!/bin/bash
markdownlint '**/*.md' --config .markdownlint.json
```

### CI/CD Integration

```yaml
# .github/workflows/docs.yml
name: Documentation Quality

on: [pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Lint Markdown
        uses: nosborn/github-action-markdown-cli@v3.0.1
        with:
          files: .
          config_file: .markdownlint.json
```

### VS Code Settings

Add to `.vscode/settings.json`:
```json
{
  "markdownlint.config": {
    "default": true,
    "MD013": false
  },
  "[markdown]": {
    "editor.formatOnSave": true,
    "editor.rulers": [80],
    "files.trimTrailingWhitespace": true
  }
}
```

## Maintenance

### Regular Reviews
- **Weekly**: Run linter on all docs
- **Monthly**: Check for broken links
- **Quarterly**: Review and update quality standards

### Continuous Improvement
- Track common linting errors
- Update rules based on team feedback
- Add new patterns to style guide
- Share learning in team meetings

## Resources

- [Markdownlint Rules](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)
- [CommonMark Spec](https://spec.commonmark.org/)
- [GitHub Flavored Markdown](https://github.github.com/gfm/)
- [Markdown Guide](https://www.markdownguide.org/)
