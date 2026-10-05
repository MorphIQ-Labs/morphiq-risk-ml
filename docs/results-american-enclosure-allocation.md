# American enclosure allocation follow-up (#119)

This follows the [first boxing pass](results-american-allocation.md). The frozen
[protocol](evidence/american-enclosure-allocation/protocol.md) targets at least
50% less allocation than #131 for matched no/zero/one-cash prices, including
requested diagnostics, without more than 10% median latency regression. This
is a local engineering criterion, not a deployment allocation budget or SLA.

## Implementation and ownership

The three-request Memprof baseline identifies immutable enclosure construction,
packing arrays and arithmetic as the remaining allocation owners. Scalar fusion
avoids temporary exact/negated records. Scalar quotient refinement reuses one
private eight-word packing array, with explicit used lengths and immutable
returned records. The [operation-level derivation](runtime-enclosures.md#scalar-fusion-and-quotient-local-scratch)
preserves operand words, signed-zero shortcuts, separately rounded operations,
explicit FMA, radius accumulation and finite checks. Both enclosure precisions
share this implementation; European users are therefore also qualified.

Within American pricing, a private solver-pair closure fixes the immutable model,
side, stock grid, time count, cash schedule and capture policy. The lower and
upper boundary solves share the same immutable payoff and spatial coefficients.
Those quantities do not depend on the varying boundary choice. Each pair owns
its preparation; no cache key, global state, reuse across requests, or reuse
across different grids/refinement configurations is involved. The shared arrays
replace the corresponding per-solve arrays, so no additional grid-sized live
storage is required by this reuse. The existing conservative workspace bound
also covers the quotient's eight-word temporary.

Both solves still visit their payoff/stencil rows, enforce the same work limits
and cancellation polling, and report the same logical row/upwind counts. The
first preparation checks all coefficients/payoffs before sharing them. The
boundary arithmetic indicator is monotone over the request and already retains
the first identical payoff checks. Solution vectors, matrices, policy flags,
boundary values and dividend state remain separate mutable solve storage.
Coefficient reuse must be reconsidered if future piecewise inputs make the
operator time dependent; this closure covers the current constant-input model.

Time stepping reuses the previous step's centre instead of recomputing the
identical expression at `j-1`. Its grid validation remains in place. The old
expression equals the prior evaluated coordinate for every step: `j-1` is
strictly below the terminal step index, so the endpoint special case cannot
alter it. A preceding failure cannot produce a cached coordinate.

## Qualification

All 284 complete American outcomes are compared with #131: 41 no-cash and
30 cash cases, primary/loose targets, initial/refined configurations. This
includes failed outputs and work/refinement/mapping diagnostics. Independent
reference scoring remains authoritative; replay identity is compatibility
evidence only. Strict-target failures and unresolved references remain visible.

The new scalar enclosure witness covers 10,400 differential cases and 38,616
exact-rational containment checks across two/four-word configurations. Its
complete field/refusal replay matches the unchanged baseline. Signed zeros,
subnormals, residual-quantum thresholds, exponent extremes, nonzero radii,
overflow refusals and independent domain ownership are exercised. Existing
Fast, European model/Greek/IV certificate and determinism suites remain required.

Three new optional mutants target a lost scalar input radius, stale scratch
tail slots and a reversed reused stencil. The full catalog is now 108; default
CI remains the same five jobs and seven core mutants. No public API, assurance
classification, accuracy threshold or numerical policy changes.

## Measurements

<!-- measured-results -->

Both builds use the same updated allocation driver. `Gc.counters` measures
allocated words (minor + major − promoted), replacing the approximate
`quick_stat` word totals in the previous report. Historical #131 samples retain
their original accounting and sources; the paired baseline here is remeasured.
GC cycle counts still use `quick_stat`. Each child's own `wait4` supplies peak
RSS and CPU use. All raw samples, hashes and host load remain in the evidence.

The American campaign reuses the exact #131 configurations and full refinement
program, with five alternating fresh-process pairs and three calls per process
after warmup (100000 admissions). The European certified campaign runs all eight
existing `certified_scalar` cases in five alternating process pairs, retaining
the five inner samples per phase, complete CHECK records and explicit refusals.
All task-owned computation finishes before timing. Shared-host measurements are
engineering evidence, not production capacity or tail-latency guarantees.

This is a second focused scalar pass. Remaining enclosure/mapping allocation
and further compiled-workload, backend and algorithm evaluation stay under #119;
strict accuracy and source-artifact qualification remain under #120.
