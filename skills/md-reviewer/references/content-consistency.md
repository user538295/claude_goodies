# Content Consistency Reference

Systematic approach to detecting content inconsistencies between master and follower documents.

## Overview

Content consistency ensures that follower documents don't contradict, conflict with, or drift from master document claims. This goes beyond simple text matching to semantic understanding of what documents are actually *claiming*.

## Claim Model

Every extractable piece of information is modeled as a **claim**:

```json
{
  "id": "claim-001",
  "category": "tool",
  "subject": "database",
  "predicate": "uses",
  "object": "PostgreSQL",
  "scope": null,
  "source": {
    "file": "README.md",
    "line": 45,
    "type": "prose"
  },
  "quote": "All data is stored in PostgreSQL",
  "implicit": false,
  "confidence": 1.0
}
```

### Claim Fields

| Field | Description | Example Values |
|-------|-------------|----------------|
| `id` | Unique identifier | `claim-001`, `master-db-001` |
| `category` | Claim type (see categories below) | `tool`, `config`, `behavior` |
| `subject` | What the claim is about | `database`, `authentication`, `timeout` |
| `predicate` | The relationship/action | `uses`, `equals`, `requires`, `supports` |
| `object` | The value/target | `PostgreSQL`, `30 seconds`, `JWT` |
| `scope` | Context qualifier (if any) | `production`, `development`, `v2.0+` |
| `source` | Location in document | `{"file": "...", "line": N, "type": "..."}` |
| `quote` | Original text | Verbatim excerpt |
| `implicit` | Whether inferred vs explicit | `true` / `false` |
| `confidence` | Extraction confidence | `0.0` - `1.0` |

---

## Claim Categories

### 1. Tool/Technology Claims

What tools, technologies, or services are used.

**Extraction patterns:**
```
Explicit:
- "uses X", "built with X", "powered by X"
- "X database", "X framework", "X library"
- "install X", "requires X"
- "we chose X", "we use X"

Implicit (from code blocks):
- `npm install` → uses npm
- `pip install` → uses pip/Python
- `mysql` command → uses MySQL
- `docker-compose` → uses Docker
- Import statements → uses that library
```

**Examples:**
```markdown
<!-- Explicit claim -->
The application uses PostgreSQL for data persistence.
→ {subject: "data persistence", predicate: "uses", object: "PostgreSQL"}

<!-- Implicit claim from code -->
```bash
mysql -u root -p mydb
```
→ {subject: "database", predicate: "uses", object: "MySQL", implicit: true}
```

### 2. Version/Requirement Claims

Version numbers, minimum requirements, compatibility.

**Extraction patterns:**
```
- "version X.Y.Z", "v X.Y", "X.Y.Z"
- "requires X Y+", "minimum X Y"
- "compatible with X", "works with X"
- "X or higher", "X or later", "at least X"
- Package.json, requirements.txt, etc. in code blocks
```

**Examples:**
```markdown
<!-- Explicit -->
Requires Python 3.9 or higher.
→ {subject: "Python", predicate: "requires_minimum", object: "3.9"}

<!-- From code block -->
```json
"node": ">=18.0.0"
```
→ {subject: "node", predicate: "requires_minimum", object: "18.0.0", implicit: true}
```

### 3. Configuration Claims

Settings, parameters, defaults, limits.

**Extraction patterns:**
```
- "default X is Y", "defaults to Y"
- "set X to Y", "configure X as Y"
- "X = Y", "X: Y" (in config examples)
- "maximum X", "minimum X", "limit of X"
- "port X", "timeout X", "X connections"
```

**Examples:**
```markdown
<!-- Explicit -->
The default timeout is 30 seconds.
→ {subject: "timeout", predicate: "defaults_to", object: "30 seconds"}

<!-- From config example -->
```yaml
server:
  port: 8080
  max_connections: 100
```
→ {subject: "port", predicate: "equals", object: "8080"}
→ {subject: "max_connections", predicate: "equals", object: "100"}
```

### 4. Behavior Claims

How the system behaves, what it does/returns.

**Extraction patterns:**
```
- "returns X", "responds with X"
- "throws X", "raises X error"
- "X happens when Y", "if X then Y"
- "X triggers Y", "X causes Y"
- "automatically X", "X by default"
```

**Examples:**
```markdown
The API returns JSON for all responses.
→ {subject: "API responses", predicate: "returns", object: "JSON"}

Invalid requests throw a 400 Bad Request error.
→ {subject: "invalid requests", predicate: "throws", object: "400 Bad Request"}
```

