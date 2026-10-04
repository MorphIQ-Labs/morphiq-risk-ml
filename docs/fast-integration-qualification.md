# Integrated fast pricing qualification (#98)

The additive `Batch.Fast` and `Planner.Fast` APIs retain the existing scalar
price kernels with explicit approximate-result types. This campaign qualifies
their integration; it does not add an error certificate, aggregate-price
contract, Greek/IV batch mode, release approval or deployment SLA.

The qualified implementation is PR #100 merge
`e7eca36ca1acf848e8946708cd84ef1ff7d3c8f2`. Qualification sources are
`1f6dd3b1cbd76287657c88b227cb0af4e66bb473`; no production source or numerical
formula changes in this qualification. [Evidence](evidence/fast-integration/README.md)
records toolchain, source identities, raw checks and measurement limitations.

## Numerical coverage and ownership

The shared fixture reader validates immutable fixture membership before either
batch or planner comparison. All 99,088 European/displaced fixture outcomes
retain exact scalar result words/classes through one-shot and compiled batches.
Planner maturity is a civil-day count divided by 365 or 360. Its new fixture
check accepts only exact round trips, with no input rounding:

| Model | Planner fixture outcomes |
| --- | ---: |
| BSM | 24,256 |
| Black-76, including shifted-input comparisons | 6,696 |
| Displaced Black | 41,768 |
| Bachelier | 5,024 |
| Total | 77,744 |

The remaining 21,344 fixture rows have nonrepresentable maturities in this
civil-day API. They remain in the complete batch/scalar checks; no changed
maturity is compared against an old reference value. The selected rows retain
both sides and the fixture's ordinary/tail/boundary regimes. Independent
high-precision price scoring runs separately in the ordinary suite. Adapter
agreement with scalar output is not an independent numerical accuracy proof.

Additional native and bytecode controls exercise original-word severe BSM
carry cancellation (including an unresolved-cell availability guard), mixed
payoff overflow, exact expiry and explicit post-expiry. The original cancellation
cells are the same independently checked cases retained in
[the carry-cancellation report](results-carry-cancellation.md).

The planner control suite now also checks three simultaneous callers, each
replaying the same frozen plan three times with two workers; reentrant execution
from a sink; fresh tile-array ownership; and a throwing sink's accepted prefix.
Existing checks retain original array isolation, both day counts, six shock/date
scenarios, workers 1–4, empty inputs, all resource fields, overflow, cancellation
and compile-time separation from certified plans, tiles and results.

The test-only planner wrapper now observes fast tile retention as well as the
shared scheduler. Explicit tile failures with one and four workers retain the
four rows preceding the failed tile, join all spawned domains, and release
all tracked output slots. Existing 44 certified scheduler fault/stress cases
remain applicable to their shared scheduler and still pass. Wrapper generation
rejects missing or ambiguous source sites; instrumentation is not production code.

## Bounded memory

A separate instrumented campaign uses eight Black-76 positions, a compact
linear scenario axis and a non-retaining sink. Six fresh processes vary scenario
count and worker count. Four-row tiles have a configured sixteen-row buffer
bound. Samples force major collection at the first row and every 4,000 rows;
these live-heap observations are not peak RSS or a universal heap bound.

| Scenarios | Total rows | Peak output slots, one / four workers | Sampled live words, one / four workers |
| --- | ---: | ---: | ---: |
| 8 | 64 | 4 / 16 | 5,937 / 6,130 |
| 800 | 6,400 | 4 / 16 | 5,937 / 6,130 |
| 8,000 | 64,000 | 4 / 16 | 5,937 / 6,130 |

All six runs begin at 5,840 live words. A thousandfold increase in scenario
count leaves sampled live data and peak retained row slots unchanged. The
checked slot limit is an exact instrumentation assertion; sampled live heap is
empirical corroboration. The entire result cube is not retained by this sink.
The caller can still defeat bounded retention by collecting every emitted row.

Allocation counters sum coordinator and spawned-worker-body `Gc.counters`
deltas after every domain has joined. This includes probe overhead, but excludes
worker runtime initialization, stacks and non-OCaml allocation. The generated
wrapper uses test build flags, so these figures are not production timing or
an exact allocation profile of the optimized production binary. At 64,000 rows,
one worker allocates 1,044,247,696 bytes cumulatively and four allocate
1,053,367,768 bytes (about 16.32 / 16.46 KB per row on this Black-76 corpus).
These are temporary allocation volumes, not a one-gigabyte retained book.
Unlike the earlier coordinator-only counter, this comparison does account for
pricing work performed in spawned domains.

## Performance and reuse

All task-owned builds, tests, mutations and package validation finished before
these timing runs. Measurements use Apple M1 Pro, macOS 27 and OCaml 5.3.0
Flambda with production library `-O3`. Other host activity increased: one-minute
load reached 134.6–148.8 during the repeated certified ABBA campaign and remained
138.4–148.8 across fast campaigns. This attempt did **not** produce a quiet-host
comparison. Keep that unresolved performance qualification under #8/#27; do not
infer an idle-host SLA or absence of timing regression from these measurements.

Five fresh processes retain twenty-five means per fast phase/configuration,
with three warmups and full major collection outside timing. Phases run in a
fixed order. Reported costs are per-batch or per-job means, not individual
latency percentiles. Raw elapsed/CPU ranges and loads are retained.

