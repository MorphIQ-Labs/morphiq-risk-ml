# Bounded American policy kernels and memory diagnosis (#119)

Move policy selection, Thomas elimination/back substitution and value copying
into bounded original-project C loops. Complete ordinary put price and inverse
requests improve by about 26–28% in the fixed local campaign; cash controls
improve by 24–26%. Numerical operations, outcomes, refinements and logical work
remain unchanged over the qualification corpus. Allocation is essentially
unchanged. This is an estimated-solver latency improvement, not certification
or a new financial method.

## Ownership, arithmetic and adoption

The [frozen protocol](evidence/american-native-policy/protocol.md) precedes the
implementation. The OCaml operation reference was committed separately as
`e7a1802` before native code `83d058d`. Selection retains three nested explicit
FMAs and the strict exercise comparison. Forward/back substitution retain
separately rounded products, subtraction/division, identity-row bands, positive
pivot checks, nonfinite failure order and partial writes. Fingerprint arithmetic
uses unsigned modular operations matching OCaml immediate integers.

The internal owner borrows nine disjoint float bands and two disjoint masks,
roots them for each call, validates shape/range/aliasing before arithmetic, and
visits at most 256 interior rows. Valid blocks neither allocate nor call OCaml,
release the runtime lock, retain pointers, create threads or change the floating
point environment. Invalid inputs may allocate when raising an exception.
Immediates written into masks/state require no pointer write barrier. The owner
and caller retain exclusive workspace ownership; this is a documented discipline,
not a compiler-enforced ownership proof.

OCaml still owns assembly, boundary removal, outer policy iteration, stagnation,
original-system residual checks, refinement and failures. One pre-row tick starts
each block. Its end precedes the next callback/budget edge; actual visited rows,
including a failing row, restore exact accounting. Metadata fits the existing
64 KiB workspace reserve; numerical buffers are unchanged. The small additional
per-request allocation is recorded below. No matrix factors are cached and no
LAPACK/BLAS, vendor code or dependency is introduced.

Disposition: **adopt these bounded kernels** on the American integration branch.
The unchanged full-request benchmarks include validation, dispatch, assembly,
policy systems, elimination, residuals and refinements. This is not an isolated
Thomas-solve benchmark or a LAPACK crossover study. Broader backend/batch and
worker evaluation remains in #119. The blocking/vendor storage rules and
arithmetic constraints remain in the [solver design](american-solver-design.md).

## Numerical and resource qualification

- Full development and release ordinary suites, release install/build/format
  passed. Both native and bytecode internal controls passed; an initial standalone
  bytecode invocation lacked stub search paths and was corrected without changing
  runtime code. The final test-only commit prevents constant folding of FP probes.
- Direct blocks of 1, 7, 255 and 256 rows match the separately frozen OCaml
  operation graph, including signed zero, subnormals, all six failure statuses,
  partial writes and fingerprint wrap. Independent exact-rational small systems
  and a mixed identity-row system check numerical meaning separately from replay.
  Exact arithmetic witnesses distinguish fused and separately rounded operations.
- Shape, range, alias, GC-surrounding and independent concurrent-owner controls
  pass. These exercised cases are safety evidence, not a proof for arbitrary
  unsafe callers or all runtime/compiler environments.
- All **572 complete price outcomes**, **920 Greek rows with full payloads** and
  all **three 30-case inverse campaigns** match the pre-change runtime exactly.
  Existing independent scores, refusals and unresolved references are preserved;
  replay equality itself is not independent accuracy evidence.
- Installed native/bytecode consumers agree on **80 terminal** and **30 tight IV**
  outcomes, also matching the prior runtime. **54 complete callback, cancellation
  and row-budget traces** match across both builds and both execution modes.
- **12/12 targeted compiled mutants** were killed after a clean baseline: ten
  policy arithmetic/mask/pivot/finite/work/alias mechanisms and the two affected
  residual controls. The optional catalog is now 167; default CI remains five
  checks and seven core mutants.

Full suites and compiled mutants cover runtime `83d058d`; the final measured
`a07ae172b0dca2cffb26693fdd3180a9c05df190` changes only interface commentary and
opaque-input FP tests, which pass in both modes. No serving numeric result or
public API changes are intended. Evidence does not close historical strict
price/Greek reference gaps or certify general early exercise.

## Matched complete-request measurements

Baseline is clean `eaa5e189015219dc489542c86fc654ee2f8bc904`, whose tree equals
integration `d690ce76051807a3c129fc8ab1d1587edf006096`. Candidate is the clean
`a07ae17` above. Both use OCaml 5.3.0 Flambda, release builds, library/benchmark
`-O3`, and explicit no-contraction/no-fast-math C flags on an Apple M1 Pro.
Exact sources, driver/binary hashes, OS/compiler/configuration, loads, raw
samples and own-child resource usage are in the [timing record](evidence/american-native-policy/raw/timing.json).

The unchanged `bench/american_iv.ml` uses 128/128 grids, three domain expansions,
width 0.005 and unchanged budgets/quotes. Five alternating fresh-process pairs
have one warmup and three timed blocks per path. Medians below cover 15 blocks;
analytical blocks average 20 sequential requests, other blocks one. Task-owned
builds, qualification, allocation profiles and RSS probes all finished first.
One-minute host load ranged about 6.3–12.5; this was a shared host. Baseline
samples include substantial variation, retained in full. These are local warm
engineering results, not cold-start, tail-latency or deployment guarantees.

