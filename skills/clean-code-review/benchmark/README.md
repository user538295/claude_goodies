# Recall benchmark for /clean-code-review

This is an **evaluation fixture, not a CI test**. It measures how much of the
skill's *judgment layer* (the LLM review agents) actually gets found on a known
set of planted violations — the part of the pipeline that deterministic tests
cannot cover. Run it after changing agent prompts, group files, or when a new
model version lands, and compare scores across runs.

The regex layer does NOT need this benchmark — it is fully covered by
`tests/test_corpus.sh` (semantic MATCH/NOMATCH per pattern) and
`tests/test_checks.sh` (golden hits).

## Contents

- `python/order_service.py` + `python/test_order_service.py` — 34 planted violations
- `typescript/orderService.ts` + `typescript/inventory.test.ts` — 29 planted violations
- `csharp/OrderProcessing.cs` + `csharp/OrderProcessingTests.cs` — 20 planted violations
- `swift/Checkout.swift` + `swift/CheckoutTests.swift` — 13 planted violations
- `planted.tsv` — the catalog: check, file, line, detect (scripted/judgment), description

96 rows covering the original **85 checks** at least once. The 24 checks added later (safety-08 through safety-21, smells-20 through smells-23, arch-11, tests-13, ddd-06 through ddd-09) are all scriptable or judgment-only and already covered by `tests/corpus.tsv` where scriptable; they have no planted violation here yet — of the 109 checks that exist today, this fixture exercises 85.

**Never "fix" these files.** Broken is their job. For a scriptable check,
`tests/corpus.tsv` (semantic MATCH/NOMATCH, see `tests/test_corpus.sh`) is the
required test home — the pattern must land there before the check ships.
Adding a row to `planted.tsv` here is best-effort on top of that: it earns a
recall data point in this benchmark but doesn't gate the check. Judgment-only
checks have no other test, so planting one here is the only way to ever
measure them — do it when you can.

## How to run

From this directory, invoke the skill in file mode:

```
/clean-code-review python/order_service.py python/test_order_service.py typescript/orderService.ts typescript/inventory.test.ts csharp/OrderProcessing.cs csharp/OrderProcessingTests.cs swift/Checkout.swift swift/CheckoutTests.swift
```

## How to score

Compare the report's findings against `planted.tsv`:

- **Found**: a finding with the same check id and file, anchored within ±3
  lines of the planted line.
- **Recall** = found / planted (report per detect-type: `scripted` rows should
  approach 100% since their hits are precomputed; `judgment` rows measure agent
  quality).
- **Extras**: findings not in the catalog. Judge each — a reasonable extra
  finding is fine (the fixture contains incidental smells); a nonsensical one
  counts against precision.

Run the benchmark 2–3 times before drawing conclusions — judgment findings
vary between runs; the spread itself is a useful metric.

**Record every run in the Baselines table below** with the model and reasoning
effort the review agents ran on (they inherit the session's model and
`effortLevel` unless overridden). Scores are only comparable between runs with
the same model, effort, AND catalog version.

## Precision probes (planted traps that should NOT be reported)

The fixture also plants decoy hits that reach the agents as precomputed hits
but should be **dismissed** by their judgment rules:

- `tests-01` on `python/order_service.py` — a test file DOES exist
  (`test_order_service.py`); flagging it is a false positive.
- `clarity-16` on `python/order_service.py` — the file-level keyword count
  exceeds 10, but no single function has more than 10 branches; flagging any
  function is a false positive.
- `solid-06` on the Python `self.x = ...` constructor assignments — plain
  attribute initialization, not an encapsulation break.
- `clarity-06` on `TestOrderManager` — a test class, not a production noise-word name.
- `tests-01` on `csharp/OrderProcessing.cs` — `OrderProcessingTests.cs` exists.
- `clarity-16` on `csharp/OrderProcessing.cs` — file-level keyword count is high,
  but no single function exceeds 10 branches (the planted clarity-16 lives in
  `swift/Checkout.swift`).
- `solid-10` on `new Mock<>()`/`new Order()` inside `OrderProcessingTests.cs` —
  test-file instantiation is a documented dismissal.
