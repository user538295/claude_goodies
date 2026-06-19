# Check Types Reference

Detailed patterns and examples for each check category.

## 1. Terminology Consistency

### Variant Detection

**Pattern**: Same concept, different surface forms.

```
Examples:
- "API" vs "api" vs "Api" (case variants)
- "REST API" vs "RESTful API" vs "REST endpoint" (synonym variants)
- "config" vs "configuration" vs "settings" (abbreviation variants)
- "frontend" vs "front-end" vs "front end" (spacing variants)
- "JavaScript" vs "Javascript" vs "JS" (name variants)
```

**Detection approach**:
1. Build glossary from master documents (preferred terms)
2. Track all term occurrences with file:line locations
3. Flag when follower uses variant instead of preferred term

**Severity**:
- Warning: Using common variant (e.g., "config" instead of "configuration")
- Critical: Using variant that changes meaning in context

### Undefined Terms

**Pattern**: Technical terms used without definition, especially on first use.

```
Flags:
- Acronyms not expanded on first use (e.g., "JWT" without "JSON Web Token")
- Domain-specific terms without explanation
- Internal codenames without context
```

**Severity**: Info (documentation quality concern)

### Conflicting Definitions

**Pattern**: Same term defined differently in different documents.

```
Example:
- README.md: "A 'session' lasts 30 minutes of inactivity"
- API.md: "Sessions expire after 1 hour"
```

**Severity**: Critical (semantic contradiction)

---

## 2. Formatting Standards

### Heading Hierarchy

**Rules**:
- Document should start with H1 (`#`)
- No skipped levels (H1 → H3 without H2)
- Consistent style (ATX `#` vs Setext underlines)

**Pattern detection**:
```python
# Check for skipped levels
prev_level = 0
for heading in headings:
    if heading.level > prev_level + 1:
        flag_error(f"Skipped from H{prev_level} to H{heading.level}")
    prev_level = heading.level
```

**Severity**: Warning
**Auto-fixable**: Yes (can adjust heading levels)

### Code Block Styles

