# Remaining American allocation: focused attribution

After retaining bounded native solving in the [backend comparison](results-american-backends.md),
the next #119 optimization target is enclosed time-step/boundary arithmetic,
followed by cash interpolation. These owners dominate the current Bermudan,
piecewise and cash workloads. This attribution pass changes only a profiling harness and
documentation; production arithmetic, work bounds and served values are unchanged.

The subsequent [exponential scratch qualification](results-enclosure-exponential-scratch.md)
records the implementation, matched savings and remaining cash-interpolation cost.
The measurements below remain the pre-optimization attribution.

## Scope and evidence

The [frozen protocol](evidence/american-remaining-allocation/protocol.md) profiles
the same singleton requests and 64-cell/64-step initial settings as #147.
Baseline integration is `9fae37a6f6eb13d09db99f658d8432a84c3421f6`; the exact
measured harness revision, source snapshot, compiler and executable hashes are
in the [manifest](evidence/american-remaining-allocation/manifest.json) and
[raw archive](evidence/american-remaining-allocation/raw.tar.gz).
[Summary and original frame attribution](evidence/american-remaining-allocation/summary.json).
Collection used the existing OCaml 5.3.0 Flambda toolchain on the same M1 Pro.

Eight workloads each run three fresh native processes with 20 unprofiled calls
and 20 separately profiled calls. `Gc.counters` measures main-domain managed
allocation; these scalar executions create no worker domains. `Gc.Memprof`
uses rate 0.0001 and stack depth 20. Full stacks and process records are retained.
Builds finish first, source/binary guards pass, and every process completes with
unchanged complete request replay. Sixteen preliminary native/bytecode runs
agree on request digests; all seven cases shared with #147 match its digests.
Piecewise without cash is the additional existing workload.

Grouped sample counts repeat identically across the three processes for every
workload. Repetition therefore does not establish independent sampling precision.
Shares below are approximate attribution, not exact byte budgets or predicted
optimization savings. Raw RSS includes profiling, captured stacks and harness
tables; it is not an unprofiled deployment peak. No latency comparison is made.

## Current allocation owners

Decimal MB per singleton request; shares group stack frames by spatial
preparation, time slabs/boundaries, cash interpolation and grid construction.
Other frames remain explicit in the summary. The aggregation script and its
grouping rules are retained in the raw archive.

| Workload | Managed MB | Spatial preparation | Time/boundary arithmetic | Cash interpolation | Grids | Other |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Flat | 6.983 | 46.1% | 36.4% | 0% | 6.9% | 10.6% |
| Cash | 22.574 | 14.6% | 29.2% | 44.7% | 4.2% | 7.3% |
| Bermudan with cash | 42.328 | 7.9% | 61.9% | 24.2% | 2.1% | 4.0% |
| Piecewise | 33.160 | 19.5% | 76.5% | 0% | 1.6% | 2.4% |
| Piecewise-cash | 45.321 | 14.9% | 57.4% | 22.2% | 2.0% | 3.4% |
| Delta/gamma | 7.162 | 44.3% | 35.5% | 0% | 7.1% | 13.1% |
| IV resource-limit refusal | 6.225 | 51.8% | 30.1% | 0% | 8.2% | 9.9% |
| Strict arithmetic refusal | 0.902 | 79.5% | 0.4% | 0% | 11.2% | 8.9% |

The small difference from #147's allocation figures reflects harness/counter
scope; no production optimization occurred. Refused IV and strict requests are
kept as refusals, not successful throughput or accuracy passes.

`Enclosure.Make.pack_array` is the largest sampled allocation leaf in cash,
Bermudan and piecewise-cash, followed by enclosure construction and arithmetic
scratch. The expensive callers differ: cash interpolation's enclosed weight and
value calculation, Bermudan discount exponentials, and piecewise zero/top
boundary exponentials. A leaf count alone does not establish that its record
can safely be eliminated; the original-input enclosure and failure contracts
still govern any implementation.

## Next implementation pass

Prioritize repeated time-step/boundary enclosure work across Bermudan and
piecewise requests. Investigate bounded call-owned scratch and reuse only where
the complete arithmetic inputs/dependencies match. Preserve intermediate error
checks, original time words, curve segments, exercise/cash sides, local allowances
and logical callback/work ordering. Existing boundary reuse already applies in
some paths; this profile does not justify a broader cache without a validity
argument and workspace accounting.

Cash interpolation is the next separate candidate, particularly temporary
enclosures for weights and interpolated values. Retain its original-input
arithmetic error checks and mapping refinement. Spatial preparation remains a
material owner in flat/Greek requests and should remain in the regression corpus.

Before implementing either change, freeze its specific safety/dependency argument
and paired acceptance campaign. Require independent numerical evidence for a
changed operation graph, or complete exact replay plus applicable enclosure
witnesses for storage-only changes. Measure cumulative allocation and ordinary
latency separately; do not infer a speedup from these profiles. #119 remains open
and #120 still owns final integration qualification.

To reproduce a native profile after building the executable:

```sh
opam exec --switch=morphiq-risk-ml -- dune build --profile release \
  bench/american_remaining_allocation.exe bench/american_remaining_allocation.bc.exe
env -u MORPHIQ_CAPTURE_CELLS _build/default/bench/american_remaining_allocation.exe \
  --case cash --calls 20
```

The raw collector repeats all eight cases, checks source/binary identities and
compares the shared request digests with the retained #147 qualification. Its
recorded local paths must be adjusted when rerunning elsewhere.
