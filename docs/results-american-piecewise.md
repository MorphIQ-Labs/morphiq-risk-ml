# Piecewise coefficient qualification (#114)

The scalar estimated API supports distinct complete rate, yield and lognormal
volatility schedules. Read the [API and derivation](piecewise-american.md).
The frozen [protocol](evidence/american-piecewise/protocol.md) and 40 original-word
[cases](evidence/american-piecewise/cases-v1.json) were committed at `159a9a5`
before reference execution or runtime edits. Independent references were
committed at `b5f6f44`; runtime implementation is `7edc4bb`. Subsequent commits
add qualification drivers, evidence and documentation without changing runtime
arithmetic. The existing integration baseline is `e733c881434eb0ccc9faea045f90f5c13742a1dd`.

## Numerical results

The primary target is `2^-16 max(S,K)`; the separate loose target is `max(S,K)/100`.
Neither is a certified runtime error bound or a recommended trading tolerance.
The frozen independent reference radius must fit one eighth of the target
before an accuracy comparison can pass.

| Configuration | Target | Accuracy passes | Runtime unavailable | Reference too wide |
|---|---|---:|---:|---:|
| Initial 32/32 | Primary | 14 | 26 | 0 |
| Initial 32/32 | Loose | 17 | 23 | 0 |
| Refined 128/128 | Primary | 14 | 26 | 0 |
| Refined 128/128 | Loose | 36 | 0 | 4 |

All 14 analytical rows pass both targets. On the refined loose configuration,
all 40 requests return estimates, but four references are too uncertain to score.
Strict stochastic pricing remains unavailable under these configurations. An
unavailable runtime result or unresolved reference is never an accuracy pass.

Analytical references use independent mpmath 1.3.0 calculations at 80 and 160
places from exact input words: integrated European prices, interior signed-rate
or yield optima, and deterministic cash/stock trajectories. A separate N=8
positive Gaussian quadrature replay agrees across both precisions and with the
binary64 research implementation under the recorded arithmetic screen. This
fixed-discrete comparison does not establish continuum accuracy.

Stochastic references refine original positive three-point Gaussian quadrature
at N=256/512/1024 per event slab, with 16N log-stock nodes and zero/global-cap
exterior pairs. The radius is the predeclared empirical formula; it is neither
a theorem nor a full-price enclosure. The final references resolve 15 rows at
the primary width and 36 at the loose width. No threshold was increased after
observing runtime results.

[References](evidence/american-piecewise/references-v1.json) retain every row,
analytical digits, all quadrature levels and all canonical outcomes.
[Original raw observations](evidence/american-piecewise/reference-raw.tar.gz)
precede implementation. A [second complete reproduction](evidence/american-piecewise/reference-reproduction.tar.gz)
produces identical reference rows and retains command, source and binary hashes.
[Controls](evidence/american-piecewise/reference-controls.json) record research
CLI and malformed/truncated-input rejection; ordinary tests also exercise
missing/reordered rows, invalid outcomes, nonfinite prices, failed accuracy,
unavailable output and insufficient reference width.

## Canonical comparison and provenance

