# Piecewise American and Bermudan coefficients

`Early_exercise.Bsm.Piecewise` adds deterministic piecewise-constant rates,
continuous dividend yields and lognormal volatility to scalar American and
Bermudan pricing, with optional liquidator cash payments. Results remain
`Estimated_only`; neither admission nor successful refinement supplies a
continuum price certificate. See the [executed qualification](results-american-piecewise.md).

## Declaring a complete curve

`Rate`, `Yield` and `Volatility` have separate abstract types. Each constructor
accepts `~horizon`, `~initial` and `~changes`, an array of `(time, new_level)`.
Rate and yield levels are annual continuously compounded rates; volatility
levels have type `Vol.lognormal Vol.t`, in annual lognormal units. Time uses
the same explicit year coordinate as the option. No calendar or market-curve
bootstrap is inferred.

The initial level starts at zero. Changes must be finite, strictly increasing
and strictly inside `(0,horizon)`; the final interval ends at the declared
horizon. Each level applies on `[start,end)`. Expiry uses the final left limit.
Negative finite rates and yields are valid; volatility remains nonnegative.
Zero horizon validates the initial level and requires an empty change array.
Admission rejects duplicate, unsorted or out-of-horizon knots, nonfinite
levels, and any curve horizon different from the option's expiry. It does not
repair, sort, average or extrapolate schedules.

For example, construct a rate curve with a half-year change:

```ocaml
let rate =
  Early_exercise.Bsm.Piecewise.Rate.create
    ~horizon:1. ~initial:0.05 ~changes:[| (0.5, -0.03) |]
```

Construct yield and volatility curves in their respective modules, then use
`Piecewise.admit`, `admit_cash` or `admit_bermudan`. The `inputs` record retains
spot, strike, expiry and opening fields, with the three curve types replacing
constant coefficients. `price` uses the existing `Bsm.configuration`, failure
variants and private estimate type. A piecewise admitted value cannot be passed
to constant `Bsm.price` or its constant-input getter.

Constructors freeze caller arrays. `changes`, `cash_specification` and
`exercise_schedule` return copies. Original redundant knots survive getters;
execution coalesces adjacent equal levels only after validation. Fully constant
curves, including redundant splits, delegate to the existing constant path and
retain its complete outcomes.

A future parallel rate/yield Greek will shift every original level by one
annual continuous-rate displacement. A segment Greek will perturb one original
level. Volatility perturbations use annual lognormal units and must remain
nonnegative. Those coordinates are defined here; this change adds no Greeks,
IV, batch/planner adapter, nonconstant interpolation or stochastic volatility.

## Event ordering and numerical method

The backward-Euler policy solver splits rollback intervals at the union of
coefficient knots, cash dates, finite exercise dates and American opening.
Spatial bands are rebuilt when their coefficient tuple changes; cached bands
are owned by the request and keyed by both stock grid and coefficients.
At a cash date the backward order remains After exercise, liquidator mapping,
Before exercise. A coefficient change adds neither a stock jump nor a Bermudan
exercise right. The traversed interval uses its own coefficients.

The zero-stock put boundary is
`K max_u exp(-integral_t^u r)`, where `u` ranges over permitted exercise times.
For American exercise the candidates are the window endpoints and interior rate
knots; for Bermudan exercise they are only listed rights. The local rate's sign
cannot select a future optimum when rates change sign. A zero-strike no-cash
call uses the corresponding yield integral. Safe exterior envelopes use
`exp(integral max(-r,0))` or `exp(integral max(-q,0))`. Discrete negative-rate
amplification is screened with `exp(2 integral max(-r,0))`, retaining the existing
per-step matrix-margin restriction.

On each constant slab, the future optimal discount and remaining envelope
integrals are prepared once. At an interior numerical time, only that slab's
original-word elapsed-time enclosure is added. Maxima with overlapping candidate
intervals retain an enclosure of the maximum; ambiguous ordering is not resolved
by silently discarding the other candidate. Successful boundary scalars may be
reused only within the same immutable request and exact slab/time-grid identity.

All-zero volatility follows the deterministic stock trajectory through coefficient
and cash events. American exercise also considers admissible stationary points
`q*S=r*K` within each segment. Bermudan exercise considers listed instants only.
Mixed zero/nonzero volatility retains stochastic continuation and deterministic
transport intervals in the numerical solve.

No-cash terminal reductions integrate `R=integral r`, `Q=integral q` and
`A=integral sigma^2` as enclosures of original inputs. The European expression
uses discounted legs `X=S exp(-Q)`, `Y=K exp(-R)` and
`d1=(log(X)-log(Y)+A/2)/sqrt(A)`, `d2=d1-sqrt(A)`.
It does not pass rounded average parameters into the constant-model API.
No-cash premiums use that same integrated European comparison; cash premiums
remain explicitly unavailable. Arithmetic uncertainty and failed refinement
remain failures under the existing budgets.

Curve metadata joins cash and exercise metadata in checked workspace
reservations. Integration and boundary searches count toward row visits;
coefficient preparation retains cancellation and work checks. The conservative
metadata reservation is 1024 bytes per declared coefficient level, in addition
to the existing stock-grid/solver reservations. It covers partition references,
merged-event storage and temporary enclosure work; it is not measured allocation
per request. Execution scratch is request-owned; the admitted curves are immutable.
