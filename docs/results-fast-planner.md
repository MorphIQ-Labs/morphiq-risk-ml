# Fast scenario planner measurements (#97)

`Planner.Fast` adds bounded, ordered approximate price streaming over frozen
portfolios and scenarios. [The contract](fast-planner.md) defines per-unit
prices, explicit failures, separate types and replay identity. There are no
certified radii or aggregate totals in this interface.

Implementation revision: `e5bf63a51e692b2432f7dc1bcb0654609c64e2aa`, based on
PR #99 merge `b9c9c47e843ecc6ce1c15a5f4ed2732120827830`. Subsequent documentation
and evidence commits leave measured implementation sources unchanged.
[Retained evidence](evidence/fast-planner/README.md) binds sources, binaries,
toolchain, outcomes and sample distributions.

## Fast workload costs

Apple M1 Pro, macOS 27, OCaml 5.3.0 Flambda, Dune default profile with library
`-O3`. Task-owned builds/tests/profilers completed before timings. Other host
activity was substantial: recorded one-minute load was 57.5–65.9 during
this fast campaign. Per-process load is retained in the raw report. Five fresh
processes provide twenty-five batch means per size/phase: three warmups,
five samples and `max(1,4096/n)` iterations per sample, with full major GC
outside timing. Phase order is fixed, not randomized.

Each job contains n positions mixing all four European models, both sides and
varying strikes, evaluated at four valuation dates (0, 7, 30, 90 days) with
fixed day-365 expiries. All measured prices succeed. Tiles contain 32 rows;
limits allow four workers and 128 buffered results. Worker-one/four ordered
row and completion digests match before timing. Failed inputs, expiry and
other correctness cases are checked separately, not counted as fast successes.

| Positions × scenarios | Compile, ms/job | Execute one worker, ms/job | Execute four workers, ms/job | Pack + compile + execute one worker, ms/job | One-worker execution, µs/row |
| --- | ---: | ---: | ---: | ---: | ---: |
| 32 × 4 | 0.060 | 0.259 | 0.370 | 0.329 | 2.027 |
| 256 × 4 | 0.426 | 2.082 | 2.782 | 2.546 | 2.034 |
| 1024 × 4 | 1.676 | 8.280 | 10.894 | 10.180 | 2.021 |

These are medians of whole-job means, not individual BSM latency percentiles.
Compilation caches structural validation and bindings; each generated scenario
row still requires transformation and model admission. Unlike `Batch.Fast`,
it does not retain admitted inputs for the entire Cartesian cube. Reusing a
plan saves compilation and input packing on later executions, but does not
remove those per-row costs or change the scalar numerical kernels.

Four-worker execution is 1.32–1.43 times the one-worker elapsed median here,
and consumes roughly three times its process CPU time. These 32-row waves
spawn and join domains; this workload establishes no parallel speedup. Prefer
one worker for this measured configuration. Larger tiles, workload crossover
and broader integrated qualification remain under #98; no worker-pool or
scheduling optimization is implied by this feature. Spreads include host
interference: the largest four-worker job ranges from 8.844 to 33.033 ms.

| Positions | Compile allocated bytes/job | One-worker execution allocated bytes/row | Full request allocated bytes/row |
| --- | ---: | ---: | ---: |
| 32 | 72,465 | 13,107 | 13,701 |
| 256 | 537,104 | 13,106 | 13,658 |
| 1024 | 2,130,064 | 13,106 | 13,654 |

Allocation uses current-domain `Gc.counters` (minor + major - promoted words,
eight bytes/word). With one worker this covers the job's OCaml allocation;
these are cumulative temporary bytes, not retained size or RSS. The raw
four-worker allocation is **coordinator-only**, excluding worker domains, and
must not be presented as total allocation or an allocation improvement.
Plan explanation's eight bytes per raw price is a checked value-volume lower
bound, not an OCaml heap estimate. Execution retains bounded wave rows while
plan storage scales with the frozen structure; the caller owns sink retention.

## Certified compatibility