| Flat batch size | Compile CPU, µs/item | Reused execute CPU, µs/item | One-shot CPU, µs/item | Full request CPU, µs/item | Full request elapsed, µs/item |
| --- | ---: | ---: | ---: | ---: | ---: |
| 32 | 0.955 | 0.960 | 1.917 | 2.168 | 3.247 |
| 256 | 1.089 | 0.995 | 2.046 | 2.205 | 3.979 |
| 1024 | 1.213 | 0.980 | 1.942 | 2.369 | 3.902 |

Full requests include input packing, compilation, execution and extraction.
Reused execution still matches manually pre-admitted scalar dispatch closely
in this corpus. For R executions, compare `compile + R × execute` against
`R × one-shot`; the measured costs are near crossover after one execution for
32 items and favor reuse by the second for all sizes. Such small crossover
estimates are sensitive to phase noise. The earlier [lower-load batch report](results-fast-batch.md)
found the same second-execution crossover. Compilation does not accelerate
scalar kernels. Current compile allocation is about 6.4 KB/item; execution
is 5.6–5.8 KB/item and full request allocation is 12.2–12.3 KB/item.

The worker/tile campaign holds 4,096 mixed-model positions and four dates fixed
(16,384 prices per job). Each configuration checks identical worker-one/four
outcomes outside timing; only tile and buffer limits vary.

| Tile rows | Compile, ms/job | Execute one worker, ms/job | Execute four workers, ms/job | One-worker CPU, ms/job | Four-worker CPU, ms/job | Full one-worker request, ms/job |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 6.762 | 47.934 | 167.984 | 34.170 | 180.783 | 68.356 |
| 256 | 6.638 | 34.300 | 94.116 | 33.962 | 123.846 | 56.704 |
| 1024 | 6.630 | 36.061 | 83.045 | 33.878 | 144.246 | 55.766 |

Larger tiles reduce the four-worker elapsed median in this sequence, but none
beats one worker. The host was heavily contended and tile campaigns were
sequential, so this is not a demonstrated general crossover or an optimal tile
size. One-worker execution CPU is about 2.07–2.09 µs/row; allocation remains
about 13.1 KB/row. Raw four-worker production counters are coordinator-only;
use the separately scoped memory probe above when examining worker allocation.

The certified comparison repeats two sequential ABBA rounds against merged
PR #99 head `f5069cd28362a3babf4152fd3e451eaedb2b83f8`, using the unchanged
24-row mixed-model portfolio harness. All nine certificate/aggregate/failure
outcome digests still match across revisions and workers 1/2.

| Certified regime / outputs per row | Baseline elapsed, ms/job | Candidate elapsed, ms/job | Baseline CPU, ms/job | Candidate CPU, ms/job |
| --- | ---: | ---: | ---: | ---: |
| boundaries/1 | 6.093 | 6.095 | 6.093 | 6.095 |
| boundaries/11 | 19.254 | 18.524 | 14.163 | 13.791 |
| boundaries/2 | 9.361 | 12.548 | 8.977 | 9.414 |
| failure/1 | 0.079 | 0.081 | 0.079 | 0.081 |
| failure/11 | 0.208 | 0.281 | 0.207 | 0.281 |
| failure/2 | 0.197 | 0.082 | 0.197 | 0.082 |
| ordinary/1 | 18.784 | 18.947 | 18.782 | 18.861 |
| ordinary/11 | 68.262 | 67.887 | 46.268 | 47.355 |
| ordinary/2 | 45.308 | 45.307 | 29.573 | 29.578 |

The large variations, including on very short failure-only workloads, make
elapsed improvements and regressions inconclusive. CPU medians are also
workload/host-dependent and are not a substitute for a controlled deployment
comparison. Deterministic allocation remains +16 bytes per certified plan and
+768 bytes per 24-row execution versus #99. The original noisy comparison is
retained in [the implementation report](results-fast-planner.md); neither run
is presented as proof of unchanged timing.

## Package and platform evidence

The immutable qualification source archive installs into an isolated prefix.
Native and bytecode external consumers pass the four-model Fast batch checks,
Fast planner worker/expiry checks and existing certified Batch/Planner/Exchange
contracts; all ten installed notices match their originals. Both installed
Exchange consumers retain 649 outcomes. The archive and matching report/build
log are preserved outside the checkout in the revision's local acceptance store.

The merged implementation's five successful checks are retained: ordinary tests
on Ubuntu x86-64, Ubuntu ARM64 and macOS ARM64, formatting and seven core
mutations. This qualification PR must pass those same checks before landing.
Local public build/format and the complete ordinary suite pass, including the
new native/bytecode ownership controls and full independent reference checks.
A clean mutation baseline and both targeted fast-planner tile/side kills pass;
the optional catalog remains 94 and the default CI selection remains seven.
Public numerical digest remains
`5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.

No new approximation or numerical bound is introduced. Fast prices remain
finite nonnegative approximations or explicit failures; quantities are metadata
on planner rows, and callers own any subsequent weighting/aggregation.
The civil-day maturity restriction, instrumented memory scope, shared-host
measurement limits and lack of parallel speedup for small tiles remain explicit.
Institutional review and deployment decisions stay under Epic #27.