### 5. Architecture Claims

System design, structure, patterns.

**Extraction patterns:**
```
- "X architecture", "X pattern"
- "microservices", "monolith", "serverless"
- "X communicates with Y via Z"
- "X layer", "X component"
- "REST", "GraphQL", "gRPC", "WebSocket"
```

**Examples:**
```markdown
The system follows a microservices architecture.
→ {subject: "system", predicate: "follows", object: "microservices architecture"}

Services communicate via REST APIs.
→ {subject: "services", predicate: "communicate_via", object: "REST APIs"}
```

### 6. Process/Procedure Claims

Order of operations, steps, workflows.

**Extraction patterns:**
```
- Numbered lists under "Installation", "Setup", "Getting Started"
- "first X, then Y", "after X, do Y"
- "step 1", "step 2", etc.
- "before X", "after X"
- "X followed by Y"
```

**Examples:**
```markdown
## Installation
1. Clone the repository
2. Run `npm install`
3. Copy `.env.example` to `.env`
4. Run `npm start`

→ {subject: "installation", predicate: "has_steps", object: ["clone", "npm install", "copy env", "npm start"]}
```

### 7. Recommendation Claims

Best practices, suggestions, preferred approaches.

**Extraction patterns:**
```
- "we recommend X", "recommended: X"
- "best practice", "should X"
- "prefer X over Y", "use X instead of Y"
- "ideal for X", "optimized for X"
```

**Examples:**
```markdown
We recommend using environment variables for configuration.
→ {subject: "configuration", predicate: "recommended", object: "environment variables"}
```

### 8. Limitation Claims

What is NOT supported, restrictions, constraints.

**Extraction patterns:**
```
- "does not support X", "X is not supported"
- "cannot X", "unable to X"
- "X is not available", "no X"
- "limited to X", "restricted to X"
- "except X", "excluding X"
```

**Examples:**
```markdown
The API does not support XML responses.
→ {subject: "API", predicate: "not_supports", object: "XML responses"}

File uploads are limited to 10MB.
→ {subject: "file uploads", predicate: "limited_to", object: "10MB"}
```

---

## Extraction Sources

Extract claims from ALL content types:

### 1. Prose Paragraphs

Standard text analysis for explicit statements.

```markdown
The application connects to a PostgreSQL database running on port 5432.
```

Extract:
- `{subject: "database", predicate: "uses", object: "PostgreSQL"}`
- `{subject: "database port", predicate: "equals", object: "5432"}`

### 2. Code Blocks

Analyze commands, configs, and code for implicit claims.

```bash
pip install flask gunicorn
```

Extract:
- `{subject: "package manager", predicate: "uses", object: "pip", implicit: true}`
- `{subject: "dependencies", predicate: "includes", object: "flask", implicit: true}`
- `{subject: "dependencies", predicate: "includes", object: "gunicorn", implicit: true}`

```yaml
database:
  host: localhost
  port: 3306
  engine: mysql
```

Extract:
- `{subject: "database engine", predicate: "uses", object: "mysql", implicit: true}`
- `{subject: "database port", predicate: "equals", object: "3306", implicit: true}`

### 3. Tables

Parse structured data for claims.

```markdown
| Setting | Default | Description |
|---------|---------|-------------|
| timeout | 30s | Request timeout |
| retries | 3 | Max retry attempts |
```

Extract:
- `{subject: "timeout", predicate: "defaults_to", object: "30s"}`
- `{subject: "retries", predicate: "defaults_to", object: "3"}`

### 4. Lists

Both ordered (procedures) and unordered (features/options).

```markdown
Supported databases:
- PostgreSQL
- MySQL
- SQLite (development only)
```

Extract:
- `{subject: "databases", predicate: "supports", object: "PostgreSQL"}`
- `{subject: "databases", predicate: "supports", object: "MySQL"}`
- `{subject: "databases", predicate: "supports", object: "SQLite", scope: "development"}`

---

## Contradiction Detection

### Contradiction Types

#### 1. Direct Contradiction

Same subject, opposite claims.

```
Master: "The API requires authentication"
Follower: "The API does not require authentication"
```

Detection: `predicate` vs `not_predicate` for same subject.

**Severity: CRITICAL**

#### 2. Value Mismatch

Same subject and predicate, different values.

