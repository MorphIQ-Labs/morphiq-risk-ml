# Shared Greek intermediates: qualification and measurements

Issue [#8](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/8), 2026-10-04.
Baseline: `c5126db391b42529867e3716b5b9ef0b10ed43f6` (PR #91).
Implementation: `e9572101db6e8b6a982937aa19b0c30102cceff3`.
This round extends reuse within grouped certified requests; stable Production,
Batch and Planner signatures, exact input meaning and numerical formulas remain
unchanged. The unstable Internal model interface gains a worker-owned evaluator.
No version, release or deployment acceptance changes.

## Selection and arithmetic argument

The [pre-change phase profile](evidence/shared-greeks/preparation-profile.txt)
attributes about 0.617 MB to one ordinary BSM common Greek setup, including
standardized inputs and weighted density. Each signed CDF costs about
1.75–1.76 MB in that sample. Ten individually evaluated Greeks allocate 15.18 MB
(BSM) or 12.88 MB (Bachelier), even after the model itself has been prepared.
[Host conditions](evidence/shared-greeks/preparation-host.json) are retained;
this diagnostic selected repeated work, not a universal cost model.

The [dependency and failure contract](shared-greek-intermediates.md) precedes
scoring. Common setup fixes original model, side, volatility and rho convention.
Quantity-specific CDF/derivative expressions remain lazy. Each reused enclosure
has the same words and radius as independently evaluating that expression;
existing outward arithmetic is still performed at each use. There is no
physical-identity shortcut or assumption that interval errors are independent.
The same analytical bounds and arithmetic capability guards therefore apply.
No CDF term count, approximation, threshold or accuracy allowance changes.

The evaluator is local to one synchronous call. An arithmetic failure is cached
only in the affected common setup or deferred dependency; final accuracy-limit
failure remains per-output. Price/IV retain their separate evaluators. The
existing scalar Greek wrapper builds a fresh evaluator for each call; this
round does not introduce a persistent cache on an admitted model or plan.

## Correctness and compatibility

Build/install, pinned formatting and the complete ordinary suite pass. The
[ordinary execution log](evidence/shared-greeks/ordinary.log.gz) retains an initial
compile error in the new optional shadow renderer; correcting its typed float
conversion changes no runtime/test source. The
[final successful combined build/format/ordinary check](evidence/shared-greeks/final-ordinary.log.gz)
uses those passing test results through Dune's dependency graph.

- 4,176 independent public certificate references and 3,932 exact accuracy-limit
  controls pass. The grouped path is checked against the independently scored
  scalar certificate, including exact-bound acceptance and smaller-bound refusal.
- Native and bytecode tests cover reordered/duplicate/empty requests, both sides,
  all four models, displaced low words, both rho conventions, mixed limits,
  boundary/failure outcomes and independent concurrent calls.
- The new tiny-maturity witness fixes exact T=2^-1060 for normal ATM with r=0.
  Inverse maturity overflows for three time derivatives, while price and vega
  remain sqrt(T)/sqrt(2*pi), and delta remains +/-1/2. Those independent values
  must survive in either output order. The
  [same witness passes the baseline](evidence/shared-greeks/baseline-guard.log.gz).
- [Six compiled mutation witnesses](evidence/shared-greeks/mutations.log.gz) are
  killed after a clean mutation-profile baseline: eager inverse maturity,
  grouped/scalar accuracy limits, certificate radius, rho convention and daily
  units. The new fault is rejected by independent ATM availability/value checks,
  before any frozen replay assertion. Optional full catalog: 86; default CI: seven.

The [independent Arb planner audit](evidence/shared-greeks/planner-arb.json)
passes all 2,376 original-input price/Greek certificates, including corrupt-result
and truncation controls. Workers 1/2/3/4 emit identical bytes; the
[baseline comparison](evidence/shared-greeks/planner-replay.json) is unchanged at
SHA-256 `f3f24cbb32e0a6c151ab34038b6adb5428700cc0c9a14d814f1f11e049610fd6`.
The ordinary public digest remains
`5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.

The [retained-corpus replay](evidence/shared-greeks/shadow-replay.json) checks both
scalar and grouped evaluation on baseline and candidate. All 258 synthetic inputs
(3,258 output rows) and 720 canonical inputs (9,360 rows) match their captured
results exactly, including admission, certificate words/radii, errors and IV.
Counts include admissions; canonical non-admission outcomes remain 8,640.
Truncated, corrupted and reordered output controls are rejected. No failures are
omitted. These replays establish compatibility; independent references establish
accuracy over exercised inputs, not every finite admitted input.

The [source-artifact installation](evidence/shared-greeks/installed-e957210.json)
passes external native/bytecode multi-output consumers. All ten installed notices
match. The full 649-case Exchange replay is unchanged in both modes (625 served,
10 numerical failures, five accuracy failures, seven invalid inputs and two
invalid-accuracy controls). Source archive, report and build log are retained in
the local acceptance archive under the exact implementation commit. This local
qualification does not claim a new three-platform full-86 candidate campaign or
independent human/institutional acceptance.

## Paired portfolio measurements

The [raw ABBA campaign](evidence/shared-greeks/portfolio-abba.json.gz) retains source,
binary and driver hashes, compiler configuration, output digests/counts, host load
and every wall/CPU/allocation sample. Both worktrees use the identical
`bench/shared_portfolio.ml` already delivered by PR #91. The baseline library is
unchanged; optional shadow/profile scaffolding is copied separately for validation.

Apple M1 Pro, macOS 27 arm64, OCaml 5.3.0 Flambda; Dune release with library `-O3`
and standard release benchmark flags. No task-owned build, test, mutation, oracle
or package replay runs during measurement. Sampled one-minute host load spans
7.06–8.58; other machine activity continues. These are shared-host observations,
not isolated tail-latency or production-host guarantees.

Two sequential ABBA rounds give four fresh processes per version. Each phase has
two warm-ups and five two-call samples per process: 20 batch means per variant.
Explicit full major GC precedes each sample outside timing; allocation and GC
caused by the measured operation remain inside. `Gc.counters` measures current-
domain total allocated bytes, not retained heap or peak RSS. Execution uses one
worker; digest/coverage validation checks workers 1/2 outside the timed region.
Compilation, execution and end-to-end phases are recorded separately.

Each invocation processes 24 rows: both sides of four models across three
scenarios, with fixed original words, weights 100/-99 and typed limits 1e-8.
Ordinary valuation offsets are 0/7/30 days against 365-day expiry; boundary offsets
are 0/365/366; arithmetic-failure cases use rate -2000. Requested outputs are price
only, price/Delta, or all eleven quantities. Every complete event/status digest
matches across variants, repeated execution, fresh compilation and worker count.

Milliseconds below are per complete 24-row execution, median [min–max]; allocation
is decimal MB per execution. All nine workloads are retained.

| Regime / outputs | Before ms | After ms | Speedup | Allocated MB before → after |
| --- | ---: | ---: | ---: | ---: |
| boundaries/1 | 7.363 [7.268–7.604] | 7.344 [7.253–7.505] | 1.00× | 38.977 → 38.979 |
| boundaries/11 | 31.138 [30.709–31.553] | 16.654 [16.492–16.861] | 1.87× | 160.198 → 86.576 |
| boundaries/2 | 10.984 [10.799–11.247] | 10.917 [10.809–11.059] | 1.01× | 57.189 → 57.197 |
| failure/1 | 0.090 [0.086–0.105] | 0.088 [0.087–0.091] | 1.03× | 0.425 → 0.426 |
| failure/11 | 0.126 [0.123–0.181] | 0.127 [0.123–0.130] | 0.99× | 0.517 → 0.518 |
| failure/2 | 0.093 [0.089–0.098] | 0.092 [0.089–0.095] | 1.01× | 0.434 → 0.435 |
| ordinary/1 | 22.619 [22.463–23.124] | 22.647 [22.449–31.479] | 1.00× | 118.647 → 118.651 |
| ordinary/11 | 96.400 [95.451–110.686] | 51.366 [51.052–57.221] | 1.88× | 491.446 → 264.031 |
| ordinary/2 | 33.488 [33.174–34.283] | 33.999 [33.250–35.015] | 0.98× | 173.975 → 173.998 |

Eleven ordinary outputs improve from 96.40 to 51.37 ms (1.88×, 46.7% less time),
with 46.3% less allocation. End-to-end medians are
96.11 → 51.58 ms (1.86×).
One/two-output cases have no repeated Greek work to remove; their medians are
essentially unchanged (ordinary execution +0.12%/+1.53%, allocation
+0.0037%/+0.0129%). Failure cases already reject during model preparation and
have no expected improvement. No compile-only or single-output speedup is claimed.

Ordinary served counts are 24/48/264. Boundary served/failed counts are 16/8,
24/24 and 96/168; arithmetic-failure counts are 0/24, 0/48 and 0/264. These match
before/after. No availability improvement is inferred from faster grouped work.

## Standalone Greek overhead

A separate [phase ABBA campaign](evidence/shared-greeks/scalar-abba.json.gz) runs
the identical `greek_preparation` harness sequentially, after portfolio timing.
It constructs no shared evaluator between scalar calls. BSM/normal Delta, Vega,
Theta and complete ten-Greek sequences show median changes from effectively 0%
to -2.02%, with allocation increases of 0.026–0.115%. These small timing changes
are not claimed as scalar speedups. The bounded lazy-cell allocation adds little
to each scalar enclosure's existing cost in these ordinary cases; this is not a
whole-domain overhead bound. Raw spread and CDF/common-setup control phases remain.

## Reproduction and remaining work

Use isolated worktrees at the two commits above and the pinned switch. Build
`bench/shared_portfolio.exe` with `dune build --release -j 2` in each. For shadow
and phase comparisons, copy the candidate's `bench/shadow.ml`,
`bench/greek_preparation.ml` and corresponding Dune stanza into the baseline,
then build those executables with the same profile. Keep its library unchanged.

```sh
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_shared_portfolio.py \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --rounds 2 --output /tmp/portfolio.json
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_greek_preparation.py \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --output /tmp/scalar.json
python3 scripts/replay_greek_sharing.py \
  --baseline /path/to/baseline/_build/default/bench/shadow.exe \
  --candidate /path/to/candidate/_build/default/bench/shadow.exe \
  --output /tmp/replay.json
```

Run timing campaigns sequentially, with builds/tests finished. The phase driver
is included with this qualification follow-up; numerical implementation, tests
and benchmark sources remain the implementation commit above. Ordinary suite,
`audit_planner.py`, and `candidate_artifact.py` retain their documented commands.
This engineering round is complete; #8/#16 remain open for isolated target-
environment and operational qualification against predeclared requirements.
