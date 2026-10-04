# Production boundary design

This is the implementation contract for #13 under Epic #27, not an accepted
production release. The existing scalar price/Greek API has mathematical
admission and checked-input evidence. That admission does not certify every
served result. The production boundary must make the numerical obligation
explicit and enforce it on the actual request.

## Intended use and exclusions

The candidate covers scalar, cash-settled European calls and puts under BSM,
Black-76, displaced Black and Bachelier. Inputs describe the same exact real
models as [the model contracts](model-contracts.md). Prices are per underlying
unit in one caller-selected currency; no notional or contract multiplier is
implicit. Rates and yields are annual continuous decimals; volatility is per
unit, with the existing normal/lognormal coordinate types retained. The caller
owns dates, year fractions, curves, data provenance and conversion to these
flat model inputs. Time Greeks retain the explicit negative maturity
derivative divided by 365, irrespective of the caller's date convention.

This slice is for model valuation and local analytic sensitivity calculation.
It does not implement exercise policy, discrete dividends, barriers, stochastic
volatility, calibration, settlement, credit/funding adjustments, margin,
portfolio netting, market-data validation or regulatory capital. A scenario
planner is separately tracked in #23. Exact binary64 inputs do not imply exact
knowledge of the market: numerical error and model/input uncertainty are
different quantities.

## Ownership and typed outcomes

Keep the existing model admission owners. A separate production adapter owns
capability admission and numerical output acceptance, preserving model and
volatility-coordinate types. Its abstract admitted value cannot be constructed
by labelling an unchecked float or reusing another model's admission token.
Public inputs remain original values; no rounded shifted sum becomes the
definition of a displaced contract.

Prices and smooth Greeks must return a finite value with an outward absolute
error bound for the exact real quantity. The caller supplies an explicit
absolute numerical limit in that quantity's units before evaluation; there is
no fitted default tolerance. Acceptance requires the computed bound to meet
that limit. The limit must be finite and nonnegative. A result exceeding it is
a failed accuracy request, not a successful approximate value. Unit/coordinate
tags must survive extraction of a certified sensitivity.

Positive IV already has a stronger, fixed criterion: nearest-even binary64
rounding of the exact quote's inverse. Preserve its mathematical classes,
rounded-intrinsic convention and computational failures. Do not replace an IV
failure with a fast proposal. Any downstream economic tolerance is additional
to this numerical contract.

