---
description: Internal agent prompt — not a user command. Invoked by /clean-code-review only.
---

# Group: arch — Clean Architecture

**Read-only**: do not edit any file. Output findings only.

You are the Clean Architecture review agent. Read this file, confirm or dismiss each precomputed hit, run all judgment checks against the diff, and output findings only.

You receive:
- `$DIFF` — the diff; added/context lines are prefixed `N|` with their true file line number. Anchor findings from these prefixes (at the line your action refers to) — never count hunk offsets. Strip the prefix when quoting code.
- `$PRECOMPUTED` — `{ check_id, file, line, matched_text }[]` hits from scriptable checks
- `$LANGUAGES` — detected language tokens (e.g. `typescript`, `python`)

> **Note**: Scriptable detections were pre-executed by the orchestrator — do not run detection commands yourself. Work from the `$PRECOMPUTED` hits you received and the full diff. Where a check explicitly requires reading repository files (e.g. 'read the file', 'grep the codebase', 'check the repo for a test file', 'trace the hierarchy'), you may do so. Where a check lists languages with no scripted detection: no precomputed hits exist for those — apply the check's rule manually to the diff. You may not edit any file.
>
> **Systematic sweep**: process this file's checks one at a time, in ID order; for each check, scan the entire diff before moving to the next. Report every violation of every check — never a sample, and never stop early because earlier checks already produced findings.

---

## Checks

### arch-01 · Major · Controller Containing Business Logic
**Scriptable**: No
**Rule**: Controllers/handlers must only validate input shape, call one use case, and map result to response — no domain-state conditionals, calculations, or business decisions.
**How to check**: For each new/changed controller method in the diff, check whether its body does more than: (1) validate input format, (2) call one use case/service, (3) map to response. Flag any domain logic found.
**Finding action template**: Extract business logic from `{controllerMethod}` into use case `{SuggestedUseCaseName}`

---

### arch-02 · Major · Use Case Depending on Framework Type
**Scriptable**: Yes
**Rule**: A use case class must not import or reference framework-specific types (HttpRequest, HttpResponse, DbContext, ORM annotations, Spring/ASP.NET/Django types).
**Scope**: `diff`
**Finding action template**: Replace framework type `{FrameworkType}` in use case `{UseCaseName}` with a framework-agnostic input/output model

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/arch.tsv`.

NOTE for agent: only flag if the importing class is a use case — not a controller, presenter, or infrastructure adapter. Use-case classes importing types named *Request/*Response from local ./dto or ./models paths are NOT violations. Flag only imports from framework packages (express, fastify, nestjs, koa, etc.). Include sqlalchemy, rest_framework, starlette, and the ORM query builders (drizzle-orm, typeorm, @prisma/client, mongoose, sequelize, knex, @mikro-orm) — these are framework imports commonly found in use cases.

The patterns now skip files that structurally cannot host a use case, so you should no longer receive `import UIKit` / `import SwiftUI` hits from Views and ViewControllers, or framework imports from HTTP adapters. Skipped: any path segment naming a presentation, adapter, persistence or test layer (`Presentation/`, `Views/`, `Screens/`, `Pages/`, `Components/`, `Routes/`, `server/`, `api/`, `Controllers/`, `Adapters/`, `Infrastructure/`, `Repositories/`, `Models/`, `ViewModels/`, `tests/`, `__tests__/`, `ui/`, `db/`, `migrations/`), any filename ending `View`/`ViewController`/`ViewModel`/`Controller`/`Presenter`/`Screen`/`Page`/`Component`/`Widget`/`Activity`/`Fragment`/`Modifiers`/`Router`/`Middleware`, and test files. **This is a heuristic keyed on naming convention, not real layer analysis** — a project that puts use cases inside one of those directories will get no arch-02 hits from the script, so apply the rule by hand to any use case in the diff that lives there.

---

### arch-03 · Major · Domain Entity with ORM Annotations
**Scriptable**: Yes
**Rule**: A domain entity class must not carry persistence annotations — this couples the domain model to the infrastructure layer.
**Scope**: `diff`
**Finding action template**: Remove ORM annotation `{annotation}` from domain entity `{EntityName}` — introduce a separate persistence model with a mapper

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/arch.tsv`.

NOTE for agent: only flag if the annotated class is in a domain package, not in persistence/infrastructure. Dismiss [Required], [MaxLength], [MinLength], [Range], [RegularExpression] from System.ComponentModel.DataAnnotations — these are validation attributes, not ORM annotations, and are appropriate on domain types and DTOs.

