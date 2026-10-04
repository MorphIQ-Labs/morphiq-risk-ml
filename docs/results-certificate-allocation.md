# Certificate allocation optimization (#8)

The enclosure owner now accumulates expansion terms in a private checked float
array. It preserves the ordered TwoSum operations, retained words, discarded
word allowances and public acceptance rules. On the measured exchange workload,
this reduces cumulative allocation 65–74% and evaluation time 14–22%.

Baseline: `bea4620a94104ab526fb61f6919012e5f9faa309` (qualified exchange main).
Runtime candidate: `d81e2302fa1b0c0a6954954169716e722ace07d5`.
Later changes in this PR only retain results and documentation. The
[raw evidence](evidence/certificate-allocation/README.md) pins source/binary
hashes, compiler, host, loads, samples and compatibility outputs.

## Why this change

A separate three-second sampling run of the exchange benchmark recorded 2,482
main-thread samples: 1,334 at the expansion grow loop and 177 at list reversal.
The original ordinary exchange evaluation allocated 21,414,657 bytes/call.
This points to expansion work and temporary storage, not a build/compiler
bottleneck. Sampling is not an exhaustive allocation attribution or GC pause
measurement; instrumented timing is excluded from comparisons.

A preliminary list-only version removed one reversal. It allocated 9–14% less,
but observed evaluation times were flat to 4% slower; it was not retained.
[Its summary](evidence/certificate-allocation/list-prototype.json) records this
negative result. The final change removes intermediate boxed expansion lists
throughout a pack, while preserving the public immutable representation.

## Arithmetic and storage obligations

The [storage argument](runtime-enclosures.md#allocation-preserving-arithmetic-order)
proves traversal equivalence, capacity from input count, initialized reads and
absence of writes into unread terms. The final reverse-index pass is the same
word/radius order as the old reversed list. Every access remains checked and
each buffer belongs to one call. No global cache, unsafe access, shared scratch,
foreign primitive, threshold, series count or new numerical method is introduced.

This change applies to both two-word and four-word enclosures and their price,
Greek and IV consumers. Previous canonical expansion and exchange comparisons
remain references for the identical arithmetic; they are not rerun or presented
as new canonical results. The existing exact-rational and independent fixture
checks are executed against the candidate.

## Numerical and compatibility evidence

- Build/install, formatting and the complete ordinary suite pass. Each enclosure
  configuration checks 1,126 deterministic primitive cases, 2,000 random
  compositions and 40,354 elementary/normal references; out-of-domain rows remain
  separately counted. Both model configurations check 1,670 original-input rows.
- All 649 qualified exchange requests reproduce their outcome, value and radius
  words in baseline native, candidate native and candidate bytecode. Independent
  scoring still contains both reference intervals for all 625 served certificates;
  15 explicit failures and nine invalid controls remain unchanged.
- The frozen 258-contract shadow workload reproduces all 3,258 output rows:
  admission, certified prices/Greeks with radii, IV roots and failures.
- The public replay digest remains
  `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
- Five affected mutations cover dropped grow residuals, discarded words,
  product preconditions, series tails and FMA residual underflow. The mutation
  log records the clean baseline and designated numerical kills. The optional
  catalog grows to 84; the seven default CI selections are unchanged.

These finite campaigns supplement the operation/storage argument; they do not
prove the compiler or establish availability for every mathematically valid input.
No oracle allowance, requested limit or digest was changed to accept the candidate.

## Controlled measurements

Both versions use the same OCaml 5.3.0 Flambda switch and Dune default build;
the numerical library and assurance harness use `-O3`. Host: Apple M1 Pro,
macOS 27. No task-owned tests, builds or profiler ran during the A/B/B/A timing.
Other workstation activity remained: one-minute loads ranged approximately
3.9–4.5. These are local workload observations, not quiet-host service guarantees.

The exchange harness performs 20 warm-up evaluation/end-to-end pairs, then seven
rounds of 100 calls per phase. Phase order alternates within each run; admission
uses 20,000 calls. Each version therefore has 14 batch samples per phase.
Times below are median [minimum–maximum], in milliseconds per call. Allocation
is cumulative decimal MB/call, including the same small measurement overhead;
it is not RSS. Failure rows remain in the denominator and raw evidence.

| Exchange regime | Baseline ms | Candidate ms | Time reduction | Allocated MB, before → after |
| --- | ---: | ---: | ---: | ---: |
| Ordinary | 1.507 [1.496–1.546] | 1.255 [1.253–1.275] | 16.7% | 21.415 → 6.765 |
| Near singular correlation | 0.657 [0.655–0.688] | 0.562 [0.560–0.569] | 14.4% | 9.680 → 3.385 |
| Deep OTM tail | 4.457 [4.415–4.610] | 3.484 [3.476–3.593] | 21.8% | 63.555 → 16.703 |

End-to-end medians improve 14.6–21.6% across those three regimes. Early domain
failure allocation remains about 353 bytes/evaluation and 409 bytes/end-to-end;
its tiny timings and admission timings are too small for strong conclusions.

The existing assurance harness separately tests 32 fixed contracts per
model/regime, five warm batches and all 384 outcomes in every A/B/B/A run.
Across its twelve IV groups, cumulative allocation falls 46.2–51.9%; observed
median-time reductions are 1.4–6.8%. Complete admission/price/IV/Greek workflow
allocation falls 45.9–51.5%, with observed time reductions 1.9–7.2%. Raw per-run
spread, CPU time and collection counts remain in the evidence. Small timing
differences may be workstation noise. Fast price/Greek allocations are unchanged;
their noisy short-call timings are not claimed as improvements from this change.

## Decision and remaining scope

Retain the private-buffer change: it substantially reduces allocation, improves
the measured full-certificate exchange paths, and preserves the measured
certificates and failures. Public compatibility is patch-level under the
stability policy; this work does not bump a version, tag or publish a release.

#8 remains open for further profiling and operational measurement. Representative
business portfolios and owner-defined latency/failure limits remain #16;
independent human review and release decisions remain #15/#17. The remaining
millisecond costs and multiple MB of cumulative allocation per exchange call
still matter for high-throughput applications.