```
Master: "Default timeout is 30 seconds"
Follower: "Set timeout to 60 seconds by default"
```

Detection: Same `subject` + `predicate`, different `object`.

**Severity: CRITICAL**

#### 3. Tool/Technology Conflict

Mutually exclusive tools for same purpose.

```
Master: "Install dependencies with npm"
Follower: "Run yarn install to get dependencies"
```

Detection: Same `subject` (dependency installation), conflicting tools (npm vs yarn).

**Severity: CRITICAL** (for same project context)

#### 4. Implicit Contradiction

Code/examples contradict prose.

```
Master (prose): "We use PostgreSQL for all data storage"
Follower (code): `mysql -u root -p`
```

Detection: Implicit claim from code conflicts with explicit master claim.

**Severity: CRITICAL** (with note about implicit detection)

#### 5. Sequence Conflict

Different order for same procedure.

```
Master: "1. Install dependencies  2. Configure environment  3. Start server"
Follower: "1. Configure environment  2. Install dependencies  3. Start"
```

Detection: Same procedure topic, different step order.

**Severity: WARNING** (order may or may not matter)

#### 6. Scope Ambiguity

Claims that may or may not conflict depending on context.

```
Master: "Production uses PostgreSQL. Development can use SQLite."
Follower: "Connect to your SQLite database"
```

Detection: Follower claim matches master scoped claim, but follower has no scope.

**Severity: WARNING** with note "Verify intended scope (development vs production)"

#### 7 Scope Expansion (Semantic Check)

**This check uses semantic understanding, not keyword matching.**

When validating each follower, the agent must ask:

> "Does this follower document introduce topics, solutions, methods, 
> or approaches that are NOT covered in ANY master document?"

**Comparison Framework**:
```
For the current follower, identify:
1. TOPICS discussed (what domains/areas does it cover?)
2. SOLUTIONS mentioned (what specific technologies/methods?)
3. APPROACHES described (what ways of doing things?)

Then check against masters:
- Is this topic mentioned in masters? 
- If yes, is this specific solution/approach mentioned?
- If no, this is SCOPE EXPANSION → WARNING
```

**Severity**: WARNING

**Rationale**: Masters define the "official scope" of the project. Followers 
that go beyond this scope might be:
- Documenting unofficial features
- Out of date (feature was removed)
- Covering edge cases masters forgot
- Simply wrong

All cases deserve human review, hence WARNING not CRITICAL.

**Recording Format**:
```json
{
  "id": "SE-001",
  "severity": "warning",
  "category": "scope_expansion",
  "type": "unmentioned_concept",
  "line": 45,
  "message": "Follower introduces 'on-premise deployment' but masters only discuss cloud deployment",
  "follower_topic": "deployment method",
  "follower_value": "on-premise",
  "master_coverage": "Masters mention: AWS, cloud, ECS. No on-premise references.",
  "recommendation": "Verify if on-premise deployment is officially supported"
}
```

**Examples**:

| Masters Say | Follower Says | Finding |
|-------------|---------------|---------|
| "Deploy to AWS cloud" | "For on-premise, install locally" | ⚠️ SE: deployment scope expansion |
| "Uses PostgreSQL" | "Configure MongoDB connection" | ⚠️ SE: database scope expansion |
| "REST API endpoints" | "GraphQL schema definition" | ⚠️ SE: API style scope expansion |
| (no mobile content) | "iOS app setup guide" | ⚠️ SE: platform scope expansion |
| "English documentation" | "Magyar nyelvű útmutató" | ⚠️ SE: language scope expansion |

**Key Principle**: The agent uses its own semantic understanding to detect 
scope expansion. No hardcoded keyword lists - this works universally across 
languages and domains.

---

## Matching Algorithm

```python
def check_consistency(master_claims, follower_claims):
    findings = []
    
    for f_claim in follower_claims:
        # Find related master claims (same subject area)
        related = find_related_claims(f_claim, master_claims)
        
        if not related:
            # No master claim about this subject - might be OK
            continue
        
        for m_claim in related:
            result = compare_claims(m_claim, f_claim)
            
            if result.type == "match":
                continue  # Consistent
            
            elif result.type == "contradiction":
                findings.append({
                    "severity": "CRITICAL",
                    "type": result.subtype,
                    "master": m_claim,
                    "follower": f_claim,
                    "confidence": result.confidence
                })
            
            elif result.type == "possible_conflict":
                findings.append({
                    "severity": "WARNING",
                    "type": result.subtype,
                    "master": m_claim,
                    "follower": f_claim,
                    "confidence": result.confidence,
                    "note": result.note
                })
    
    return findings
```

