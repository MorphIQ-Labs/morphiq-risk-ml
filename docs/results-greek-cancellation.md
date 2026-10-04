# Greek cancellation qualification (#80)

The fast Black-family Greek API now refuses exhausted DD coordinates instead
of serving inaccurate finite sensitivities or inventing a payoff kink from a
rounded zero. Zero-volatility theta uses a stable DD identity. A separate
smooth-theta component-cancellation limit refuses only that field. See the
[derivation and declared capability](greek-cancellation-design.md).

This is a **major outcome/numerical change** (minor while 0.y.z). The model,
original binary64 input meaning and Greek units are unchanged. Refusals are
not accuracy successes; no empirical allowance was widened. These selected
limits do not certify all other fast Greeks or imply whole-domain accuracy.
Production and certified IV keep their own owners and contracts.

## Original-input challenges

Generator version 1 freezes 10,760 requests: all ten fields, calls/puts,
neighboring rates and spots, dyadic maturities, currency scales, zero/tiny/
ordinary volatility, common discount, tied models, exact ATM, displaced low
words and underflowed real carry. Independent Arb formal-series sensitivities
and boundary identities use original inputs, bounded refinement through
256/512/1024/2048/4096 bits, and outward intervals to resolve references.
The fixture records transitive source hashes and Python 3.14.8, mpmath 1.3.0,
python-flint 0.9.0 and FLINT 3.6.0. Generation uses 64-row subprocesses with
60-second deadlines. Runtime checks require exact membership and every result
ID, verify provenance, and impose a 120-second batch deadline.

| Outcome | Baseline | Candidate |
| --- | ---: | ---: |
| Independently checked values | 10,187 | 9,458 |
| Quality excursions | 437 | 0 |
| Independently checked boundary classes | 96 | 96 |
| Wrong classes | 32 | 0 |
| Explicit numerical failures | 8 | 1,206 |
| Unresolved references | 0 | 0 |

Nine inaccurate values become checked values, 428 become numerical failures,
and 32 wrong classes become numerical failures. Another **738 previously
within-budget values become unavailable** under the conservative capability
restriction. All 96 kink/control classes are preserved. Exact-ATM controls
also require their existing smooth results; availability is not silently
weakened there. The ten original #80 fields have permanent independent-value
or numerical-failure regressions, with no false payoff-kink allowance.

The baseline is `7783c6b7b38a10e54ce6855525fdd64f45e365cf` (PR #81's
qualified tree). The qualified arithmetic is `856ef7a`; subsequent documentation
and rebases preserve that runtime source. Per-row before/after outcomes,
references, runner binary hashes and scorer provenance are retained.

## Compatibility and public replay

All **66,400 historical Greek oracle rows** remain byte-identical. Their
finite-corpus accuracy and classification gates are not universal guarantees.
The original-input challenge above exercises cases absent from that corpus.

The public replay changes **1,013 words, all zero-volatility theta**. An
independent audit reconstructs original replay inputs using the emitted exact
moneyness factors and encloses every changed derivative. Worst baseline error
among those records is 13,458,194 ULP; every candidate is within 1 ULP. All other
price, IV and Greek replay words/classes are unchanged. This evidence supports
the intentional digest change from
`e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593` to
`5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
The retained audit contains every changed word and original-input reference.

The broader 7,095-request #54 campaign retains one quality finding (#77),
with 6,195 checked values, 438 class checks, 166 reference-uncertain rows,
278 availability failures and 17 nonfinite fast prices. It has zero contract
violations. Four formerly checked values become explicit failures; the campaign
is not a clean overall accuracy claim, and #57 remains open.

## Separate performance measurements

The same benchmark harness ran baseline/candidate/candidate/baseline, each with
one warm-up and seven measured batches (14 samples per variant). Host: Apple
M1 Pro, macOS arm64, OCaml 5.3.0 Flambda, Dune 3.24.2, `-O3`. No other task test,
reference generator or benchmark ran during timing. Load snapshots, compiler
configuration, source/harness/binary hashes and every sample are retained.

Median microseconds for the fixed ordinary BSM cases:

| Operation | Baseline | Candidate |
| --- | ---: | ---: |
| Admission, sigma=0.2 case | 1.129 | 1.146 |
| Price, sigma=0.2 | 1.518 | 1.514 |
| All Greeks, sigma=0.2 | 9.392 | 9.306 |
| Admission + Greeks, sigma=0.2 | 10.504 | 10.459 |
| Price, sigma=0 | 1.278 | 1.281 |
| All Greeks, sigma=0 | 1.407 | 2.753 |
| Admission + Greeks, sigma=0 | 2.562 | 3.873 |

The extra zero-variance DD assembly costs about 1.35 µs in this ITM sample.
Ordinary positive-volatility differences are within observed variation.
Selected severe-cancellation Greek requests now refuse before price evaluation;
end-to-end admission/refusal measures about 1.1 µs. This is reduced capability,
not accelerated successful evaluation. The 100-call severe batches do not
resolve precise nanosecond refusal costs; their raw post-admission numbers
must not be treated as such a claim. Price/admission algorithms are unchanged;
no workload-wide overhead or availability rate follows from these samples.

## Validation

Local `dune build @install @fmt @runtest -j 2` passed. Seven affected mutants
had a clean baseline, compiled successfully and failed their numerical guards:
`smooth-theta-cancellation`, `zero-variance-theta-cancellation`,
`cancelled-greek-coordinate`, `underflowed-greek-coordinate`,
`cancelled-price-refinement`, `greek-finite-result` and `zero-variance-veta`.
The four new mechanisms are optional. Default CI still runs the same seven
core mutants; the full manual catalog now has 72. This qualification does not
claim that the full catalog ran locally.

## Reproduction

```sh
opam exec --switch=morphiq-risk-ml -- dune build @install @fmt @runtest
python3 scripts/check_greek_cancellation.py \
  --reference oracle/challenges/greek-cancellation-v1.json.gz \
  --runner _build/default/test/numerical_boundary_runner.exe \
  --runner-source "$(git rev-parse HEAD)" --output /tmp/greek-cancellation.json
opam exec --switch=morphiq-risk-ml -- dune exec bench/greek_cancellation.exe
```

Optional reference regeneration uses the pinned Python environment:
`python scripts/greek_cancellation_reference.py --output /tmp/greek-reference.json.gz`.
For the replay audit, run each qualified implementation's `test/determinism.exe`
with its digest file and a second output-file argument, then use
`scripts/audit_greek_replay.py --before BEFORE --after AFTER --harness
_build/default/bench/greek_cancellation.exe --output /tmp/replay-audit.json.gz`.
The reference tools support `--help` and `--version`; ordinary CI needs only
Python's standard library and committed fixtures.

[Retained evidence](evidence/greek-cancellation/) includes the complete outcome
reports, per-word replay audit, compatibility hashes and performance samples.
No release, whole-domain assurance or independent human sign-off is implied.
