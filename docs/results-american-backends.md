# Actual American policy backend comparison

Keep the bounded native solver. In this #119 experiment, reference LAPACK
DGTSV is slower after packing, dispatch and original-system residual checks,
and remains slower in complete scalar and compiled requests. It does not reduce
the existing allocation burden. The optional wrapper also violates the physical
work boundary needed for bounded cancellation, so it is not a production adapter.
Production `lib/` and served results are unchanged by this change.

## Candidate, provenance and reproduction

Measured source: `65f90e3d0340ee778434a363ab24ded4b7328c09`, clean, based on
American integration `69c8f4c76574c304c430d57deabaa50a3401cc45`.
The final report, notice clarification and evidence are a documentation-only
bridge. Source guards cover tracked/untracked files, isolated patches, foreign
archive and executable hashes. Native measurements use the unchanged production
owner; the isolated native adapter is used only to capture matrices.

Host: Apple M1 Pro, 10 logical CPUs, macOS-27.0-arm64-arm-64bit-Mach-O;
OCaml 5.3.0 Flambda, release/O3; Apple clang 21.0.0; GNU Fortran 16.2.0.
Fortran uses `-O3 -ffp-contract=off -fno-fast-math -fno-tree-vectorize
-fno-tree-slp-vectorize -fPIC`. All task-owned builds, tests and reference
generation finished before timing. One-minute host load ranged **6.85–42.08**;
this shared-machine campaign is not an isolated-host benchmark or deployment SLA.

[Frozen protocol](evidence/american-backends/protocol.md),
[all five-process summaries](evidence/american-backends/summary.json),
[raw observations and reproducible source changes](evidence/american-backends/raw.tar.gz),
[archive/file SHA-256 manifest](evidence/american-backends/manifest.json), and
[optional adapter instructions](../bench/american_backends/README.md).
Raw evidence includes failed preliminary build logs, distinct from the completed
`experiment-v6` build and source-bound qualification/campaign.