### Subject Matching

Subjects match if they refer to the same concept:

```python
def subjects_match(subj_a, subj_b):
    # Exact match
    if normalize(subj_a) == normalize(subj_b):
        return 1.0
    
    # Synonym match
    if are_synonyms(subj_a, subj_b):
        return 0.9
    
    # Hierarchical match (e.g., "database" matches "PostgreSQL database")
    if is_subset(subj_a, subj_b) or is_subset(subj_b, subj_a):
        return 0.8
    
    # Partial word overlap
    overlap = word_overlap(subj_a, subj_b)
    if overlap > 0.5:
        return overlap * 0.7
    
    return 0.0
```

### Predicate Comparison

```python
OPPOSITE_PREDICATES = {
    "uses": "not_uses",
    "supports": "not_supports",
    "requires": "not_requires",
    "enables": "disables",
    "allows": "forbids",
    "includes": "excludes",
}

EQUIVALENT_PREDICATES = {
    "uses": ["utilizes", "employs", "runs_on", "built_with"],
    "requires": ["needs", "depends_on", "must_have"],
    "defaults_to": ["default_is", "default_value"],
}

def predicates_conflict(pred_a, pred_b):
    # Direct opposites
    if OPPOSITE_PREDICATES.get(pred_a) == pred_b:
        return True
    if OPPOSITE_PREDICATES.get(pred_b) == pred_a:
        return True
    return False

def predicates_equivalent(pred_a, pred_b):
    if pred_a == pred_b:
        return True
    if pred_b in EQUIVALENT_PREDICATES.get(pred_a, []):
        return True
    if pred_a in EQUIVALENT_PREDICATES.get(pred_b, []):
        return True
    return False
```

### Object Comparison

```python
def objects_match(obj_a, obj_b, category):
    # Exact match
    if normalize(obj_a) == normalize(obj_b):
        return {"match": True, "confidence": 1.0}
    
    # Version comparison
    if category == "version":
        return compare_versions(obj_a, obj_b)
    
    # Numeric comparison
    if category == "config":
        num_a = extract_number(obj_a)
        num_b = extract_number(obj_b)
        if num_a is not None and num_b is not None:
            if num_a == num_b:
                return {"match": True, "confidence": 0.95}  # Same value, different format
            else:
                return {"match": False, "confidence": 0.95}  # Clear mismatch
    
    # Tool/technology - check for known conflicts
    if category == "tool":
        if are_mutually_exclusive(obj_a, obj_b):
            return {"match": False, "confidence": 0.9}
    
    # Fuzzy string match
    similarity = string_similarity(obj_a, obj_b)
    if similarity > 0.9:
        return {"match": True, "confidence": similarity}
    elif similarity > 0.7:
        return {"match": "unclear", "confidence": similarity}
    else:
        return {"match": False, "confidence": 1.0 - similarity}
```

---

## Confidence Scoring

### Extraction Confidence

| Source Type | Base Confidence |
|-------------|-----------------|
| Explicit prose statement | 1.0 |
| Table data | 0.95 |
| Numbered list (procedure) | 0.95 |
| Bullet list | 0.9 |
| Code block (config) | 0.85 |
| Code block (command) | 0.8 |
| Implicit from code | 0.75 |
| Inferred from context | 0.6 |

### Match Confidence

Final confidence = `extraction_confidence × match_confidence`

| Match Type | Confidence Modifier |
|------------|---------------------|
| Exact match | 1.0 |
| Normalized match | 0.95 |
| Synonym match | 0.85 |
| Partial match | 0.7 |
| Inferred match | 0.6 |

### Reporting Thresholds

| Confidence Range | Reporting |
|------------------|-----------|
| ≥ 90% | Report as finding |
| 70-89% | Report with "Possible: " prefix |
| 50-69% | Add to "Review Suggested" section |
| < 50% | Do not report (too uncertain) |

---

## Scope Handling

When claims have scope qualifiers, special handling applies:

### Scope Extraction

```markdown
"In production, we use PostgreSQL"
→ {subject: "database", predicate: "uses", object: "PostgreSQL", scope: "production"}

"For development, SQLite is recommended"
→ {subject: "database", predicate: "recommended", object: "SQLite", scope: "development"}

"Starting from v2.0, JWT is required"
→ {subject: "authentication", predicate: "requires", object: "JWT", scope: "v2.0+"}
```

