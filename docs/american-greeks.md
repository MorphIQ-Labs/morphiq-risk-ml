# Estimated American and Bermudan Greeks

`Early_exercise.Bsm.greeks` and `Bsm.Piecewise.greeks` evaluate requested delta,
gamma, vega, rho and theta alongside the underlying price. All successful
quantities are **Estimated_only**. A price can pass while one or more Greeks
remain unavailable or fail their independent refinement screens. These values
cannot be used as `Production` certificates. A price accepted by the separate
[`Bsm.Certified` reduction API](american-certification.md) does not certify these
finite-difference Greeks.

## Requesting quantities

Construct the usual admitted contract and `Bsm.configuration`, then select
quantities using `request_greek` and freeze the selection with `configure_greeks`:

```ocaml
let delta = A.request_greek ~tolerance:0.02 A.Delta in
let vega = A.request_greek ~bump:0x1p-10 ~tolerance:1. A.Vega in
match delta, vega with
| Ok delta, Ok vega ->
    (match A.configure_greeks [delta; vega] with
    | Ok requested -> A.greeks configuration requested contract Side.Put
    | Error message -> failwith message)
| Error message, _ | _, Error message -> failwith message
```

Here `A = Morphiq_risk.Early_exercise.Bsm`; `configuration` and `contract`
come from the [pricing setup](american-pricing.md). These are illustrative loose
engineering targets, not recommended trading tolerances. Every target and bump
must be positive, finite and resolvable. Only vega/rho accept bumps. Empty or
duplicate selections fail configuration. The result preserves caller order.
Use `Piecewise.greeks` with its distinct admitted type for coefficient curves.

## Coordinates and units

| Quantity | Varied coordinate | Held fixed / units |
| --- | --- | --- |
| Delta | Declared-side spot | Strike, nominal cash amounts, all events and coefficients; currency per spot unit |
| Gamma | Spot twice | Same fixed inputs; currency per squared spot unit |
| Vega | Add one displacement to every volatility level | Rate/yield curves and events fixed; currency per unit annual lognormal volatility |
| Rho | Add one displacement to every rate level | Both discount and stock drift change; yield stays fixed; currency per unit annual continuous rate |
| Theta | Move valuation forward, fixing absolute future events and spot | Model-year derivative divided by 365; currency per day |

Vega/rho are not divided by 100. Theta is not a one-day cash P&L, an Actual/360
calendar roll, or a dividend jump. Its forward convention applies to the
remaining continuous American window. Bucketed curve risks, yield sensitivity
and higher Greeks are outside this API. Original binary64 words remain exact
real inputs: a parallel perturbation is declined if any shifted original level
cannot be represented exactly, rather than silently changing the perturbation.

## Methods and numerical acceptance

Delta/gamma use adjacent and twice-wide nonuniform stencils on the price solver's
spot-anchored grid. Both exterior-boundary solutions and every space, time,
domain and cash-interpolation refinement participate. Spot bumps that remesh
around a different anchor are not used. A mixed or unresolved sampled exercise
neighborhood declines the spatial Greeks. Exercise-interior values follow the
payoff, with zero theta; sampled classification remains empirical.

In continuation, theta uses the local backward equation with the initial
coefficient levels, not averaged future coefficients. Future knots, cash dates
and exercise rights remain fixed. Analytical no-cash terminal reductions use
enclosed original-word rate/yield/variance integrals and European derivatives.
The no-early-exercise call reduction is also available for spatial quantities. Scalar terminal-cash call prices now have an exact European reduction, but
Greek base and perturbed prices retain their independently qualified routes.
Consequently their reported price estimates and method/diagnostic fields can
differ from a separate scalar price request for the same model. Extending the
reduction to spatial or fixed-event theta requires separate qualification.

Vega/rho use central bumps `h`, `h/2`, `h/4` on unchanged stock grids and event
schedules. They compare the derivatives across every underlying refinement and
across bumps. A separate right-minus-left slope check rejects apparently stable
central averages at stopping kinks. A change between analytical and numerical
pricing routes is explicitly unavailable. The method is intentionally bounded;
it does not retry at larger grids or invent a smaller bump without the caller.

Every refinement change, final boundary spread, and maximum stencil/arithmetic
indicator across the observed refinement levels must fit one eighth of the
requested Greek target; the assembled final indicators must fit half. This
conservative maximum can reject a request whose finest-grid stencil is small.
The [frozen protocol](evidence/american-greeks/protocol.md) and
[derivation corrections](evidence/american-greeks/protocol-addendum.md) specify
those screens. They establish empirical convergence observations, not a
continuum error bound or a proof of differentiability.

## Results, uncertainty and limits

The outer result fails if the base price fails, or on cancellation/resource
exhaustion. Otherwise it contains the accepted base price and a per-quantity
outcome:

- `Greek_estimate`: private finite value, requested target, method and diagnostics.
- `Greek_accuracy_not_demonstrated`: retained derivative refinement, bump,
  stencil and arithmetic diagnostics, without a usable value.
- `Greek_unavailable`: unsupported/nonsmooth coordinate or unresolved arithmetic
  in the implemented derivative route, with a reason.
- `Greek_failure`: a failed perturbed price or numerical dependency.

All accepted perturbation prices carry their quantity and signed displacement.
Price refinement, residuals, roundoff indicators and work are retained. The
Greek's `amplified_price_indicator` expresses the underlying price indicator in
Greek units using stencil weights or bump division. It can be much larger than
the derivative target even when differences look stable; cancellation of mesh
error is not a certified error bound. Analytical spatial formulas carry their
own enclosure arithmetic, with zero price amplification. Do not reinterpret
any of these diagnostics as a `value ± error` certificate.

Current capability exclusions are explicit:

- Spot-zero, zero-strike and general analytical deterministic-stopping spatial
  Greeks are not qualified. Positive-spot, positive-strike no-cash expiry
  delta/gamma are available away from the strike; the strike kink is unavailable.
- Ordinary two-sided vega is unavailable if any volatility level is zero.
  No one-sided vega is silently substituted. Expiry vega/rho are also declined.
- Spatial Greeks before a valuation-date cash jump are declined, including the
  liquidation kink. This restriction prevents a converged central delta from
  averaging unequal derivatives at the jump. After-cash spot is its own input.
- Theta is unavailable at expiry, at a valuation cash event on either side, or
  at a Bermudan exercise right at valuation. A cash-event jump is not theta.
- Near exercise transitions, short maturities, extreme scales or tight targets,
  refinement or arithmetic may remain unresolved. Failure is a supported outcome.

Work limits cover the whole request. One base price and up to six prices per
requested parallel derivative share fixed work partitions, with another share
for derivative preparation. Scratch is request-owned; 64 KiB plus bounded curve
copy storage is reserved beyond the price solver workspace. Unused shares are
not reassigned. Cancellation is checked during preparation, each underlying
solve and before publication; caller callback exceptions propagate. A Greek
request therefore has a different resource allocation from standalone pricing.

See [qualification and initial costs](results-american-greeks.md) and the
[subsequent boundary optimization](results-american-greek-optimization.md). Tight-target
refusals, unresolved reference rows and shared-host performance limits are part
of that evidence, not successful accuracy comparisons.
