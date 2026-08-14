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
| 2026-08-13 | Sonnet 5 | high | 42 rows (py+ts only) | 40/42 (95.2%) | 25/26 | 15/16 | 4/4 |
| 2026-08-14 | Fable 5 | high | 96 rows (4 languages) | 83/96 (86.5%) strict, 89/96 counting anchor drift | 35/38 | 48/58 | all |
| 2026-08-14 | Sonnet 4.6 | default | 96 rows (4 languages) | 85/96 (88.5%) | 42/42 (100%) | 43/54 (79.6%) | 9/10 |

2026-08-14 notes: C# 19/19 and Swift 13/13 (100% on new fixtures). Misses were
py/ts judgment variance (clarity-05/10, smells-13, solid-06/07/12, tests-07/11),
anchor drift beyond ±3 on the same defect (smells-08 ts, solid-11 ts), and one
check-id crossover (clarity-02 ts reported as clarity-04). Two rows were catalog
defects and have been fixed since: `safety-06` ts:47 (sync context — safety.md
scopes the check to async; replaced by a C# plant inside `async BuildAsync`)
and `clarity-15` re-anchored to the function declaration (agents' consistent
convention, 2/2 runs). The two baseline runs are not directly comparable: the
catalog AND the model both changed between them.

2026-08-14 (Sonnet 4.6) notes: Scripted layer 42/42 (100%). Judgment misses:
smells-02 py (dedup-dropped by smells-03 rule), smells-04/solid-06/solid-07/ddd-03/tests-07/tests-11
all python (not flagged), smells-13 py (anchor at :37 vs planted :22, different function),
clarity-02 ts (check-id crossover — reported as clarity-04), clarity-13 ts (not flagged for
orderService.ts), solid-11 ts (anchor drift: planted :13, reported :34). 1 trap failure:
clarity-06 on TestOrderManager (test class, should be dismissed). C# and Swift both 100%.
