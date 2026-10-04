# Financial type and construction-boundary audit

This audit addresses #18. Types preserve the meanings they actually encode;
they do not prove a model formula, a numerical bound or a caller's raw data
interpretation. Production-domain enforcement remains #13 and runtime IV
uncertainty remains #14.

## Public boundary inventory

| Surface | Enforcement | Remaining obligation |
| --- | --- | --- |
| `Side.Call`, `Side.Put` | Closed static variant; `Side.sign` gives ±1. | Call/put selection must match the trade. |
| Built-in model input records | Field names distinguish spot/forward, carry and displacement; model entry points select semantics. | Floats carry no currency, day-count or percent/decimal provenance. Use common price units, annual year fractions, continuous decimal rates and the documented carry convention. |
| `Black.*.admit`, `Bachelier.admit` | Runtime checks on original inputs; model-specific abstract `admitted` types prevent cross-model use. | Admission is not an error certificate or a guarantee of finite intermediates/outputs. Joint production constraints are a separate obligation. |
| Displaced live admission | Original values finite; exact shifted sums have positive finite high words, with low words preserved. | Shifted overflow is refused even when the mathematical shifted real value exists. At expiry the unshifted payoff is used. |
| `Black.Coordinates` | Private variants/records expose inspection without public construction. | Inspected raw floats lose the owner's invariants if extracted/relabelled. |
| `Black.CARRY`, `Black.Make` | A carry must return the private coordinate type; the functor preserves a model's admitted type. | Reusing the same carry module can share applicative functor types; this is not a fresh generative model token per invocation. A custom wrapper owns its input-mapping semantics. |
| `Coordinates.exp_neg_product` | Raw numerical helper. | It does not validate a financial input or guarantee finite results for arbitrary floats. Prefer model admission and model operations. |
| `Vol.lognormal`, `Vol.normal` | Runtime finite/nonnegative checks and distinct private coordinate tags. | Volatility is per unit, not percent; normal volatility is in price units per √year. Finite σ alone does not make σ√T or every price/Greek representable. |
| `Vol.to_float`, private-float coercions | Explicit extraction. | Erases the tag; the caller owns any subsequent construction or conversion. |
| `Units.per_calendar_day`, `annualise` | Factor-of-365 conversion with statically distinct time tags. | Input meaning is supplied by the caller; conversion follows binary64 arithmetic and may overflow. |
| `Units.time_rate`, `per_volatility`, `per_volatility_squared`, `volatility_time_rate` | Trusted labeling of raw values; private result types retain the chosen tags afterward. | They perform no validation, provenance check or implicit conversion. A caller can deliberately attach a wrong tag or label NaN. Their signatures now say so explicitly. |
| `Units.annualise_volatility` | Converts daily mixed sensitivity to annual while preserving the volatility coordinate. | As for annualise, finiteness and original provenance remain caller obligations. |
| `Greeks.t` | Public record with per-field kink results and the declared unit/coordinate tags. | Users can construct records: this is data, not proof that the numbers came from a model or satisfy a numerical certificate. |
| `Greeks.daily`, `daily_volatility`, `expiry`, `kink` | Construction/conversion helpers. | Raw inputs are trusted. In particular `expiry` expects θ=±1 and validated model quantities; it is not another admission boundary. Its completed fields pass `Greeks.ensure_finite`, which rejects nonfinite payloads without certifying finite accuracy. |
| `Iv.t` | Exhaustive variants retain the volatility coordinate and distinguish computational failures. | Exhaustiveness covers declared cases only. The exact-model meaning of a boundary decision still needs its numerical/domain justification. |
| `Refusal.t` | Typed parameter names with the rejected original value where applicable. | A public diagnostic constructor can be manufactured by a caller; it is not admission evidence. |
| `Normal` | Raw scalar functions with documented NaN/infinity and probability-domain behavior. | No financial unit or admission types. `norm_cdf_dd` has a caller-owned low-word precondition and first-order semantics. |
| `Internal` | Explicitly unstable research/testing access. | No production integration contract; do not bypass model admission through it. |

