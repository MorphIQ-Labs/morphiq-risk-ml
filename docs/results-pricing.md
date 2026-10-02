# Results: European pricing

Measured on 2026-10-02 with OCaml 5.3.0 + flambda (`-O3`).

## Accuracy

Prices are scored against FerroRisk's #440 exact-input oracle: 50,094 contracts, mpmath values refined until successive precisions agree to 1e-45 (`oracle/convert_440.py`). Regions follow FerroRisk's `score_european_formulations.region()`. Every row passes.

Worst error per region, ours vs FerroRisk's published SPEC §7.1 (#440) contract:

| Region | Rows | Worst ULP | FerroRisk worst ULP | Worst ε·scale | FerroRisk worst ε·scale |
| --- | ---: | ---: | ---: | ---: | ---: |
| Black family, deep ITM | 6,133 | 2 | 175 | 1.03 | 28.4 |
| Black family, ITM | 3,414 | 7 | 37 | 2.08 | 17.3 |
| Black family, near ATM, tiny variance | 4,016 | 4 | 552 | 0.0099 | 0.10 |
| Black family, OTM | 9,897 | 16 | 3,504 | 2.06 | 17.9 |
| Black family, strike outside [1e-100, 1e100] | 19,320 | 10 | 7.3e6 | 1.79 | 613 |
| Black family, zero variance | 4,278 | 1 | 4.3e15 | 0.54 | 567 |
| Bachelier, all regions | 3,036 | 3 | 329 | 5.07 | 4.3 |

The enforced ULP budgets are the measured worst with about 2× headroom, so a regression to FerroRisk-level error fails.

Two Bachelier rows exceed FerroRisk's ε·scale worst: s = 1000, a price of 359, and 2 ULP. The scorer accepts any value within 4 ULP of exact, because ε·scale exists to expose cancellation in values far below the scale, and a near-exact value has none.

In this table "Black family" means BSM, Black-76 and #440's displaced rows, which are scored as Black-76 on binary64-shifted coordinates (`black76_shifted`), because that is what #440 measured.

## Displaced Black on its own definition

`oracle/gen_displaced.py` is this project's own exact-sum oracle: 41,760 contracts, 63% of which have an unrepresentable F + d or K + d. It covers shifts from 5bp to 100, forwards near the −d floor, maturities from a day to 30 years and volatilities from 0 to 3. Every row passes:

| Region | Rows | Worst ULP |
| --- | ---: | ---: |
| deep ITM | 11,136 | 2 |
| ITM | 4,852 | 5 |
| near ATM, tiny variance | 2,436 | 5 |
| OTM | 18,116 | 15 |
| zero variance | 5,220 | 1 |

A rounded-shift implementation fails 2,450 of these contracts: up to 1.6e9 ULP near the money, and zero-variance values flipped outright.

## The zero-variance price and the inverse share one boundary

The zero-variance price and the in-the-money intrinsic are computed from the double-double legs the inverse uses to classify quotes, then rounded once. Zero-variance prices are now 0–1 ULP (Bachelier 0). More importantly, a served zero-variance price always has an inverse: either σ = 0 or an exact positive root that reprices to it.

The binary64 intrinsic it replaced could land below the exact intrinsic. The inverse then correctly reported `Below_intrinsic` for the library's own price. `test/consistency.ml` found that; a mutant that restores it fails with "no root for its own price".

## A zero-variance cancellation

The #440 grid's worst zero-variance case is a put with S ≈ 9.8e-151, K = 1e-150 and (r − q)T = 0.02. Its value (3.2e-168) is 3e-18 of either leg. Checked independently with mpmath at 400 digits, FerroRisk's reference is right to 1.8e-17. We were at 1.2e-15, which is 8 ULP.

The cause was the log-moneyness's quotient remainder `(S − qK)/(qK)`. It was rounded to binary64, costing about 1e-33 in x, and that error survives a cancellation to 1e-18. With the remainder and its second-order term carried in double-double, the case is now 1 ULP. A mutant that rounds the remainder fails that row.

## Known limit: Region III's erfcx difference

The worst extreme-scale case (10 ULP at h = −4.6, s = 1) is in the normalised Black function's Region III. There, `b = e^(−(h²+t²)/2)·(erfcx(q1) − erfcx(q2))/2` and the two erfcx values cancel by about 6×. This is the method's own accuracy, the same as Jäckel's reference, and FerroRisk's value checks out to 4.7e-17 against mpmath. It stays within budget (32) and is analysed in [error-analysis.md](error-analysis.md).

## What made the difference

Each technique below is derived from first principles. Where a mutant can decide it, the mutation catalog (`scripts/mutation/`) removes it and requires the price oracle to fail. Where it cannot, the reason is in docs/error-analysis.md §5.1.

| Technique | What it fixes | Mutant |
| --- | --- | --- |
| Log-moneyness `x = ln(S/K) + (r−q)T` as a double-double: an atanh-series log, exact carry products, and the quotient remainder of S/K | Contracts at the money by construction, e.g. `ln(S/K) = 4.5` cancelled by `(r−q)T = −4.5`. FerroRisk's 4.3e15-ULP zero-variance row is one of these. | the remainder is below the certified bound's resolution (§5.1) |
| `√T` and `s = σ√T` as double-doubles, carried into `h = x/s` | A relative ε in s becomes ε·h² in `exp(−h²/2)`: 413 ULP at h = 25 | `root-time-low` |
| `x`'s low part carried into the Gaussian exponent | The deep-OTM tail | (covered by the first mutant) |
| Forward intrinsic as `K e^(−rT)·expm1(x)` near the money | Cancellation between the two discounted legs | `intrinsic-expm1` |
| Exact power-of-two rescaling of (S, K), applied back once inside the exponential (Cody-Waite `2^−n e^(−r)`) | Strikes at 1e±300, and prices that underflow before rescaling | `floor-exponent`, `subnormal-rounding` |
| Bachelier `d = Δ/s` with its remainder | The Bachelier OTM tail | `bachelier-distance` |

The normalised Black kernel follows Jäckel's 2024 reference: three regions with η = −13 and τ = 2ε^(1/16). The asymptotic-expansion coefficients are generated mechanically from his C macros rather than transcribed by hand. A direct mpmath probe of `b(x, s)` measures about 1 ULP across Region I.

## Types

| Hypothesis | Status | Evidence |
| --- | --- | --- |
| Admission is a type | Shown | Each `Black.Make` application has its own abstract `admitted`. A forged one is rejected (`test/types/forge_admitted`), and so is a BSM contract passed to Black-76 (`cross_model`). |
| Volatility coordinate is a type | Shown | `Vol.lognormal Vol.t` and `Vol.normal Vol.t` do not unify (`mix_coordinates`). A raw float is not a volatility (`forge_volatility`). |
| One kernel per family | Shown | BSM, Black-76 and displaced Black are `Black.Make` over three `CARRY` modules of about ten lines each. |
| Exercise style unrepresentable in a European slice | Shown | There is no exercise-style input. The `UnsupportedModelExerciseCombination` refusal of the Rust engine has no counterpart. |

The compiler's diagnostics are pinned in `test/types/*.expected`.
