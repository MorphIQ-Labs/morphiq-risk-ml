# Slice 1: findings

Status as of 2026-10-02. The exact European family (BSM, Black-76, displaced Black and Bachelier) has prices, implied volatility and ten analytic Greeks. All are scored against FerroRisk's independent references, and every row with an expectation passes.

## Exit criteria (SLICE.md)

### 1. Accuracy

Measured against this project's own oracles (docs/oracles.md): mpmath, refined to agreement between precisions, committed and hash-checked. FerroRisk's references are an optional cross-check (`scripts/ferro_crosscheck.sh`), and every row of them also passes.

| Layer | Oracle | Rows | Worst error |
| --- | --- | ---: | --- |
| Elementary functions | `elementary` | 111,470 | ≤ 1 ULP (exp, expm1, log, log1p) |
| Normal distribution | `normal` | 82,000 | ≤ 4 ULP, tails included |
| Prices: BSM, Black-76, Bachelier | `european` (grid, carry-cancelled forwards, random) | 57,296 | 1–22 ULP per region; zero variance 1; Bachelier ≤ 5 |
| Prices: displaced Black | `displaced` (exact sums) | 41,760 | 1–15 ULP per region |
| Implied volatility | `iv` (exact roots and rounding cells) | 8,254 | every outcome class matches; Black-family roots within their derived bound (Bachelier: price-error/vega bound) (Black-family worst 4–7 ULP from the exact root) |
| Greeks | `greeks` (closed form vs mpmath differentiation) | 66,400 | ≤ 7 ULP for every Greek; underflow and kink classes exact |
| Properties | `test/properties.ml` (random, fixed seed) | 22,000 | bounds, parity, monotonicity, Greek signs, exact homogeneity, translation, IV composes forward and inverse error on identifiable inputs, finite differences |
| Cross-quantity consistency | `test/consistency.ml` | 128 | displaced = Black-76 bit for bit; IV inverts the served price; Greeks match finite differences |

### 2. Iteration speed

Measured on an Apple M1 Pro with OCaml 5.3.0 + flambda `-O3`. The library is about 2,100 lines and the tests about 700.

| Step | Wall time |
| --- | --- |
| Clean build | 0.71–0.76 s |
| Incremental rebuild after editing `normal.ml` (at the root of the dependency graph) | 0.13 s |
| Incremental rebuild after editing `black.ml` | 0.22–0.24 s |
| Full test suite: every oracle, the consistency, property and compile-failure tests | 0.54–0.55 s, with the 41,760-row displaced oracle and double-double intrinsics |
| One mutant: rebuild plus the full suite | 0.73 s |

The mutation catalog (`dune exec scripts/mutation/mutation.exe`) removes each claimed mechanism and requires the test that guards it to fail. The expanded catalog has 28 mechanisms (see the numerical assurance audit below). Three lessons for mutation testing:

- **Equivalent mutants are common.** A last-digit change to a 17-digit literal often parses to the same double, and a mutant that only breaks compilation, such as an unused variable under warnings-as-errors, is not a kill.
- **Budgets come from the error analysis, not from the mutants.** Tightening a measured budget until a mutant dies proves nothing. The scorers check derived bounds (docs/error-analysis.md §1, §5.1, §6), and a survivor can also expose a corpus or scoring-resolution gap.
- **Exclusions are provisional.** The direct coordinate oracle now kills the quotient-remainder mutant. The intrinsic branch-rule probe still survives the price corpus; that is not a proof that no test can distinguish it.

### 3. Types

| Hypothesis | Status | Evidence |
| --- | --- | --- |
| Admission is a type | Shown | Each model application has its own abstract `admitted`. A forged one is rejected, and so is a BSM contract given to Black-76. |
| Volatility coordinate in the type | Shown | `Vol.lognormal Vol.t` and `Vol.normal Vol.t` do not unify, and the same holds for IV outcomes and per-volatility Greeks. |
| Units in the type | Shown | A daily theta is not an annual rate. A Black vega and a Bachelier vega do not net. |
| Exhaustive outcome variants | Shown | `Iv.t` covers FerroRisk's #448 classes. `Greeks.value` puts a payoff kink in the one Greek it affects. |
| One kernel per family | Shown | BSM, Black-76 and displaced Black are `Black.Make` over three ~10-line carries. |
| Exercise style unrepresentable | Shown | A European slice has no exercise-style input. |

