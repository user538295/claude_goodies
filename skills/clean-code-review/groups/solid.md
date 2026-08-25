---
description: Internal agent prompt — not a user command. Invoked by /clean-code-review only.
---

# Group: SOLID (inc. OOP & Encapsulation)

**Read-only**: do not edit any file. Output findings only.

You receive:
- `$DIFF` — the diff; added/context lines are prefixed `N|` with their true file line number. Anchor findings from these prefixes (at the line your action refers to) — never count hunk offsets. Strip the prefix when quoting code.
- `$PRECOMPUTED` — `{ check_id, file, line, matched_text }[]` hits from scriptable checks
- `$LANGUAGES` — detected language tokens (e.g. `typescript`, `python`)

For each precomputed hit: confirm (real violation) or dismiss (false positive, silently).
For each non-scriptable check: analyse the diff and report violations.
Output findings only — one line per finding, no prose.

> **Note**: Scriptable detections were pre-executed by the orchestrator — do not run detection commands yourself. Work from the `$PRECOMPUTED` hits you received and the full diff. Where a check explicitly requires reading repository files (e.g. 'read the file', 'grep the codebase', 'check the repo for a test file', 'trace the hierarchy'), you may do so. Where a check lists languages with no scripted detection: no precomputed hits exist for those — apply the check's rule manually to the diff. You may not edit any file.
>
> **Systematic sweep**: process this file's checks one at a time, in ID order; for each check, scan the entire diff before moving to the next. Report every violation of every check — never a sample, and never stop early because earlier checks already produced findings.

---

### solid-01 · Major · Single Responsibility Principle
**Scriptable**: No
**Rule**: Each changed class/function must have exactly one reason to change; flag if the name implies multiple responsibilities or the body mixes concerns.
**How to check**: For each new/changed class, list all the things it does. If more than one distinct concern is present (e.g. validation + persistence + formatting), flag it.
**Finding action template**: Split `{ClassName}` — separate `{concern1}` and `{concern2}` into distinct classes

---

### solid-02 · Major · Open/Closed Principle
**Scriptable**: No
**Rule**: New behaviour should extend, not modify, existing closed classes.
**How to check**: Does adding this new behaviour require editing an existing class's core logic rather than adding a new implementation/subclass/strategy?
**Finding action template**: Extract new behaviour from `{ClassName}` into a new strategy/subclass rather than modifying the existing class

---

### solid-03 · Critical · Liskov Substitution Principle
**Scriptable**: No
**Rule**: Changed subclasses must honour the parent contract — never weaken preconditions or strengthen postconditions.
**How to check**: For overridden methods in the diff: do they throw exceptions the parent doesn't throw? Return null where parent returns non-null? Require additional preconditions? If the full class hierarchy is NOT visible in the diff, report the finding at Major severity (one level below Critical) with the caveat in the action field: `… — hierarchy not fully visible in diff, advisory`. This mirrors the ddd-03 severity-downgrade pattern.
**Finding action template**: Restore parent contract in `{ClassName}.{methodName}` — {specific violation, e.g. "never return null where parent guarantees a value"}

---

### solid-04 · Moderate · Interface Segregation Principle
**Scriptable**: No
**Rule**: Changed interfaces/protocols must be focused; flag interfaces with unrelated methods grouped under one name.
**How to check**: For each new/changed interface in the diff, list all methods. Are all methods cohesive (same client needs all of them)? Flag if some clients would only use a subset.
**Finding action template**: Split `{InterfaceName}` — separate `{methodGroup1}` and `{methodGroup2}` into focused interfaces

---

### solid-05 · Major · Dependency Inversion Principle
**Scriptable**: No
**Rule**: High-level changed modules must depend on abstractions, not concretions; flag direct imports of infrastructure from domain code.
**How to check**: For each new import in the diff, check whether a high-level module (use case, domain service, entity) imports a concrete infrastructure type (DB client, HTTP client, file system, ORM).
**Finding action template**: Replace direct dependency on `{ConcreteType}` in `{ClassName}` with an interface — inject the implementation

