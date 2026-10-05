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

[All American samples](evidence/american-enclosure-allocation/performance.json)
and [European samples](evidence/american-enclosure-allocation/european-performance.json)
retain both build manifests, raw records, GC counters and per-child RSS.
Apple M1 Pro, 16 GiB, macOS 27, OCaml 5.3.0 Flambda, release `-O3`.
American one-minute load: 5.84–15.46; the host was shared.
European one-minute load: 5.63–7.37; the host was shared.

| American price, full refinement | Allocation before → after | Reduction | Median latency before → after | Candidate process-mean range |
| --- | ---: | ---: | ---: | ---: |
| none | 48.33 → 16.69 MB | 65.5% | 152.6 → 142.9 ms | 142.2–143.4 ms |
| zero | 92.90 → 37.01 MB | 60.2% | 419.2 → 405.1 ms | 403.5–411.0 ms |
| cash | 115.78 → 49.75 MB | 57.0% | 429.4 → 416.6 ms | 413.0–426.0 ms |
| multiple | 166.06 → 76.78 MB | 53.8% | 641.5 → 620.6 ms | 618.1–643.2 ms |

American latency is broadly unchanged: median reductions are only 3–7% on this
shared host; this campaign does not establish a portable speed advantage.
The material result is reduced allocation. All frozen allocation/latency criteria
also pass with optional diagnostics; admission allocation is unchanged.

For none: baseline 7.7 MB peak RSS, 72 minor / 9 major collections → candidate 7.8 MB peak RSS, 26 minor / 9 major collections (GC counts per three measured requests).
For cash: baseline 7.9 MB peak RSS, 171 minor / 17 major collections → candidate 8.1 MB peak RSS, 76 minor / 15 major collections (GC counts per three measured requests).

MB means 1,000,000 bytes. Cumulative allocation is distinct from simultaneous
live storage and process RSS. A roughly 50 MB cash request still warrants care
before portfolio scaling; this pass does not declare it an acceptable deployment
budget. Follow-up profiles retain dividend interpolation, enclosed time/boundary
arithmetic and grid preparation as remaining allocation owners.

| European certified price case | Allocation before → after | Median latency before → after | Median ratio |
| --- | ---: | ---: | ---: |
| black76 | 1296.5 → 633.7 KB | 854.36 → 748.16 µs | 1.14× |
| bsm-accuracy-failure | 1308.2 → 639.9 KB | 893.55 → 798.81 µs | 1.12× |
| bsm-expiry | 0.6 → 0.3 KB | 0.11 → 0.09 µs | 1.29× |
| bsm-ordinary | 1308.3 → 639.9 KB | 893.44 → 800.00 µs | 1.12× |
| bsm-short | 673.1 → 369.6 KB | 327.35 → 296.06 µs | 1.11× |
| bsm-tail | 4181.0 → 2309.9 KB | 3208.01 → 2898.69 µs | 1.11× |
| displaced | 1295.2 → 616.5 KB | 846.68 → 749.18 µs | 1.13× |
| normal | 628.0 → 290.5 KB | 310.95 → 261.34 µs | 1.19× |

Every complete CHECK record is unchanged, including the explicit accuracy
failure. Price and end-to-end phases pass the frozen 10% latency/allocation
regression limits. Ratios are these shared-host sample medians, not a portable
guarantee. European Fast kernels were not changed or claimed faster.

The [compatibility record](evidence/american-enclosure-allocation/compatibility.json),
[profiles](evidence/american-enclosure-allocation/profiles.json), and
[validation record](evidence/american-enclosure-allocation/validation.json)
retain the qualification details. Compressed raw outputs and logs sit beside
these records. Initial loader/startup failures and the first invalid mutation
attempt are retained and excluded from successful numerical/timing evidence.

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
All task-owned builds, tests and profilers finish before timing. Shared-host measurements are
engineering evidence, not production capacity or tail-latency guarantees.

This is a second focused scalar pass. Remaining enclosure/mapping allocation
and further compiled-workload, backend and algorithm evaluation stay under #119;
strict accuracy and source-artifact qualification remain under #120.

## Reproduction

The measured baseline is `1b0481dfdb14bdb8726ca45830fb8112230dcb2e`
(#131 runtime plus the updated allocation driver); the measured candidate is
`812b1f63c198a003cda894ea15d68beab1d42757`. Later changes in this PR only
package documentation and evidence. Each performance JSON retains the complete
`builds.baseline` and `builds.candidate` manifests, including compiler settings,
source hashes and executable hashes. Rebuild the recorded sources in separate
worktrees using the pinned Flambda switch and the release profile. Record new
binary paths/hashes and compiler output for that build; do not relabel historical
binaries. Run the collectors from the candidate worktree after other task-owned
work has finished, with fresh output directories:

```sh
python3 scripts/benchmark_american_allocation.py \
  --baseline baseline-build.json --candidate candidate-build.json \
  --minimum-allocation-reduction .5 --maximum-latency-regression .1 \
  --output american-paired
python3 scripts/benchmark_enclosure_consumers.py \
  --baseline baseline-build.json --candidate candidate-build.json \
  --output european-paired
```

The collectors validate the recorded source/driver hashes and executable bytes;
output directories retain incomplete attempts as well as completed samples.
Exact source hashes, rather than a relocated temporary path, identify the build.
