# Exponential scratch pass (#119)

Freeze before runtime edits. Baseline runtime is integration `9fae37a`, with
the attribution harness/report on `8e1aba0`. Profiles identify repeated enclosed
exponentials in Bermudan and piecewise time/boundary work. Investigate private
scratch reuse inside each exponential/expm1 call, in both enclosure precisions.
Do not add another boundary cache or alter pricing, time grids or policies.

## Storage argument and numerical contract

General multiplication uses at most `2 * words * words` terms, addition at most
`2 * words`, scalar multiplication at most `4 * words`, and scalar quotient
suboperations at most eight. Thus a call-owned array of `max 8 (2*words*words)`
floats suffices for the supported two/four-word configurations. Each operation
must overwrite its entire used prefix and pass the used length, not capacity,
to packing. Packing copies all retained words/radius into immutable records;
none borrow scratch. Nested arithmetic evaluates each result before another
operation reuses the array. No callback, global storage, unsafe access, new FFI,
or sharing across calls/domains is permitted. Failed calls abandon their array.

Preserve zero shortcuts, scalar validation, padding-zero signs, product/FMA
order, discarded-word/radius accumulation, quotient iterations, series degrees,
tail bound and ten reconstruction steps. No arithmetic/tolerance change is
authorized by this storage optimization. Ordinary public arithmetic keeps its
fresh-storage behavior; only exponential-owned operations reuse this array.

## Qualification and paired measurement

Freeze a baseline checkout with the same new tests and existing request drivers.
Compare complete fields/failures for exp/expm1 in both precisions across native
and bytecode, signed zero, subnormal/normal boundaries, domain edges, uncertain
inputs, retained results, failed intervening calls and independent domains.
Add exact-rational Taylor bounds for independent containment checks; retain
existing elementary/model/certificate references and affected mutation witnesses.
Full development/release suites, determinism and historical American/Bermudan/
piecewise/Greek/IV complete outcomes must agree. Replay alone is not accuracy.

Use unchanged #147 `backend_requests` singleton cases call, flat, cash, Bermudan,
piecewise, piecewise-cash, delta/gamma, IV, certified and strict. Also compare
eight-row cash/Bermudan/piecewise-cash one/four-worker planners. Five fresh
processes per workload/build, alternating order; one warmup and full collection
before each timed operation, separate allocation runs, compilation/admission
separate, failures retained. Use the existing European `certified_scalar` eight
cases with five alternating process pairs and unchanged CHECK records. Keep
all raw observations, source/binary hashes, host load and per-child RSS. Finish
owned builds, tests and profiles before timing; reject any source drift.

Engineering acceptance: at least 10% lower median singleton managed allocation
for Bermudan, piecewise and piecewise-cash; at most 5% allocation increase and
10% median pricing latency regression in the other American controls and
European price/end-to-end cases. For the three target workloads also require
no more than 10% median latency regression. Tiny compile/admission timings are
reported separately, not used to fit a gate. These are local improvement
criteria, not deployment budgets. If they fail, retain the evidence and revise
the implementation or defer; do not relax the criteria to force acceptance.

Cash interpolation remains a distinct later opportunity. Default CI stays at
five jobs/seven core mutants. #119 and final integration qualification #120
remain open beyond this focused pass.