- `tests-01` on `swift/Checkout.swift` — `CheckoutTests.swift` exists.
- `solid-06` on `swift/Checkout.swift:7` (`var amount` in the `Money` struct) —
  value-object mutability is ddd-01's finding (which IS planted there); solid-06
  dismisses value-object structs. Note the synthesizer's solid-06↔ddd-01 pair rule
  drops ddd-01 if solid-06 survives — a solid-06 false positive here also costs
  the ddd-01 recall point.
- `solid-06` on `swift/Checkout.swift:138` (`var heading`) — a function-local
  variable, not a field; the planted finding on that line is solid-08.

Each trap that shows up in the report as a finding is a precision failure.

## Baselines

| Date | Model | Effort | Catalog | Recall | Scripted | Judgment | Traps passed |
|---|---|---|---|---|---|---|---|
| 2026-08-14 | Haiku 4.5 | default | 96 rows (4 languages) | 68/96 (71%) | 38/42 | 30/54 | 5/10 |
| 2026-08-14 | Sonnet 4.6 | high | 96 rows (4 languages) | 85/96 (88.5%) | 42/42 (100%) | 43/54 (79.6%) | 9/10 |
| 2026-08-14 | Sonnet 5 | high | 96 rows (4 languages) | 83/96 (86.5%) strict, 84/96 counting anchor drift | 40/42 (95.2%) | 43/54 (79.6%) | 9/10 |
| 2026-08-14 | Opus 5 | high | 96 rows (4 languages) | 82/96 (85.4%) strict, 88/96 (91.7%) counting anchor drift | 40/42 | 42/54 (77.8%) | 9/10 |
| 2026-08-14 | Fable 5 | high | 96 rows (4 languages) | 83/96 (86.5%) strict, 89/96 counting anchor drift | 35/38 | 48/58 | 10/10 |
| 2026-08-17 | Sonnet 4.6 | default | 96 rows (4 languages) | 79/96 (82.3%) | 40/42 (95.2%) | 39/54 (72.2%) | 7/10 |
| 2026-08-17 | Opus 5 | default | 96 rows (4 languages) | 84/96 (87.5%) | 40/42 (95.2%) | 44/54 (81.5%) | 9/10 |
| 2026-08-17 | Opus 5 | high (run A) | 96 rows (4 languages) | 82/96 (85.4%) post-dedup, 84/96 (87.5%) raw | 40/42 (95.2%) | 42/54 (77.8%) | 9/10 |
| 2026-08-17 | Opus 5 | high (run B) | 96 rows (4 languages) | 83/96 (86.5%) post-dedup, 85/96 (88.5%) raw | 40/42 (95.2%) | 43/54 (79.6%) | 9/10 |
| 2026-08-17 | Haiku 4.5 | default | 96 rows (4 languages) | 83/96 (86.5%) | 39/42 (92.9%) | 44/54 (81.5%) | 2/10 |

2026-08-14 (Haiku 4.5) notes: Scripted layer 38/42 (90.5%). Judgment layer 30/54 (55.6%) — lower judgment
recall reflects model capability tier. Precision issues: 5 trap failures — tests-01 py/cs/swift (test file
exist dismissal), clarity-06 TestOrderManager (test class), solid-06 sw Money/heading (value object + local var),
solid-10 cs mocks (test instantiation). Strong on architecture/SOLID/safety (major findings), weaker on nuanced
clarity/naming patterns. All four languages represented; py/ts showed lower recall (62/66, 63.6%) than cs/sw
(both ~85% on core patterns). Deduplication successful; cross-group pair rules consolidated 127 raw findings
to 117 unique findings (8 Critical, 63 Major, 17 Moderate, 29 Minor).

2026-08-14 (Sonnet 4.6) notes: Scripted layer 42/42 (100%). Judgment misses:
smells-02 py (dedup-dropped by smells-03 rule), smells-04/solid-06/solid-07/ddd-03/tests-07/tests-11
all python (not flagged), smells-13 py (anchor at :37 vs planted :22, different function),
clarity-02 ts (check-id crossover — reported as clarity-04), clarity-13 ts (not flagged for
orderService.ts), solid-11 ts (anchor drift: planted :13, reported :34). 1 trap failure:
clarity-06 on TestOrderManager (test class, should be dismissed). C# and Swift both 100%.

