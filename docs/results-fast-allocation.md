# Fast pricing allocation optimization (#8)

This round reduces temporary allocation in double-double Horner evaluation,
used by Black-family admission and fast in-the-money pricing. APIs, stored
coefficients, polynomial degrees, operation order, thresholds and numerical
budgets are unchanged. [Retained evidence](evidence/fast-allocation/README.md)
binds source revisions, profiles, toolchain, fixtures and measurements.

Implementation: `75999776291370412dc0ffe3b4504b17e7979e3c`, based on PR #101
merge `8ab5b8ce052a9b0753d10e1d7d5567aec52bd756`. Baseline worktree head
`ff602ee21949663025e6cbfbe044fb5a539cccf6` has that merge's source tree; its
added measurement harnesses match the candidate. Later evidence/documentation
commits leave the measured implementation unchanged.

## Mechanism and arithmetic contract

Allocation sampling identifies DD logarithm/exp/expm1 temporaries as material
costs in Black admission and intrinsic evaluation. Cost is regime-dependent:
out-of-the-money displaced and Bachelier samples allocate much less than the
in-the-money BSM/Black-76 samples. A mixed-model average is not a universal
single-price allocation figure.

Both fixed-degree DD Horner loops now carry high and low words in separate
scalar references. At every iteration they reconstruct the same mathematical
DD operand, call the same multiply/add algorithms in the same order and assign
both result words. Native compilation can keep the loop state unboxed instead
of allocating a record at every iteration. Selected local calls in the logarithm
loop are inlined, as the exponential's already were. `Split.two_sum` receives
an inline hint so cross-module native optimization can eliminate its tuple.
Its Knuth algorithm is unchanged; it remains the shared primitive owner.

There is no reassociation, new FMA, altered polynomial grouping, host function
substitution, mutable shared cache or unsafe representation cast. Every source
multiplication still uses `Morphiq_fp`; only explicit `Float.fma` calls fuse.
The original DD error derivations and reference budgets remain applicable to
this unchanged operation sequence. Replay and independent checks below verify
the exercised inputs; they are not a universal compiler proof.

Both DD Horner siblings are covered. Cody/error-function and normalized-Black
polynomials already carry scalar accumulators. `Normal_dd.cdf_from_square` has
a separate variable-length recurrence and prepared-division workload; changing
that recurrence or planner scheduling is outside this fixed-degree storage
change and remains a profiling opportunity under #8.

## Build profiles and allocation

Dune development builds use opaque module boundaries even with library `-O3`.
Release builds permit cross-module optimization. No compiler/version/profile
setting changes here: performance evidence separates both existing profiles.
CI's existing three platform test jobs now exercise both profiles; the five
required check names and seven-mutant default selection remain unchanged.

The singleton profiler runs 5 warmups and 2,000 calls for cumulative GC
allocation, then independently samples stacks with `Gc.Memprof` (rate 0.01,
16 frames). These are bytes allocated over time, not live heap or retained
memory. Inputs and output words are retained with every raw stack profile.
BSM/Black-76 use an in-the-money call; displaced/Bachelier use an
out-of-the-money call. This regime difference explains the different costs.

| Mode/profile and sampled model | Compile bytes/call, before → after | Execute bytes/call, before → after |
| --- | ---: | ---: |
| Native development, BSM/Black-76 | 8,288 → 7,232 | 14,392 → 13,024 |
| Native release, BSM/Black-76 | 2,952 → 1,840 | 2,640 → 1,056 |
| Native development, displaced | 8,496 → 7,440 | 656 → 656 |
| Native release, displaced | 3,048 → 1,936 | 520 → 520 |
| Native development, Bachelier | 624 → 624 | 504 → 504 |
| Native release, Bachelier | 536 → 536 | 504 → 504 |
| Bytecode, either profile, BSM/Black-76 | 31,608 → 32,912 | 66,320 → 69,728 |
| Bytecode, either profile, displaced | 32,000 → 33,304 | 4,496 → 4,496 |
| Bytecode, either profile, Bachelier | 1,856 → 1,856 | 2,352 → 2,352 |