| Path | Median ms/request, before → after | Cumulative MB/request, before → after |
| --- | ---: | ---: |
| `american-put/end-to-end` | 673.1310 → 498.5050 | 80.923200 → 80.946048 |
| `american-put/price` | 113.2650 → 81.3380 | 13.475224 → 13.479032 |
| `american-put/solve` | 692.6760 → 499.8820 | 80.922728 → 80.945576 |
| `call-100-0.05-american/end-to-end` | 0.4884 → 0.4941 | 0.710182 → 0.710182 |
| `call-100-0.05-american/price` | 0.0792 → 0.0782 | 0.116662 → 0.116662 |
| `call-100-0.05-american/solve` | 0.4896 → 0.4880 | 0.709710 → 0.709710 |
| `cash-terminal-american/end-to-end` | 0.3590 → 0.3480 | 0.527464 → 0.527464 |
| `cash-terminal-american/price` | 0.0730 → 0.0740 | 0.120672 → 0.120672 |
| `cash-terminal-american/solve` | 0.3570 → 0.3560 | 0.526536 → 0.526536 |

All frozen criteria pass: at least 25% improvement on general put price, solve
and end-to-end paths; at most 10% latency regression for analytical/terminal
controls; at most 5% allocation growth everywhere. Observed allocation growth
on the general paths is below 0.03%, rather than a material allocation reduction.
Whole mixed-process peak RSS remains about **19–20 MB** for both versions.

The unchanged `american_allocation` cash controls use two domain expansions,
one warmup and three sequential prices per process, again five alternating
pairs. They are a separate configuration from the three-expansion table above.
[All four controls](evidence/american-native-policy/raw/cash-timing.json) exceed
the frozen 20% latency gain with less than 5% allocation growth:

| Cash schedule | Median ms/request, before → after | Cumulative MB/request, before → after |
| --- | ---: | ---: |
| none | 101.820 → 75.223 | 12.910552 → 12.914360 |
| zero | 284.603 → 210.611 | 29.433464 → 29.438360 |
| cash | 294.566 → 223.243 | 42.173304 → 42.178200 |
| multiple | 445.676 → 339.426 | 69.210192 → 69.215088 |

The allocation probe still observes enclosure and grid preparation allocations;
its small sampled site counts are retained without claiming precise proportions.
This pass does not solve the remaining cumulative allocation cost. Latency
collector controls reject truncated, malformed, duplicate, nonfinite, failed,
timeout and impossible-criterion evidence; nine controls pass.

## Explaining PR #143's higher mixed-process RSS

A common instrumented public client compares pre-#143 `07916c6` with post-#143
`eaa5e18`, separate from the new native candidate. Three fresh-process repetitions
per version/configuration yield 54 processes. The client records `Gc.quick_stat`
at phase boundaries and after explicit `Gc.full_major` calls, while the parent
collects each child's own peak RSS with `wait4`. The installed OCaml 5.3.0 GC
interface documents that quick statistics are sampled; `Gc.stat` itself forces
collection, so it is not used to observe unperturbed phases. Interface/source,
client hashes and all raw counters are retained.

| Instrumented workload | Median peak RSS MB, pre-#143 → post-#143 |
| --- | ---: |
| Original mixed order | 12.829 → 18.399 |
| Reversed mixed order | 9.159 → 8.733 |
| Extra collection after each mixed path | 14.565 → 22.381 |
| Isolated general put price | 8.077 → 7.995 |
| Isolated general put inverse | 8.602 → 8.651 |
| Isolated terminal-cash price | 8.929 → 4.555 |
| Isolated terminal-cash inverse | 8.700 → 4.833 |
| Repeated general put price, 20 rounds | 8.143 → 8.012 |
| Repeated general put inverse, 20 rounds | 8.782 → 8.700 |

The higher peak first appears during the general put's initial inverse checks
after the now-cheap terminal case, before timed price blocks. In original order,
major-heap high-water words rise from 693,280 to 1,254,439; reversing order removes
that increase. Every original/reverse/extra-collection mixed process ends at the
same **5,442 reachable words and 57,747 heap words** after collection. In repeated
put probes, post-collection live words stay exactly **5,586 for price** and
**5,580 for inverse** across all 20 rounds in both versions.

These probes locate the regression in transient, history-dependent heap growth
and collection behavior; they do not show retained-object growth in the exercised
requests. The exact OCaml allocator/pacing mechanism was not instrumented, so a
particular runtime heuristic is not asserted as the sole cause. Logging and
forced collections perturb scheduling; the original uninstrumented observation
remains valid. Peak RSS includes native/runtime pages and is not cumulative
allocation or live numerical workspace. More forced collection made the peak
worse, so no production GC setting or collection call is introduced. Deployment
memory and long-lived concurrent services still need their own campaign.

## Evidence and remaining work

[Raw archive](evidence/american-native-policy/raw.tar.gz),
[manifest](evidence/american-native-policy/manifest.json),
[RSS summary](evidence/american-native-policy/raw/rss-summary.json) and
[source manifest](evidence/american-native-policy/raw/source-manifest.json) retain
original-project collectors, all samples, compatibility payloads, build/ordinary/
mutation/installed logs and failed startup evidence. Reference derivations and
fixtures remain in their existing owning documents; public validation needs no
private archive.

#119 remains open for compiled/worker/cancellation measurements, actual-matrix
backend crossover studies, justified alternative methods and further allocation
work. #118 owns compiled American execution and #120 final artifact qualification.
The earlier specialized-method production defer decision is unchanged. This pass
lands only on the American integration branch; it does not establish an SLA,
independent review, release acceptance or final main-branch qualification.
