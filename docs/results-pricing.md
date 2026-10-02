# Results: European pricing

Measured on 2026-10-02 with OCaml 5.3.0 + flambda (`-O3`).

## Accuracy

Prices are scored against FerroRisk's #440 exact-input oracle: 50,094 contracts, mpmath values refined until successive precisions agree to 1e-45 (`oracle/convert_440.py`). Regions follow FerroRisk's `score_european_formulations.region()`. Every row passes.

Worst error per region, ours vs FerroRisk's published SPEC §7.1 (#440) contract:

| Region | Rows | Worst ULP | FerroRisk worst ULP | Worst ε·scale | FerroRisk worst ε·scale |
| --- | ---: | ---: | ---: | ---: | ---: |
| Black family, deep ITM | 6,133 | 3 | 175 | 1.65 | 28.4 |
| Black family, ITM | 3,414 | 7 | 37 | 2.08 | 17.3 |
| Black family, near ATM, tiny variance | 4,016 | 4 | 552 | 0.0099 | 0.10 |
| Black family, OTM | 9,897 | 16 | 3,504 | 2.06 | 17.9 |
| Black family, strike outside [1e-100, 1e100] | 19,320 | 10 | 7.3e6 | 1.79 | 613 |
| Black family, zero variance | 4,278 | 7 | 4.3e15 | 1.27 | 567 |
| Bachelier, all regions | 3,036 | 3 | 329 | 5.07 | 4.3 |

The enforced ULP budgets are the measured worst with about 2× headroom, so a regression to FerroRisk-level error fails.

Two Bachelier rows exceed FerroRisk's ε·scale worst: s = 1000, a price of 359, and 2 ULP. The scorer accepts any value within 4 ULP of exact, because ε·scale exists to expose cancellation in values far below the scale, and a near-exact value has none.

## What made the difference

Each technique below is derived from first principles and guarded by a mutant that fails rows when it is removed:

| Technique | What it fixes | Mutant |
| --- | --- | --- |
| Log-moneyness `x = ln(S/K) + (r−q)T` as a double-double: an atanh-series log, exact carry products, and the quotient remainder of S/K | Contracts at the money by construction, e.g. `ln(S/K) = 4.5` cancelled by `(r−q)T = −4.5`. FerroRisk's 4.3e15-ULP zero-variance row is one of these. | 767 rows fail |
| `√T` and `s = σ√T` as double-doubles, carried into `h = x/s` | A relative ε in s becomes ε·h² in `exp(−h²/2)`: 413 ULP at h = 25 | 42 rows fail |
| `x`'s low part carried into the Gaussian exponent | The deep-OTM tail | (covered by the first mutant) |
| Forward intrinsic as `K e^(−rT)·expm1(x)` near the money | Cancellation between the two discounted legs | 3,886 rows fail |
| Exact power-of-two rescaling of (S, K), applied back once inside the exponential (Cody-Waite `2^−n e^(−r)`) | Strikes at 1e±300, and prices that underflow before rescaling | 62 rows fail |
| Bachelier `d = Δ/s` with its remainder | The Bachelier OTM tail | 41 rows fail |

The normalised Black kernel follows Jäckel's 2024 reference: three regions with η = −13 and τ = 2ε^(1/16). The asymptotic-expansion coefficients are generated mechanically from his C macros rather than transcribed by hand. A direct mpmath probe of `b(x, s)` measures about 1 ULP across Region I.

## Types

| Hypothesis | Status | Evidence |
| --- | --- | --- |
| Admission is a type | Shown | Each `Black.Make` application has its own abstract `admitted`. A forged one is rejected (`test/types/forge_admitted`), and so is a BSM contract passed to Black-76 (`cross_model`). |
| Volatility coordinate is a type | Shown | `Vol.lognormal Vol.t` and `Vol.normal Vol.t` do not unify (`mix_coordinates`). A raw float is not a volatility (`forge_volatility`). |
| One kernel per family | Shown | BSM, Black-76 and displaced Black are `Black.Make` over three `CARRY` modules of about ten lines each. |
| Exercise style unrepresentable in a European slice | Shown | There is no exercise-style input. The `UnsupportedModelExerciseCombination` refusal of the Rust engine has no counterpart. |

The compiler's diagnostics are pinned in `test/types/*.expected`.