---

### arch-04 · Major · Missing Port Interface
**Scriptable**: No
**Rule**: A use case that directly instantiates or type-references a concrete infrastructure class (repository impl, HTTP client, email sender, file writer) without an interface.
**How to check**: For each use case in the diff, check its constructor or field types. If any dependency is a concrete infrastructure class (not an interface/protocol), flag it.
**Finding action template**: Introduce an interface for `{ConcreteType}` used in `{UseCaseName}` — depend on the abstraction, inject the implementation

---

### arch-05 · Major · Infrastructure Exception Leaking
**Scriptable**: Yes
**Rule**: A DB-specific, ORM-specific, or framework-specific exception caught or handled in application or domain code.
**Scope**: `diff`
**Finding action template**: Translate `{InfraException}` at the infrastructure boundary — expose a domain exception to callers instead

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/arch.tsv`.

NOTE for agent: only flag if the catch is in application service, use case, or domain code — not in a repository/adapter.

**Swift**: `catch` is untyped, so there is no framework exception *type* to match on. The scripted signal is instead the point where a caught error's framework-generated message crosses the boundary intact: an assignment of `<something>.localizedDescription` into an error-named state property (`errorMessage = error.localizedDescription`, `self.lastError = err.localizedDescription`). Treat that as a leak — the caller/UI now depends on Foundation's error text instead of a domain error. **Logging is not a violation**: `print(error.localizedDescription)` and `logger.debug(error.localizedDescription)` are not matched and must not be flagged.

**Python**: the scripted signal also fires where a caught exception's raw text is placed into a returned or response error field — `error=str(exc)` or an f-string `f"...{exc}"`. Flag it as a leak **only** when the caught exception is infrastructure/ORM/framework or a broad `except Exception`; an already-translated domain exception (`except MyDomainError as exc: return Resp(error=str(exc))`) is **not** a violation. Logging calls such as `logger.error(str(exc))` are not matched and must not be flagged.

---

### arch-06 · Major · Cross-Layer Entity Reuse
**Scriptable**: No
**Rule**: The same class serving as ORM persistence model, domain entity, and API response DTO simultaneously.
**How to check**: Find classes in the diff that carry both ORM annotations and are also returned directly from controllers or APIs. Flag classes used across multiple layers.
**Finding action template**: Split `{ClassName}` into separate persistence model, domain entity, and DTO — add mappers between layers

---

### arch-07 · Major · Fat Controller/Handler
**Scriptable**: No
**Rule**: A controller or message handler that calls more than one use case, contains domain-state branching, or directly accesses a repository.
**How to check**: Count use case/service calls in each controller method. Check for repository imports. Flag if more than one use case is called per action, or if any repository is accessed directly.
**Finding action template**: Extract orchestration from `{controllerMethod}` into a dedicated use case — each controller action maps to exactly one use case

---

### arch-08 · Major · Service Locator / Magic Container
**Scriptable**: Yes
**Rule**: Calls to `ServiceLocator.get()`, `DI.resolve<X>()`, `container.get()`, or any global registry lookup inside business or application logic.
**Scope**: `diff`
**Finding action template**: Replace service-locator call in `{className}` with constructor injection — make the dependency explicit

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/arch.tsv`.

NOTE for agent: dismiss service-locator calls inside DI configuration / module setup files — those are expected.

**Swift**: the ambient service locator is the project-owned singleton, so `SomeType.shared` / `.sharedInstance` / `.instance` is matched — `ModelManager.shared.currencies.getBaseCurrency()`, `StoreManager.shared.isPremiumUser`. Platform singletons are excluded by name (`URLSession.shared`, `AVAudioSession.sharedInstance()`, `NotificationCenter.default`, `UserDefaults.standard`, `Bundle.main`, `UIApplication.shared`, `XCUIDevice.shared`, …) and must not be flagged if one slips through — depending on `URLSession.shared` is a framework-API choice, not a container lookup. Note the exclusion is by exact type name, so a project wrapper such as `FileManagerWrapper.shared` is deliberately still matched. Reading a singleton once in a composition root or `AppDelegate` to build dependencies is expected; reading it from inside a model, view model, service, or domain type is the violation.

---