2026-08-14 (Opus 5) notes: Single run. 158 raw group findings → 155 after synthesis
(9 Critical, 81 Major, 30 Moderate, 35 Minor). C# 20/20 and Swift 13/13 (100%);
TypeScript 25/29; Python 24/34 — python judgment recall is the weak spot again, as
in every run so far. Scripted misses (2): `solid-12` ts:26 (`console.log` in a domain
class — precomputed hit was silently dismissed by the solid agent, a false dismissal)
and `smells-08` ts:29 (anchored at :20, the `Order | null` signature, instead of the
`return null` at :29 — the defect was found, the anchor drifted). Judgment misses (12):
`smells-02` py (dedup-dropped by the smells-03 pair rule — same as the Sonnet 4.6 run),
`clarity-05`/`smells-04`/`ddd-03`/`tests-07`/`tests-11` py (not flagged), `clarity-02` ts
(check-id crossover — reported as clarity-04 at the same line, same recurring failure),
and 5 anchor drifts beyond ±3 on the same defect: `clarity-10` py (:22 vs :37),
`smells-13` py (:27 vs :22), `solid-06` py (:59 vs :28), `solid-07` py (:22 vs :57),
`solid-11` ts (:34 vs :13). 1 trap failure: `solid-06` on `python/order_service.py:59`
(`self.total = total`) — the trap line, though the action text argues external mutation
by `OrderRepository.save`, i.e. the planted solid-06 with a drifted anchor rather than a
pure false positive. Extras were all reasonable (mostly `arch-10` missing-doc and
`solid-07` primitive-obsession sweeps across files); none nonsensical.

Cross-run pattern worth acting on: `clarity-02`↔`clarity-04` crossover and the
python anchor drift have now recurred in 3 of 4 runs. Those are prompt problems,
not model problems.