All six compile-failure tests pin the compiler's diagnostic, so a change in why something is rejected is visible.

## Where FerroRisk's references disagree with each other

- **Displaced Black shift.** #440 uses binary64-shifted coordinates; the IV and Greek references use exact sums. This project defines displaced Black on the exact sums, owns an oracle for that definition, and labels #440's displaced rows `black76_shifted` (docs/model-contracts.md). It's being taken up in FerroRisk separately.
- **Oracle versions.** The IV reference at the `!551` head predates #448's rounded zero-volatility bound. Scoring needs the #448 stack tip.

## Not attempted in this slice

The following were out of scope (see SLICE.md):
- American models, Heston, Merton, local vol, surfaces, risk, SIMD and batch APIs.
- Performance against Rust, which was explicitly not measured.

## Numerical assurance audit

The expanded checks add 24,451 DD references and 2,005 high-precision coordinate/near-maximum IV references, plus analytic tiny-carry, displaced-spread, nonfinite-scorer and rho controls. The DD corpus includes 13,041 nonzero low words. Build, format, the full test suite and all 28 catalogued mutations pass locally on macOS arm64. The intrinsic branch guard is separately probed and survives; its exclusion is provisional.

The unchanged historical model corpus still has the same determinism digest. New cases change a tiny BSM zero-variance call from 0 to 2^-74 and a tiny displaced call from 0 to 2^-574; a subnormal DD quotient changes from 0.5 to RN(1/3). These are improvements outside that old corpus, so an unchanged digest does not mean unchanged numerics.

The bound and coverage corrections are implemented; uniform certification of the rounded kernels and non-rho Greeks is not complete. [Error analysis](error-analysis.md#certification-status-and-remaining-proof-obligations) distinguishes derived majorants, conditional compositions and measured regression gates.

### Performance versus 15b5f7a

Same Apple M1 Pro, OCaml 5.3.0+flambda release build, fixed 20,000-contract corpus, median of seven runs after warm-up. Baseline was an isolated archive of 15b5f7a; the changed build ran separately. Extreme operands are normalized before DD division/square root. Ordinary operands retain the exponent range they already have, avoiding unnecessary scaling. These are single-session measurements, not statistically established speedups.

| Model | Regime | Quantity | Before ns/op | After ns/op | Change |
| --- | --- | --- | ---: | ---: | ---: |
| BSM | near the money | admit | 971 | 965 | -0.6% |
| BSM | near the money | price | 941 | 928 | -1.4% |
| BSM | near the money | implied volatility | 2657 | 2634 | -0.9% |
| BSM | near the money | all ten Greeks | 8735 | 8702 | -0.4% |
| Bachelier | near the money | price | 384 | 382 | -0.5% |
| Bachelier | near the money | implied volatility | 3273 | 3221 | -1.6% |
| Bachelier | near the money | all ten Greeks | 5494 | 5473 | -0.4% |
| BSM | OTM tail | admit | 971 | 969 | -0.2% |
| BSM | OTM tail | price | 178 | 181 | +1.7% |
| BSM | OTM tail | implied volatility | 2667 | 2654 | -0.5% |
| BSM | OTM tail | all ten Greeks | 11789 | 11803 | +0.1% |
| Bachelier | OTM tail | price | 95 | 94 | -1.1% |
| Bachelier | OTM tail | implied volatility | 6103 | 6005 | -1.6% |
| Bachelier | OTM tail | all ten Greeks | 7253 | 7293 | +0.6% |
| BSM | in the money | admit | 983 | 965 | -1.8% |
| BSM | in the money | price | 1423 | 1407 | -1.1% |
| BSM | in the money | implied volatility | 2778 | 2752 | -0.9% |
| BSM | in the money | all ten Greeks | 15403 | 15310 | -0.6% |
| Bachelier | in the money | price | 629 | 591 | -6.0% |
| Bachelier | in the money | implied volatility | 5577 | 5478 | -1.8% |
| Bachelier | in the money | all ten Greeks | 9680 | 9689 | +0.1% |
