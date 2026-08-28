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
- `cpp/order_processing.cpp` + `cpp/order_processing_test.cpp` — 23 planted violations
- `planted.tsv` — the catalog: check, file, line, detect (scripted/judgment), description

119 rows across **5 languages**, exercising **88 of the 126 checks** at least once. The C++ fixture (added 2026-08-28) is the first to plant `safety-16`, `safety-17`, and `safety-19`, which previously had no fixture anywhere. The remaining unplanted checks (the rest of safety-08 through safety-32, smells-20 through smells-25, arch-11 through arch-15, tests-13, ddd-06 through ddd-09) are scriptable or judgment-only and covered by `tests/corpus.tsv` where scriptable; they have no planted violation here yet.

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
/clean-code-review python/order_service.py python/test_order_service.py typescript/orderService.ts typescript/inventory.test.ts csharp/OrderProcessing.cs csharp/OrderProcessingTests.cs swift/Checkout.swift swift/CheckoutTests.swift cpp/order_processing.cpp cpp/order_processing_test.cpp
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
- `solid-06`/`ddd-01`/`solid-07`/`safety-16` on the plain data structs in
  `cpp/order_processing.cpp` (`Address`, `LineItem`, `Order` — public fields like
  `street`, `quantity`, `total`, `currency`) — these are idiomatic public data
  carriers / value objects, not encapsulation breaks; only the `OrderManager`
  member `lastArchivedOrderId` (solid-06) and the `Money` mutator+field (ddd-01)
  are real. The line patterns cannot see the enclosing type's role, so expect and
  dismiss the struct-field hits.
- `tests-05` on `cpp/order_processing_test.cpp:7` IS a real finding (a test that
  `#include`s the implementation `.cpp`), not a decoy — it is planted.

Each trap that shows up in the report as a finding is a precision failure.

## Baselines

| Date | Model | Effort | Catalog | Recall | Scripted | Judgment | Traps passed |
|---|---|---|---|---|---|---|---|
| 2026-08-14 | Haiku 4.5 | default | 96 rows (4 languages) | 68/96 (71%) | 38/42 | 30/54 | 5/10 |
| 2026-08-14 | Sonnet 4.6 | high | 96 rows (4 languages) | 85/96 (88.5%) | 42/42 (100%) | 43/54 (79.6%) | 9/10 |
| 2026-08-14 | Sonnet 5 | high | 96 rows (4 languages) | 83/96 (86.5%) strict, 84/96 counting anchor drift | 40/42 (95.2%) | 43/54 (79.6%) | 9/10 |
| 2026-08-14 | Opus 5 | high | 96 rows (4 languages) | 82/96 (85.4%) strict, 88/96 (91.7%) counting anchor drift | 40/42 | 42/54 (77.8%) | 9/10 |
| 2026-08-14 | Fable 5 | high | 96 rows (4 languages) | 83/96 (86.5%) strict, 89/96 counting anchor drift | 35/38 | 48/58 | 10/10 |
| 2026-08-17 | Haiku 4.5 | default | 96 rows (4 languages) | 83/96 (86.5%) | 39/42 (92.9%) | 44/54 (81.5%) | 2/10 |
| 2026-08-17 | Sonnet 4.6 | high | 96 rows (4 languages) | 79/96 (82.3%) | 40/42 (95.2%) | 39/54 (72.2%) | 7/10 |
| 2026-08-17 | Opus 5 | high | 96 rows (4 languages) | 83/96 (86.5%) post-dedup, 85/96 (88.5%) raw | 40/42 (95.2%) | 43/54 (79.6%) | 9/10 |
| 2026-08-17 | Fable 5 | high | 96 rows (4 languages) | 84/96 (87.5%) strict, 86/96 (89.6%) counting anchor drift | 40/42 (95.2%) | 44/54 (81.5%) | 10/10 |