Counters include singleton batch/result overhead (and about 0.1 byte/call of
measurement overhead). Native release ITM execution saves 60.0%; the same
sample in opaque development saves 9.5%. Allocation stacks identify the
remaining opaque cross-module `Split.two_sum` tuple/boxed-word boundary.

**Bytecode tradeoff:** scalar references and reconstruction add 4.1% admission
and 5.1% ITM execution allocation because bytecode does not eliminate these
intermediates. This is a native optimization, not an across-mode speed claim.
Both modes remain supported and numerically checked; no duplicate algorithm
or runtime compiler-dependent dispatch is added to hide the tradeoff.
Bytecode elapsed performance was not qualified in this round.

Native DD object text grows from 9,416 to 10,080 bytes in development and
8,608 to 9,000 bytes in release; Split text is unchanged (3,712/3,696 bytes).
These are Mach-O `__text` sizes, separate from debug/object-file bytes.

## Paired workload costs

Apple M1 Pro (10 logical CPUs), macOS 27 ARM64, OCaml 5.3.0 Flambda,
library `-O3`. Two sequential A/B/B/A rounds per profile run three existing
harnesses, with five samples/process: 20 sample means per variant/phase.
No task-owned build, test or profiler ran alongside timing. One-minute load
at process boundaries was **5.79–10.12**; this is a shared workstation,
not an isolated target-host or operational acceptance campaign.

Each fast batch contains mixed calls/puts across four models and 32, 256 or
1,024 requests. Each fast scenario job has four time scenarios per position,
with 32-row tiles. Batch samples perform `max(1, 8192/n)` iterations after
three warmups; scenario samples perform `max(1, 4096/n)`. Timing uses the
existing monotonic clock; process CPU time and GC allocation are retained.
The certified harness uses 24 rows, 1/2/11 outputs and ordinary, boundary,
and failure regimes; two warmups and two iterations/sample. Correctness and
one/multiple-worker trace comparisons run outside timing.

Tables normalize 1,024-request batches by 1,024 and four-scenario jobs by
4,096 emitted prices. These are **amortized batch means**, not measured
single-request latency or percentiles. Full raw samples and all sizes/phases,
including CPU time and compile-only scenario costs, are retained.

### Native development, 1,024 positions

| Phase | Median µs/price before → after | Sample range µs/price before → after | Bytes/price before → after |
| --- | ---: | --- | ---: |
| Batch compile | 1.105 → 1.031 | 1.079–1.127 → 1.000–1.107 | 6,406 → 5,614 |
| Batch execute | 0.950 → 0.912 | 0.917–0.964 → 0.885–0.935 | 5,737 → 5,231 |
| Batch one-shot | 1.879 → 1.790 | 1.839–1.910 → 1.754–1.821 | 12,135 → 10,837 |
| Batch pack/compile/execute/extract | 2.105 → 1.993 | 2.056–2.139 → 1.950–2.033 | 12,243 → 10,945 |
| Scalar preadmitted | 0.959 → 0.912 | 0.927–1.030 → 0.878–0.932 | 5,737 → 5,231 |
| Scenario execute, one worker | 1.972 → 1.884 | 1.944–1.999 → 1.867–1.908 | 13,106 → 11,744 |
| Scenario pack/compile/execute | 2.416 → 2.308 | 2.386–2.464 → 2.290–2.330 | 13,654 → 12,292 |

### Native release, 1,024 positions

