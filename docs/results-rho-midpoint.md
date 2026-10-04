# Subnormal BSM rho qualification (#77)

BSM rho now refines finite zero, subnormal and smallest-normal proposals from
the original inputs, accepting only an enclosed nearest-even rounding cell.
Unresolved arithmetic or cells return field-specific `Numerical_failure`.
The [derivation](rho-subnormal-design.md) covers normalized coefficients,
central probability corrections, scaled Mills tails and inexpensive zero
proofs. Other fields and tied forward-model rho keep their existing owners.
This does not certify unselected normal-range fast rho results.

At S=K=1, r=q=0, T=2^-1074 and sigma=1/4, call rho is strictly between
zero and 2^-1075: it must round to zero. Put rho lies just below -2^-1075
and rounds to -2^-1074. The baseline loses the one-sided probability
correction. Its one-ULP error is within the existing 16-ULP allowance but
fails the independent rounded-zero diagnostic. No allowance was widened.

## Independent original-input evidence

Version 1 of `scripts/rho_midpoint_reference.py` freezes 11,630 requests:
adjacent subnormal/normal maturities, neighboring strikes, currency scales,
ITM/ATM/OTM coordinates, zero/tiny/ordinary volatility, common discount,
both sides, ordinary controls and tied Black-76/displaced controls. Arb
formal-series price differentiation and boundary identities use original
binary64 words, refining at 256/512/1024/2048/4096 bits. The original
midpoint resolves at 2048 bits. Generation uses 64-row subprocess batches
with 60-second deadlines, pinned Python 3.14.8, mpmath 1.3.0,
python-flint 0.9.0 and FLINT 3.6.0. Fixture and transitive source hashes
are checked before scoring; runtime batches have a 120-second deadline.

| Outcome | Baseline | Candidate |
| --- | ---: | ---: |
| Independently checked values | 9,778 | 10,114 |
| Checked boundary classes | 1,260 | 1,260 |
| Strict rounding-cell differences | 461 | 0 |
| Rounded-zero diagnostic failures | 17 | 0 |
| Original call/put witness failures | 2 | 0 |
| Explicit numerical failures | 0 | 204 |
| Unresolved comparisons | 112 | 52 |

The 461 strict-cell differences are at most two ULP; they are not failures
of the old 16-ULP allowance. The 17 zero diagnostics and two original
witnesses differ by one ULP. The new selected-cell contract requires zero
ULP error for each available selected value. Of these 480 baseline
differences, 408 become independently checked values and 72 become explicit
failures. Another 72 previously checked values become unavailable. Of the
112 references whose intervals do not resolve a rounding cell, 60 requests
now fail explicitly and 52 remain unresolved comparisons. Those 112
references have not become resolved merely because runtime refusal changes
the outcome category. Per-row results and transitions are retained.

The strict 7,095-request broad campaign has zero quality excursions and
zero contract violations: 6,193 checked values, 438 class checks,
166 unresolved references, 281 numerical failures and 17 nonfinite fast
prices. These last three categories are not accuracy successes. This is
finite-corpus evidence, not a whole-domain proof or deployment approval.

## Compatibility and validation

Baseline source is `5933a547e71cb58bbed7c7ad6383e87ba410b2a4`, whose
tree was merged by PR #82 as `6b156b2901f0603f44cd875317dc2db756c9e4c7`.
Candidate runtime and harness source is
`dd15dcb811799c601f5cad725999a5c0987c0a4f`; later changes retain evidence
and documentation only. This is a **major outcome/numerical change**
(minor while 0.y.z), because some previously available results now fail.
Model definitions, units, Production acceptance and certified IV are unchanged.

The ordinary suite checks package installation, formatting, model/oracle
certificates, arithmetic, API rejection, planner behavior, fixture provenance
and replay identity. The 66,400-row ordinary Greek trace is byte-identical
to baseline; the public digest remains
`5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
The 880-row finite-Greek challenge reports 581 checked values, 201 failures
and 98 kinks; the cancellation challenge keeps 9,458 checked values,
1,206 failures and 96 checked classes.

Seven affected mutations exercise the quick zero threshold, full tail zero
proof, scaled tail exponent, refinement dispatch, probability low words,
finite-result guard and exhausted-coordinate guard. Each requires a clean
baseline, successful mutated build and failing designated numerical witness.
Default CI still runs its seven reviewed core mutants; the optional catalog
contains 77. The retained mutation log records this focused run, not a claim
that all 77 ran here.

## Performance

Paired A/B/B/A measurements used an Apple M1 Pro, macOS 27 arm64,
OCaml 5.3.0 Flambda, Dune 3.24.2 and the library's `-O3` flags. Each
invocation discards one warm-up sample and retains seven samples per case;
the table combines fourteen samples per variant. No task-owned tests,
generators or other benchmarks ran concurrently. Load snapshots, compiler
configuration, binary hashes and raw samples are retained; host activity
and short-run timer variation remain limitations.

| All-Greeks call, microseconds | Baseline | Candidate |
| --- | ---: | ---: |
| Ordinary | 9.298 | 9.251 |
| Ordinary zero-volatility OTM | 1.320 | 3.060 |
| Original midpoint | 1.422 | 30.680 |
| Tiny-maturity ITM zero-volatility | 0.296 | 2.767 |
| Underflowed tail | 0.855 | 6.717 |

Admission plus Greeks is respectively 10.386→10.366, 2.447→4.198,
2.663→31.663, 1.467→3.865 and 1.960→7.965 microseconds. Admission
and prices are measured separately in the retained data and remain similar.
The difficult midpoint pays for full refinement. Analytical shortcuts reduce
the intermediate implementation's approximately 463/464-microsecond OTM/tail
cost to 3/7 microseconds, while still proving each zero. Historical
pre-shortcut timings are retained separately. No performance threshold gate
or broad throughput advantage is claimed.

## Reproduction and retained artifacts

From the repository root with the documented opam switch:

```sh
opam exec --switch=morphiq-risk-ml -- dune build @install @fmt @runtest -j 2
python3 scripts/check_rho_midpoint.py \
  --reference oracle/challenges/rho-midpoint-v1.json.gz \
  --runner _build/default/test/numerical_boundary_runner.exe \
  --runner-source "$(git rev-parse HEAD)" --output /tmp/rho-report.json
python3 scripts/numerical_campaign.py check \
  --reference docs/evidence/numerical-campaign/numerical-full-v1.json.gz \
  --runner _build/default/test/numerical_boundary_runner.exe \
  --output /tmp/numerical-report.json
DUNE_JOBS=2 opam exec --switch=morphiq-risk-ml -- \
  dune exec scripts/mutation/mutation.exe -- \
  rho-quick-zero-threshold rho-tail-exponent rho-tail-zero-proof \
  rho-subnormal-refinement rho-midpoint-probability \
  greek-finite-result cancelled-greek-coordinate
opam exec --switch=morphiq-risk-ml -- dune exec bench/rho_midpoint.exe
```

Optional regeneration uses the pinned reference environment:
`python scripts/rho_midpoint_reference.py --output /tmp/rho-reference.json.gz`.
Ordinary CI only needs Python's standard library. See the
[evidence inventory](evidence/rho-midpoint/SHA256.json) for per-row baseline
and candidate reports, transitions, broad campaign, compatibility, mutation
log, timings and source hashes. #57 owns the combined finding adjudication;
independent reviewer appointment and sign-off remain with #15.