QuantLib is an optional research dependency, not a runtime dependency. The
canonical checkout is `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c`, with the
[operator's time-interval coefficient contract](https://github.com/lballabio/QuantLib/blob/79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c/ql/methods/finitedifferences/operators/fdmblackscholesop.cpp)
and yield/variance/step-condition interfaces recorded in
[provenance](evidence/american-piecewise/reference-provenance.json).
Original project adapters supply piecewise discount/variance integrals,
coefficient stopping times, finite or continuous exercise and liquidator cash
mapping. QuantLib supplies meshing, differential operators, rollback and final
interpolation. No upstream runtime implementation is copied or translated.

N=128/256/512 canonical runs retain both the adapted liquidator result and the
unmodified vanilla engine result. The latter has different cash-floor,
coincidence/side and coefficient-step conventions. It is supplementary evidence,
not an interchangeable oracle. Actual360 date conversions that do not preserve
an original exercise/cash time exactly remain excluded, as do unsupported
analytical and endpoint-cash cases. Curve queries outside the declared horizon
are rejected. Per-row output retains all exclusions and discrepancies.

## Reproduce

Compile the original quadrature adapter with a C++17 compiler and
`-O3 -ffp-contract=off`. Compile the QuantLib adapter against the pinned optional
checkout/build, using the include, library and runtime-library paths appropriate
to that build. The executed macOS command is retained in provenance. Then run:

```sh
python3 scripts/generate_american_piecewise.py \
  --quadrature /path/to/piecewise-quadrature \
  --quantlib /path/to/piecewise-quantlib \
  --mpmath-python /path/to/pinned-venv/bin/python \
  --output /new/reference-directory
python3 scripts/collect_american_piecewise.py \
  --raw /new/reference-directory --output /new/references.json
opam exec --switch=morphiq-risk-ml -- dune build --release test/american_piecewise.exe
python3 scripts/check_american_piecewise.py \
  --executable _build/default/test/american_piecewise.exe --mode loose --refined
```

Ordinary public builds and CI use committed evidence and the Python standard
library; they require neither QuantLib, mpmath nor private research access.

## Compatibility and validation

All 412 complete existing American/cash/Bermudan outcomes match the baseline,
including unavailable results, diagnostics, work and optional-output fields
captured by the full outcome fingerprints. Their independent scores also match.
Constant and redundantly split curves reproduce the same complete outcome.
Existing public European replay identity remains unchanged.

Development and release ordinary suites, install and formatting checks pass.
Native and bytecode controls exercise the new financial contracts, admission,
array ownership, resource/cancellation limits and concurrent request isolation.
Three compiler-negative witnesses reject rate/yield type confusion, normal
volatility and using piecewise admission with constant pricing. All 15 affected
compiled mutations are killed, including averaged profiles, left-hand knot
coefficients, omitted interior discount optima and stale spatial preparation.
Default CI remains five jobs and the same seven core mutants; the full optional
catalog now has 117 entries. These tests are evidence over the exercised inputs,
not universal numerical or concurrency proofs.

[Qualification records](evidence/american-piecewise/qualification.json) identify
the captured builds, all 160 new outcomes, per-case canonical discrepancies,
validation and performance. The [raw archive](evidence/american-piecewise/qualification-raw.tar.gz)
retains both complete 412-outcome campaigns, collector output, test logs and all
performance samples. Runtime arithmetic has not changed since `7edc4bb`; the
measured candidate with the final timing driver is `4e62c7a`.

## Performance and remaining allocation work

Apple M1 Pro, macOS 27 arm64, OCaml 5.3.0 Flambda, release library `-O3`.
Task-owned builds, tests, profilers and reference calculations finished before
measurement. Five fresh-process rounds alternate baseline/candidate order,
with one warmup and three reused-admission prices per sample. Host load ranged
from 11.05 to 13.28; this was a shared machine, not an isolated benchmark host.
Values below are medians; raw records retain minima/maxima, GC and per-child RSS.

| Workload | Baseline ms/price | Candidate ms/price | Baseline MB allocated/price | Candidate MB allocated/price |
|---|---:|---:|---:|---:|
| american none | 154.62 | 157.60 | 12.898 | 12.905 |
| american cash | 434.07 | 441.97 | 42.154 | 42.164 |
| bermudan none | 302.66 | 300.94 | 40.525 | 40.532 |
| bermudan cash | 442.67 | 446.34 | 63.986 | 63.996 |
| piecewise none | — | 924.65 | — | 340.841 |
| piecewise cash | — | 572.77 | — | 218.944 |

All constant-price workloads meet the predeclared +10% latency and +5% allocation
regression limits. The new varying workloads are `american-staggered` and
`cash-coefficient-american` from the frozen corpus, using refined 128/128 and
loose tolerance. They are characterization, not a new deployment SLA.

Varying requests still allocate about 219–341 MB cumulatively per price. That
is material remaining work for #119; multiple coefficient slabs require repeated
spatial preparation, and profiling should determine the useful bounded reuse
strategy. It is not a measured live-memory requirement: per-child peak RSS for
these fresh-process runs is 6.98–8.01 MB, including warmup and three prices.
Do not claim the varying path inherits the constant-path allocation optimization.
Broader American integration qualification and release obligations remain #120.

Reproduce the timing campaign after capturing source-guarded release builds:

```sh
python3 scripts/benchmark_american_piecewise.py \
  --baseline /path/to/baseline-build.json \
  --candidate /path/to/candidate-build.json \
  --output /new/performance-directory
```

The subsequent [piecewise allocation pass](results-piecewise-allocation.md)
qualifies bounded stencil/boundary and slab-matrix reuse against these frozen
workloads. The measurements above remain the original #114 characterization.
