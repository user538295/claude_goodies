# Code Review and Architecture Protocol

Use this for code snippets, repositories, technical designs, architecture, APIs, database schemas, tests, and implementation plans.

## Review sequence

1. Identify language, framework, runtime, platform, and likely constraints.
2. Inspect the provided code, files, tests, errors, and requirements before judging.
3. Research current official docs and best practices when versions, frameworks, security, or platform behavior matter.
4. Find correctness and safety issues first.
5. Then evaluate design, maintainability, idioms, tests, and performance.
6. Propose concrete code or architecture improvements.
7. Provide 3-4 improvement options when the solution direction is not obvious.

## Severity levels

- Blocker: likely wrong, unsafe, insecure, data-loss-prone, or prevents release.
- Major: significant maintainability, performance, UX, security, or architecture risk.
- Moderate: worth fixing soon, but not release-blocking.
- Minor: polish, naming, formatting, local simplification.

## Code quality dimensions

### Correctness

- Does the code satisfy the stated behavior?
- Are edge cases handled?
- Are null/empty/invalid inputs handled intentionally?
- Are concurrency and ordering assumptions valid?

### Readability

- Is the intent obvious?
- Are names precise?
- Is complexity localized?
- Can a new maintainer modify it safely?

### Idiomatic design

- Does it follow the language and framework conventions?
- Are abstractions natural for this ecosystem?
- Is the code fighting the framework?

### Architecture

- Are responsibilities separated?
- Are dependencies pointed in the right direction?
- Is coupling justified?
- Is state ownership clear?
- Are boundaries testable?

### Error handling

- Are failures explicit?
- Are errors recoverable where appropriate?
- Are user-facing messages safe and useful?
- Are internal details protected?

### Security and privacy

- Are inputs validated and encoded correctly?
- Are secrets excluded from code/logs/errors?
- Are authorization checks enforced at the right layer?
- Are dependencies, injection risks, file access, network calls, and deserialization considered?

### Performance

- Is there avoidable repeated work?
- Are database/network/file operations batched appropriately?
- Are memory and CPU costs acceptable for expected scale?
- Are expensive operations measured rather than guessed?

### Testing

- Are important behaviors covered by tests?
- Are edge cases and failure paths tested?
- Are tests deterministic and readable?
- Are mocks/fakes used where appropriate without hiding integration risk?

### Observability

- Would production failures be diagnosable?
- Are logs, metrics, traces, and error reports placed at useful boundaries?
- Is sensitive data kept out of telemetry?

## Design pattern discipline

Do not recommend a design pattern because it sounds professional. Recommend one only when it solves a real pressure:

- Strategy: multiple interchangeable algorithms or policies
- Adapter: incompatible external interface
- Factory: complex object creation or platform variants
- Repository: persistence abstraction with real testability or storage flexibility need
- Coordinator/Router: navigation or workflow orchestration
- Observer/Publisher-subscriber: decoupled event notification
- Decorator: composable behavior around a stable interface
- Command: undo, queueing, logging, or delayed execution

If a simple function, type, or module is enough, say so.

## Output requirements for code reviews

Include:

1. Initial verdict
2. Highest-impact issues first
3. Concrete fixes
4. Better design option if needed
5. Tests to add or change
6. Recommendation

When changing code, prefer small patches unless the current structure is fundamentally wrong.