Distinguish invalid mathematical inputs, unsupported production capability,
an unresolved enclosure and an error bound exceeding the requested limit.
No failure contains a usable fallback value. A payoff kink is specific to the
requested derivative; it cannot erase a smooth derivative with respect to a
different coordinate (Bug #34). The initial smooth-Greek certificate explicitly excludes expiry and zero
variance; their separate boundary contracts are not implemented by this adapter. Such exclusions must be enforced and
must not silently call the fast API.

## Numerical domain and joint constraints

Mathematical validity follows the existing model owners: finite original
inputs, nonnegative maturity and volatility, positive live lognormal shifted
coordinates, finite normal coordinates of either sign, and finite nonnegative
quotes. A finite shifted high word is an implementation admission requirement.

Runtime capability additionally depends on combinations of inputs. Discount
products, exponent arguments, normalized denominators, total volatility and
the precision needed after cancellation must be representable by the
[enclosure algorithms](runtime-enclosures.md). Their written preconditions,
including the model exponential guard and positive denominator intervals,
are checked at the operation that owns them. Unsupported arithmetic fails;
neither a sampled rectangle of rates/spot/volatility nor a measured ULP budget
is used to imply success throughout an unproved joint domain.

Underflow must remain in the absolute error radius. Tail prefactors can rescue
small probabilities; overflow is never accepted as an infinite error bound.
Close-to-intrinsic and close-to-maximum quotes need original-input comparisons.
Sparse displaced inputs can exceed the working precision and legitimately
fail. Absolute requested accuracy remains meaningful at Greek zeros, unlike
an unqualified relative-error promise.

## Evidence and acceptance

Operation-level derivations precede implementation and reference scoring.
Prices use the existing independent real-model enclosures. Smooth Greek
enclosures require explicit differentiation identities and propagation through
their original-input factors; resemblance to the fast implementation is not
evidence. Validate against precision-refined references, including low words,
Greek zeros, tails and interacting input constraints. Test both sides of each
enforced capability boundary and requested error limit, plus compile-time
model/coordinate rejection.

Before institutional acceptance, the designated owner must approve intended
use, per-output numerical limits, economic materiality (including notionals,
aggregation and decision thresholds), permitted failure rates and operational
requirements. The agent cannot infer those from a finite corpus or invent an
approval. #15 supplies independent review; #16 supplies portfolio and comparator
evidence; #17 binds those decisions to an exact release candidate. This design
does not discharge those separate obligations.

## Implemented public boundary

`Morphiq_risk.Production` contains `Bsm`, `Black76`, `Displaced` and `Bachelier`.
Each has its own abstract `admitted` type and delegates mathematical validation
to the corresponding existing owner. `evaluate` takes a typed volatility, a
quantity GADT and a mandatory `max_error` in that quantity's units. The private
certificate retains both `value` and `absolute_error` with those units.
The caller cannot construct a certificate or reuse another model's token.

```ocaml
let request inputs sigma price_limit =
  match Morphiq_risk.Production.Bsm.admit inputs with
  | Error error -> Error error
  | Ok admitted ->
      Morphiq_risk.Production.Bsm.evaluate admitted Morphiq_risk.Side.Call
        sigma Morphiq_risk.Production.Price ~max_error:price_limit
```

The limit is a caller input, selected before requesting the result. In a risk
integration it must come from that quantity's numerical/economic policy; this
example intentionally supplies no production default. Time limits use
`Units.time_rate` with the per-calendar-day tag, vega/vanna/volga retain their
volatility coordinate, and veta retains both tags. Raw unit constructors still
trust caller labels; they do not establish market provenance or currency.

| Output | Runtime acceptance | Capability exclusions |
| --- | --- | --- |
| Price | Original-input model enclosure; finite value and outward absolute error <= requested limit | Arithmetic guard, representability or requested accuracy failure |
| Ten smooth Greeks | [Differentiation identities and propagated enclosures](production-greek-enclosures.md), same typed absolute criterion | T=0 and sigma=0 explicitly `Unsupported`; arithmetic/accuracy failures remain possible |
| Positive IV | Existing exact-model nearest-even root certificate | Explicit `Iv.Numerical_failure` / `Non_convergence`; no proposal fallback |
| IV mathematical boundaries | Existing original-input comparisons and rounded-intrinsic exception | Unresolved comparisons remain computational failures |

`Invalid_input` carries the original owner's refusal. `Invalid_accuracy` rejects
NaN, infinities and negative limits. `Unsupported Expiry_greek` and
`Unsupported Zero_volatility_greek` state the offered capability even when a
particular boundary derivative exists. `Numerical_failure` means enclosure
arithmetic could not resolve the request; `Accuracy_exceeded` means a finite
proved bound exceeded the requested limit. Neither contains a fallback value.
`implied` preserves the existing `Iv.t` variants inside its result: callers must
handle those computational outcomes as well as the outer input refusal.

The arithmetic capability is joint and checked on the actual request. For
example the model exponential encloses arguments of magnitude at most 1024,
with its elementary substeps guarded at 256; these guards use outward bounds.
A large rate alone is not refused if its maturity product resolves inside the
guard. Positive total volatility/denominators, finite expansions and retained
underflow allowances are checked by their owning operations. Overflowing
F-K, an unresolved shifted ratio or excessive cancellation can fail even when
all inputs are finite. These are enforced computational outcomes, not an
unproved rectangular guarantee of availability.

## Exercised evidence

- 4,176 public price/Greek certificates contain the existing extra-bit original-
  input references, including 1,670 model prices and 2,506 smooth Greeks.
- 3,932 positive error-bound cases accept the exact computed limit and reject
  its immediate predecessor. A zero limit accepts exact payoff identities and
  refuses nonexact prices; invalid limits have separate controls.
- 2,376 interior output requests meet a fixed test requirement of 1e-10 in each
  quantity's units. This is test coverage, not a default or an economic policy.
- Explicit tests cover owner input refusals, expiry with invalid live shifted
  coordinates, zero variance, tiny values, overflowing distance and both sides
  of exponential capability, including interacting rate/maturity inputs.
- Four compiler-rejection witnesses cover certificate construction, model
  tokens, volatility coordinate and time-unit mixing.
- [Independent Arb series differentiation](evidence/arb-greek-reference.json)
  validates all 2,506 Greek references without importing the analytic Greek
  formulas. Working precision ranges from 256 to 2048 bits; none is unresolved.
  The polynomial coefficients and polarization identities are recorded in
  `scripts/arb_greek_audit.py`, using the documented
  [Arb series API](https://python-flint.readthedocs.io/en/stable/arb_series.html).

The finite corpus does not guarantee availability for every valid request.
Correctness of accepted outputs rests on the documented enclosure identities,
checked arithmetic premises and acceptance rule; independent references test
that implementation. The owner has since [reviewed and approved this declared
boundary](acceptance/owner-review-2026-10-03.md), closing #13. Independent numerical
review, application-specific economic policy and target-deployment operational
acceptance remain separate Epic #27 requirements.

The complete local ordinary suite, install and formatting checks pass. Replay
remains `f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b`:
the new adapter and internal derivative capability do not change legacy served
values or outcomes. All twelve [affected/core mutation witnesses](evidence/production-mutations.txt)
are killed after a clean baseline and successful builds. Four optional mechanisms
brought the catalog to 47 at this stage; default CI retained seven. See
[mutation policy](mutation-policy.md) for the current catalog count.

The [legacy API A/B/B/A check](evidence/production-compatibility-bench.json)
against `ee1ffed` retains all 768 successful IV outcomes in every run. Legacy
price spans 0.11–1.77 µs before and 0.11–1.84 µs after, all Greeks 6.84–20.19 µs
before and 6.86–20.42 µs after, and IV 0.38–1.03 ms before and 0.38–1.01 ms after.
These shared-host ranges show no material regression on the exercised legacy
workload. They do not measure the new adapter's additional per-request work or
establish operational acceptance; that belongs to the portfolio/performance
campaign. No local test/profile ran concurrently with this comparison.

## Multiple outputs from one admitted model

`Production.Bsm.evaluate_many` and its Black76/Displaced/Bachelier counterparts
accept ordered typed `Production.Request (quantity, max_error)` values and return
`Production.Outcome (quantity, result)` for every entry. `Batch.evaluate_many`
adds model dispatch and one admission for the fixed inputs. Limits and result
units remain checked by the quantity GADT. Empty lists and duplicate quantities
are supported; a failed output does not suppress later results.

Only immutable original-model preparation is shared within a call. Scalar
acceptance and error precedence remain the owner; no mutable cache escapes to
an admitted value or plan. See [shared certification](shared-certification.md)
for dependencies, boundaries and compatibility evidence. The existing `MODEL`
module type remains source-compatible; `MULTI_OUTPUT_MODEL` extends it.
