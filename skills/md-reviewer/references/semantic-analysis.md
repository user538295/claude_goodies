# Semantic Analysis Reference

Techniques for semantic comparison, contradiction detection, and intelligent document analysis.

**For claim extraction and content consistency checking, see `content-consistency.md`** which provides:
- Claim model (subject-predicate-object-scope)
- 8 claim categories with extraction patterns
- Contradiction detection algorithms
- Confidence scoring system
- Mutual exclusion rules

This document covers supporting analysis techniques.

## 1. Master Document Extraction

### Structured Extraction Format

Extract key information from masters into structured format for comparison:

```json
{
  "document": "README.md",
  "extracted_at": "2025-01-15T10:30:00Z",
  
  "versions": [
    {"component": "main", "version": "3.4.0", "line": 8, "context": "Current version: 3.4.0"},
    {"component": "python", "version": "3.9+", "line": 12, "context": "Requires Python 3.9+"}
  ],
  
  "terminology": [
    {"term": "API endpoint", "context": "REST API endpoint for user data", "line": 45},
    {"term": "configuration file", "variants": ["config file", "settings"], "line": 67}
  ],
  
  "facts": [
    {"topic": "database", "claim": "PostgreSQL", "line": 102, "quote": "All data is stored in PostgreSQL"},
    {"topic": "authentication", "claim": "JWT tokens", "line": 89, "quote": "Authentication uses JWT tokens"}
  ],
  
  "instructions": [
    {
      "topic": "installation",
      "steps": ["npm install", "copy .env.example to .env", "npm start"],
      "lines": [23, 24, 25]
    }
  ],
  
  "anchors": ["#installation", "#configuration", "#api-reference", "#troubleshooting"]
}
```

### Extraction Patterns

**Version Extraction**:
```
Patterns to match:
- "version X.Y.Z" / "Version: X.Y.Z" / "v X.Y.Z"
- "requires <package> X.Y+" / "<package> >= X.Y"
- "@X.Y.Z" (npm style)
- "X.Y.Z-<tag>" (semver with prerelease)

Context capture: Include surrounding sentence for disambiguation
```

**Fact Extraction**:
```
Look for declarative statements:
- "X uses Y" / "X is Y" / "X requires Y"
- "We use X for Y"
- "The system stores/processes/handles X"
- Specification statements: "Maximum X is Y"
```

**Instruction Extraction**:
```
Look for:
- Numbered lists following headings like "Installation", "Setup", "Getting Started"
- Imperative sentences: "Run X", "Configure Y", "Set Z"
- Code blocks following instruction text
```

---

## 2. Contradiction Detection

### Types of Contradictions

**1. Direct Negation**
```
Doc A: "The API requires authentication"
Doc B: "The API does not require authentication"
```
Pattern: Same subject + opposite predicate

**2. Conflicting Values**
```
Doc A: "Timeout is 30 seconds"
Doc B: "Timeout is 60 seconds"
```
Pattern: Same attribute + different values

**3. Incompatible Methods**
```
Doc A: "Install using npm"
Doc B: "Install using yarn"
```
Pattern: Same action + mutually exclusive approaches

**4. Contradictory Existence**
```
Doc A: "The config file is required"
Doc B: "The config file is optional"
```
Pattern: Same entity + conflicting properties

### Detection Algorithm

```
For each extracted fact from followers:
  1. Find matching topic in master_facts
  2. Compare claims:
     - If exact match: OK
     - If semantic opposite: CRITICAL contradiction
     - If different value for same attribute: CRITICAL mismatch
     - If partially overlapping: WARNING (needs human review)
  3. Log finding with both sources
```

### Semantic Similarity Thresholds

```
Exact match:      100% - No issue
High similarity:  >90% - Likely OK, might be paraphrase
Medium:           70-90% - Review for subtle differences
Low:              <70% - Likely different claims, check manually
```

---

## 3. Terminology Variant Recognition

### Variant Categories

**Case Variants**:
```
API, Api, api, API's
JavaScript, Javascript, JAVASCRIPT
PostgreSQL, Postgresql, postgresql, Postgres
```

**Abbreviation Variants**:
```
configuration ↔ config ↔ conf
repository ↔ repo
environment ↔ env
documentation ↔ docs
```

**Synonym Variants** (context-dependent):
```
REST API ↔ API endpoint ↔ endpoint ↔ service
settings ↔ configuration ↔ options ↔ preferences
error ↔ exception ↔ fault ↔ failure
```

