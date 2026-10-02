# Results: Greeks

Measured on 2026-10-02 with OCaml 5.3.0 + flambda (`-O3`).

## Accuracy

Scored against FerroRisk's Greek derivative reference (`greek_derivative_reference.json`): 61,621 Greek values for the four slice models. Each value comes from mpmath at two precisions and, where both exist, from two independent routes (explicit closed form and differentiated price).

Conventions are FerroRisk's:
- Time Greeks are `−∂/∂T / 365`.
- Vega is per unit volatility.
- Forward models' rho is `−T·V`.
- Displaced Black shifts by the exact sum `F + d`.

| Greek | Black family worst ULP (rows) | Budget | Bachelier worst ULP (rows) | Budget |
| --- | ---: | ---: | ---: | ---: |
| delta | 6 (3,318) | 16 | 4 (1,068) | 8 |
| gamma | 4 (2,586) | 8 | 2 (776) | 4 |
| theta | 4 (2,889) | 8 | 3 (918) | 8 |
| vega | 3 (2,634) | 8 | 2 (792) | 4 |
| rho | 6 (3,344) | 16 | 4 (1,074) | 8 |
| vanna | 4 (2,592) | 8 | 2 (778) | 4 |
| volga | 4 (2,616) | 8 | 3 (716) | 8 |
| charm | 4 (2,889) | 8 | 2 (920) | 8 |
| veta | 4 (2,172) | 8 | 2 (638) | 4 |
| color | 5 (2,154) | 16 | 4 (632) | 8 |

The median error is 0–1 ULP for every Greek. Each budget is twice the measured worst, rounded up to a power of two.

The other reference statuses:

| Status | Entries | Result |
| --- | ---: | --- |
| below_binary64 (exact value underflows) | 16,282 | all within 4 subnormal quanta of 0 |
| above_binary64 (exact value overflows) | 32 | all `infinity` |
| kink (payoff kink at expiry and strike) | 200 | all refused with `Payoff_kink` |
| boundary (one-sided limits FerroRisk makes no claim about) | 9,472 | recorded: 8,768 values, 704 refusals |

Charm cancels at the money: `q·Δ` and `D_q·φ(d1)·∂d1/∂T` agree to about 1/80 of their size, and Bachelier's two terms behave the same way. Binary64 Φ cannot resolve that difference, and the first version measured 205 ULP (Black) and 24 ULP (Bachelier). Where |d| ≤ 6, both brackets are now evaluated in double-double (`Normal_dd`), giving 4 and 2 ULP. The tails keep the Mills-ratio form, which is already relatively accurate.

FerroRisk states no per-region Greek accuracy contract for these models (#449). Its envelope measures a scaled error, not ULP, and describes itself as "not an accuracy contract". No row-level comparison is claimed.

## Method

| Technique | What it fixes | Mutant |
| --- | --- | --- |
| Each Greek is an ordinary part plus `P·exp(−(h²+t²)/2)·2^k`. The prefactor P collects every algebraic factor; the exponential, with its split argument, is applied last with one rounding. | Tail Greeks that lose bits in the subnormals or underflow before rescaling | rounded exponent: 1,431 entries fail |
| Φ enters through the Mills ratio, `AΦ(θd1) = Aφ(d1)·R(−θd1)`, sharing the exponential | Delta, rho and theta in the tails | plain Φ: 150 fail |
| d1 and d2 in double-double | Vanna and volga where `x = s²/2` makes d2 ≈ 1e-17 | float d2: 18 fail |
| Veta's `√T`-scaled bracket `q√T + √T·d1·w − 1/(2√T)` and color's bracket in double-double | Exact zero crossings, and subnormal T where `1/T` overflows | float bracket: 54 fail (Bachelier: 16) |
| `1/T` terms rewritten so `√T` and σ cancel, e.g. `vega/(2T) = Aφ(d1)/(2√T)` | Subnormal T and σ | (covered by the reference's range rows) |
| Charm's bracket `θqΦ(θd1) − φ(d1)·w` (Bachelier: `θrΦ(θd) + φ(d)·d/(2T)`) in double-double, with Φ and φ from `Normal_dd` | The at-the-money cancellation, 205 → 4 ULP | float bracket: 21 entries fail (Bachelier: 3) |
| `Normal_dd`: φ from the double-double exp, and Φ from Marsaglia's series `½ + φ(d)·Σ d^(2k+1)/(2k+1)!!`, whose terms share a sign | A Φ accurate to about 106 bits for \|d\| ≤ 6 (the final `½ − …` for d < 0 loses log₂(1/(2Φ(d))) bits, about 30 at −6) | truncated series: 3 fail; a pinned mpmath test holds Φ to `2^-100/(2Φ(d))` and φ to 2^-100 |
| Theta in double-double where \|d1\|, \|d2\| ≤ 6, legs included: `θ(qAΦ(θd1) − rCΦ(θd2)) − Aφ(d1)σ/(2√T)` (Bachelier: `D(rθΔΦ(θd) + φ(d)(rs − σ/(2√T)))`) | Cancellation between rV and the diffusion term, 17 → 4 ULP | binary64 theta: 23 entries fail (Bachelier: 4) |
| Displaced Black shifts by the exact sum, carried as hi + lo through x and the legs | ~800 ULP in displaced tails | binary64 shift: 619 fail |

## The displaced-Black convention

FerroRisk's references disagree about displaced Black:

- The #440 pricing study prices on binary64-shifted coordinates `fl(F+d)` and `fl(K+d)`. That is FerroRisk's public pricing contract.
- The IV and Greek references shift by the exact sum.

The exact sum is the model's definition, so displaced Black here uses it. The #440 displaced rows are scored as Black-76 on #440's binary64-shifted inputs, which is the model #440 actually measured. FerroRisk itself does not reconcile the two conventions.

## Types

- **Daily time Greeks.** Theta, charm, veta and color are `Units.per_calendar_day Units.time_rate`. Using one where an annual rate is expected is rejected (`test/types/daily_as_annual`).
- **Volatility Greeks carry their coordinate.** Vega, vanna and volga are `'c Units.per_volatility` (or `_squared`) with `'c` the volatility coordinate. Netting a Black vega against a Bachelier vega is rejected (`test/types/mixed_vega`).
- **Payoff kinks.** These are `Error Payoff_kink` in each Greek's own result, so the other nine Greeks of the same contract remain available.