## Greek quantities and units

Write `V` for price, `S` for the model's underlying coordinate, `σ` for its
normal/lognormal volatility, `T` for remaining years, and `r` for the annual
continuous decimal rate. `D_t = -(1/365) ∂/∂T` is the per-calendar-day operator.

| Field | Definition | Enforced tags | Dimensions left to the caller |
| --- | --- | --- | --- |
| delta | ∂V/∂S | none beyond model record | underlying and price currency/units |
| gamma | ∂²V/∂S² | none beyond model record | underlying squared denominator |
| theta | D_t V | per calendar day | price units |
| vega | ∂V/∂σ | volatility coordinate | price units; per unit σ, not vol point |
| rho | ∂V/∂r with model carry convention | none beyond model record | price per unit decimal rate; forward models hold F fixed |
| vanna | ∂²V/(∂S ∂σ) | volatility coordinate | underlying denominator and price units |
| volga | ∂²V/∂σ² | volatility coordinate squared | price units |
| charm | D_t delta | per calendar day | delta's underlying/price units |
| veta | D_t vega | **time and volatility coordinate** | price units |
| color | D_t gamma | per calendar day | gamma's underlying/price units |

The normal and lognormal coordinates are financially different, even if two
raw numbers happen to agree. The old `veta` field retained only its time tag;
extracting it erased the volatility coordinate and allowed normal/lognormal
veta netting. It also unified with theta. The new
`('time, 'coordinate) Units.volatility_time_rate` closes both demonstrated
misuses. `annualise_volatility` supplies the corresponding safe conversion.
The mathematical values, expression ordering and storage representation are
unchanged.

## Decisions and compatibility

- **Adopt the mixed veta type.** Three compiler-rejection witnesses cover
  normal versus lognormal veta, veta versus theta, and daily versus annual
  veta. This is a breaking field-type change under the stability policy.
- **Retain and document raw unit labeling.** Financial data adapters need a
  construction boundary. A finite-value check cannot determine whether a
  float came from the intended model, coordinate or time convention. Do not
  market these constructors as validation or rewrap a model result casually.
- **Retain the existing admission owners.** No duplicate validation is added
  to the unit layer. Production capability admission and output uncertainty
  belong to #13/#14, with model admission still owning mathematical inputs.
- **Defer currency/underlying dimension types.** This slice has no portfolio
  aggregation or FX model. Different currencies, delta/gamma dimensions and
  rate-risk factors remain explicit caller obligations. Planner aggregation
  (#23/#26) must establish those contracts before netting outputs.
- **Do not introduce an instrument hierarchy or wrap every float.** No
  demonstrated misuse here is prevented merely by renaming a raw-float
  constructor. A future rate-percent or calendar/day-count API needs a clear
  conversion owner and integration use case; field names and this documented
  convention remain the current boundary.

All nine negative type snippets run in ordinary CI and pin the intended
compiler diagnostic. Runtime tests cover finite/nonnegative volatility
construction at NaN, infinities, signed zero, the least subnormal and the
largest finite value, plus coordinate-preserving annualisation. The test that
labels NaN deliberately documents an unchecked boundary rather than implying
that the label validates finiteness.

## Caller migration

Keep mixed sensitivities typed through computation and aggregation:

```ocaml
let daily :
    (Units.per_calendar_day, Vol.lognormal) Units.volatility_time_rate =
  Result.get_ok greeks.veta
in
let annual = Units.annualise_volatility daily in
(annual : (Units.per_year, Vol.lognormal) Units.volatility_time_rate :> float)
```

Handle `Payoff_kink` instead of `Result.get_ok` in an integration that can
reach it. Extract the raw float only at an explicitly documented output
boundary. No pricing result or determinism digest changes in this type-only
step; the ordinary numerical suite verifies that claim on its fixed corpus.
