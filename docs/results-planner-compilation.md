# Planner compilation group-count qualification

Issue [#63](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/63), measured
2026-10-04 UTC. This is a patch-level internal performance change: public
signatures, resource-policy outcomes, plan identities and numerical operations
are unchanged. No version bump or release is made.

## Change and invariant

The previous compiler called `Buckets.cardinal` after every position. That
operation traverses the map: with one new group per position, the traversals
visit 1 + 2 + ... + N nodes, independently establishing quadratic work.

The compiler now maintains a distinct-group count. Initially both map and count
are empty/zero. For each requested position/output key:

- Membership uses the **same map comparator** as aggregation and execution.
- An existing key changes neither the map nor count.
- A new key requires count < max_groups, then increments and inserts exactly one
  entry. Thus count equals map cardinality by induction and remains bounded by
  the validated nonnegative limit. Checking before increment also covers max_int.

Group bookkeeping is O(K log(G + 1)) for K requested position/output pairs and G
groups, excluding key-comparison cost. This is not a universal whole-compiler
complexity claim: hashing identities, encoding strings, sorting kernels and
constructing the final indexed map remain. There is no scalar evaluation in
compilation. A search of `lib/` found no other repeated `cardinal` call.

The original `Buckets.add key 0` retains the first key when its existing integer
value is physically equal to 0 (OCaml 5.3 `Map.add`). Skipping equivalent insertions
preserves that representative, including its zero sign. Signed zeros compare as
the same real model, while all original input words remain in plan encoding.
`Buckets.bindings` still determines sorted bucket indices. Rejecting the first
excess key returns the same group-limit error as the former per-position check;
no intervening validation or successful output is bypassed.

## Correctness evidence

Build/install, formatting and the complete ordinary development suite pass
([full local log](evidence/planner-groups-validation.log.gz)). This includes
planner scalar/batch comparisons, exact-rational aggregate containment, failure
and cancellation handling, worker/tile replay, and the numerical reference suite.
Release builds of both comparison benchmarks and the focused guard also pass.
There is no arithmetic, compiler, dependency, tolerance or fixture change.

`test/planner_groups.ml` exercises empty portfolios/outputs, one and two outputs,
one group, twelve duplicate positions, a new group at either end, every limit
from zero through one above the true count, and a max_int limit. BSM dividend
yields and displaced-model parameters cover both signed-zero orders and a
nonzero distinct parameter. Accepted plans must report the expected count,
ordered unique summaries, complete totals and every duplicate contribution.
The representative zero sign is checked explicitly.

The exact same focused guard passes against the unchanged baseline and candidate.
Their manifests and complete emitted events have identical BLAKE2b-256 replay:
`add1883b68d8d6d69536da521294fc00f87a8bd0e2d02617101e7128848f447f`.
This identity comparison is compatibility evidence, not the correctness oracle.
The independent boundary assertions establish the group-policy expectations.

Two [fault-injection controls](evidence/planner-groups-controls.json) start from
a passing clean guard, compile successfully, then fail the intended assertion:
counting duplicates rejects a valid book; bypassing the limit accepts an invalid
book. Exact replacement snippets and commands are retained. The isolated source
was restored byte-for-byte and the baseline benchmark rebuilt afterward. These
local controls are not additions to the curated mutation catalog; the existing
seven-core CI policy is unchanged.

A separate `bench/planner_reference.exe --workers 1` run retains identical bytes
for all 2,376 price/Greek rows over 27 scenarios, eight instruments and four models.
SHA-256 before and after is
`f3f24cbb32e0a6c151ab34038b6adb5428700cc0c9a14d814f1f11e049610fd6`.
The ordinary financial replay remains
`e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593`.

## Controlled compile-only measurements

Baseline production source: `e8ed54219a473c72a18a318b90381ed0d91ff80a`.
Candidate implementation and harness: `e8ca8f8e428be43168a34afa06bd6ccc692b74b5`.
Only identical new benchmark/test scaffolding is copied into the baseline; its
production source is unchanged. The [raw campaign](evidence/planner-compile-abba.json.gz)
retains revisions, source and binary hashes, source-diff hashes, complete compiler
configuration, timestamps, load, allocations, GC counts and plan identities.

Apple M1 Pro, macOS 27 arm64, OCaml 5.3.0 Flambda, Dune release with library and
benchmark `-O3`. No task-owned builds/tests ran during measurement. Other machine
activity remained: one-minute load ranged 4.56–7.66. This is shared-host evidence,
not an isolated performance bound or latency SLA.

For each of twelve books, three sequential ABBA rounds give six fresh-process
samples per version (144 measured compiles total). Each process constructs the
portfolio/market first, compiles once as warm-up, performs a full major GC, then
times one `Planner.compile` with the existing monotonic benchmark clock. Setup,
warm-up, explicit GC reset and JSON output are outside timing; allocations and
GC work caused by compilation are inside. Result counts are checked, and every
before/after/repeated plan identity must agree or the campaign fails.

Books use the issue's Black76 expiry-price setup: one unshocked scenario,
forward/strike 100, volatility 0.2, rate 0, quantity 1, USD, unique position IDs,
one requested price with limit 1e-10, aggregate-only output. Only the explicit
rate-factor group count varies: one, N/10 or N. Max instruments/calculations/groups
are N; max scenarios/workers are 1; tile/buffer sizes are 100. No plan is executed.

| Positions | Groups | Before ms, median [min–max] | After ms, median [min–max] | Speedup |
| ---: | ---: | ---: | ---: | ---: |
| 5,000 | 1 | 7.49 [7.29–7.62] | 7.31 [7.17–7.61] | 1.02× |
| 5,000 | 500 | 14.51 [13.93–15.05] | 8.54 [8.44–8.79] | 1.70× |
| 5,000 | 5,000 | 57.32 [56.43–59.89] | 12.81 [12.54–13.06] | 4.47× |
| 10,000 | 1 | 15.11 [14.62–15.22] | 14.50 [14.21–15.15] | 1.04× |
| 10,000 | 1,000 | 41.54 [41.09–44.36] | 17.10 [16.63–17.30] | 2.43× |
| 10,000 | 10,000 | 180.05 [174.52–182.21] | 24.79 [24.59–24.93] | 7.26× |
| 20,000 | 1 | 28.92 [28.57–29.53] | 29.12 [28.50–29.47] | 0.99× |
| 20,000 | 2,000 | 153.34 [150.80–156.14] | 34.74 [34.14–35.43] | 4.41× |
| 20,000 | 20,000 | 619.07 [612.08–639.15] | 51.92 [51.21–53.36] | 11.92× |
| 40,000 | 1 | 59.08 [58.78–60.15] | 59.51 [58.84–60.89] | 0.99× |
| 40,000 | 4,000 | 506.13 [493.13–509.79] | 70.21 [68.94–71.15] | 7.21× |
| 40,000 | 40,000 | 2318.03 [2300.65–3153.46] | 116.44 [113.39–142.43] | 19.91× |

At 40,000 distinct groups, median compilation improves from 2318.03 ms to 116.44 ms
(19.91×). Doubling distinct-group books from 20,000 to 40,000 takes 2.24× after
the fix, compared with 3.74× before. One-group median differences are small
relative to observed variation; no homogeneous speedup is claimed.

Allocation uses current-domain `Gc.counters`, with an executable known-allocation
control. `Gc.quick_stat` is retained only for sampled collection counts. An initial
diagnostic used its lagging allocation snapshots; those allocation estimates
were discarded and the whole campaign repeated with the corrected harness.
The final measurements show six additional allocated words per position plus
three fixed words for this one-output corpus (240,003 words, about 1.83 MiB, at
40,000 positions). That is total allocation, not retained heap or peak RSS. The
count adds constant retained state; the existing per-position closures capture
additional counting state. This change addresses traversal cost, not allocation
elimination or execution throughput. Full raw spreads remain available.

## Reproduction

In two isolated worktrees, check out the baseline and candidate revisions above.
Copy `bench/planner_compile.ml` and its executable stanza in `bench/dune` from the
candidate to the baseline, then build each with the same pinned opam switch:

```sh
opam exec --switch=morphiq-risk-ml -- dune build --release -j 2 bench/planner_compile.exe
```

From the candidate, with absolute binary/worktree paths and all builds finished:

```sh
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_planner_compile.py \
  --baseline /path/to/baseline/_build/default/bench/planner_compile.exe \
  --candidate /path/to/candidate/_build/default/bench/planner_compile.exe \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --rounds 3 --sizes 5000 10000 20000 40000 --output /tmp/planner-compile.json
```

For focused compatibility, copy `test/planner_groups.ml` and its test stanza to
the baseline and compare the two executable outputs. The same guard supports the
two recorded fault controls in isolated copies. Ordinary CI runs the bounded
functional tests; the scale/timing campaign remains explicitly manual.
