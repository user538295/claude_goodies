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

96 rows covering **all 85 checks** at least once.

**Never "fix" these files.** Broken is their job. If a check is added or
changed, plant a new violation and add its row to `planted.tsv`.

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
| 2026-08-14 | Sonnet 5 | default | 96 rows (4 languages) | 83/96 (86.5%) strict, 84/96 counting anchor drift | 40/42 (95.2%) | 43/54 (79.6%) | 9/10 |
| 2026-08-14 | Opus 5 | high | 96 rows (4 languages) | 82/96 (85.4%) strict, 88/96 (91.7%) counting anchor drift | 40/42 | 42/54 (77.8%) | 9/10 |
| 2026-08-14 | Fable 5 | high | 96 rows (4 languages) | 83/96 (86.5%) strict, 89/96 counting anchor drift | 35/38 | 48/58 | 10/10 |

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

2026-08-14 (Sonnet 5) notes: Single run, default effort (no override). C# 20/20,
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


