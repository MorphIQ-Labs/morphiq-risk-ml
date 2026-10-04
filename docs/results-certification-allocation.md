# Certification allocation optimization (#8)

Representative runtime-certified BSM allocation falls from 5.71 MB to 1.31 MB
per price (77.1% less), with 11.4% less elapsed time in the paired run. These
are cumulative temporary allocations, not retained memory or a leak estimate.

Baseline is PR #93 merge `13087ffc4d6169ee976fe4b50b0aef560aff8fb6`.
Implementation is `5c5cc5256a03f175831b42000cd76524e23b5e31`; subsequent changes
retain evidence and documentation. [Raw measurements and validation](evidence/certification-allocation/README.md)
bind source revisions, hashes, binaries, harnesses and outcomes.

## Change and compatibility

Enclosures now use immutable all-float records and bounded, private float arrays.
This removes boxed word lists, product tuples, reversed packing lists and float
argument/result boxes. Packing consumes its own initialized input array, with
writes proved not to overwrite unread terms. Normal product exponents are
extracted directly; zero/subnormal inputs retain `Float.frexp`. The
[representation, ownership and operation-order argument](runtime-enclosures.md#fixed-words-and-private-packing-storage)
records capacities, padding, retained words and exponent preconditions.

No accuracy limit, precision, series count, arithmetic order or certificate
acceptance rule changes. No global cache, shared scratch, unchecked access or
new FFI is introduced. Stable public APIs are unchanged. The unstable
`Internal.Enclosure.S.t` research surface replaces `tail : float list` with
`third` and `fourth` fields; `words` still reconstructs its logical expansion.
Internal consumers that inspect the old field must adapt and recompile.

Ordinary fast scalar pricing and fast Greek kernels are unchanged. The fast
Black-family price API already refines severe coordinate cancellation through
enclosures; those exceptional calls use the optimized implementation too.
Certified prices, smooth Greeks, IV, Exchange and planner execution all consume
enclosures. This does not turn ordinary fast prices into runtime certificates.

## Allocation attribution

A separate OCaml `Gc.Memprof` run samples 100 representative BSM prices after
five warm-ups, at rate 0.001 with twelve call-stack frames. Before profiling,
`Gc.counters` measures 5,709,577 versus 1,309,113 allocated bytes per call.
Sampled site estimates are diagnostic and vary between runs; profiled elapsed
time is excluded from performance comparisons. The baseline shows widespread
list, tuple and boxed-float allocation in packing and multiplication.

The remaining candidate samples concentrate in packed result records (~293 KB),
multiplication buffers (~256 KB), exact-value records (~184 KB), addition
buffers (~176 KB) and negated records (~97 KB) per price. The retained raw
stacks and aggregation expose the other sites. About 1.3 MB is still material:
further reduction would need fewer immutable intermediate values or a separately
justified evaluation/storage strategy. It is not an allocation-free evaluator.

## Paired scalar performance

Apple M1 Pro, macOS 27, OCaml 5.3.0 Flambda, Dune default profile, library `-O3`.
Both variants use identical benchmark sources and compiler settings. All task-owned
builds, tests, profilers and mutation campaigns finished before timing. Other
workstation activity remained. One-minute load observations span 14.2–18.7 for
scalar runs, 9.7–10.9 for portfolios, 9.3–10.8 for Exchange and 7.1–15.3 for IV.
These shared-host batch means are not request tail latencies or deployment SLAs.

Scalar measurements use two ABBA rounds, twenty samples per variant, five warm-up
calls per phase and forty calls per timed price batch. Admission uses 1,000 calls.
Full major GC precedes each sample outside timing. CPU time, allocation and
collection counts are retained. Volatility construction is outside timing;
end-to-end includes model admission. MB below means decimal megabytes.

| Price request | Baseline ms, median [min–max] | Candidate ms, median [min–max] | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| black76 | 0.941 [0.935–0.954] | 0.836 [0.827–0.852] | 5.607 | 1.297 |
| bsm-ordinary | 1.005 [0.995–1.016] | 0.890 [0.879–0.913] | 5.710 | 1.309 |
| bsm-short | 0.372 [0.365–0.384] | 0.331 [0.322–0.340] | 2.408 | 0.674 |
| bsm-tail | 3.389 [3.348–3.443] | 3.205 [3.181–3.260] | 17.737 | 4.182 |
| displaced | 0.924 [0.912–1.004] | 0.845 [0.836–0.861] | 5.514 | 1.296 |
| normal | 0.342 [0.338–0.349] | 0.310 [0.304–0.318] | 2.551 | 0.629 |

Ordinary BSM admission-plus-price falls from 1.007 to 0.890 ms. The price-only
allocation counter records 5,709,579 versus 1,309,115 bytes/call, including small
counter overhead. Each forty-price batch has 108 baseline versus 24 candidate
minor collections; both have zero major collections inside the measured batch.
This is a collection count, not a measurement of GC pause duration or retained RSS.

The expiry control remains in the evidence: 907 to 603 bytes/call, with batch
means around 100 to 125 ns/call, too short for strong timing claims with this
protocol. The impossible-accuracy control still refuses the request; its cost
is retained rather than counted as a served price. All eight scalar outcome
strings match exactly, including values, radii and failures.

## Other enclosure consumers

The twenty-four-row ordinary portfolio spans all four models and both sides.
Times below are whole executions, not BSM-specific latency. Two ABBA rounds
retain twenty samples per variant, ordered output checks and worker replay.
Boundary and failure workloads are retained alongside ordinary rows.

| Outputs per row | Baseline execution ms | Candidate execution ms | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| 1 | 20.674 | 18.386 | 118.773 | 27.620 |
| 2 | 30.453 | 26.892 | 174.144 | 40.211 |
| 11 | 46.461 | 40.807 | 264.237 | 60.936 |

Exchange ordinary/singular/tail evaluation allocates 76.9%/72.7%/76.4% less and
measures 9.8%/5.9%/5.0% less time. All classifications, values and radii match.
The retained spreads include a baseline tail timing interruption; the comparison
uses medians and does not remove that observation.

The IV/workflow ABBA campaign keeps all 384 outcomes per process. IV allocation
falls 68.6–72.2%, but elapsed time is mixed: group averages of the two run medians
range from 2.1% faster to 7.2% slower. Out-of-the-money IV groups are consistently
about 2.8–5.8% slower in this run, despite much lower allocation. Some workflow
samples also show wall/CPU separation under changing host load. These observations
are retained as a cost tradeoff, not attributed entirely to GC or host noise.
Ordinary fast price allocation is identical between variants; no fast-path
speedup is claimed. All per-run medians, ranges, CPU times and counts remain in
`assurance-abba.json.gz`. Future IV latency work should profile the two-word
adaptive workload separately from the four-word certified price workload.

## Numerical and packaging validation

- Build/install, formatting and the complete ordinary suite pass.
- Both configurations retain 1,126 deterministic primitive cases, 2,000 random
  compositions and 40,354 elementary/normal checks each. The exact-rational
  sum guard passes 30,774 finite cases plus ten overflow refusals per configuration
  in native and bytecode modes.
- Model/public suites retain 1,670 original-input prices, 2,506 smooth Greeks,
  4,176 public certificates and 3,932 acceptance-limit controls.
- The public digest remains `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
- All 12,618 outcomes across 978 retained input rows match baseline/candidate
  scalar/grouped paths exactly, including radii and failures. Truncated,
  corrupted and reordered replay controls reject.
- Eleven compiled targeted mutants are killed after a clean baseline: new
  packed-fourth-word and biased-normal-exponent faults, plus discarded word,
  grow residual, sum order/finiteness, product guard, FMA underflow, series tail,
  public certificate radius and IV rounding-cell acceptance. The optional catalog
  now has 90 mechanisms; default CI remains seven.
- The immutable implementation artifact installs and passes external native and
  bytecode consumers, including planner concurrency/replay. All ten installed
  notices match. Both installed Exchange modes reproduce 649 qualified rows:
  625 served, ten numerical failures, five accuracy failures, seven invalid
  inputs and two invalid accuracy limits.

These finite tests support the change over their exercised inputs; they do not
prove universal availability or resolve independent review obligations. This
finishes the measured allocation round. #8 still owns operational qualification;
its IV latency tradeoff and remaining 1.3 MB cost are explicit. Three-platform CI
is required before landing. No release, version bump or tag is created.
