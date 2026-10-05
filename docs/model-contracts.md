# Model contracts

These definitions are what the library computes. Every accuracy claim is measured against them, and an oracle that measures anything else is labelled for what it measures.

## Common to every model

- **Inputs are exact.** Every binary64 input (spot or forward, strike, shift, time, rate, yield, volatility, quote) means exactly the real number it represents. No intermediate rounding is part of any model's definition. A computation that rounds where the definition does not is an error to be measured, not a convention.
- **One function per model.** The price, its implied volatility and its Greeks all describe the same real function:
  - implied volatility inverts the exact real price function at the supplied quote;
  - each Greek is a derivative of that real function;
  - the zero-variance price and the inverse's zero-variance boundary are one value.

  `test/consistency.ml` checks these properties across quantities.
- **Numerical outputs.** The target is the nearest-even binary64 value of the defined real quantity. Positive IV roots require a runtime rounding certificate. Fast price/Greek evaluations have implementation error, checked by the documented per-input analytical certificates and historical quality gates; admission alone does not establish a universal error guarantee. See [certification status](error-analysis.md#certification-status-and-remaining-proof-obligations).

The separate [production adapter](production-boundary-design.md) serves prices and smooth Greeks with enforced, caller-requested absolute error bounds in their units. It uses these same exact models and preserves the certified IV contract. Its explicit boundary exclusions and computational failures are capability outcomes, not new financial definitions.

## Black-76 family

| Model | Definition |
| --- | --- |
| BSM | `θ(S e^(−qT) Φ(θd1) − K e^(−rT) Φ(θd2))`, with `d1,2 = (ln(S/K) + (r − q)T)/(σ√T) ± σ√T/2` |
| Black-76 | BSM with the forward F as S and q = r |
| Displaced Black | Black-76 on the real numbers F + d and K + d |

**Displaced Black.**
- **Exact sums.** The shift is applied as an exact sum. The library retains both words of F + d and K + d through the log-moneyness, discounted legs and Greeks, and retains the original unscaled words for runtime IV enclosures.
- **Admission.** Live contracts need F + d > 0 and K + d > 0. Admission also requires their rounded high words to be finite. A shifted sum that overflows binary64 is refused even though the mathematical real sum exists; this is a numerical capability restriction.
- **Expiry.** The payoff is `max(θ(F − K), 0)` on the unshifted inputs, which equals the shifted form exactly.
- **Agreement with Black-76.** Where F + d and K + d are representable, displaced Black's price, IV and Greeks are bit-for-bit those of Black-76 on the sums.

**Why not round the sums first.** Rounding F + d and K + d separately prices a different contract. It can move the shifted forward to the other side of the shifted strike: on this project's 41,760-contract displaced oracle, a rounded-shift implementation fails 2,450 contracts. The errors reach 1.6e9 ULP near the money and flip zero-variance values outright, so the problem is not confined to tail ULPs.

## Bachelier

`θ D (F − K) Φ(θd) + D σ√T φ(d)`, with `d = (F − K)/(σ√T)` and `D = e^(−rT)`. The volatility is in price units per √year, and F and K may take any finite sign.

## Implied volatility

- **Exact quotes, representable answers.** A quote denotes its exact binary64 value. A positive `Root sigma` is its real inverse rounded to nearest-even binary64. It does not promise exact repricing. The rounded intrinsic exception below is explicit.
- **Computational success.** Original-input runtime enclosures prove the root's rounding cell or decide the midpoint of a proved adjacent-float bracket. Certification uses annual volatility itself, including conversion uncertainty. Both proposal generation and certification have finite work bounds. A rounded-evaluator equality or a small Newton step alone cannot accept a public root. See [the acceptance derivation](certified-iv.md).
- **Mathematical classes.** Below intrinsic, above maximum, expiry non-identifiability and below-smallest-volatility are distinct from computational failure. A computed zero, NaN or infinity in a positive-root calculation does not establish one of these classes.
- **Failure.** `Non_convergence` means an iteration budget was exhausted; `Numerical_failure` means an evaluation, bracket, normalization or conversion was unresolved. Neither includes a usable root. Callers must handle both variants explicitly. They may not replace failure with a mathematical classification or a last iterate.
- **Rounded bound.** A quote below the exact discounted intrinsic returns σ = 0 only when an enclosure proves the correctly rounded intrinsic equals that quote. An unresolved comparison returns `Numerical_failure`. A quote rounding the intrinsic upward has a positive real inverse and must meet the positive-root certificate.

## European exchange prices

`Exchange` receives one unit of asset 1 against delivery of one unit of asset 2.
Its original-input constant correlated lognormal model, continuous yields,
closed form, exact boundaries and failure semantics are specified in the
[selection contract](first-model-extension.md). Only certified scalar prices
are exposed: a finite value/error pair must meet the caller's explicit absolute
currency limit. Nearest-even rounding is not additionally promised by this
certificate. Correlation is abstract, volatility coordinates stay lognormal,
and reversing exchange swaps the complete asset records. Common interest rate
cancels. [Usage, capability limits and evidence](exchange-prices.md).

This additive API has no Greek, IV, Batch, Scenario or Planner adapter. Existing
portfolio specifications describe one underlying and cannot express both asset
shocks, yields and correlation with compatible aggregation semantics.

## Greeks

- **Time.** Time Greeks are `−∂/∂T / 365`: per calendar day, as remaining maturity decreases.
- **Volatility.** Volatility Greeks are per unit volatility in the model's own coordinate, and the types keep the coordinates apart.
- **Mixed time/volatility.** Veta keeps both the per-calendar-day tag and the normal/lognormal volatility coordinate. Use `Units.annualise_volatility` to convert its time unit. Raw unit constructors are trusted labels, not value/provenance validation; see [the type audit](type-boundary-audit.md).
- **Rho.** For forward models, rho moves the rate with the forward held fixed: `−T·V`.
- **Kinks are coordinate-specific.** `Payoff_kink` means the requested derivative is undefined, not that every derivative at the same contract is undefined. At positive maturity and zero-volatility ATM, fixed-forward rho and theta are zero; veta is the time derivative of right vega and exists. For BSM with S=K and r=q, theta/veta have the same time identity but rho remains a kink. See [the boundary derivation](zero-volatility-greeks.md).
- **Carry cancellation.** Fast Black-family Greeks return `Numerical_failure` in every field when DD coordinate precision is exhausted, or a computed zero lacks original-input ATM identity. Genuine boundary kinks retain their existing classes. Zero-volatility theta forms its cancelling discount terms in DD; unresolved cancellation inside smooth theta refuses that field alone. See [the derivation and capability restriction](greek-cancellation-design.md).
- **Subnormal BSM rho.** A finite zero/subnormal/smallest-normal rho proposal requires an original-input nearest-even rounding proof. Bounded refinement may report a field-specific `Numerical_failure`; mathematical ATM kinks keep their existing class. See [the exponent and midpoint derivation](rho-subnormal-design.md).
- **Computation failures.** Every fast model Greek field rejects a nonfinite result in its output units with `Greeks.Numerical_failure`, distinct from a payoff kink. This finite-result requirement is not an accuracy certificate. Zero-volatility ATM veta additionally requires its existing runtime rounding certificate. Unresolved intrinsic arithmetic must not become a finite zero price/rho through a failed NaN comparison; the float-returning fast price propagates NaN and the Greek owner reports failure. Severe carry cancellation in the fast Black-family price uses bounded original-input refinement and returns NaN if it cannot prove a rounding cell, including some tiny positive-volatility requests. This does not extend certification to all fast prices or Greeks; see [the refinement contract](carry-cancellation-design.md). See [finite Greek results](finite-greek-results.md) for the scope, corrected rho scaling and independently checked outcomes.
