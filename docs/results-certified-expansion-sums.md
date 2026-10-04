# Certified expansion sum optimization (#8)

Runtime enclosure addition now uses magnitude-ordered FastTwoSum and a single
final residual finiteness check. The comparison establishes the algorithm’s
precondition; it retains the exact rounded sum/residual pair used by the previous
Knuth TwoSum. The [derivation](runtime-enclosures.md#magnitude-ordered-exact-sums)
covers subnormals, zeros, overflow rejection and zero elimination. No accuracy
limit, series count, retained precision, model formula or public signature changes.

Baseline is PR #92 merge `9d535fbfc3c984b35d200bcf267a8ffde8fdc570`.
Implementation is `0a2c8723e9d1c293b9f21f8da9833eb7aa1751dd`; subsequent
changes correct harness metadata/mutation dispatch and retain documentation.
[Raw evidence](evidence/certified-expansion-sums/README.md) binds the numerical
sources, binaries, harnesses, outcomes and host observations.

## Profile and decision

A five-second baseline sample of the retained BSM harness found 1,970 top-of-stack
samples in enclosure `grow`, the largest individual entry. The harness includes
fast and certified calls; the sample is a diagnostic, not a timing comparison.
A private-array/list-removal probe reduced allocation by about 14.6% but raised
ordinary BSM price time by about 2% in its paired probe. It was discarded.
The retained change leaves storage and term order intact and reduces exact-sum
work and repeated finiteness checks.

## Paired performance

Apple M1 Pro, macOS 27, OCaml 5.3.0 Flambda, Dune default profile, numerical
library `-O3`. Each baseline/candidate pair uses identical harness sources and
compiler settings. No task-owned build, test, oracle, mutation or profiler ran
during these timings. Other workstation activity remained; one-minute loads
ranged 19.4–29.7 in scalar runs, 15.1–20.3 in portfolio runs and 10.6–15.1 in
Exchange runs. These measurements do not establish an isolated-host SLA.

Times below are median [minimum–maximum] batch means in milliseconds per price.
Two ABBA rounds provide four fresh processes and twenty samples per variant.
Each scalar phase has five warm-ups, then five batches of 40 evaluations or
end-to-end calls; admission uses 1,000 calls per batch. Full major GC precedes
each sample outside timing; CPU time and cumulative allocation are retained.
Volatility construction is outside timing. End-to-end includes model admission.

| Price request | Baseline ms | Candidate ms | Time reduction |
| --- | ---: | ---: | ---: |
| black76 | 1.066 [1.055–2.063] | 0.958 [0.942–1.148] | 10.1% |
| bsm-ordinary | 1.143 [1.113–1.195] | 1.022 [1.003–1.184] | 10.6% |
| bsm-short | 0.426 [0.419–0.473] | 0.373 [0.366–0.385] | 12.5% |
| bsm-tail | 3.842 [3.801–4.217] | 3.370 [3.343–3.434] | 12.3% |
| displaced | 1.047 [1.035–2.224] | 0.926 [0.917–0.958] | 11.5% |
| normal | 0.388 [0.382–0.960] | 0.346 [0.340–0.355] | 10.9% |

Ordinary BSM admission-plus-price falls from 1.134 to 1.023 ms (9.7% less
elapsed time). Price-only allocation is essentially unchanged: 5,709,883 to
5,709,579 bytes/call, including counter overhead. This round does not solve
certification’s multi-MB allocation cost. Expiry and accuracy-failure cases stay
in the raw counts; no failed request is reported as a served price.

| 24-row ordinary portfolio execution | Baseline ms | Candidate ms | Time reduction |
| --- | ---: | ---: | ---: |
| 1 outputs/row | 23.091 | 20.963 | 9.2% |
| 11 outputs/row | 52.213 | 46.969 | 10.0% |
| 2 outputs/row | 34.060 | 30.832 | 9.5% |

The portfolio contains all four models and both sides; its per-row averages
are not BSM-specific latency. Ordered outcomes match between variants and
worker counts; boundary and failure workloads remain in the evidence.

Exchange ordinary/singular/tail evaluation time falls 9.7%/13.9%/10.9% in its
ABBA campaign. Every measured result retains its previous status and certificate.

The initial IV/workflow ABBA run had a candidate-process interruption: for example
Black-76 OTM IV measured 1,736.5 µs wall time versus 910.2 µs CPU time, compared
with 841.8 µs in the other candidate run. We retained that run and repeated the
identical binaries, inputs and protocol. The repeat measures 4.5–6.0% less IV
time and 4.2–6.6% less full-workflow time across twelve model/regime groups.
Each run retains all 384 outcome classifications. No speedup is claimed for
unchanged fast price/Greek paths; both initial and repeat spreads remain visible.

## Numerical and packaging validation

- Build/install, formatting and the complete ordinary suite pass. Initial harness
  configuration/format failures and the successful corrections are recorded,
  rather than counted as numerical passes or mutation kills.
- New independent exact-rational sum guard: 30,774 served cases and ten overflow
  refusals per enclosure configuration and mode, passing on both baseline and
  candidate in native and bytecode execution.
- Existing two-/four-word tests each check 1,126 deterministic primitive cases,
  2,000 random compositions and 40,354 elementary/normal references. The model
  and public suites retain 1,670 original-input prices, 2,506 smooth Greeks,
  4,176 public certificates and 3,932 acceptance-limit controls.
- Public digest remains `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
- All 12,618 retained outcomes over 978 input rows match baseline/candidate
  scalar/grouped paths exactly, including radii and failures. Truncated, corrupt
  and reordered output controls reject.
- All nine targeted compiled mutations are killed after a clean baseline:
  sum ordering, sum finiteness, grow residual, discarded word, product guard,
  FMA underflow, series tail, public radius and IV rounding-cell acceptance.
  The optional catalog has 88 mechanisms; default CI remains seven.
- The immutable source artifact installs and passes external native/bytecode
  consumers. All ten installed notices match. Both installed Exchange consumers
  reproduce all 649 qualified rows: 625 served, ten numerical failures, five
  accuracy failures, seven invalid inputs and two invalid accuracy limits.

## Remaining scope

This completes the measured exact-sum optimization round. It does not finish
#8’s target-environment/operational qualification, or remove the roughly 1 ms
ordinary certified BSM cost. Further substantial reductions require a separately
justified allocation or evaluation strategy; no tolerance relaxation is implied.
Three-platform numerical CI is required before landing. Performance has only
been measured on this shared M1 Pro host. No version, release or tag is created.