2026-08-14 (Fable 5) notes: C# 19/19 and Swift 13/13 (100% on new fixtures). Misses were
py/ts judgment variance (clarity-05/10, smells-13, solid-06/07/12, tests-07/11),
anchor drift beyond ±3 on the same defect (smells-08 ts, solid-11 ts), and one
check-id crossover (clarity-02 ts reported as clarity-04). Two rows were catalog
defects and have been fixed since: `safety-06` ts:47 (sync context — safety.md
scopes the check to async; replaced by a C# plant inside `async BuildAsync`)
and `clarity-15` re-anchored to the function declaration (agents' consistent
convention, 2/2 runs). The two baseline runs are not directly comparable: the
catalog AND the model both changed between them.

2026-08-14 (Sonnet 5) notes: Single run, high effort. C# 20/20,
Swift 13/13 (both 100%); TypeScript 24/29; Python 26/34 — python judgment recall
is again the weak spot, consistent with every prior run. Scripted misses (2):
`solid-12` ts:26 (`console.log` in a domain class — precomputed hit silently
dismissed by the solid agent, the same false dismissal seen in the Opus run) and
`tests-01` ts:1 (found at ts:13 instead — the scripted detector itself always
anchors this hit at the class declaration line 13, so the catalog's line-1 anchor
is a stale catalog artifact, not a model miss; candidate for the same re-anchor
fix already applied to clarity-15). Judgment misses (11): `clarity-02` ts
(check-id crossover — reported as clarity-04 at the same line, now recurred in
4/5 runs), `clarity-03`/`clarity-05`/`clarity-13`/`smells-04`/`smells-09`/
`solid-06`/`solid-07`/`ddd-03` py/ts (not flagged), and 2 anchor drifts beyond
±3 on a different underlying finding rather than the same defect: `clarity-10`
py (:22 vs :37 — a different `process`-level abstraction complaint, not the
`export_report` I/O-mixing defect) and `smells-13` py (:37 vs :22 — a genuine
`export_report` feature-envy finding, not the planted `process` self-envy one).
1 trap failure: `clarity-06` on `TestOrderManager` (test class, should be
dismissed) — this exact trap has now failed in 2 of 5 runs. Extras were all
reasonable (a large `arch-10` missing-doc sweep across every public symbol in
all four languages, plus additional `solid-01`/`solid-05`/`ddd-04` examples
beyond the single planted instance); none nonsensical, though `ddd-04` findings
at csharp:323/403 overlap conceptually with `arch-01`'s bulk-discount/VAT
findings — a group-boundary blur worth a prompt clarification.

Cross-run pattern update: `clarity-02`↔`clarity-04` crossover has now recurred
in 4 of 5 runs and is the single highest-value prompt fix available — it costs
a judgment-recall point almost every run regardless of model.

2026-08-17 (Sonnet 4.6, default effort) notes: Single run. C# 12/13, Swift 7/7
(both near-perfect); TypeScript judgment 5/8; Python catalogued judgment 4/14 —
python remains the persistent weak spot across all runs. Scripted misses (2):
`arch-02` ts:7 (express import in business code — arch agent dismissed it as a
false positive on the grounds that SessionManager does not use any express types,
but the check targets the import itself not the usage; same false-dismissal logic
as prior runs) and `solid-12` ts:26 (`console.log` in domain class — precomputed
hit silently dismissed by the solid agent, now recurred in 3 of 6 runs, a reliable
prompt gap). Judgment misses (15): `ddd-04` py:70 (anchor drift — found at :74,
4 lines off); `clarity-10` py:37 (found a different defect at py:22, not
export_report I/O-mixing); `smells-19` cs:434 (anchor drift — found at :428,
6 lines off); plus `smells-04`/`smells-09`/`smells-13`/`solid-05`/`solid-06`
(planted at :28)/`solid-07`/`ddd-03`/`tests-07`/`tests-11` py (not flagged) and
`clarity-03`/`clarity-13`/`solid-11` ts (not flagged). 3 trap failures:
`solid-06` on Python constructor assignments (py:18/19/20/58/59 — agent flagged
all as public mutable fields; the trap requires dismissing plain `__init__`
assignments), `clarity-06` on `TestOrderManager` (test class, should be dismissed
— now recurred in 3 of 6 runs), and `solid-10` on C# test mock instantiations
(`new Order()`/`new Mock<>()` inside `OrderProcessingTests.cs` — test-file
instantiation is a documented dismissal in the solid group MD). Effort level
(default vs high) explains the gap vs the 2026-08-14 Sonnet 4.6 high-effort run
(82.3% vs 88.5%); model and prompt are identical.

2026-08-17 (Opus 5, default effort) notes: Single run, full pipeline including
the synthesizer (scores are post-deduplication, matching what a real invocation
returns). C# 20/20 (100%) and Swift 12/13 (92%); TypeScript 26/29 (89.7%);
Python 26/34 (76.5%) — python remains the persistent weak spot across every run
to date. Scripted misses (2): `solid-12` ts:26 (`console.log` in domain class —
precomputed hit silently dismissed by the solid agent, now recurred in 4 of 7
runs, the most reliable prompt gap in the catalog) and `ddd-01` sw:7 (Money
value-object mutability — found correctly by the ddd agent, then dropped from
the final report by the solid-06↔ddd-01 synthesizer pair rule once the solid-06
trap below fired on the same line; a true scoring loss caused by a precision
failure, not a recall miss by the ddd agent). Judgment misses (10): `smells-02`
py:22 (dedup-dropped by the smells-03 pair rule — same mechanism as the
2026-08-14 Sonnet 4.6 run); `clarity-02` ts:34 (check-id crossover — reported as
`clarity-04` at the same line, now recurred in the majority of runs and remains
the single highest-value prompt fix available); `solid-11` ts:13 (the
anemic-entity finding itself not flagged — the related ts:34 `totalWithTax`
symptom was flagged instead, under both `smells-13` and `solid-11`, a different
location for a distinct instance of the same check); plus `clarity-05`/
`smells-04`/`smells-13`/`solid-06`/`solid-07`/`ddd-03`/`tests-07` py (not
flagged at their planted lines — `smells-13` fired instead on a different,
legitimate py:70 instance). 1 trap failure: `solid-06` on
`swift/Checkout.swift:7` (`var amount` in the `Money` value object) — the solid
agent flagged public-mutable-field instead of dismissing it as ddd-01's
territory per the documented pair rule; this is the first run where this
specific trap fails, and it cost a second point indirectly by causing the
synthesizer to drop the correctly-found `ddd-01`. 9/10 traps passed overall,
consistent with the Sonnet 5/Opus 5/Fable 5 high-effort runs from 2026-08-14.
Extras were dominated by a large `arch-10` missing-doc sweep and additional
`solid-07`/`solid-11` instances beyond the single planted example in each file;
none nonsensical.

2026-08-17 (Opus 5, high effort, runs A and B) notes: Two independent runs of
the same catalog, model, and prompts — the spread is the useful signal here.
Group agents produced 151 (A) and 152 (B) raw finding lines. Post-dedup scores
were derived by applying the synthesizer's drop rules to the co-located
findings rather than by spawning the synthesizer agent: every `file:line`
collision in both runs was checked against the pair table, and exactly two
rules fired on planted rows — `solid-06 ↔ ddd-01` (`synthesizer.md:69`, keep
solid-06) drops the correctly-found `ddd-01` sw:7, and `smells-02 ↔ smells-03`
(`synthesizer.md:90`, keep smells-03) drops the correctly-found `smells-02`
py:22. Each run therefore loses one scripted and one judgment point between
the raw group output and the final report. A third collision fired
(`tests-07 ↔ tests-11` on cs:347) but hit extras only.

Per-language recall (raw, before those two drops) was identical across both
runs except one row: C# 20/20 and Swift 13/13 (100%), TypeScript 26/29
(89.7%), Python 25/34 (A) and 26/34 (B) — the single difference between the
two runs was `arch-10` py:48 (`pop_next` undocumented), found in B, missed in
A. Every other planted row resolved the same way in both runs, which puts
run-to-run variance for this model/effort at one point.

Misses common to both runs — scripted (1): `solid-12` ts:26 (`console.log` in
a domain class, precomputed hit silently dismissed by the solid agent; now 6
of 9 runs, still the most reliable prompt gap in the catalog). Judgment (10):
`clarity-02` ts:34 (check-id crossover — both runs reported `clarity-04` at
that exact line instead; now 7 of 9 runs and unchanged as the
highest-value prompt fix available), `solid-11` ts:13 (the anemic-`Order`
finding itself missed; both runs flagged the `totalWithTax` symptom elsewhere
instead), and the persistent Python cluster `clarity-05` :23 / `smells-04`
:28 / `smells-13` :22 / `solid-06` :28 / `solid-07` :57 / `ddd-03` :45 /
`tests-07` :37 / `tests-11` :22 — all unflagged at their planted lines in
both runs, with `smells-13` firing instead on a legitimate but different
py:27 (A) / swift:95 (B) instance.

1 trap failure in both runs, the same one: `solid-06` on `swift/Checkout.swift:7`
(`var amount` in the `Money` value object) — the solid agent flagged
public-mutable-field instead of leaving it to ddd-01, exactly as in the Opus 5
default-effort run above, and again cost a second point by triggering the
pair-rule drop of `ddd-01`. This trap has now failed in 4 of 9 runs — the
Haiku 4.5 run and the three most recent ones; the `clarity-06`
`TestOrderManager` trap that dominated the earlier failures passed cleanly in
both runs. Extras were again dominated
by the `arch-10` missing-doc sweep (26 arch findings in B vs 15 in A — the
largest single-group divergence between the two runs) plus additional
`solid-01`/`solid-05`/`solid-07`/`ddd-04` instances; none nonsensical.

Effort comparison: at high effort Opus 5 scores 82–83/96 against 84/96 at
default effort in the run recorded above. Those two rows are not directly
comparable — the default-effort row is a single post-synthesis run and its
`ddd-01` loss came from the same trap failure, so the 1–2 point difference sits
inside the run-to-run spread measured here. Two runs at one effort level are
not enough to claim an effort effect in either direction.
