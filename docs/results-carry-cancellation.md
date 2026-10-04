# Severe carry-cancellation price qualification (#76)

The original BSM zero-volatility witness now returns the independently proved
nearest-even word `3615555555555556`, instead of `35f5555555555554`. Its error
falls from 9,007,199,254,740,994 ULP to zero. The mathematical model and original
binary64 inputs are unchanged. See the [method](carry-cancellation-design.md)
for the cancellation mechanism, stable identity, finite work and rounding proof.

This is a **major numerical/outcome change** under the stability policy (minor
while 0.y.z): severe-cancellation prices can change materially in ULP terms or
become NaN when refinement cannot resolve a cell. Absolute economic materiality
is not inferred from a ULP count. The original witness is about 3.65e-48.

## Independent original-input campaign

Generator version 1 constructs 2,748 requests before evaluating the library:
three neighboring spots, three neighboring rates, three exact dyadic maturities,
five currency exponents (-900/-400/0/400/900), swapped coordinates/carry signs,
both sides, and volatility 0/minimum-subnormal/2^-200/2^-160/0.2. Common-discount
and tied Black-76/displaced controls check related carry and shift mechanisms.
Every original word and outward reference interval is retained in
[`carry-cancellation-v1.json.gz`](../oracle/challenges/carry-cancellation-v1.json.gz).

References use the original-input Arb formulas from #54, independently of the
runtime enclosure implementation. Python 3.14.8, mpmath 1.3.0, python-flint 0.9.0
and FLINT 3.6.0, bounded precision 256/512/1024/2048/4096 bits, and transitive source
hashes accompany the fixture. Precision agreement alone is not acceptance.
The SHA/row-count sidecar, complete membership and source closure are verified
before scoring. Runtime batches have a 120-second limit and require every ID.

| Outcome | Baseline | Candidate |
| --- | ---: | ---: |
| Independently checked values within the diagnostic allowance | 2,563 | 2,626 |
| Quality excursions | 185 | 0 |
| Explicit unavailable fast prices (NaN) | 0 | 122 |
| Unresolved references / wrong statuses | 0 | 0 |
| Total | 2,748 | 2,748 |

Of the 185 inaccurate baseline results, **84 become checked values and 101 become
explicit failures**. Another **21 previously within-budget results become
failures** because the finite enclosure does not resolve their rounding cell.
All zero-volatility requests in this corpus remain available; the 122 failures
have positive volatility. Failed requests are not counted as accuracy successes.
The diagnostic uses the existing 32-ULP Black-family maximum from #54; existing
stronger regional and derived gates remain unchanged. Candidate finite values
are at most 3 ULP from their independent references. The exact discovered case
requires availability and zero ULP, and every zero-volatility corpus row requires
availability. Tests do not freeze the current 122 NaNs as expected results;
future work may improve availability without relaxing accuracy.