**Rules**:
- Consistent fence style (``` vs ~~~)
- Language specifier present for syntax highlighting
- Indented code blocks vs fenced (pick one style)

**Flags**:
```markdown
<!-- Inconsistent: mixing fenced and indented -->
```python
code here
```

    also code here  <!-- indented style -->
```

**Severity**: Warning
**Auto-fixable**: Yes (normalize to fenced with language)

### List Format Consistency

**Rules**:
- Consistent markers (- vs * vs +)
- Consistent spacing after marker
- Ordered lists: consistent numbering (1. 2. 3. vs 1. 1. 1.)

**Severity**: Warning
**Auto-fixable**: Yes

---

## 3. Cross-Reference Validity

### Broken Internal Links

**Pattern**: Links to files or sections that don't exist.

```markdown
[Setup guide](./setup.md)           <!-- setup.md doesn't exist -->
[See authentication](#auth)          <!-- #auth anchor doesn't exist -->
[API docs](../api/reference.md)      <!-- path doesn't resolve -->
```

**Detection**:
1. Extract all internal links (relative paths, anchor references)
2. Build map of all existing files and anchors
3. Flag links that don't resolve

**Severity**: Critical
**Auto-fixable**: No (requires human decision)

### Dead Anchors

**Pattern**: Link to anchor (`#section-name`) that doesn't exist in target.

```markdown
<!-- In file A -->
See [configuration options](./config.md#advanced-options)

<!-- In config.md - heading is actually "Advanced Settings" -->
## Advanced Settings  <!-- anchor is #advanced-settings, not #advanced-options -->
```

**Detection**:
- Parse all headings to build anchor map
- GitHub-style anchor generation: lowercase, spaces→hyphens, remove special chars
- Check all anchor references against map

**Severity**: Critical

### Missing Images

**Pattern**: Image references to non-existent files.

```markdown
![Architecture](./images/arch.png)   <!-- arch.png doesn't exist -->
![Logo](../assets/logo.svg)          <!-- path doesn't resolve -->
```

**Severity**: Critical

### External Link Issues

**Pattern**: External URLs that may be problematic.

```
Checks:
- HTTP instead of HTTPS (security)
- Known dead domains
- Placeholder URLs (example.com in production docs)
```

**Severity**: Warning (can't verify without network access)

---

## 4. Voice & Tone

### Formal/Informal Mixing

**Informal markers**:
```
- Contractions: "don't", "can't", "won't", "it's"
- Casual phrases: "pretty much", "kind of", "a lot of"
- Exclamations: "!", "awesome", "cool"
- Slang: "gonna", "wanna", "gotta"
```

**Formal markers**:
```
- Full forms: "do not", "cannot", "will not"
- Technical language: "utilize", "implement", "configure"
- Passive constructions: "is configured", "should be implemented"
```

**Detection**: Flag documents that mix both styles significantly.

**Severity**: Warning

### Passive Voice Overuse

**Pattern**: Excessive use of passive constructions.

```markdown
<!-- Passive -->
The configuration file is created by the system.
The API should be called with authentication.

<!-- Active (preferred for docs) -->
The system creates the configuration file.
Call the API with authentication.
```

**Detection**: Count passive constructions, flag if >30% of sentences.

**Severity**: Info

### Person Consistency

**Pattern**: Mixing addressing styles within a document.

```markdown
<!-- Inconsistent -->
You can configure the settings.     <!-- 2nd person -->
Users should then restart.          <!-- 3rd person -->
We recommend using v2.              <!-- 1st person plural -->
```

**Recommended**: Pick one style per document type:
- Tutorials: "you" (2nd person)
- API reference: "the user" or "the client" (3rd person)
- Company docs: "we" (1st person plural)

**Severity**: Warning

---

## 5. Technical Accuracy

### Version Mismatches

**Pattern**: Follower doc has different version than master.

```markdown
<!-- Master (README.md) -->
Current version: 3.4.0
Requires Python 3.9+

<!-- Follower (install.md) -->
Install version 3.2.1              <!-- CRITICAL: outdated -->
Works with Python 3.7+             <!-- CRITICAL: wrong requirement -->
```

**Detection**:
1. Extract all version patterns from masters
2. Store as facts: `{component: "main", version: "3.4.0"}`
3. Check followers for same components, compare versions

**Version patterns**:
```regex
v?\d+\.\d+(\.\d+)?           # v1.2.3, 1.2.3, 1.2
\d+\.\d+\.\d+(-\w+)?         # 1.2.3-beta
[><=~^]?\d+\.\d+             # >=1.2, ~1.2, ^1.2
\w+ \d+(\.\d+)?[+]?          # Python 3.9+, Node 18+
```

**Severity**: Critical

### Deprecated Features

**Pattern**: References to features marked deprecated in master.

```markdown
<!-- Master -->
**Deprecated**: The `oldMethod()` is deprecated. Use `newMethod()` instead.

<!-- Follower still references -->
Call `oldMethod()` to initialize.   <!-- WARNING: deprecated -->
```

**Detection**: Build deprecation list from master, scan followers.

**Severity**: Warning

### Numeric Spec Drift

**Pattern**: Specifications that have drifted from master values.

```markdown
<!-- Master -->
Maximum file size: 10MB
Timeout: 30 seconds
Rate limit: 100 requests/minute

<!-- Follower -->
Files up to 5MB are supported       <!-- CRITICAL: different limit -->
Timeout after 60 seconds            <!-- CRITICAL: different value -->
```

**Detection**: Extract numeric specifications with context, compare values.

**Severity**: Critical

---

## 6. Content Consistency (Contradiction Detection)

**For the complete claim-based system, see `content-consistency.md`.**

This section provides quick reference for common contradiction patterns.

### Claim-Based Model

Every checkable statement is a **claim**: `{subject, predicate, object, scope}`

Extract claims from:
- Prose paragraphs (explicit)
- Code blocks (implicit)
- Tables (structured)
- Lists (enumerated)

### Contradiction Categories

#### 6.1 Direct Contradiction

Same subject, opposite predicates.

```markdown
Master: "The API requires authentication"
Follower: "The API does not require authentication"
```

**Detection**: `predicate` vs `not_predicate` for same subject
**Severity**: Critical

#### 6.2 Value Mismatch

Same subject and predicate, different values.

```markdown
Master: "Default timeout is 30 seconds"
Follower: "Timeout defaults to 60 seconds"
```

**Detection**: Same `{subject, predicate}`, different `object`
**Severity**: Critical

#### 6.3 Tool/Technology Conflict

Mutually exclusive tools for same purpose.

```markdown
Master: "Install dependencies with npm"
Follower: "Run yarn install to set up dependencies"
```

**Known mutually exclusive sets:**
- Package managers: npm, yarn, pnpm, bun
- Databases: PostgreSQL, MySQL, SQLite, MongoDB
- Python envs: pip, conda, poetry, pipenv

**Severity**: Critical

#### 6.4 Implicit Contradiction

Code/examples contradict prose.

```markdown
Master (prose): "We use PostgreSQL for all data storage"
Follower (code): `mysql -u root -p database`
```

**Detection**: Implicit claim from code conflicts with explicit master claim
**Severity**: Critical (flagged as implicit)

#### 6.5 Sequence Conflict

Different order for procedures.

```markdown
Master: "1. Install  2. Configure  3. Start"
Follower: "1. Configure  2. Install  3. Run"
```

**Detection**: Same topic, different step sequence
**Severity**: Warning (order may/may not matter)

#### 6.6 Scope Ambiguity

Follower lacks scope qualifier present in master.

```markdown
Master: "Production uses PostgreSQL. Development can use SQLite."
Follower: "Connect to your SQLite database"
```

**Detection**: Follower matches scoped master claim but lacks scope
**Severity**: Warning with note "Verify intended scope"

#### 6.7 Scope Expansion

**Pattern**: Follower covers topics/solutions not present in masters.

**Detection**: Semantic comparison (not keyword matching). The agent asks:
- What topics does this follower discuss?
- Are these topics covered in masters?
- Does follower introduce new options within covered topics?

**This is NOT a contradiction** - masters don't forbid it. But it signals 
the follower goes beyond defined scope.

**Severity**: WARNING

**ID Prefix**: SE (Scope Expansion)

### Confidence Scoring

| Confidence | Reporting Action |
|------------|------------------|
| ≥90% | Report as finding |
| 70-89% | Report with "Possible:" prefix |
| 50-69% | Add to "Review Suggested" section |
| <50% | Do not report |

### Quick Detection Patterns

**Tool claims** (from code blocks):
```
npm/yarn/pnpm → JavaScript package manager
pip/conda/poetry → Python package manager
mysql/psql/sqlite3 → Database client
docker/podman → Container runtime
```

**Config claims** (from YAML/JSON/TOML):
```
port: N → port configuration
timeout: N → timeout setting
host: X → host configuration
```

**Version claims**:
```
v?\d+\.\d+(\.\d+)? → version number
>=\d+, >\d+, ~\d+, ^\d+ → version constraint
requires X Y+ → minimum requirement
```

---

## 7. Duplicate Content

### Copy-Paste Detection

**Pattern**: Identical or near-identical paragraphs across documents.

```markdown
<!-- Doc A -->
To configure logging, edit the `config.yaml` file and set the `log_level` 
parameter to one of: DEBUG, INFO, WARNING, ERROR.

<!-- Doc B (exact copy) -->
To configure logging, edit the `config.yaml` file and set the `log_level` 
parameter to one of: DEBUG, INFO, WARNING, ERROR.
```

**Risk**: When one is updated, the other becomes stale.

**Detection**:
1. Hash paragraphs (normalized: lowercase, collapsed whitespace)
2. Flag exact matches across different files
3. For near-matches: compute similarity score

**Severity**: Info

### Near-Duplicate Paragraphs

**Pattern**: Similar content with minor variations.

```markdown
<!-- Doc A -->
Configure the database connection by setting DB_HOST, DB_PORT, and DB_NAME 
in your environment variables.

<!-- Doc B -->
Set up database connectivity using the DB_HOST, DB_PORT, and DB_NAME 
environment variables.
```

**Detection**: Similarity threshold (e.g., >80% token overlap).

**Severity**: Info (potential maintenance burden)

---

## Severity Definitions

| Level | Meaning | Action |
|-------|---------|--------|
| **Critical** | Factual error, broken functionality, or contradiction | Must fix before publish |
| **Warning** | Style issue, potential confusion, or quality concern | Should fix |
| **Info** | Minor suggestion, observation, or potential improvement | Consider fixing |

## Auto-Fix Capabilities

| Check | Auto-fixable | Fix Description |
|-------|--------------|-----------------|
| Terminology variants | Yes | Replace with preferred term |
| Heading hierarchy | Yes | Adjust heading levels |
| Code block style | Yes | Normalize to fenced + language |
| List markers | Yes | Standardize to `-` |
| Contractions | Yes | Expand to full forms |
| Version numbers | Partial | Update with confirmation |
| Broken links | No | Requires human decision |
| Contradictions | No | Requires human decision |