---

### solid-06 · Major · Public Mutable Fields
**Scriptable**: Yes
**Rule**: Public instance fields on classes that aren't plain data holders (DTO, record, struct, value object) break encapsulation.
**Scope**: `diff`
**Finding action template**: Make `{fieldName}` in `{ClassName}` private — add an accessor/property if external read access is needed

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/solid.tsv`.

NOTE for agent: dismiss data classes, DTOs, records, structs, and value objects — public fields are expected there. For TypeScript: flag `public` instance properties in classes where the value can be set from outside the class after construction. For C#: flag `public` fields (not properties) and `public` auto-properties with a `set` accessor on a class that should be a value type. Dismiss in test files (files matching test naming conventions — `*Test.kt`, `*Spec.kt`, `*Tests.swift`, `src/__tests__/`, etc.) — public `var` is normal for test fixtures and `sut` fields. For Swift and Kotlin the pattern only accepts a declaration at exactly one indentation level (one tab, two spaces, or four spaces), so it sees type-body members and not locals inside function bodies; a member nested inside an inner type is therefore missed, and in a two-space codebase a local at depth two still slips through. It also skips computed properties (`var body: some View {`) and anything narrowed with `private(set)`, and it does accept attributed declarations — `@IBOutlet var`, `@Published var`, `@StateObject var` are non-private mutable members and are flagged; judge those against the rule like any other (a plain `@Published var` a view writes back to is a violation, one the view only reads should have been `private(set)`).

---

### solid-07 · Moderate · Primitive Obsession
**Scriptable**: Yes
**Rule**: Domain concepts represented as raw primitives (`string` for email/URL, `int` for userId/money, `bool` for status) should be named types, value objects, or enums.
**Finding action template**: Wrap `{primitiveType} {name}` in a `{SuggestedValueObject}` value object or enum

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/solid.tsv`.

NOTE for agent: the pattern only recognises a fixed vocabulary of domain names (email, url, phone, postal code, currency, amount, price, and the `*Id` / `*Code` / `*Mode` suffixes) carried as text or numbers. It is a starting point, not the whole check — the rule covers any domain concept, so still read the diff for domain-specific ones the vocabulary does not know. The patterns exclude files matching the test naming conventions, so every hit is production code. Dismiss hits at genuine system boundaries where a primitive is correct: serialisation shapes (DTOs, wire contracts, database rows), framework-required signatures, and the constructor of the value object itself, which must accept the primitive it wraps.

---

### solid-08 · Minor · Unnecessary Mutability
**Scriptable**: Yes
**Rule**: Variables assigned exactly once but not declared `const`/`val`/`final`/`readonly`.
**Scope**: `diff`
**Finding action template**: Declare `{variable}` as `{const/val/final/readonly}` — it is only assigned once

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 4 language(s). Patterns: `scripts/checks/solid.tsv`.
No scripted detection for:
- python: skip — Python has no const keyword
- csharp: non-scriptable — C# has no readonly locals; `const` requires compile-time constants. Agent must check the diff for mutable local variables that are reassigned, which is the actual violation. Dismiss `var` declarations whose value is immediately used and never reassigned.
- java: non-scriptable — `^\s*\w+\s+\w+\s*=` matches every typed local variable declaration; agent must check the diff for variables assigned exactly once

NOTE for agent: only flag if the variable is assigned exactly once in its scope. Dismiss if it is reassigned anywhere. Dismiss in test files. The detection is no longer a single-line regex: it reads the whole file and drops the declaration when the same bare name is reassigned anywhere else in it (`=`, `+=`, `x[i] =`, `++`/`--`, and for Swift also value-type mutators such as `.append`/`.sort`/`.removeAll` and `&x` inout). Two blind spots remain, so still read the surrounding code: a field mutated through another reference (`result.count -= 1`) is not seen because the name is qualified, and a same-named variable in a different scope in the same file suppresses the hit.

---

### solid-09 · Major · Global Mutable State
**Scriptable**: Yes
**Rule**: New `static` mutable fields, module-level variables that aren't constants, and singleton patterns holding mutable state create hidden coupling and make tests order-dependent.
**Scope**: `diff`
**Finding action template**: Remove global mutable `{name}` — scope it locally or pass it explicitly as a parameter

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/solid.tsv`.

NOTE for agent: Dismiss only true constants (primitive values, frozen objects, immutable types). Do NOT dismiss `const`/`val`/`readonly` bindings to mutable containers like `Map`, `Set`, `Array`, `List`, `Dictionary`, `WeakMap` — these are global mutable state regardless of the binding's immutability. Examples that SHOULD be flagged: `export const cache = new Map()`, `val registry = mutableMapOf<String, User>()`, `static readonly List<Foo> items = new()`. Dismiss in test files. Also flag singleton patterns that hold mutable state (e.g. a class with a private static `_instance` field and a public `get_instance()` method holding mutable data) — these are not detectable by the scriptable pattern above, which targets direct variable declarations. Apply this judgment to the diff. Dismiss Python module-level names matching UPPER_CASE_CONVENTION — these are module constants, not mutable state; the Python pattern already excludes them, along with the `logger = logging.getLogger(...)` idiom and `Annotated`/`TypeVar`/`NewType` aliases, and in exchange it now flags any other module-level binding, not just list/dict/set literals. Swift and Kotlin add the in-type equivalent of a module global: `static var` (Swift) and `@JvmStatic var` (Kotlin). A Kotlin `companion object { var … }` spans lines and is still invisible to the pattern — judge it from the diff.

---

### solid-10 · Major · Hardcoded Dependency Creation
**Scriptable**: Yes
**Rule**: `new ConcreteClass()` inside method bodies in non-factory, non-infrastructure code prevents testing and substitution.
**Scope**: `diff`
**Finding action template**: Remove `new {ConcreteClass}()` from `{methodName}` — inject it via constructor

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 6 language(s). Patterns: `scripts/checks/solid.tsv`.
No scripted detection for:
- kotlin: non-scriptable — pattern too broad; judge from diff

NOTE for agent: dismiss instantiations in factory methods, builders, infrastructure adapters, and test files. Flag only in domain/application service method bodies. Dismiss `new Date()`, `new Error()`, `new Map()`, `new Set()`, language collection types, `new Promise()`, `new URL()`, geometry/value structs (`Vector3`, `Quaternion`, `Color`), `Intl.*` formatters, any exception type (`*Exception`, `*Error`), test-doubles (`new Mock<T>()`, `new Stub()`, `new Spy()`), and domain event types. Flag concrete infrastructure classes like `new PostgresClient()`, `new S3Storage()`, `new UserRepository()` — these should be injected via a constructor or factory. Swift and Python have no `new` keyword, so those two patterns instead match an assignment whose right-hand side constructs a type whose name ends in a collaborator suffix (`…Service`, `…Repository`, `…Store`, `…Client`, `…Manager`, `…ViewModel`, `…Config`, and about seventy more), and they skip comment lines and test files. Consequences worth knowing: a collaborator whose name carries no such suffix (`StarField()`, `ImportFromKoin()`) is missed, `X.shared` singleton access and `= .init()` are not matched at all, and construction inside a composition root — a `build_pipeline`-style factory function — matches the pattern but is exactly what the first sentence tells you to dismiss.

---

### solid-11 · Major · Anemic Domain Model
**Scriptable**: No
**Rule**: New classes that have only fields, getters, and setters with no methods containing business logic are a sign all behaviour lives in a separate service.
**How to check**: For each new class in the diff, check whether it has any methods beyond getters/setters. If not, and a separate service operates on it, flag both.
**Finding action template**: Move business logic from `{ServiceClass}` into domain class `{DomainClass}` — it should own its behaviour

---

### solid-12 · Moderate · Logging Inside Domain
**Scriptable**: Yes
**Rule**: Direct logger instantiation or logging calls inside domain entities, value objects, aggregates, or business logic classes violate DIP — logging is an infrastructure concern.
**Scope**: `diff`
**Finding action template**: Remove logging from `{ClassName}` — move to application or infrastructure layer

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/solid.tsv`.

NOTE for agent: only flag if the class is in a domain/entity/aggregate/business-logic package. Dismiss logging in controllers, services, repositories, or infrastructure.

The rows now apply that layer test to the file list before matching: a file reaches you only when its path has a `domain/`, `entities/`, `models/`, `aggregates/` or `value-objects/` segment, or its name ends in `Entity`/`Aggregate`/`ValueObject`/`Model` — with `*ViewModel` excluded as presentation. That gate is a naming convention, not proof: still confirm the flagged type is domain logic. It also means a domain class in an unconventionally named file never reaches you — judge those from the diff. The swift row matches any `*Log`/`*Logger` façade (`AppLog.warning`) but skips `*.assert*` methods, which are assertions — safety-13 owns those.

---

### solid-13 · Moderate · Inheritance Depth
**Scriptable**: No
**Rule**: Class hierarchies where a class is more than 3 inheritance levels deep cause the yo-yo problem — understanding any single class requires bouncing up and down the chain.
**How to check**: For each class in the diff that extends/inherits, trace the hierarchy. Flag if depth exceeds 3 levels (including the base).
**Finding action template**: Flatten `{ClassName}` hierarchy (depth {N}) using composition or delegation

---

### solid-14 · Major · Inheriting Concrete for Reuse
**Scriptable**: No
**Rule**: A subclass that inherits from a non-abstract, non-interface class to reuse methods (not as a true specialisation) breaks encapsulation and creates a fragile base class.
**How to check**: For each `extends` on a concrete class in the diff: is the subclass a true behavioural specialisation, or is it just reusing helper methods?
**Finding action template**: Replace inheritance from concrete `{ParentClass}` in `{ChildClass}` with composition — hold a `{ParentClass}` instance instead

---

### solid-15 · Major · Switch/If-Else Dispatching on Type
**Scriptable**: Yes
**Rule**: Switch statements or if-else chains that select behaviour based on a type field, string constant, or enum violate OCP — add polymorphism instead.
**Scope**: `diff`
**Finding action template**: Replace type-dispatch in `{functionName}` on `{typeField}` with polymorphism — strategy, visitor, or factory

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 6 language(s). Patterns: `scripts/checks/solid.tsv`.
No scripted detection for:
- kotlin: non-scriptable — `\bis\s+[A-Z]\w+` matches all type-check expressions including prose in comments and legitimate single-expression guards; agent must check the diff for `when` blocks or `if/else` chains that dispatch on type identity across multiple branches

NOTE for agent: dismiss switch/when on simple value enums used for configuration. Flag only when behaviour (method dispatch) differs per case. The discriminator is recognised by name, not by meaning: TypeScript, JavaScript, Swift and Python all key off a vocabulary of suffixes — `type`, `kind`, `status`, `state`, `mode`, `variant`, `category`, `role`, `level`, `severity`, `action`, `format`, `provider`, `backend`, `direction`, `strategy` (plus `code` in Swift, `suffix`/`scheme`/`command` in Python) — so a discriminator named anything else is missed and you must still read the diff for it. Python is matched only through `elif`, because an `elif` is evidence of a chain where a lone `if isinstance(...)` would just be validation. A single guard `if` on a vocabulary word is not a dispatch chain — dismiss it.

---

## Output instruction

Output one finding line per violation, exactly in this format:
```
[solid-NN] · Severity · Check Name | file:line | One-line action
```
No prose. Dismiss false positives silently.

If the action field contains a literal ` | ` (e.g. a TypeScript union type like `string | null`), escape it as ` \| ` to prevent splitting. The synthesizer unescapes ` \| ` back to ` | ` before rendering.

On the **final line** of your output, always emit:
`STATUS: GROUP=solid findings=N checks=M ok`
where N is the number of finding lines and M is the total count of `### solid-NN` check headers in this file (15 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. Exception: solid-03 may be reported at Major severity when the full class hierarchy is not visible in the diff alone. On error: `STATUS: GROUP=solid failed=<brief reason>`
