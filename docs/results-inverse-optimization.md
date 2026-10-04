# Inverse-normal optimization: operation-preserving reuse

Baseline: `e673a3d9534f8dd64b1cee835a51c71bd9e4dd58` (PR #69).
The maintainer authorized starting this performance round while that PR was
still awaiting merge. This is separate work under #8; no merge is implied.

## Contract fixed before scoring

Keep all inverse steps, domain switches, series coefficients, stopping rules,
explicit multiplication/FMA boundaries and error allowances unchanged. Target
bit-for-bit preservation of both words of Normal_dd results, every inverse
fixture, the financial replay and fixed-quote IV outcomes. A measured speedup
cannot justify weakening any of those checks.

The baseline native sample identifies DD division, its reciprocal construction,
Marsaglia's series and the DD exponential as hot operations. Existing paired
benchmarks separately record allocations and full-workflow costs. Sampling is
attribution evidence, not a controlled throughput comparison.

Two reuse opportunities preserve the original rounded operation graph:

1. The final inverse correction evaluates Phi(d) and phi(d). Phi already
   computes the identical density. Return the CDF and density together from
   their owner; compute d*d once as well. Each reused DD value is the result
   of exactly the same operations on the same immutable input words.
2. Each normal-series denominator is an exact positive odd integer, 3 through
   801. Dd.div's divisor normalization and reciprocal construction depend
   only on the divisor. Prepare those exact intermediate words once with the
   existing operations; retain the original dividend normalization, final
   DD multiplication and exponent restoration on every call. The general
   Dd.div implementation remains unchanged as a compatibility witness.

The DD owner exposes an abstract prepared divisor, constructed only for a
finite nonzero high word. Its original two-word divisor is retained for exact
rational replay. Prepared division is algebraically **and operationally** the
same quotient path, not multiplication by a newly rounded 1/n approximation.
Existing 9.8u² and finite-exponent allowances therefore remain applicable.
Preparation and use require the same normalized-DD/arithmetic-environment
preconditions as ordinary division. Invalid preparation is explicit.

Normal_dd owns its private fixed table, initialized once with those operations
and read afterward. The 400-entry limit follows from the existing k>400 stop:
iteration k=400 can divide by 801; k=401 stops before indexing. There is no
lazy shared mutable cache, new coefficient source or foreign arithmetic.
Pair evaluation remains inside the existing |d.hi|<=6 component domain.

## Numerical and package qualification

Full ordinary suites pass in both development and release, including generated
exact-rational replay, existing bounds, properties, oracle checks and financial
certificates. Build/install and format checks pass. No tolerance, reference,
coefficient, iteration count, digest or CI requirement changes.

The [compatibility record](evidence/inverse-optimization-compatibility.json)
retains source and trace hashes. All 86,145 DD rows (both words), 130,394 normal
rows and 8,330 fixed-quote IV outputs match the baseline. The 11,379 inverse
inputs retain central maximum 0 ULP, tail maximum 2 ULP and zero sampled
monotonicity reversals. This does not establish universal correct rounding.
The financial and inverse digests remain, respectively:

- `e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593`
- `91bedc0a4352538aa60ae7c831f27bcaf16be0058a45daa3d6c33f2501344c19`

All 4,468 prepared-quotient cases agree with unchanged Dd.div word for word and
pass independent exact-rational quotient allowances. Cases include all 400
series denominators, subnormal dividends, both signs, nonzero low words,
normalization-threshold neighbors and exponent rescue from subnormal inputs.
Paired CDF/PDF results additionally pass independent pinned references.

The [IV work trace](evidence/inverse-optimization-iterations.json.gz) retains
identical counts: 4,540 iterated LBR calls / 9,068 steps, and 8,948 certified
calls / 4,373 refinement steps. [Development](evidence/inverse-optimization-dev.log.gz)
and [release](evidence/inverse-optimization-release.log.gz) logs preserve the
full ordinary qualification.

All seven affected [mutation witnesses](evidence/inverse-optimization-mutations.log)
start from a clean passing baseline, build successfully and fail their designated
numerical guard: prepared quotient exponent, reciprocal residual and numerator
normalization; existing division normalization, DD series, inverse iteration
count and inverse correction. Replay changes are not counted as kills.
The optional catalog grows from 58 to 61; default CI retains seven core mutants.

Installed native and bytecode consumers reproduce the complete inverse digest,
endpoint/domain checks and a certified Black-76 price/IV smoke case. The
[package record](evidence/inverse-optimization-install.json) includes consumer
source, both outputs and byte-for-byte documentation/notice checks.
The primary integration API is unchanged; preparation and paired evaluation
are exposed only through the unstable Internal modules. This is a patch-level
performance change with no observed served-value changes and no version bump.

## Related paths checked

Dd.log_float already prepares its fixed odd reciprocals at module initialization;
it does not repeat this divisor construction in its loop. DD divisions in model
formulas and inverse refinement use request-dependent denominators and remain
ordinary divisions. Interval divisions in Enclosure and Model_enclosure have
different outward-rounding contracts. Reusing them requires separate analysis;
this change does not make that substitution. Every Normal_dd CDF consumer,
including cancellation-sensitive Greeks, receives the prepared-series benefit.

## Performance evidence

Measured on Apple M1 Pro (10 hardware threads), macOS 27.0, OCaml 5.3.0
Flambda, library/benchmarks `-O3`. The three repeated AB/BA/AB orders use
sequential processes after all task-owned builds/tests stop. One-minute host
load spans 5.15–12.11; this remains a shared-workstation campaign. Primitive
batches contain 20,000 inputs, one warm-up and nine samples. Each full-workflow
cell has 64 deterministic inputs and seven batches. The primitive harness uses
wall-clock batch time; the assurance harness records its calibrated clock,
CPU time, request distributions, GC and outcomes. Batch averages are not
single-request latency.

[Raw paired measurements](evidence/inverse-optimization-benchmark.json.gz)
retain all runs, within-run spread, allocations, source/harness fingerprints
and load. The candidate was uncommitted during timing, so its **source hashes**,
not its then-shared HEAD value, identify the changed implementation.
[The baseline profile](evidence/inverse-optimization-profile.txt.gz) was collected
with `sample PID 2 -file OUTPUT` during the release inverse harness. Partial
stack unwinding does not support precise hotspot percentages.

Release medians of the three process medians:

| Workload | Baseline ns/call | Optimized ns/call | Time reduction | Words/call before → after |
| --- | ---: | ---: | ---: | ---: |
| Inverse central | 2,555 | 1,554 | 39.2% | 835.6 → 431.3 |
| Inverse ordinary tail | 4,127 | 2,702 | 34.5% | 1,493.1 → 816.1 |
| Inverse power-of-two corpus | 1,495 | 1,432 | 4.2% | 412.5 → 376.3 |
| LBR proposal | 4,263 | 2,919 | 31.5% | 1,699.6 → 986.5 |

The power-of-two corpus spans 2^-1 through 2^-1074 and includes a small fraction
inside the changed DD-correction domain; its label `inverse_extreme` does not
mean every sample exercises only the untouched extreme-tail path. Individual
release batch ranges are retained: central baseline 2,528–3,619 ns vs optimized
1,533–1,605; ordinary tail 4,084–4,618 vs 2,680–2,738; power-of-two 1,476–1,551 vs
1,412–1,476; LBR 4,199–4,477 vs 2,885–3,039.
Development reductions are respectively 42.7%, 37.8%, 6.0% and 37.6%.

Across four models and three regimes, all-ten-Greek batches improve 15.2–36.7%
with reduced allocations. Full workflow medians move -1.74% to +1.46%; IV
medians move -0.35% to +1.07%. These small timing differences are not a causal
regression bound. Large exact-model certification workloads dominate the full
path; improving the proposal alone does not deliver a comparable end-to-end
gain. Per-operation records and outcomes remain in the raw artifact.

[Cold-process measurements](evidence/inverse-optimization-initialization.json.gz)
use 50 alternating pairs, force library initialization and then collect live
words after a full major collection. Live heap increases 320 → 4,724 words:
4,404 words / 35,232 bytes (34.4 KiB) on this runtime. Launch-plus-initialization
medians are 3.725 ms baseline and 3.712 ms optimized. Ranges are 3.287–102.585 ms
and 3.368–5.275 ms: OS process-launch noise, including a baseline outlier,
prevents extracting a reliable small initialization-time delta. These numbers
are not isolated table-construction times or RSS measurements.

## Reproduction and remaining scope

Use baseline `e673a3d9534f8dd64b1cee835a51c71bd9e4dd58` and this candidate in
separate worktrees; copy this candidate's `bench/initialization.ml` and its
Dune stanza into the baseline solely for the identical startup harness.
Build `bench/inverse_normal.exe`, `bench/assurance.exe` and
`bench/initialization.exe` in development and release (`--profile release
--build-dir _build-release`), always with `-j 2` on this shared machine.

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 @install @fmt @runtest
opam exec --switch=morphiq-risk-ml -- dune build -j 2 --profile release --build-dir _build-release @install @runtest
# Export MORPHIQ_ORACLE_TRACE separately for baseline/candidate DD and normal tests.
python3 scripts/measure_inverse_iterations.py --root . --output IV.json.gz
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- prepared-quotient-exponent prepared-reciprocal-residual prepared-numerator-scale normal-dd-series division-numerator-scale inverse-iteration-count inverse-dd-refinement
# Stop task-owned checking before timing.
python3 scripts/benchmark_inverse_normal.py --baseline BASELINE --replacement . --output BENCH.json
python3 scripts/benchmark_initialization.py --baseline BASELINE --replacement . --output STARTUP.json
```

Required three-platform CI and seven-core mutation CI remain the merge gates;
local evidence does not substitute for those checks. #8 retains business-workload
and operational qualification. Further approximation/refinement changes require
fresh derivations and separate numerical compatibility evidence. #64's final
provenance/artifact audit and exact-candidate acceptance remain separate.
