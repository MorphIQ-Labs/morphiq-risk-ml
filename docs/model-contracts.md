# Model contracts

These definitions are what the library computes. Every accuracy claim is measured against them, and an oracle that measures anything else is labelled for what it measures.

## Common to every model

- **Inputs are exact.** Every binary64 input (spot or forward, strike, shift, time, rate, yield, volatility, quote) means exactly the real number it represents. No intermediate rounding is part of any model's definition. A computation that rounds where the definition does not is an error to be measured, not a convention.
- **One function per model.** The price, its implied volatility and its Greeks all describe the same real function:
  - the implied volatility inverts the served price;
  - each Greek is a derivative of it;
  - the zero-variance price and the inverse's zero-variance boundary are one value.

  `test/consistency.ml` checks these properties across quantities.
- **Served values are rounded once.** Each served value is the binary64 rounding of the defined real value, up to the measured error budgets in the results docs.

## Black-76 family

| Model | Definition |
| --- | --- |
| BSM | `θ(S e^(−qT) Φ(θd1) − K e^(−rT) Φ(θd2))`, with `d1,2 = (ln(S/K) + (r − q)T)/(σ√T) ± σ√T/2` |
| Black-76 | BSM with the forward F as S and q = r |
| Displaced Black | Black-76 on the real numbers F + d and K + d |

**Displaced Black.**
- **Exact sums.** The shift is applied as an exact sum. The library carries F + d and K + d as unevaluated double-doubles through the log-moneyness, the discounted legs, the inverse's classification and the Greeks.
- **Admission.** Live contracts need F + d > 0 and K + d > 0. The sign of a binary64 sum always matches the sign of the exact sum, so admission depends only on the definition.
- **Expiry.** The payoff is `max(θ(F − K), 0)` on the unshifted inputs, which equals the shifted form exactly.
- **Agreement with Black-76.** Where F + d and K + d are representable, displaced Black's price, IV and Greeks are bit-for-bit those of Black-76 on the sums.

**Why not round the sums first.** Rounding F + d and K + d separately prices a different contract. It can move the shifted forward to the other side of the shifted strike: on this project's 41,760-contract displaced oracle, a rounded-shift implementation fails 2,450 contracts. The errors reach 1.6e9 ULP near the money and flip zero-variance values outright, so the problem is not confined to tail ULPs.

## Bachelier

`θ D (F − K) Φ(θd) + D σ√T φ(d)`, with `d = (F − K)/(σ√T)` and `D = e^(−rT)`. The volatility is in price units per √year, and F and K may take any finite sign.

## Implied volatility

- **Exact quotes, representable answers.** A quote denotes its exact binary64 value. `Root sigma` is a representable approximation to its real inverse; it does not promise an unrepresentable exact real root or exact repricing. The rounded intrinsic exception below is explicit.
- **Computational success.** For positive roots, the normalized evaluator either equals its target or brackets it between adjacent floating-point total volatilities. The final conversion to annual volatility adds rounding. This establishes termination of the implemented evaluator, not a universal exact-model error bound. Executed per-input price/vega certificates and the retained quality gates assess exact-root accuracy on the checked corpus; see [the IV analysis](error-analysis.md#6-implied-volatility).
- **Mathematical classes.** Below intrinsic, above maximum, expiry non-identifiability and below-smallest-volatility are distinct from computational failure. A computed zero, NaN or infinity in a positive-root calculation does not establish one of these classes.
- **Failure.** `Non_convergence` means an iteration budget was exhausted; `Numerical_failure` means an evaluation, bracket, normalization or conversion was unresolved. Neither includes a usable root. Callers must handle both variants explicitly. They may not replace failure with a mathematical classification or a last iterate.
- **Rounded bound.** A quote below the exact discounted intrinsic that equals its correctly rounded value is the binary64 rounding of the zero-volatility price, and returns σ = 0 (#448). The DD classification still needs domain/uncertainty enforcement beyond the checked corpus; this remains a production-readiness obligation under #13/#14.

## Greeks

- **Time.** Time Greeks are `−∂/∂T / 365`: per calendar day, as remaining maturity decreases.
- **Volatility.** Volatility Greeks are per unit volatility in the model's own coordinate, and the types keep the coordinates apart.
- **Mixed time/volatility.** Veta keeps both the per-calendar-day tag and the normal/lognormal volatility coordinate. Use `Units.annualise_volatility` to convert its time unit. Raw unit constructors are trusted labels, not value/provenance validation; see [the type audit](type-boundary-audit.md).
- **Rho.** For forward models, rho moves the rate with the forward held fixed: `−T·V`.
- **Kinks.** At a payoff kink (the strike at expiry, or the forward at zero variance), a spot or time derivative does not exist, and that Greek alone returns `Payoff_kink`.