The broad 7,095-request campaign now has 6,199 value checks, 438 class checks,
166 reference-uncertain cases, 274 availability failures, 17 nonfinite fast prices
and **one** quality finding: [#77](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/77).
It has zero contract violations. Strict scoring still exits 1 for #77;
a green contract-only gate is not a clean full accuracy campaign.

## Compatibility and executable checks

The runtime baseline is `b862fe2033af0a7c4a42128d77f66d29c7707b72`; the qualified
runtime implementation is `fecf7c9`. Later commits document its contract and
clarify scorer accounting/provenance without changing numerical arithmetic.
The retained per-row reports identify runner and scorer sources separately and
hash their binaries/reference snapshot.

Before/after compatibility traces are byte-identical for all **99,088 ordinary
price rows** (57,320 European plus 41,768 displaced) and **66,400 Greek rows**.
Existing regional worst errors and outcome classes are therefore unchanged on
those corpora. This finite observation does not cover every admitted input.
The public determinism digest also remains
`e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593`.

Local build, formatting and the complete ordinary suite passed. Seven affected
mutants each had a clean baseline, compiled and failed their designated numerical
guard: `cancelled-price-refinement`, `cancelled-price-cell`,
`intrinsic-nonfinite-price`, `zero-variance-veta`, `quotient-remainder`,
`intrinsic-tiny-carry` and `intrinsic-expm1`. The two new mutants are optional;
default CI still runs the same seven core mutants. The full catalog now has 68.

## Focused performance cost

The fixed-input, post-admission benchmark ran baseline/candidate/candidate/baseline
on Apple M1 Pro, macOS 27 arm64, OCaml 5.3.0 Flambda and Dune 3.24.2 with `-O3`.
Each process warms up once and measures seven batches: 100,000 calls per ordinary
case and 2,000 per cancellation case. No other task benchmark or test was launched
during these measurements. Host load snapshots, every sample, compiler settings,
harness hash and both binary hashes are retained; this is a local observation,
not a calibrated cross-machine gate.

| Price case | Baseline median (µs) | Candidate median (µs) |
| --- | ---: | ---: |
| Ordinary, sigma=0.2 | 1.502 | 1.502 |
| Ordinary, sigma=0 | 1.271 | 1.274 |
| Severe cancellation, sigma=0 | 0.700 | 54.353 |
| Severe cancellation, sigma=0.2 | 0.920 | 892.633 |

Ordinary median differences are within sample variation. Selected severe cases
pay about 78× / 970× the previous cost in these two samples. Zero variance uses
the tighter `expm1` identity; positive volatility pays for the full original-model
enclosure even when the old approximation happened to be accurate. No assertion
about workload-average overhead follows without measuring how often a workload
triggers refinement. Admission code is unchanged; this harness measures pricing.
Fast Greeks also invoke this price path internally, so selected Greek latency
may increase; Greek performance was not measured in this benchmark.

A cheaper first enclosure or a tighter positive-volatility formula could improve
cost/availability, but must preserve the full rounding-cell test. These limits
remain explicit in #57's disposition; the change does not silently revert to the
old approximation when refinement is inconclusive. It does not certify every
fast Greek, expand Production's contract, or alter the independent public IV
certificate.

## Known Greek sibling: #80

The sibling search found inaccurate finite results in **all ten fast Greeks**
for the original BSM witness with positive volatility `2^-160`. Independent
original-input Arb references resolve each value. For example, delta returns
`3fed14cc3547f8d9` instead of `3fefffffe61da6af`. Baseline and candidate return
identical Greek words for this witness: refining the price does not repair the
DD coordinates used by the analytic sensitivities.

[Bug #80](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/80) enumerates all
ten fields and blocks #57's clean assurance closeout. Its separate change needs
a sensitivity derivation and explicit outcome/availability review; #76 addresses
prices only. The optional `scripts/probe_carry_greeks.py` reproducer and
[`greek-followup.json.gz`](evidence/carry-cancellation/greek-followup.json.gz)
retain original words, independent references, errors and source hashes.
Unchanged historical Greek traces above do not establish correctness here.

## Reproduction and retained artifacts

[`docs/evidence/carry-cancellation/`](evidence/carry-cancellation/) retains full
per-request before/after outcomes, broad campaign results, compatibility hashes,
mutation outcomes and timing samples. The public fixture contains original words
and independently bounded references. These are reproducibility evidence.

```sh
opam exec --switch=morphiq-risk-ml -- dune build @install @fmt @runtest
python3 scripts/check_carry_cancellation.py \
  --reference oracle/challenges/carry-cancellation-v1.json.gz \
  --runner _build/default/test/numerical_boundary_runner.exe \
  --output /tmp/carry-cancellation.json
opam exec --switch=morphiq-risk-ml -- dune exec bench/carry_cancellation.exe
DUNE_JOBS=2 opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- \
  cancelled-price-refinement cancelled-price-cell zero-variance-veta \
  intrinsic-expm1 intrinsic-tiny-carry intrinsic-nonfinite-price quotient-remainder
```

Optional regeneration uses the pinned Python environment above:
`python scripts/carry_cancellation_reference.py --output /tmp/carry-reference.json.gz`.
To record a separately built baseline, supply its known `--runner-source` and
`--record-only`; the report retains failures instead of claiming baseline success.
For paired timings, build the committed benchmark harness against each specified
runtime source in isolated worktrees with identical compiler settings.
No private research access or optional Python numerical packages are needed in
ordinary CI. No release/tag or independent human sign-off is implied.
