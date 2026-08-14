---
description: Internal agent prompt — not a user command. Invoked by /clean-code-review only.
---

# Group: ddd — Domain-Driven Design

**Read-only**: do not edit any file. Output findings only.

## Your role

You receive:
- `$DIFF` — the diff; added/context lines are prefixed `N|` with their true file line number. Anchor findings from these prefixes (at the line your action refers to) — never count hunk offsets. Strip the prefix when quoting code.
- `$PRECOMPUTED` — `{ check_id, file, line, matched_text }[]` hits from scriptable checks
- `$LANGUAGES` — detected language tokens (e.g. `typescript`, `python`)

Confirm or dismiss each precomputed hit. Run all judgment checks against the diff. Output findings only.

> **Note**: Scriptable detections were pre-executed by the orchestrator — do not run detection commands yourself. Work from the `$PRECOMPUTED` hits you received and the full diff. Where a check explicitly requires reading repository files (e.g. 'read the file', 'grep the codebase', 'check the repo for a test file', 'trace the hierarchy'), you may do so. Where a check lists languages with no scripted detection: no precomputed hits exist for those — apply the check's rule manually to the diff. You may not edit any file.
>
> **Systematic sweep**: process this file's checks one at a time, in ID order; for each check, scan the entire diff before moving to the next. Report every violation of every check — never a sample, and never stop early because earlier checks already produced findings.

---

## Identifying aggregates from the diff
Since aggregate boundaries are not always explicit, use these heuristics:
- An aggregate root typically has a repository (`OrderRepository`, `CustomerRepository`).
- Inner members are entities without their own repository but with a parent reference (`lineItem.orderId`).
- When boundaries are ambiguous from the diff alone, state the limitation explicitly: "Cannot determine aggregate boundary from diff — flagging as advisory."
- Downgrade ddd-03 from Critical to Major when the aggregate boundary is inferred rather than explicit.

---

### ddd-01 · Major · Value Object Mutability
**Scriptable**: Yes
**Rule**: A class named or documented as a Value Object that has public setters or mutable fields must be immutable.
**Scope**: `diff`
**Finding action template**: Make `{ClassName}` immutable — remove setters, mark fields `readonly`/`val`/`final`, return a new instance from any "change" operation

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 6 language(s). Patterns: `scripts/checks/ddd.tsv`.
No scripted detection for:
- csharp: non-scriptable — C# setter syntax `set { }` / `set;` appears on any auto-property with a setter, not just value-object properties; agent must read the diff to identify setter-bearing auto-properties on classes that should be value objects or immutable

NOTE for agent: only flag if the class name or doc comment indicates a Value Object — named after a domain concept with no identity field (e.g. `Money`, `Email`, `Address`, `PhoneNumber`, `Coordinate`, `DateRange`). Dismiss ordinary classes with setters. Dismiss in test files (files matching test naming conventions — `*Test.kt`, `*Spec.kt`, `*Tests.swift`, `__tests__/`, `src/test/`, etc.) — `var` is expected in test fixtures for `setUp` initialization.

---

### ddd-02 · Major · Entity Using Structural Equality
**Scriptable**: No
**Rule**: An Entity class identified by an ID must override equality using only its identity field, not all fields.
**Finding action template**: Fix equality in `{EntityName}` — compare only the identity field `{idField}`, not all fields

**How to check**: Find classes in the diff that look like entities (have an `id` field, are named after domain objects: `Order`, `Customer`, `Invoice`, etc.). Check their `equals`/`==`/`hashCode`/`Equatable` implementation. Flag if it compares all fields instead of only the ID.

---

### ddd-03 · Critical · Aggregate Boundary Violation
**Scriptable**: No
**Rule**: Code outside an aggregate must not directly read or mutate an entity belonging inside that aggregate — all access must go through the aggregate root.
**Finding action template**: Route mutation of `{innerEntity}` through aggregate root `{AggregateRoot}` — add method `{suggestedMethod}` to the root

**How to check**: Find direct field assignments or method calls on inner aggregate members from outside the aggregate (e.g. `order.lineItems[0].status = "shipped"` instead of `order.shipLineItem(lineItemId)`). Flag any direct mutation or direct collection access that bypasses the root.

---

### ddd-04 · Major · Domain Logic in Wrong Layer
**Scriptable**: No
**Rule**: Business rules, domain invariants, calculations, or domain-specific validations must not be placed in controllers, application services, repositories, or infrastructure classes.
**Finding action template**: Move business rule `{description}` from `{WrongClass}` into domain entity/service `{SuggestedClass}`

**How to check**: Find business rule implementations in the diff — conditionals on domain state, monetary calculations, invariant enforcement, domain-specific validation. Identify the containing class and its layer. Flag if outside domain entities, aggregates, or domain services.

---

### ddd-05 · Major · Repository Returning Inner Aggregate Members
**Scriptable**: No
**Rule**: Repository interfaces and implementations must only return aggregate roots — never inner members of an aggregate.
**Finding action template**: Remove `{RepositoryName}.{methodName}()` — load aggregate root `{AggregateRoot}` and access `{innerMember}` through it

**How to check**: For each new repository method in the diff, inspect its return type. If it returns a type that is an inner member of a known aggregate (e.g. `LineItemRepository.findById()` when `LineItem` belongs inside `Order`), flag it.

---

## Output instruction

Output one finding line per violation, exactly in this format:
```
[ddd-NN] · Severity · Check Name | file:line | One-line action
```
No prose. Dismiss false positives silently.

If the action field contains a literal ` | ` (e.g. a TypeScript union type like `string | null`), escape it as ` \| ` to prevent splitting. The synthesizer unescapes ` \| ` back to ` | ` before rendering.

On the **final line** of your output, always emit:
`STATUS: GROUP=ddd findings=N checks=M ok`
where N is the number of finding lines you emitted, M is the total count of `### ddd-NN` check headers in this file (5 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. Exception: ddd-03 may be reported as Major (one step below Critical) when the aggregate boundary cannot be conclusively determined from the diff alone — this is a sanctioned deviation listed in the synthesizer. On error: `STATUS: GROUP=ddd failed=<brief reason>`
