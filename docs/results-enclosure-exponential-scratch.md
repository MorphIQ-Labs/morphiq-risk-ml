# Enclosed exponential scratch: allocation qualification

Bounded call-owned scratch reduces cumulative managed allocation by **13.3% for
Bermudan, 20.5% for piecewise and 15.0% for piecewise-cash singleton pricing**.
Ordinary cash allocation is unchanged; latency is broadly unchanged. Adopt this
storage optimization on the American integration branch. This is a local
engineering result, not a deployment budget or a new accuracy claim.

## Change and frozen scope

The [allocation profile](results-american-remaining-allocation.md) identified
repeated enclosed exponentials in time/boundary work. `Enclosure.exp` and
`expm1` now reuse one private packing array within each call. Both precisions
use the same storage discipline; all retained words and radii are copied into
immutable results. The array is bounded by `max 8 (2 * words * words)` floats,
with a checked allocator and explicit used-prefix lengths. The
[storage argument](runtime-enclosures.md#exponential-owned-scratch) covers
nested operations, failure and independent domains.

No arithmetic order, series degree, error bound, work budget, cancellation
boundary, public API, financial method or failure classification changes.
There is no additional cache, factor reuse, FFI or vendor dependency. European
Fast pricing kernels are unchanged; shared runtime enclosure consumers benefit.

The [protocol](evidence/american-remaining-allocation/exponential-protocol.md)
and independent exponential tests were frozen before runtime edits at baseline
`450d3aa107c2b5ce6b35e0a96415ee45b7a2c40d`. Its production runtime is identical
to integration `9fae37a6f6eb13d09db99f658d8432a84c3421f6`. The measured candidate
is `86c336c9daf893358f34a7601a5079dda8c18fba`. Historical qualification captured
`aeb1a65`; all runtime, test and oracle source hashes match the measured
candidate. The intervening change adds campaign environment metadata only.
Later evidence publication changes no runtime source.

[Complete summary](evidence/american-remaining-allocation/exponential/summary.json),
[archive inventory and SHA-256](evidence/american-remaining-allocation/exponential/manifest.json),
and [raw observations/source snapshots](evidence/american-remaining-allocation/exponential/raw.tar.gz).
The archive retains the initial stale mutation-catalog-count failures as well
as the corrected successful checks; a failed baseline is not a mutation kill.

## Controlled comparison

The 140-process campaign uses five alternating fresh process pairs for ten
singleton American cases, three eight-row cases and eight European certified
cases. American inputs, 64-cell/64-step initial settings, drivers and method
orders come from the [backend campaign](results-american-backends.md).
Eight rows mean four positions × two dated scenarios. Fixed batching and
one/four-worker planners use tile size one and a no-op sink. Compilation,
admission, first output and reused execution remain separate.

All task-owned builds, qualification, mutations and profiles finished before
timing. Each timed operation has a warmup and full collection; separate
allocation experiments use whole-program `Gc.stat` counters including joined
worker bodies. No profiler runs during timing. Source guards include tracked,
staged, unstaged and untracked files; executable hashes and source identities
remain unchanged throughout. All complete outcomes agree across methods,
workers, process rounds and builds.

Host: Apple M1 Pro, ten logical CPUs, macOS 27.0 arm64, OCaml 5.3.0 Flambda,
release `-O3`; collection began 2026-10-06 22:27 UTC. Recorded one-minute host
load spans 4.46–11.90. This shared host is not isolated. Tables show medians
and observed minimum–maximum ranges of five process samples; these are not
production tail percentiles. Decimal MB means cumulative managed allocation,
not live workspace or process RSS.

All frozen criteria pass: target singleton allocation falls at least 10%;
other pricing allocation grows no more than 5%; American and European median
pricing latency regresses no more than 10%. The largest American measured
median increase is 4.1% on a tiny strict-refusal batch. Compilation/admission
are recorded, not used to fit an adoption threshold.

## American singleton requests

Times are milliseconds per scalar request; parentheses give observed ranges.
IV and strict arithmetic refusals remain refused and are not successful pricing
throughput. The certified row is a supported guarded reduction, not general
American stopping certification.

| Workload | Baseline ms (range) | Candidate ms (range) | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| Analytical call | 0.079 (0.077–0.079) | 0.078 (0.075–0.084) | 0.117 | 0.104 |
| Flat put | 21.357 (21.283–21.494) | 21.516 (21.409–21.655) | 6.983 | 6.967 |
| Cash put | 65.909 (65.232–66.212) | 66.165 (65.137–68.750) | 22.574 | 22.574 |
| Bermudan with cash | 107.103 (105.768–109.574) | 105.910 (104.465–108.759) | 42.328 | 36.705 |
| Piecewise | 59.146 (58.662–60.254) | 58.759 (57.698–60.614) | 33.161 | 26.366 |
| Piecewise-cash | 84.927 (82.379–86.156) | 83.059 (82.691–85.614) | 45.321 | 38.543 |
| Delta/gamma | 21.707 (21.604–22.344) | 21.973 (21.575–22.270) | 7.162 | 7.146 |
| IV resource-limit refusal | 15.035 (14.791–16.332) | 15.237 (14.777–15.382) | 6.225 | 6.225 |
| Certified reduction | 0.395 (0.382–0.408) | 0.396 (0.384–0.398) | 0.403 | 0.351 |
| Strict arithmetic refusal | 0.453 (0.439–0.474) | 0.456 (0.438–0.683) | 0.902 | 0.902 |

## Eight-row planner requests

Whole-request times and whole-program allocation include all eight rows.
Dividing by eight gives amortized cost, not single-request latency.

| Workload/workers | Baseline ms (range) | Candidate ms (range) | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| Cash put / 1 | 549.020 (545.083–565.731) | 554.607 (551.695–558.636) | 185.237 | 185.237 |
| Cash put / 4 | 144.920 (141.012–177.004) | 144.278 (141.549–147.409) | 185.240 | 185.240 |
| Bermudan with cash / 1 | 878.638 (863.123–881.813) | 879.971 (860.853–947.971) | 343.247 | 298.261 |
| Bermudan with cash / 4 | 228.873 (227.300–275.461) | 229.398 (226.338–232.279) | 343.251 | 298.265 |
| Piecewise-cash / 1 | 700.292 (681.515–740.916) | 688.720 (677.328–705.615) | 371.279 | 316.117 |
| Piecewise-cash / 4 | 184.283 (177.875–196.098) | 180.498 (176.283–205.855) | 371.283 | 316.121 |

The summary retains scalar/fixed/planner execution, first-output samples,
compilation and admission for every case. Per-child peak RSS across all
processes is 5.83–25.31 MB baseline and 5.91–25.21 MB candidate. These process
peaks include harness, warmups and separate memory runs; they are not aggregate
concurrent deployment memory. Lower cumulative allocation does not establish
a smaller peak or an accepted deployment budget.

## European certified consumers

The unchanged `certified_scalar` harness records eight cases, three phases and
five inner samples per process. Each process contributes its mean; the table
shows the median of five process means for pricing only. Admission and
end-to-end statistics/ranges remain in the complete summary. CHECK records are
identical, including the requested-accuracy refusal.

| Case | Baseline μs | Candidate μs | Baseline kB | Candidate kB |
| --- | ---: | ---: | ---: | ---: |
| black76 | 742.315 | 734.885 | 633.675 | 555.691 |
| bsm-accuracy-failure | 798.105 | 793.920 | 639.859 | 558.627 |
| bsm-expiry | 0.090 | 0.085 | 0.267 | 0.267 |
| bsm-ordinary | 797.380 | 789.850 | 639.915 | 558.683 |
| bsm-short | 299.765 | 288.945 | 369.627 | 304.531 |
| bsm-tail | 2927.675 | 2923.455 | 2309.899 | 2231.771 |
| displaced | 746.975 | 737.130 | 616.451 | 540.899 |
| normal | 261.885 | 258.025 | 290.507 | 238.179 |

Non-expiry certified price allocation falls 3.4–18.0%; expiry is unchanged.
The Fast European kernels are outside this change and these timings.

## Numerical and operational qualification

- Full development and release install/format/ordinary suites pass. The existing
  cross-platform determinism expectation remains
  `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`
  over 6,069,960 bytes; no digest update is needed.
- Baseline/candidate native and bytecode exponential checks agree over 1,046
  inputs per precision, covering zeros, subnormal/normal boundaries, domain
  edges, low words, uncertain inputs, retained results, failures and independent
  domains. All five output fields and exception payloads contribute to replay.
  Full replay is `9774d530f6bbe0c6ef10686930ed1d75`; Fast is
  `4cc59550274d058814ce54d6aa178f9b`.
- The new independent exact-rational degree-96 Taylor witness checks 248
  containment cases across both precisions and exp/expm1. For |x| ≤ 1 its
  absolute remainder is bounded by `3 |x|^97 / 97!`; it does not reuse the
  production range reduction or floating series. Existing elementary,
  scalar, model and certificate checks remain in the ordinary suite.
- All **572 historical price outcomes**, **920 Greek rows** and **three
  30-case inverse campaigns** have identical complete payloads and independent
  scores. Primary/loose and initial/refined settings retain every runtime
  refusal, wide reference and unresolved reference; these are not accuracy
  passes. The retained campaign completion records enumerate each category.
- Twelve affected mutants build and are killed by their designated witnesses:
  `enclosure-scalar-radius`, `enclosure-scratch-length`,
  `enclosure-product-guard`, `enclosure-exponential-prefix`,
  `enclosure-series-tail`, `enclosure-sum-order`, `enclosure-sum-finite`,
  `enclosure-grow-residual`, `enclosure-packed-word`,
  `enclosure-normal-exponent`, `enclosure-discarded-word`, and
  `enclosure-fma-underflow`. The new prefix fault is rejected by the independent
  exponential witness, not by a changed digest. No full-catalog run is claimed.
- Collector controls reject incomplete/duplicate campaigns, altered complete
  replay, missed allocation targets and European allocation regressions.
  The curated optional catalog now has 177 entries; default CI remains five
  jobs and seven core mutants.

The candidate's separate four-case allocation profiles corroborate lower
Bermudan/piecewise allocation without attributing a latency improvement to a
profiler. The earlier 24-process attribution archive remains unchanged.

## Disposition and reproduction

Adopt call-owned exponential scratch. Cash interpolation is the next distinct
allocation candidate: ordinary cash still allocates about 22.57 MB per singleton
and 185.24 MB per eight-row planner execution at these settings. Any follow-up
needs its own storage/rounding argument and frozen before/after qualification.
#119 remains open for deployment requirements; #120 owns final integration
qualification. This pass neither closes those obligations nor changes the
specialized-engine/backend defer decisions.

Build both recorded revisions in separate worktrees with the same toolchain:

```sh
opam exec --switch=morphiq-risk-ml -- dune build --profile release \
  bench/backend_requests.exe bench/certified_scalar.exe
```

From the candidate worktree, after all owned compute finishes:

```sh
python3 scripts/measure_exponential_scratch.py \
  --baseline /path/to/baseline --output /path/outside/source-trees
```

The collector refuses an existing output directory and preserves partial evidence
on failure. The archive includes the historical qualification driver, exact
measured changed sources, runtime patch and all raw campaign records. Local
paths in the historical driver must be adjusted for a different workspace.