| Phase | Median µs/price before → after | Sample range µs/price before → after | Bytes/price before → after |
| --- | ---: | --- | ---: |
| Batch compile | 0.948 → 0.836 | 0.911–0.978 → 0.796–0.873 | 2,354 → 1,520 |
| Batch execute | 0.728 → 0.674 | 0.694–0.773 → 0.660–0.695 | 1,283 → 697 |
| Batch one-shot | 1.506 → 1.371 | 1.471–1.536 → 1.335–1.397 | 3,629 → 2,209 |
| Batch pack/compile/execute/extract | 1.715 → 1.575 | 1.661–2.165 → 1.535–1.614 | 3,737 → 2,317 |
| Scalar preadmitted | 0.728 → 0.681 | 0.695–0.781 → 0.665–0.723 | 1,283 → 697 |
| Scenario execute, one worker | 1.570 → 1.425 | 1.551–1.598 → 1.393–1.500 | 4,145 → 2,651 |
| Scenario pack/compile/execute | 2.013 → 1.861 | 1.969–2.049 → 1.830–1.908 | 4,693 → 3,199 |

Release mixed batch execution saves **45.7% allocation** and measures **7.4%
faster**; single-worker scenario execution saves **36.0% allocation** and
measures **9.2% faster**. Opaque development gains are smaller: **8.8%/10.4%
less allocation**, respectively, and **4.0%/4.5% faster**. Across all three
batch sizes release execution median improvements are 6.9–7.8%; release
single-worker scenarios improve 9.1–9.9%. End-to-end rows include packing and
admission and show the gain survives those costs.

Four-worker results do **not** establish scaling gains: development medians
regress 1.7–6.1%, while release moves from 7.1% faster to 1.5% slower, with
broad overlapping ranges. All four-worker medians are slower than one worker
for the same candidate workload. Their GC counters cover only the coordinator,
so they are not total process/worker allocation. Scheduler/worker-pool changes
and worker/tile crossover remain separate #8 work.

Certified portfolio digests (values, radii, failures and completion) match for
all nine regimes/output counts across revisions and profiles. Ordinary
certified execution median differences are -0.5% to +0.2% in development and
-0.2% to +1.5% in release; these do not establish a timing improvement or
absence of a small regression. Ordinary certified allocation falls only
19,008/20,016 bytes per 24-row job in development/release because admission
benefits while runtime certification still dominates. This round does not
remove the remaining MB-scale certification cost.


## Numerical and package validation

- Full `@install @fmt @runtest` passes in development; full release
  `@install @runtest` also passes. Independent DD, price, Greek, normal,
  IV and certificate checks retain their original budgets and explicit
  unresolved-reference outcomes.
- All 86,145 DD fixture rows (47,719 with nonzero input low words) pass
  independent reference scoring. A separate direct production replay matches
  both output words across baseline/candidate × development/release ×
  native/bytecode, including all fixture input lines in order.
- Fast batch exact equivalence covers 99,088 outcomes. Planner equivalence
  covers 77,744 civil-day-representable maturities; the other 21,344 fixture
  maturities remain explicitly excluded, not counted as passes.
- The public digest remains
  `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
- Seven targeted, successfully compiled mutants are killed by their designated
  numerical witnesses after a clean baseline: `expm1-tiny`,
  `displaced-exact-sum`, `bachelier-distance`, `dd-exp-accumulator-low`,
  `dd-log-accumulator-low`, `dd-exp-degree`, and `normal-dd-series`.
  The optional catalog now has 96 probes; the default core stays at seven.
- The immutable implementation source archive installs successfully, preserves
  all ten license/notice files, and passes installed public-API consumers in
  native and bytecode. Both installed 649-row Exchange replays match the
  qualified values, radii and failures. These reuse the existing references.
- `actionlint` 1.7.12 validates the added release CI step. The local suites
  cover Apple ARM64; Linux x86-64/ARM64 and hosted macOS remain required PR
  checks, not inferred from this local run.

The optimization does not close #8's quiet-host/target-workload acceptance
requirements, remove all allocation, or imply production deployment approval.
No version bump, release or tag is part of this round.
