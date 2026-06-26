# Devil's Advocate Playbook

The catalogs behind the `devils-advocate` skill. Pull the lens that fits the target; don't run all of them mechanically.

---

## Questioning frameworks

**Pre-mortem.** Assume failure, then explain it. "It shipped. Three months later it caused a serious incident — outage, data loss, a furious customer, a security write-up. Walk back: what was the chain of events?" Surfaces failure modes that forward-looking optimism hides.

**Inversion.** Stop asking how to make it succeed; ask what would guarantee it fails. List those conditions, then check the target for each. The ones already present are your highest-severity concerns.

**Socratic probing.** For each claim: What's the evidence? Is this stated as fact or belief? What must be true for this to hold? What follows if it's false? Keep asking "why" until you hit a real foundation or an unsupported leap (Five Whys).

**Assumption hunt.** Make every embedded assumption explicit — especially ones written as conclusions ("users will adopt this", "the API is stable", "load stays under X"). For each: evidence for it? what breaks if it's wrong? was it validated or assumed?

**Contrarian alternative.** Generate the strongest opposing position a smart, informed expert would hold. Steelman it. If the target can't answer the steelman, that's a finding. Also ask: is there a simpler solution dismissed too fast? A more complete one avoided due to scope fear?

**Completeness / scope.** Is this solving the stated problem or a convenient proxy? Does the output actually answer the question asked, or an easier adjacent one?

**Six Thinking Hats.** Walk the decision through six lenses in turn so no single mode dominates: facts/data (white), gut reaction (red), risks & caution (black), benefits & value (yellow), new options & creativity (green), and process/meta (blue). Especially useful on strategy, business, and product calls, where pure risk-hunting would otherwise crowd out value and alternatives.

---

## Blind-spot categories

Engineers and AI consistently miss these. Scan the target against each that's relevant:

1. **Security** — authn/authz gaps, injection, secrets in code/logs, new attack surface, trust boundaries, input validation, default-open behavior.
2. **Scalability** — what holds at 10 records but not 10M; N+1 queries, unbounded loops/memory, hot partitions, synchronous calls that should be async.
3. **Data lifecycle** — migrations, backfills, schema evolution, retention/deletion, GDPR/PII, orphaned records, irreversible writes.
4. **Failure modes** — what happens when a dependency is down, slow, or returns garbage? Retries, timeouts, idempotency, partial failure, rollback path.
5. **Concurrency** — race conditions, lost updates, deadlocks, double-processing, ordering assumptions, non-atomic read-modify-write.
6. **Integration points** — contract changes, versioning, backward compatibility, third-party rate limits and outages, webhook delivery guarantees.
7. **Environment gaps** — works on my machine; config drift, env vars, timezones, locale, clock skew, prod-vs-dev data shape.
8. **Observability** — can you tell when it breaks? Logging, metrics, alerting, tracing, debuggability of the failure you just imagined.
9. **Deployment / rollout** — migration ordering, feature flags, blue-green, the moment both old and new code run together, rollback safety.
10. **Edge cases** — empty input, single item, max size, null/None, unicode, negative numbers, concurrent users, the boundary value.
11. **Operational cost** — who maintains this, who's paged, what's the on-call burden, what's the cloud bill at scale.

Stakeholder lens: **Who is harmed?** Which affected party is unrepresented in the design?

💡 **Even on a technical target** (a user story, a built solution), still pull three questions from the product group below: is this the *right thing to build* (see Completeness), will it actually be *adopted*, and what does it *incentivize*? Skip the rest (market fit, competition, unit economics, GTM, regulatory) unless the target is a business or product decision.

### Product / market blind spots

For a business plan, feature, strategy, or pricing decision — scan these the way the list above scans code:

1. **Market fit** — is the problem real and painful enough? Evidence of demand, or assumed?
2. **Competition & alternatives** — who else solves this (including "do nothing" and a spreadsheet)? Why would anyone switch?
3. **Unit economics** — does the math work *per customer* (CAC, LTV, margin), or only in aggregate hand-waving?
4. **Adoption & behavior change** — what must users stop doing to adopt this? Is that realistic?
5. **Distribution / GTM** — how do people actually find it? A real channel, or "build it and they'll come"?
6. **Regulatory / legal / trust** — compliance, liability, privacy, reputational exposure.
7. **Second-order incentives** — who is incentivized *against* this? What behavior does it accidentally reward or punish?
8. **Timing & dependencies** — why now? What external thing (market, partner, platform) must hold for it to work?

---

## AI-specific failure modes

When the target was produced by an AI (including you), check these first — they're the predictable shortcuts:

- **Happy-path bias** — code/plan handles the success case; error, empty, and concurrent cases are thin or absent.
- **Scope acceptance** — built exactly what was asked without questioning whether it's the right thing to build.
- **Confidence without correctness** — fluent, authoritative prose around a claim that was never verified.
- **Hallucinated specifics** — invented library versions, API methods, config keys, statistics, citations. Flag any specific that can't be traced to provided context. Apply STOP → STATE the claim → SEARCH/verify → only then trust.
- **Pattern attraction** — reached for a familiar pattern (microservices, a queue, a cache) because it's common, not because this problem needs it.
- **Reactive patching** — fixed the symptom in front of it rather than the cause; the bug will resurface elsewhere.
- **Test rewriting** — when tests failed, changed the tests to pass instead of fixing the code.
- **Over-engineering** — abstractions, config, and flexibility for requirements that don't exist yet.

---

## Logical fallacies to flag

- **False dichotomy** — "either X or Y" when other options exist.
- **Post hoc / correlation as causation** — "we shipped X and metric moved, so X caused it."
- **Survivorship bias** — reasoning only from the cases that succeeded.
- **Confirmation bias** — evidence selected to support a conclusion already held.
- **Appeal to authority** — "best practice says" / "everyone does" with no fit-to-context argument.
- **Circular reasoning** — the conclusion is smuggled into the premise.
- **Overgeneralization** — one example treated as a universal rule.
- **Anchoring** — the first number or design proposed framing everything after it.

---

## Recording patterns

When the same weakness recurs across reviews — an assumption type never validated, a hallucination pattern, a blind spot a given codebase keeps hitting — write it to memory so future challenges start sharper.
