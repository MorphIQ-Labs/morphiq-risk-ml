# Scenario-planner qualification

Epic #23's upstream OCaml delivery was qualified on the integration branch
before merging. The [contract](scenario-planner.md) defines dates, units,
structural compilation, bounded ownership, failure semantics and the aggregate
containment argument. This is engineering qualification, not institutional
deployment approval under Epic #27.

## Numerical and execution evidence

- The independent [Arb campaign](evidence/planner-arb-reference.json) checks
  2,376 prices and all ten analytic Greeks over 27 scenarios, eight instruments,
  four models and both sides. Price series differentiation is independent of
  production Greek formulas. All certificates meet the fixed 1e-10 typed
  requirement. Corrupt values and truncated campaigns are rejected.
- Output bytes agree across 1, 2, 3 and 4 workers. Ordinary tests also vary tile
  sizes, retain post-expiry and admission failures, check snapshot isolation,
  empty jobs, exact coverage, overflowed/resource-limited plans, sink failures
  and cancellation. A deliberately delayed sink must preserve the complete event
  sequence and execute only on the coordinator. Two compiler-negative cases retain volatility-coordinate
  separation through batch/planner operations.
- Exact rational arithmetic checks weighted aggregate intervals, including
  position multiplication, severe mixed-sign cancellation and subnormals.
  Intermediate aggregate overflow remains explicitly unresolved, even when
  later contributions would cancel it. Failed items cannot produce a complete
  total. Rate-factor identities and denomination conflicts are checked.
- `batch_iv_reference` compares all 8,330 original IV fixture outcomes against
  scalar admission/inversion, including nonfinite invalid inputs. Served
  positive roots also match the independently generated reference word.
- The local ordinary suite, build/install and formatting checks pass. Legacy
  scalar replay remains
  `f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b`.
- All four [optional planner mutants](evidence/planner-mutations.txt) compile
  and are detected: snapshot aliasing, post-expiry misclassification, discarded
  scalar radius and falsely complete totals. The catalog has 51 mechanisms;
  default CI still selects the original seven.

Independent interval validation is evidence over its recorded corpus, not a
universal availability theorem. Accepted scalar results and aggregates rely
on their runtime enclosure contracts; failures remain possible elsewhere.

## Compilation scaling follow-up

The [group-count qualification](results-planner-compilation.md) addresses #63's
quadratic compilation cost for heterogeneous aggregation keys. It adds both
homogeneous and growing-group compile-only measurements; the historical
million-instrument campaign below does not exercise that cardinality dimension.

## Layout decision

[Raw measurements](evidence/planner-scale.json) retain source/binary hashes,
commands, host load, repetitions, allocations, collections and process RSS.
The benchmark compares the direct scalar loop, typed batch requests, and a
packed structure-of-arrays alternative including packing and scalar extraction.
All served bits and outcome classes agree. Median elapsed seconds:

| Items | Scalar | Typed batch | Packed alternative |
| --- | ---: | ---: | ---: |
| 32 | 0.03473 | 0.03411 | 0.03438 |
| 256 | 0.28203 | 0.28156 | 0.28235 |
| 1,024 | 1.13543 | 1.13208 | 1.12991 |

These small differences do not justify a representation optimization. Retain
the thin typed batch API as the scalar-preserving execution boundary and the
immutable-record layout for heterogeneous plans. Do not advertise a scalar
kernel speedup. [The existing kernel harness](performance.md#reproduction-and-measurement-contract)
separately measures pre-admitted price/IV/Greek operations and admission; its
recorded scalar measurements are historical baselines, not newly measured batch
costs. The present layout and planner campaigns measure complete request costs.
The main operational benefit is bounded orchestration,
explicit outcomes and parallel execution without changing the pricing graph.

## Scale, memory and throughput

Host: Apple M1 Pro, macOS ARM64, upstream OCaml 5.3.0 Flambda with -O3.
The experiment build was explicitly paused throughout this campaign; no local
build/test ran concurrently. Recorded load averages still include prior work
and unrelated host activity. This is a workstation measurement, not an isolated
production-host SLA or a hardware-independent speed claim.

For 1,000 live instruments × three scenarios, three runs per worker count gave:

| Workers | Minimum s | Median s | Maximum s |
| --- | ---: | ---: | ---: |
| 1 | 3.709 | 3.713 | 3.727 |
| 2 | 1.953 | 1.957 | 1.957 |
| 4 | 1.164 | 1.202 | 1.657 |

The observed spread is retained; three repetitions do not establish a production
p99. Logical totals are byte-identical across worker counts and runs.
For 10,000 live instruments × three scenarios, aggregate-only execution took
12.352 seconds and streaming took 12.575 seconds, with identical totals. Peak
RSS was 29.47 MB and 28.69 MB respectively. The sink in this experiment consumes
and counts events in memory; this is not disk, network or database throughput.

The manual million-instrument campaign used four workers and 1,024 rows/tile:

| Workload | Packing s | Planning s | Execution s | Peak RSS | Buffered slots |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1,000,000 live instruments × one scenario | 0.186 | 1.742 | 412.738 | 1.137 GB | 4,096 |
| 1,000,000 expiry instruments × three scenarios | 0.194 | 1.808 | 1.148 | 1.022 GB | 4,096 |

Every requested valuation completed with no scalar failure or incomplete total.
The live run reported approximately 2.224 trillion allocated words, with
2,302,435 minor collections and 64 major collections. These are differences of
global `Gc.quick_stat` snapshots: allocation counters are sampled at collection
boundaries and can omit uncollected tails. They describe cumulative allocation,
not resident memory or exact per-domain allocation. The same sampling limitation
applies to layout and compiler-comparison allocation fields; elapsed timings
and process RSS are measured separately. Runtime certificate arithmetic remains expensive; the planner
does not make that cost disappear. The expiry case measures orchestration and
exact payoff arithmetic and must never be substituted for live-pricing speed.

Memory includes the input book, copied indices, canonical identity construction,
GC heap and bounded results. The canonical identity buffer and input validation
have O(input-size) transient memory; the planner does not promise a process-RSS
limit from its result-slot bound. There is no result cube. The million campaign
uses synthetic flat Black-76 positions, not a representative institutional book
with curves, settlement or all Greeks. The smaller independent campaign covers
all four model families and all analytic quantities.

The raw campaign source is `740cadc`; subsequent changes add inspection fields,
a denomination-conflict check, an executable example and further tests. They do
not change evaluation, reduction, result buffering or the measured kernel. The
record preserves the measured binary hashes instead of pretending those timings
were taken from a later documentation commit.

Reproduce manually (never a default CI command):

```sh
opam exec --switch=morphiq-risk-ml -- dune build bench/planner_scale.exe bench/batch_layout.exe
python3 scripts/measure_planner.py \
  --scale-binary _build/default/bench/planner_scale.exe \
  --layout-binary _build/default/bench/batch_layout.exe \
  --output /tmp/planner-scale.json --million
```

## Remaining production and feature boundaries

No economic P&L, post-expiry settlement, full market-surface roll, quote-scenario
IV planner, durable resume, full-cube output, distributed executor or SIMD
backend is implied. The scalar-equivalent batch supports supplied IV quotes.
Worker creation per bounded wave is simple and measurable; a persistent
scheduler is a future optimization requiring its own ownership/conformance
review. The [OxCaml experiment](../experiments/oxcaml/README.md) is isolated
from the deployed toolchain. Target-environment qualification, independent human
review and final production acceptance remain with Epic #27.