**Compound Variants**:
```
frontend ↔ front-end ↔ front end
setup ↔ set-up ↔ set up
login ↔ log-in ↔ log in
```

### Building the Glossary

```markdown
# Terminology Glossary

## From Masters

| Preferred | Variants | Context | Source |
|-----------|----------|---------|--------|
| API endpoint | REST API, endpoint | HTTP interface | README.md:45 |
| configuration file | config, settings | `.env` file | README.md:67 |

## Discovered Variants

| Term | Found In | Preferred Equivalent |
|------|----------|---------------------|
| REST API | docs/api.md:23 | API endpoint |
| config | docs/install.md:45 | configuration file |
```

### Normalization Rules

```python
def normalize_term(term):
    """Normalize for comparison"""
    # Lowercase
    normalized = term.lower()
    # Remove possessives
    normalized = normalized.replace("'s", "")
    # Collapse whitespace
    normalized = " ".join(normalized.split())
    # Common substitutions
    substitutions = {
        "config": "configuration",
        "repo": "repository", 
        "env": "environment",
        "docs": "documentation"
    }
    for short, full in substitutions.items():
        if normalized == short:
            normalized = full
    return normalized
```

---

## 4. Duplicate Content Detection

### Exact Duplicate Detection

```python
def find_exact_duplicates(documents):
    """Hash paragraphs to find exact copies"""
    paragraph_hashes = {}
    duplicates = []
    
    for doc in documents:
        for i, paragraph in enumerate(doc.paragraphs):
            # Normalize: lowercase, collapse whitespace
            normalized = normalize_paragraph(paragraph)
            hash_key = hash(normalized)
            
            if hash_key in paragraph_hashes:
                duplicates.append({
                    "original": paragraph_hashes[hash_key],
                    "duplicate": {"file": doc.path, "line": i}
                })
            else:
                paragraph_hashes[hash_key] = {"file": doc.path, "line": i}
    
    return duplicates
```

### Near-Duplicate Detection

```python
def similarity_score(text_a, text_b):
    """Calculate token-based similarity"""
    tokens_a = set(tokenize(text_a))
    tokens_b = set(tokenize(text_b))
    
    intersection = tokens_a & tokens_b
    union = tokens_a | tokens_b
    
    return len(intersection) / len(union)  # Jaccard similarity

def find_near_duplicates(documents, threshold=0.8):
    """Find paragraphs with >80% token overlap"""
    candidates = []
    
    for doc_a in documents:
        for doc_b in documents:
            if doc_a == doc_b:
                continue
            for para_a in doc_a.paragraphs:
                for para_b in doc_b.paragraphs:
                    score = similarity_score(para_a.text, para_b.text)
                    if score >= threshold:
                        candidates.append({
                            "file_a": doc_a.path,
                            "file_b": doc_b.path,
                            "similarity": score
                        })
    
    return candidates
```

### Minimum Duplicate Size

- Ignore duplicates under 50 characters (likely common phrases)
- Focus on paragraphs of 2+ sentences
- Code blocks: exact match only (formatting matters)

---

## 5. Cross-Reference Analysis

### Link Extraction

```python
def extract_links(markdown_content):
    """Extract all link types"""
    links = []
    
    # Standard markdown links: [text](url)
    md_links = re.findall(r'\[([^\]]+)\]\(([^)]+)\)', content)
    
    # Reference-style links: [text][ref] ... [ref]: url
    ref_links = re.findall(r'\[([^\]]+)\]\[([^\]]*)\]', content)
    ref_defs = re.findall(r'^\[([^\]]+)\]:\s*(.+)$', content, re.MULTILINE)
    
    # Autolinks: <url>
    auto_links = re.findall(r'<(https?://[^>]+)>', content)
    
    # Image links: ![alt](url)
    images = re.findall(r'!\[([^\]]*)\]\(([^)]+)\)', content)
    
    return {
        "inline": md_links,
        "reference": (ref_links, ref_defs),
        "auto": auto_links,
        "images": images
    }
```

### Anchor Generation

```python
def heading_to_anchor(heading_text):
    """Convert heading to GitHub-style anchor"""
    # Lowercase
    anchor = heading_text.lower()
    # Remove special characters except hyphens and spaces
    anchor = re.sub(r'[^\w\s-]', '', anchor)
    # Replace spaces with hyphens
    anchor = re.sub(r'\s+', '-', anchor)
    # Remove leading/trailing hyphens
    anchor = anchor.strip('-')
    return f"#{anchor}"

# Examples:
# "Getting Started" → "#getting-started"
# "API Reference (v2)" → "#api-reference-v2"
# "What's New?" → "#whats-new"
```