### Scope Comparison Rules

| Master Scope | Follower Scope | Result |
|--------------|----------------|--------|
| None | None | Compare normally |
| "production" | "production" | Compare normally |
| "production" | "development" | No conflict (different scopes) |
| "production" | None | WARNING: scope unclear |
| None | "production" | OK if master is general |

### Scope Keywords

```python
SCOPE_INDICATORS = {
    "production": ["production", "prod", "live", "production environment"],
    "development": ["development", "dev", "local", "locally", "development environment"],
    "testing": ["test", "testing", "qa", "staging"],
    "version": [r"v\d+", r"version \d+", r"starting from", r"since v"],
}
```

---

## Output Format

### In Findings Report

```markdown
## Content Consistency Issues

### Critical Contradictions

| ID | Type | Master Claim | Follower Claim | Confidence |
|----|------|--------------|----------------|------------|
| CC-001 | Value Mismatch | timeout=30s (README:45) | timeout=60s (config.md:23) | 95% |
| CC-002 | Tool Conflict | uses npm (README:12) | yarn install (install.md:8) | 90% |
| CC-003 | Implicit | PostgreSQL (ARCH:34) | mysql command (guide.md:56) | 85% |

### Possible Conflicts (70-89% confidence)

| ID | Type | Master Claim | Follower Claim | Confidence | Note |
|----|------|--------------|----------------|------------|------|
| CC-004 | Scope Unclear | PostgreSQL/prod (README:45) | SQLite (dev.md:12) | 75% | Verify intended scope |

### Review Suggested (50-69% confidence)

| ID | Master | Follower | Confidence | Reason |
|----|--------|----------|------------|--------|
| CC-005 | "fast response" | "low latency" | 60% | May be synonyms |
```

---

## Known Mutual Exclusions

Tools/technologies that typically conflict when used for the same purpose:

```python
MUTUALLY_EXCLUSIVE = {
    "package_manager": ["npm", "yarn", "pnpm", "bun"],
    "database": ["PostgreSQL", "MySQL", "SQLite", "MongoDB", "MariaDB"],
    "python_env": ["pip", "conda", "poetry", "pipenv"],
    "container": ["Docker", "Podman", "containerd"],
    "web_framework_py": ["Flask", "Django", "FastAPI", "Tornado"],
    "web_framework_js": ["Express", "Koa", "Fastify", "Hapi"],
    "test_framework_js": ["Jest", "Mocha", "Vitest", "Jasmine"],
    "bundler_js": ["Webpack", "Rollup", "Parcel", "esbuild", "Vite"],
    "auth_method": ["JWT", "API keys", "OAuth", "Basic auth", "Session"],
}

def are_mutually_exclusive(tool_a, tool_b):
    for category, tools in MUTUALLY_EXCLUSIVE.items():
        if tool_a in tools and tool_b in tools:
            return tool_a != tool_b
    return False
```

---

## Integration with Workflow

### Phase 2: Master Analysis

Extract all claims from master documents:

```
For each master document:
  1. Parse document structure (headings, paragraphs, code blocks, tables, lists)
  2. For each content block:
     a. Identify claim patterns
     b. Extract subject-predicate-object
     c. Detect scope qualifiers
     d. Assign confidence based on source type
     e. Mark explicit vs implicit
  3. Store in master_facts.md with claim structure
  4. Update glossary with extracted terminology
```

### Phase 3: Follower Validation

Add content consistency checks:

```
For each follower document:
  1. Extract claims (same process as masters)
  2. For each claim:
     a. Find related master claims
     b. Run comparison algorithm
     c. Classify result (match/conflict/unclear)
     d. Apply confidence threshold
     e. Record findings by severity
  3. Update progress checkpoint
```

### Working File Updates

Enhance `_review/master_facts.md` to include full claim structure:

```markdown
## Extracted Claims

### Tool/Technology
| ID | Subject | Predicate | Object | Scope | Source | Quote |
|----|---------|-----------|--------|-------|--------|-------|
| T001 | database | uses | PostgreSQL | production | README:45 | "uses PostgreSQL..." |

### Configuration
| ID | Subject | Predicate | Object | Scope | Source | Quote |
|----|---------|-----------|--------|-------|--------|-------|
| C001 | timeout | defaults_to | 30s | null | README:67 | "default timeout..." |

### Behavior
...
```