The baseline is merged PR #99 head `f5069cd28362a3babf4152fd3e451eaedb2b83f8`
(the source tree of merge `b9c9c47`). Both binaries use the unchanged
`shared_portfolio` harness: 24 rows across four models, three scenario dates,
and one, two or eleven certified outputs per row. Two sequential ABBA rounds
provide twenty samples per phase/variant. No task-owned tests or builds ran
alongside this comparison. Host one-minute load ranged from 60.2 to 72.5;
this is compatibility evidence with noisy timing, not an isolated performance
qualification.

All nine ordered output digests match between revisions and workers 1/2,
including certificate fields, aggregates, failure classes and completion.
Three additional compiled plan identities match at 32, 1024 and 4096 positions.
The stable certified signatures and identity encoding remain unchanged.

| Regime / outputs per row | Baseline execution, ms/job | Candidate execution, ms/job | Elapsed change | Baseline CPU, ms/job | Candidate CPU, ms/job |
| --- | ---: | ---: | ---: | ---: | ---: |
| boundaries/1 | 6.164 | 6.947 | +12.7% | 6.113 | 6.317 |
| boundaries/11 | 13.712 | 13.843 | +1.0% | 13.665 | 13.754 |
| boundaries/2 | 9.050 | 9.262 | +2.3% | 9.018 | 9.170 |
| failure/1 | 0.078 | 0.078 | +0.6% | 0.077 | 0.078 |
| failure/11 | 0.118 | 0.119 | +0.8% | 0.118 | 0.119 |
| failure/2 | 0.081 | 0.082 | +0.6% | 0.082 | 0.082 |
| ordinary/1 | 22.994 | 18.937 | -17.6% | 19.771 | 18.861 |
| ordinary/11 | 43.438 | 42.773 | -1.5% | 42.717 | 42.556 |
| ordinary/2 | 32.892 | 27.872 | -15.3% | 28.992 | 27.775 |

Execution medians range from 17.6% faster to 12.7% slower; end-to-end medians
range from 27.4% faster to 21.0% slower. The spreads overlap and some elapsed
outliers exceed 100 ms. These measurements cannot establish a stable speedup
or rule out a timing regression on a quiet deployment host. The complete
compile/execution/end-to-end ranges and CPU samples are retained. Allocation
is deterministic: shared structure adds 16 bytes per compiled plan and
768 bytes per 24-row execution in every case (32 bytes/row on this corpus).
Certified pricing still dominates these ordinary workloads; there is no
change to its numerical arithmetic or acceptance policy. A quieter performance
comparison remains part of #98 rather than treating this noisy run as a gate.

## Validation and limits

- Public build/install, formatting and the complete ordinary suite pass.
- Native and bytecode fast-planner controls compare explicit scalar requests
  for all four models, both sides, six scenarios and both supported day counts.
  They exercise date rolls, shocks, expiry/post-expiry precedence, failed
  admission, quantity-as-metadata, identity, array snapshot isolation,
  empty input, checked overflow and all resource limits.
- Workers 1, 2, 3 and 4 preserve row/event order, with coordinator-only sinks.
  Cancellation, pre-cancellation, sink rejection and worker limits are checked.
  The shared scheduler's existing 44 fault/stress cases pass after moving
  instrumentation to the extracted scheduler owner.
- Compile-failure witnesses reject mixing certified and fast plans or tiles.
  Existing fast/certified result and volatility-coordinate separation remains.
- Six targeted mutations are killed after a clean baseline: fast tile identity,
  fast side dispatch, snapshot copying, post-expiry handling, certified scalar
  radius and incomplete certified totals. Catalog: 94; default CI remains seven.
- Existing independent price-oracle checks and all 99,088 fast-batch fixture
  equivalence outcomes pass. Scalar agreement itself is not an accuracy proof.
  Public numerical digest remains
  `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
- The immutable implementation source artifact installs and passes native and
  bytecode external consumers, including fast planner worker replay,
  post-expiry failures and existing Fast Batch/certified Batch/Planner/Exchange
  checks. Ten installed notices match; both Exchange consumers retain 649 outcomes.

#98 owns integrated platform/workload qualification, including broader fast
planner numerical regimes, concurrent reuse and memory/performance controls.
The present API has no Greeks, IV, approximate aggregation or economic P&L.
Three-platform ordinary CI is required before landing; performance here covers
only this shared M1 Pro. No release, universal numerical certificate or
institutional deployment acceptance is implied.