The reference implementation is LAPACK 3.12.1
[`DGTSV`](https://github.com/Reference-LAPACK/lapack/blob/6ec7f2bc4ecf4c4a93496aa2fa519575bc0e39ca/SRC/dgtsv.f),
commit `6ec7f2bc4ecf4c4a93496aa2fa519575bc0e39ca`.
The builder checks pinned source/license hashes before compilation. The source
is unchanged; the original project `xerbla_` shim retains INFO instead of
linking the fatal error printer. `nm` finds only that external reference in
DGTSV; the resulting executable links only libSystem dynamically. There is no
BLAS dispatch, Fortran runtime dependency or nested library thread pool in this
build. The exact upstream source and notice travel together in the evidence
archive under the [LAPACK terms](../LICENSES/LAPACK-3.12.1.txt), not Apache-2.0.
The default build needs neither Fortran nor network access.

Reproduce from the measured source with a fresh output location:

```sh
opam exec --switch=morphiq-risk-ml -- dune build --profile release \
  bench/backend_requests.exe bench/backend_micro.exe bench/backend_contracts.exe
python3 scripts/build_american_backends.py --output /tmp/american-backend-build
python3 scripts/measure_american_backends.py --experiment /tmp/american-backend-build \
  --phase qualify --output /tmp/american-backend-qualification
python3 scripts/measure_american_backends.py --experiment /tmp/american-backend-build \
  --phase measure --qualification /tmp/american-backend-qualification \
  --output /tmp/american-backend-measurements
```

Finish ordinary checks and optional native/bytecode controls before the measure
phase; do not edit either source tree during collection. The raw
`summarize.py` derives the published tables from all 405 completed process
records. Its paths point to this campaign's retained local directories.

## Numerical and resource evidence

Capture covers **240 actual policy systems** from flat, cash, Bermudan,
piecewise-cash, delta/gamma, IV and strict requests, plus the declared larger-grid
flat/cash cases. Analytic call and certified controls produce no matrices.
Initial 64-cell and 256-cell settings undergo the existing adaptive refinement;
reached interior dimensions are **81, 163, 255, 281, 291, 327, 563, 1023, 1075,
1127**. Policy ordinals 1, 2, 8, 32, 128 and 512 are sampled per dimension when
reached. No artificial financial matrices fill missing sizes or ordinals.

For every original binary64 matrix and computed vector, Python `Fraction`
evaluates the residual exactly. Positive diagonal, nonpositive off-diagonal and
strict row dominance give the fixed-system bound
`||x - x_exact||∞ <= ||A*x - b||∞ / min_i(d_i + lo_i + hi_i)`.
These checks bound a discrete linear solve; they do not certify the continuum
stopping price, a Greek or an IV result.

All three modes meet the unchanged local residual allowance on **239/240**
systems. The strict request's sole captured system has residual
`8.280086257409232e-17` against allowance `1.1920928955078125e-19` in every mode.
It remains an arithmetic-unresolved price; `all_exact_residuals_pass` is
deliberately false. No threshold is widened and this refusal is not an accuracy
pass. The largest fixed-system residual/error bound across all captures is
`5.052349828993502e-12` for native/OCaml and `3.781111843283356e-12` for DGTSV.

The OCaml operation reference matches all native solution words and complete
request digests. DGTSV changes **5,409 solution words**. Request outcome
classifications remain the same, but five stochastic workload families change
their complete payloads. Most emitted changes are residual diagnostics; the
piecewise-cash portfolio also changes price by up to `4.619e-14`. Greek payload
digests can change internal price diagnostics even when emitted price/Greek
values agree. This is compatibility characterization, not independent
qualification of a new pricing operation graph.

All **720 native/bytecode system-solution comparisons** match. Direct adapter
controls pass in both modes: exact/identity/pivoted systems, singular and
nonfinite failures, finite-input overflow, subnormals/signed zero, malformed
shapes/aliases, GC, concurrent separate owners, rounding/flush rejection, and
preservation of floating-point flags. The wrapper relies on the pinned OCaml
5.3 custom-operations identity; other platforms/runtime ABIs are unqualified.

Seven callback-stop points and three row budgets retain the observed outcomes.
However, a direct 512-unknown witness requesting only one elimination row changes
**0 candidate entries under native/OCaml and all 512 under DGTSV**. Logical
visited counts still say one. The whole-system call therefore does not preserve
physical work bounds, partial failure writes or callback responsiveness. These
are explicit adoption blockers even if end-to-end timing were favorable.

## Measurement and decision

The campaign contains five alternating fresh processes for each of three modes
and 27 request/matrix groups: **405 completed processes**, with stable replay and
source identities. Complete requests check scalar/fixed/planner agreement before
timing. Each method has one warmup, untimed full major collection and one timed
execution. Compilation averages 50 repetitions and admission remains separate;
all samples are in the summary. Portfolio shape is four positions × two scenarios,
tile size one, workers one/four. Singleton is one position/scenario/worker.

The main accepted singleton medians favor native: flat **21.48 vs 24.54 ms**,
cash **64.53 vs 71.16 ms**, Bermudan **104.34 vs 111.45 ms**, and piecewise-cash
**82.26 vs 86.81 ms** (native vs DGTSV). None achieves the predeclared 10% gain
on three stochastic workloads. Controls with very small runtimes and shared-host
outliers do not support fine-grained conclusions. General IV rows all hit their
fixed resource limit, and strict rows remain arithmetic-unresolved; their costs
are refusal latency, not successful pricing throughput.

DGTSV loses all **123 capture/dimension/batch median comparisons** for complete
copy+solve+residual cost, by **3.2–18.1%** against native. The tested range reaches
1127 unknowns and batches of 64, with no observed crossover. At 1127 unknowns,
one system takes **21.91 vs 24.47 µs**, and 64 take **1.417 vs 1.570 ms**.
This is the measured adapter, not a claim about every LAPACK implementation or
larger matrix. The wrapper retains existing managed owners plus adapter records;
its overhead is included, and it is not a lower bound on all possible designs.

| Backend | Disposition | Reason |
| --- | --- | --- |
| Bounded native specialized solver | Retain | Lowest measured complete cost; existing work boundaries and qualified production arithmetic remain intact. |
| OCaml operation reference | Retain for verification; defer runtime substitution | Exact replay, but slower complete requests and matrix sweeps; no demonstrated production benefit. |
| Reference DGTSV experiment | Defer production adoption | Slower complete cost, extra scratch, changed arithmetic, nonconformant work boundaries, optional Fortran build and unqualified additional platforms. |

No backend is shipped from this experiment. Full independent pricing/Greek/IV
qualification and a conformant cancellation/workspace boundary would be required
before any future adoption. The existing allocation remains material: **22.57 MB
per singleton cash request**, **185.24 MB per eight-row cash planner execution**.
Residual/enclosure allocation is the next measured optimization opportunity;
deployment targets remain undecided under #119. Final American integration
qualification stays with #120.

Memory tables use decimal MB. Managed allocation comes from a separate untimed
`Gc.stat` pass, includes joined workers and forces collections. Native scratch is
additional: separately counted scalar executions of the same rows allocate
32 bytes per interior unknown/owner cumulatively. This is not a direct per-method
native allocation counter for planner execution. RSS is each whole child's peak,
including qualification, warmup, timing and the allocation phase, not a price's
live workspace or a deployment memory budget. No global GC tuning is applied.

Development/release ordinary suites, package build and formatting pass. Default
CI remains five jobs with seven core mutants. Small exact-residual/parser/live
matrix controls need no optional dependency. Manual collector negatives reject
changed source identities, changed captured matrices and changed qualified
request replay for their intended reasons. Shared startup/timeout/reaping
controls remain in the ordinary suite. Production numerical code is unchanged.

## Singleton scalar latency

| Workload | Native ms (range) | OCaml ms (range) | DGTSV ms (range) |
| --- | --- | --- | --- |
| call | 0.075 (0.075–0.224) | 0.080 (0.076–0.080) | 0.078 (0.076–0.109) |
| flat | 21.480 (21.109–21.705) | 24.513 (24.230–24.647) | 24.539 (24.116–24.847) |
| cash | 64.530 (63.954–73.705) | 72.588 (71.309–74.407) | 71.157 (70.052–82.607) |
| bermudan | 104.343 (103.605–107.363) | 114.143 (113.608–115.792) | 111.453 (110.720–112.084) |
| piecewise-cash | 82.264 (81.781–84.120) | 89.970 (88.241–91.460) | 86.807 (86.574–164.888) |
| greeks | 22.203 (21.460–51.392) | 24.341 (24.019–65.053) | 24.536 (23.990–71.113) |
| iv | 14.768 (14.689–15.508) | 16.899 (16.647–17.347) | 17.091 (16.823–17.362) |
| certified | 0.388 (0.382–0.393) | 0.396 (0.372–0.402) | 0.388 (0.375–0.429) |
| hard | 0.439 (0.428–0.458) | 0.453 (0.438–0.461) | 0.442 (0.436–0.456) |

## Eight-row planner latency

| Workload | Native 1 worker ms | DGTSV 1 worker ms | Native 4 workers ms | DGTSV 4 workers ms |
| --- | --- | --- | --- | --- |
| call | 0.719 (0.687–0.746) | 0.707 (0.702–0.734) | 0.665 (0.546–3.433) | 0.670 (0.650–5.499) |
| flat | 183.749 (180.347–194.816) | 206.159 (204.612–211.595) | 48.630 (48.226–49.458) | 54.113 (53.466–81.004) |
| cash | 547.420 (539.702–564.086) | 599.508 (591.680–609.753) | 145.328 (141.506–157.600) | 156.157 (154.697–157.964) |
| bermudan | 869.633 (860.991–873.884) | 926.897 (911.584–1104.601) | 224.689 (223.610–231.357) | 243.652 (237.868–1174.454) |
| piecewise-cash | 681.509 (680.449–1131.857) | 718.820 (713.710–2013.084) | 181.788 (177.672–1048.486) | 188.533 (186.564–983.748) |
| greeks | 185.047 (183.032–187.155) | 209.055 (206.024–313.642) | 48.199 (47.739–59.155) | 55.059 (54.519–116.531) |
| iv | 122.302 (119.749–122.881) | 138.119 (137.144–140.395) | 32.542 (32.026–33.854) | 37.210 (36.615–37.590) |
| certified | 4.146 (4.135–4.334) | 4.284 (4.079–4.358) | 1.564 (1.520–1.677) | 1.598 (1.518–1.673) |
| hard | 3.927 (3.752–3.995) | 3.872 (3.842–4.003) | 1.608 (1.557–1.721) | 1.646 (1.618–1.760) |

## Cumulative allocation and whole-child memory

| Workload | Native scalar MB | DGTSV scalar managed MB | DGTSV extra native scratch MB | Native / DGTSV eight-row planner4 managed MB | Native / DGTSV eight-row child RSS range MB |
| --- | --- | --- | --- | --- | --- |
| call | 0.117 | 0.117 | 0.000 | 1.076 / 1.076 | 9.29–9.47 / 9.31–9.68 |
| flat | 6.983 | 6.988 | 0.113 | 57.264 / 57.297 | 24.26–25.30 / 25.71–28.03 |
| cash | 22.574 | 22.579 | 0.155 | 185.240 / 185.283 | 22.43–24.00 / 25.85–29.47 |
| bermudan | 42.328 | 42.333 | 0.155 | 343.251 / 343.293 | 23.20–24.10 / 27.15–31.00 |
| piecewise-cash | 45.321 | 45.327 | 0.155 | 371.283 / 371.325 | 23.71–27.03 / 27.54–31.80 |
| greeks | 7.162 | 7.167 | 0.113 | 58.677 / 58.710 | 24.54–26.25 / 27.12–29.85 |
| iv | 6.225 | 6.229 | 0.092 | 50.304 / 50.330 | 22.77–23.56 / 26.08–28.43 |
| certified | 0.403 | 0.403 | 0.000 | 3.900 / 3.900 | 10.01–10.29 / 10.19–10.31 |
| hard | 0.902 | 0.903 | 0.008 | 7.545 / 7.548 | 13.83–14.42 / 13.94–14.96 |

## Microbenchmarks

Complete preparation + solve + original-system residual time, microseconds per batch (median of five processes). Each batch is an explicit loop of independent systems; no cached factors or LAPACK multi-RHS shortcut. All dimensions and preparation-only samples remain in summary.json.

| Interior rows / batch | Native µs | OCaml µs | DGTSV µs |
| --- | --- | --- | --- |
| 81/1 | 1.594 | 1.875 | 1.812 |
| 81/8 | 12.594 | 14.344 | 14.000 |
| 81/64 | 101.437 | 118.281 | 113.625 |
| 163/1 | 3.219 | 3.656 | 3.625 |
| 163/8 | 25.156 | 29.281 | 28.406 |
| 163/64 | 201.563 | 237.031 | 224.531 |
| 255/1 | 4.937 | 5.625 | 5.719 |
| 255/8 | 40.813 | 44.625 | 44.906 |
| 255/64 | 313.250 | 365.281 | 356.969 |
| 291/1 | 5.781 | 6.687 | 6.344 |
| 291/8 | 46.625 | 52.500 | 50.938 |
| 291/64 | 365.469 | 430.625 | 409.125 |
| 327/1 | 6.375 | 7.563 | 7.531 |
| 327/8 | 51.156 | 58.906 | 58.250 |
| 327/64 | 409.875 | 470.875 | 468.219 |

## Recorded numerical differences

| Workload | Changed DGTSV payloads (8 rows) | Largest price delta | Largest emitted value/diagnostic delta |
| --- | --- | --- | --- |
| call | 0 | 0 | 0 |
| flat | 8 | 0 | 1.029e-13 |
| cash | 8 | 0 | 1.294e-13 |
| bermudan | 8 | 0 | 3.154e-14 |
| piecewise-cash | 8 | 4.619e-14 | 4.18e-13 |
| greeks | 8 | 0 | 0 |
| iv | 0 | 0 | 0 |
| certified | 0 | 0 | 0 |
| hard | 0 | 0 | 0 |