### Link Resolution

```python
def resolve_link(link_target, source_file, file_map):
    """Resolve relative link to absolute path"""
    if link_target.startswith('http'):
        return {"type": "external", "url": link_target}
    
    if link_target.startswith('#'):
        return {"type": "anchor", "file": source_file, "anchor": link_target}
    
    # Split file path and anchor
    if '#' in link_target:
        file_path, anchor = link_target.split('#', 1)
        anchor = f"#{anchor}"
    else:
        file_path = link_target
        anchor = None
    
    # Resolve relative path
    source_dir = os.path.dirname(source_file)
    resolved = os.path.normpath(os.path.join(source_dir, file_path))
    
    return {
        "type": "internal",
        "file": resolved,
        "anchor": anchor,
        "exists": resolved in file_map
    }
```

---

## 6. Voice and Tone Analysis

### Formality Indicators

**Informal Markers** (score -1 each):
```
- Contractions: can't, don't, won't, it's, we're
- Casual intensifiers: really, very, pretty, super
- Colloquialisms: gonna, wanna, gotta, kinda
- Exclamation marks
- First person singular: I, me, my
- Questions to reader: "Right?", "See?"
```

**Formal Markers** (score +1 each):
```
- Full verb forms: cannot, do not, will not
- Technical vocabulary
- Passive voice
- Third person references
- Longer sentences (>20 words)
- Latin abbreviations: e.g., i.e., etc.
```

**Formality Score**:
```
Score = (formal_markers - informal_markers) / total_markers
Range: -1 (very informal) to +1 (very formal)
Mixed: -0.3 to +0.3 indicates inconsistent tone
```

### Person Consistency

```python
def detect_person(text):
    """Detect predominant grammatical person"""
    first_singular = len(re.findall(r'\b(I|me|my|mine)\b', text, re.I))
    first_plural = len(re.findall(r'\b(we|us|our|ours)\b', text, re.I))
    second = len(re.findall(r'\b(you|your|yours)\b', text, re.I))
    third = len(re.findall(r'\b(user|users|they|their|client|developer)\b', text, re.I))
    
    counts = {
        "first_singular": first_singular,
        "first_plural": first_plural,
        "second": second,
        "third": third
    }
    
    # Flag if multiple persons are significant (>20% each)
    total = sum(counts.values())
    if total == 0:
        return "neutral"
    
    significant = [k for k, v in counts.items() if v/total > 0.2]
    if len(significant) > 1:
        return "mixed"  # Warning: inconsistent
    
    return max(counts, key=counts.get)
```

---

## 7. Batch Processing Strategy

### Context Management

For 50+ file reviews, manage context efficiently:

```
Phase 2 (Master Analysis):
  - Full content of each master document
  - Extract to structured format
  - Store in _review/master_facts.md

Phase 3 (Follower Validation):
  Per batch:
    - Load: master_facts.md (structured, ~2k tokens)
    - Load: glossary.md (~500 tokens)
    - Load: 5-10 follower files (~3-5k tokens each)
    - Process batch
    - Checkpoint progress
    
Phase 4 (Cross-Document):
  - Load: cross_refs.md (link map, ~1k tokens)
  - Process link validation in batches
  - Load: all paragraphs for duplicate check (chunked)
```

### Checkpoint Format

```markdown
## File Progress
- [x] README.md (master) ✓ extracted
- [x] docs/ARCHITECTURE.md (master) ✓ extracted
- [x] docs/installation.md ✓ 3 issues
- [x] docs/quickstart.md ✓ 0 issues
- [x] docs/api/overview.md ✓ 1 issue
- [ ] docs/api/endpoints.md ← NEXT
- [ ] docs/api/authentication.md
- [ ] docs/api/errors.md
...

## Last Checkpoint
- File: docs/api/overview.md
- Time: 2025-01-15T10:45:23Z
- Batch: 3 of 10
```

### Resume Logic

```python
def find_resume_point(progress_content):
    """Find first unchecked file"""
    lines = progress_content.split('\n')
    for line in lines:
        if line.strip().startswith('- [ ]'):
            # Extract file path
            match = re.search(r'- \[ \] (.+?)(?:\s|$)', line)
            if match:
                return match.group(1)
    return None  # All complete
```
