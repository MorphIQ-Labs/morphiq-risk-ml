# Numerical boundary campaign v1 (#54)

The bounded campaign found **two fast-API quality discrepancies and no contract
violations** on the exercised inputs. Both strict runs exit 1; this is not a
clean accuracy campaign. The ordinary CI contract gate passes while reporting
the findings. Runtime arithmetic and existing accuracy allowances are unchanged.

## Design and provenance

The [protocol](numerical-campaign-protocol.md) was committed in `d25f8ba` before
scoring. The final generator adds explicit adjacent Gaussian/kernel branch
thresholds and IV representability cases to the initial grid without removing
any original cases. Transcendental threshold anchors are frozen binary64 words,
so host libm differences cannot change membership. Generator version 1 and seed
540055 produce 2,511 smoke and 7,095 full requests; the complete matrix, original
words, reference outcomes and nine transitive source hashes are retained.

References use exact rational identities or outward Arb enclosures, including
formal price-series differentiation for Greeks and independently resolved
midpoint signs for IV. The optional generation environment was Python 3.14.8,
mpmath 1.3.0, python-flint 0.9.0 and FLINT 3.6.0. Precision is bounded at
256/512/1024/2048/4096 bits, workers at 64 requests and 60 seconds, runtime batches
at 180 seconds, and membership at 50,000 requests. Repeated precision agreement
alone does not certify a result. Synthetic exact IV ties and arbitrary-word
`Enclosure.of_words` checks exercise their owners, not financial-model coverage
or normalized-DD input admission.

Retained runtime reports name source commit `387df13`, the runner SHA-256 and
scorer SHA-256. They were executed on macOS arm64 (Apple M1 Pro), OCaml 5.3.0
Flambda, Dune 3.24.2. These are correctness observations, not benchmarks.

## Outcomes

| Outcome | Smoke | Full |
| --- | ---: | ---: |
| Successful independent value checks | 1,885 | 6,198 |
| Supported classification checks | 436 | 438 |
| Reference uncertainty | 54 | 166 |
| Fast quality excursions | 2 | 2 |
| Explicit numerical availability failures | 120 | 274 |
| Nonfinite float-returning fast prices | 14 | 17 |
| **Total requests** | **2,511** | **7,095** |
| Contract violations | 0 | 0 |

The categories partition requests. Reports further separate region, model,
interface and quantity, and retain each actual status and output word. Only
value/classification checks count as successes. Reference uncertainty includes
an interval overlapping a production certificate without proving containment,
and unresolved fast rounding cells. Two sparse-maximum IV references cannot
resolve a root proposal within the bounded procedure; these remain explicit.
Neither a numerical refusal nor a nonfinite fast price is an accuracy success.
The fixed central Greek-zero neighborhood additionally requires availability;
no such regression occurred. No whole-domain availability rate is inferred.

The findings are:

- [#76](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/76), smoke `n01910`:
  zero-variance BSM call price under severe carry cancellation returns word
  `35f5555555555554`, versus independently rounded `3615555555555556`
  (9,007,199,254,740,994 ULP). Absolute values are around 10^-48. The corresponding
  production certificate contains the reference. The issue retains exact inputs
  and independent Arb and `expm1` formulations; no economic-materiality claim is
  made from the ULP count.
- [#77](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/77), smoke `n00026`:
  ATM BSM call rho at the smallest positive maturity returns the smallest
  subnormal instead of zero. Analytically, `0 < T Phi(-sigma sqrt(T)/2) < T/2`,
  so the exact value rounds to zero. This is one ULP and **within** the existing
  16-ULP rho allowance; the additional rounded-zero diagnostic identifies it.

These require separately reviewed numerical methods and regressions under
[#57](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/57). The campaign does
not encode faulty words as expected outputs or widen tolerances. New fast-price
diagnostics use existing family maxima (32 Black / 8 Bachelier); original
stronger regional and derived gates remain in force.

## Reproduction and retained evidence

The smoke reference and its SHA/row-count sidecar live in
[`oracle/challenges/`](../oracle/challenges/). The full reference, both compressed
per-request reports, and their hashes live in
[`docs/evidence/numerical-campaign/`](evidence/numerical-campaign/). These are
numerical reproducibility evidence, not generated build products. Reports join
to reference rows by stable ID; those rows hold the exact original input words.

```sh
opam exec --switch=morphiq-risk-ml -- dune build test/numerical_boundary_runner.exe
python3 scripts/numerical_campaign.py check \
  --reference oracle/challenges/numerical-smoke-v1.json.gz \
  --runner _build/default/test/numerical_boundary_runner.exe \
  --output /tmp/numerical-smoke.json
python3 scripts/numerical_campaign.py check \
  --reference docs/evidence/numerical-campaign/numerical-full-v1.json.gz \
  --runner _build/default/test/numerical_boundary_runner.exe \
  --output /tmp/numerical-full.json
```

At the recorded source both commands exit 1 for the two retained quality
findings. Add `--contracts-only` to reproduce ordinary CI's explicit narrower
gate; this reports the same findings and exits 0 when contracts hold. Ordinary
CI also runs eight scorer/input controls, with standard-library Python only.
It does not install the optional reference-generation dependencies.

To regenerate in an environment with the pinned optional dependencies:

```sh
python scripts/numerical_campaign.py generate --lane smoke --output /tmp/smoke.json.gz
python scripts/numerical_campaign.py generate --lane full --output /tmp/full.json.gz
```

Elapsed-time metadata can change archive hashes between regenerations. Input
membership and transitive source hashes must still agree. Changed reference
sources require regeneration, not hand-edited provenance.

Local `dune build @install @fmt @runtest -j 2` passed, including the smoke gate,
scorer controls and existing reference, property, type and planner checks.
The determinism digest remains
`e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593`.
No runtime algorithm changed, and no performance claim or new mutation kill is
made. The seven-mutant CI policy is unchanged. This finite campaign supplies
experimental engineering evidence, not independent human review, a universal
proof, institutional approval or a release/tag.
