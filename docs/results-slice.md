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
| Prices: displaced Black | `displaced` (exact sums) | 41,760 | 1–19 ULP per region |
| Implied volatility | `iv` (exact roots and rounding cells) | 8,254 | every outcome class matches; Black-family roots within their derived bound (Bachelier: price-error/vega bound) (Black-family worst 4–7 ULP from the exact root) |
| Greeks | `greeks` (closed form vs mpmath differentiation) | 66,400 | all 65,980 finite rows satisfy analytical certificates; 420 kink refusals; see results-greeks |
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

The mutation catalog (`dune exec scripts/mutation/mutation.exe`) removes each claimed mechanism and requires the test that guards it to fail. The expanded catalog has 33 mechanisms (see the numerical assurance audit below). Three lessons for mutation testing:

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

## Initial numerical assurance audit (through 3f5b0db)

The expanded checks add 24,451 DD references and 2,005 high-precision coordinate/near-maximum IV references, plus analytic tiny-carry, displaced-spread, nonfinite-scorer and rho controls. The DD corpus includes 13,041 nonzero low words. Build, format, the full test suite and all 29 catalogued mutations pass locally on macOS arm64. The intrinsic branch guard is separately probed and survives; its exclusion is provisional.

The unchanged historical model corpus still has the same determinism digest. New cases change a tiny BSM zero-variance call from 0 to 2^-74 and a tiny displaced call from 0 to 2^-574; a subnormal DD quotient changes from 0.5 to RN(1/3). These are improvements outside that old corpus, so an unchanged digest does not mean unchanged numerics.

At that checkpoint the bound and coverage corrections were implemented, while rounded-kernel and non-rho Greek certification remained open. The next section records the broader work. [Error analysis](error-analysis.md#certification-status-and-remaining-proof-obligations) distinguishes derived majorants, conditional compositions and measured regression gates.

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

## Broader price and Greek certification

All 99,056 price rows and 65,980 finite Greek rows now pass independent analytical certificates. The component fixture has 48,203 rows, including 22,425 nonzero low words; 2,506 extra-bit Greek rows additionally test cancellation. All nine fixture manifests pass. Exact-rational proof checks, build, formatting, the full test suite and all 33 catalogued mutations pass locally. The intrinsic-guard probe survives with replay-identity checks disabled, so its exclusion remains provisional.

The analysis exposed three implementation issues in `Split`: the Gaussian cutoff ignored a large prefactor, extreme root/quotient inputs needed normalization, and the quotient correction needed Fast2Sum renormalization before downstream DD operations. These are served-value changes, not just tighter tests.

Relative to 3f5b0db, correcting the prefactor cutoff changes 24 recorded entries across six Bachelier contracts (price, IV, theta and rho). Their previously zero tail prices become positive and agree with independent high precision within 1–6 ULP. For the six calls, S=10^150, K=S·Elementary.exp(m), σ=0.3S, with (m,T)=(0.5,1/365) or (3,2), and r in {−0.01,0.03,0.05}. Correcting quotient nonoverlap then changes a further 4,936 entries: 4,934 by at most 6 ULP, and two IV entries by 22 and 51 ULP. The latter are sensitive to quote quantization, including an unchanged subnormal quote; both pass the conditioned inverse bounds. The digest is now `f402d24368b0028ab140dcecbed0b767dbdcf8456c978829a0187353f4d8c44a`.

Fresh runs against an isolated 3f5b0db archive give the following before/after price maxima. In particular, the older prose claiming a 15-ULP displaced maximum was stale; the actual baseline already measures 19.

| Corpus | Region | Before ULP | After ULP |
| --- | --- | ---: | ---: |
| European Black | deep ITM | 2 | 2 |
| European Black | extreme scale | 18 | 18 |
| European Black | ITM | 8 | 8 |
| European Black | near ATM, tiny variance | 6 | 5 |
| European Black | OTM | 22 | 22 |
| European Black | zero variance | 1 | 1 |
| Bachelier | deep ITM / ITM / near ATM / OTM / zero variance | 2 / 3 / 2 / 5 / 0 | 2 / 3 / 2 / 5 / 0 |
| Displaced | deep ITM / ITM / near ATM / OTM / zero variance | 2 / 5 / 6 / 19 / 1 | 2 / 5 / 6 / 19 / 1 |

The new price/Greek certificate does not inherit historical measured budgets. IV and random round-trip scorers still use their historical conditional kernel premises; they have not automatically become unconditional guarantees. Nor is the test evaluator a formal proof over every finite admitted API input.

### Performance versus 3f5b0db

Sequential runs on the same Apple M1 Pro and OCaml 5.3.0+flambda, using the same default dune profile for both revisions, 20,000 contracts per regime and median of seven runs after warm-up. These are single-session measurements; small differences should not be interpreted as established speedups or regressions. The comparison uses an isolated archive of 3f5b0db and the changed working tree.

| Model | Regime | Quantity | Before ns/op | After ns/op | Change |
| --- | --- | --- | ---: | ---: | ---: |
| BSM | near the money | admit | 1233 | 1211 | -1.8% |
| BSM | near the money | price | 1167 | 1138 | -2.5% |
| BSM | near the money | implied volatility | 3171 | 3114 | -1.8% |
| BSM | near the money | all ten Greeks | 11103 | 10949 | -1.4% |
| Bachelier | near the money | price | 451 | 454 | +0.7% |
| Bachelier | near the money | implied volatility | 3475 | 3528 | +1.5% |
| Bachelier | near the money | all ten Greeks | 6879 | 6838 | -0.6% |
| BSM | OTM tail | admit | 1229 | 1210 | -1.5% |
| BSM | OTM tail | price | 191 | 191 | +0.0% |
| BSM | OTM tail | implied volatility | 3095 | 3084 | -0.4% |
| BSM | OTM tail | all ten Greeks | 14926 | 14651 | -1.8% |
| Bachelier | OTM tail | price | 103 | 105 | +1.9% |
| Bachelier | OTM tail | implied volatility | 6374 | 6439 | +1.0% |
| Bachelier | OTM tail | all ten Greeks | 9202 | 9104 | -1.1% |
| BSM | in the money | admit | 1219 | 1227 | +0.7% |
| BSM | in the money | price | 1749 | 1768 | +1.1% |
| BSM | in the money | implied volatility | 3169 | 3249 | +2.5% |
| BSM | in the money | all ten Greeks | 19467 | 19695 | +1.2% |
| Bachelier | in the money | price | 738 | 743 | +0.7% |
| Bachelier | in the money | implied volatility | 5793 | 6002 | +3.6% |
| Bachelier | in the money | all ten Greeks | 12205 | 12405 | +1.6% |