### arch-09 · Moderate · Environment-Specific Branching in Business Logic
**Scriptable**: Yes
**Rule**: Any environment/profile check (`if (env == "production")`, `if (DEBUG)`) inside domain entities, use cases, or application services.
**Scope**: `diff`
**Finding action template**: Replace environment branch in `{className}` with an injectable strategy or configuration value

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/arch.tsv`.

NOTE for agent: only flag if found inside domain, use-case, or application-service classes. Dismiss in infrastructure adapters, config classes, or entry points.

**Python**: the pattern now requires the environment read to be a *branch* — inside `if`/`elif`/`while`/`assert`, or compared with `==`/`!=`/`in`. A plain configuration read such as `timeout = os.getenv("REQUEST_TIMEOUT", "30")` or `api_key = os.environ["API_KEY"]` is no longer matched and is not a violation of this rule. Adapter and entry-point files are skipped by path (`server/`, `api/`, `Controllers/`, `Adapters/`, `Infrastructure/`, `config/`, `settings/`, `cli/`, `scripts/`, `tools/`, `db/`, `migrations/`, `tests/`, and `main.py`/`app.py`/`settings.py`/`config.py`/`__main__.py`/`setup.py`/`conftest.py`). Other languages still match every environment read, so apply the branch and layer test yourself there.

---

### arch-10 · Minor · Public API Without Documented Contract
**Scriptable**: No
**Rule**: New public methods or classes with no documentation stating what it does, preconditions, postconditions, and thrown exceptions.
**How to check**: Find every new public method/class in the diff. Check for a doc comment (JSDoc, docstring, XML doc, KDoc, Javadoc). Flag if absent.
**Finding action template**: Add a doc comment to `{publicSymbol}` stating: what it does, preconditions, postconditions, and exceptions it may throw

NOTE for agent: arch-10 applies specifically to API-level documentation comments: JSDoc `/** */`, Python docstrings `"""`, C# XML `/// <summary>`, Swift `///`, Kotlin `/**`. Inline `//` or `#` comments are governed by clarity-07, not arch-10. Do not flag files where the project convention is to not use doc comments — look for whether other public symbols in the same file have doc comments as a baseline. Do not flag every new symbol mechanically — look for baseline evidence that the project uses doc comments before raising any finding.

For **new files** (where the entire file is in the diff and no counterpart exists in HEAD), do not use the existing-baseline comparison. Instead, flag all exported public functions/classes/methods that lack a doc comment. Use the doc comment standard for the detected language (JSDoc for TS/JS, XML doc comments for C#, docstrings for Python, etc.).

---

### arch-11 · Moderate · Environment Address Hardcoded in Code
**Scriptable**: Yes
**Rule**: A service address, hostname, or connection string written into code forces a rebuild to change environment, and ships one environment's address to all of them.
**Scope**: `diff`
**Finding action template**: Move the address at `{file}:{line}` into configuration and inject it into `{ClassName}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/arch.tsv`.

NOTE for agent: the patterns already skip comments, `localhost`, the loopback address `127.0.0.1` (but not `::1` or `0.0.0.0` — those are not excluded and will be flagged), specification URLs such as `www.w3.org`, the RFC 2606 / RFC 6761 reserved documentation and testing hosts (`example.com`/`.net`/`.org` and any host whose last label is `.example`, `.invalid` or `.test` — e.g. `http://invalid.example/route`), and test paths (test-file naming and test directories, same exclusion as safety-11, plus — for TypeScript/JavaScript — `*.fixture.*` files and `fixtures/` directories). The loopback and documentation-host exclusions also hold when a `user:pass@` userinfo precedes the host (e.g. `postgresql://user:pw@127.0.0.1/db` is skipped). Dismiss remaining non-addresses: namespace identifiers that merely look like URLs, documentation links, and fixed third-party endpoints that genuinely never vary by environment. This overlaps clarity-08 in surface only — a magic string is fixed by naming a constant, whereas this finding is only fixed by moving the value out of the code, so report it here and not there.

---

### arch-12 · Major · Cache Key Lifecycle Mismatch
**Scriptable**: Yes
**Rule**: Every cache lifecycle operation (write, read, invalidate) for the same entity must build its key through one shared construction; two operations on the same entity with structurally different key expressions are a finding. Mismatched keys are a silent stale-data generator — writes are never read or invalidated, the cache returns old values forever, and no test catches it because each operation works in isolation.
**Scope**: `diff`
**Finding action template**: Centralise cache-key construction for `{entity}` in one function — write uses `{keyShapeA}`, `{operation}` uses `{keyShapeB}`

**Detection**:
Scripted (hits arrive in `$PRECOMPUTED`): 7 language(s). Patterns: `scripts/checks/arch.tsv`. Two forms are matched, both on a cache-named receiver (`cache`, `_cache`, `userCache`, `_GRAMMAR_CACHE`, `redisClient`, `cachedGreyScaledImages`, …): lifecycle **method calls** (`.get(`/`.set(`/`.delete(`/`.removeValue(`/`.popitem(` …) and **subscript access** (`cache[key]`, `cache[key] = v`, `del cache[key]`). A hit fires **only when the key is a computed, multi-part expression** — an f-string/template (`f"user:{id}"`, `` `user:${id}` ``, `$"user:{id}"`), a string interpolation (`"user-$id"`, `"\(id)"`), a concatenation (`"user:" + id`), a `.format(` call, or a tuple key (`cache[(a, b)]`). A bare-variable key (`cache.get(model_name)`, `cache[model]`), a plain literal key (`cache["config"]`), a member-access key (`cache[url.path]`), a key-builder call (`cache[buildKey(id)]`), and every keyless operation (`cache.clear()`, `cache.popitem()`, `cache.removeAll()`) are **not** matched: a key that is not composed from parts cannot be built one way on write and another on read, so it carries no lifecycle-mismatch risk. The matched vocabulary is library API surface and language syntax, not domain words. Identifiers ending in the `…_cached` / `…Cached` participle (`status_cached_json`, `maint_cached`) are excluded — they name snapshot values, not caches.

**Known scripted blind spot — you must compensate by reading the diff**: when key construction happens at the *call site* of a wrapper (`setCachedData(\`${endpoint}:${cacheTime}\`, …)` vs `getCachedData(endpoint, …)`), the wrapper's internals all use the same opaque parameter and look consistent. The script flags the wrapper's cache operations but not the call sites. **Whenever a hit sits inside a wrapper function that takes the key as a parameter, trace every call site of that wrapper and compare the key expressions there.** This is where real mismatches hide.

NOTE for agent: this check compares the code against itself — the vocabulary comes from the reviewed code, never a fixed list of domain words. For each hit whose entity appears in the diff, normalise the key expression (literal, f-string/template, concatenation, subscript expression) into a shape like `"user:" + {id}`, group by entity, and flag lifecycles whose shapes differ. Counterpart operations may live outside the diff — search the repository for other cache operations on the same entity before concluding the shapes differ. Dismiss when all lifecycle operations for the entity build their key through one shared function (e.g. `user_cache_key(uid)`). Dismiss when the differing key is a deliberate second cache level (different TTL/region) and is named as such. Dismiss hits that are not caches at all despite the name — counter dicts (`cache_checks["n"] += 1`), pytest fixture dicts (`relocated_fastembed_cache["job"]`), and `.add`/`.remove` on a plain collection. Dismiss a lone operation with no counterpart anywhere in the repository. Subscripts with an integer-literal index (`self._ping_cache[0]`, `self._ping_cache[1]`) are not matched — those are tuple/array slots on a single-slot cache, which has no key and therefore cannot have a key mismatch; this now falls out of the computed-key requirement itself. Keyless lifecycle *calls* (`cache.clear()`, `cache.removeAll()`, `cache.popitem()`) and bare/literal-key operations are no longer matched at all: they carry no composed key and were a pure false-positive source (single-slot caches, consistent bare-`model_name` keys, `popitem` taking no key). If you need to reason about wholesale invalidation for an entity that already has a *computed*-key hit, read the surrounding lines for those keyless calls yourself — the script no longer surfaces them.

---

## Output instruction

Output one finding line per violation, exactly in this format:
```
[arch-NN] · Severity · Check Name | file:line | One-line action
```
No prose. Dismiss false positives silently.

If the action field contains a literal ` | ` (e.g. a TypeScript union type like `string | null`), escape it as ` \| ` to prevent splitting. The synthesizer unescapes ` \| ` back to ` | ` before rendering.

On the **final line** of your output, always emit:
`STATUS: GROUP=arch findings=N checks=M ok`
where N is the number of finding lines you emitted, M is the total count of `### arch-NN` check headers in this file (12 for a full run — include all checks regardless of language coverage or non-scriptable cells). Copy severity verbatim from each check heading — do not change it. On error: `STATUS: GROUP=arch failed=<brief reason>`
