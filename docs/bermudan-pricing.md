# Explicit Bermudan exercise schedules

`Bsm.Piecewise.admit_bermudan` extends these same finite-rights and cash-side
conventions to [piecewise coefficients](piecewise-american.md).

`Early_exercise.Bsm.admit_bermudan` prices a call or put with a finite set of
exercise instants under constant BSM coefficients, continuous yield and optional
scheduled liquidator cash dividends. Every successful output is **Estimated_only**.
It is not a `Production` certificate. [Estimated Greeks](american-greeks.md)
retain these exercise schedules and decline theta at a valuation exercise right.
Implied volatility and portfolio adapters remain separate work under Epic #107.

## Financial admission

Construct the usual typed `Bsm.inputs`, then supply an `exercise_instant array`:

```ocaml
let dates : Early_exercise.Bsm.exercise_instant array = [|
  { time = 0.5; side = Regular };
  { time = 1.0; side = Regular };
|]
(* Bsm.admit_bermudan inputs dates, with opens_at=0.5 and expiry=1.0 *)
```

Admission requires a nonempty, strictly ordered schedule. Times are exact
original binary64 year offsets in `[0,T]`. The first time must equal `opens_at`
and the last must equal expiry. There is no sorting, deduplication, inserted
terminal date, date conversion or implicit continuous exercise. Duplicate
instants are rejected. The original array is copied; `exercise_schedule`
returns a fresh copy and preserves Bermudan identity even for a terminal-only
schedule. `None` identifies an American admitted model.

Use `~cash` with the same [cash specification](american-cash-dividends.md) as
American pricing. Each exercise instant must be `Regular` off cash dates and
`Before_cash` or `After_cash` on cash dates, including zero payments. The first
and last sides match the cash opening and expiry sides. At the same physical
time, Before then After are distinct ordered rights; repeating either is invalid.
Valuation `After_cash` uses ex-dividend stock without paying the event again.
Expiry `Before_cash` excludes the terminal cash jump.

Run [the complete example](../examples/bermudan_price.ml):

```sh
opam exec --switch=morphiq-risk-ml -- dune exec examples/bermudan_price.exe
```

Its cash-date put permits both sides at 0.5 and regular exercise at 1.0. The
illustrative tolerance of one currency unit at scale 100 is an engineering
example, not a recommended trading tolerance.

## Rollback and bounded work

The [financial contract](american-model-contract.md) defines optimal stopping.
Between listed instants the engine solves linear continuation; internal time
steps do not confer exercise rights. Backward processing at a joint cash date
projects an allowed After right, maps `max(S-D,0)`, then projects an allowed
Before right. Regular instants project their payoff directly. The terminal
payoff initializes rollback. Amounts at a common date form one joint sum.

At absorbing stock zero, a put with nonnegative rate discounts its strike to
the next allowed exercise date; with negative rate it discounts to expiry.
A deterministic path maximizes discounted payoffs over the listed instants
only. American interior stationary points do not confer Bermudan rights.
Terminal-only no-cash requests reduce to the existing enclosed European price;
zero-stock/strike and no-early-exercise reductions retain their conditions.

The existing positive spatial operator, boundary pair, checked linear solve,
original-system residual and independent space/time/domain/cash-mapping
refinements are reused. Finite exercise dates are fixed across all refinements.
Scratch remains request-owned. Preparation merges already ordered event lists
in linear time, with metadata, workspace, row, step and cancellation limits.
More exercise dates add slabs and can exhaust those limits. Admission memory
is proportional to supplied schedules; numerical work caps govern pricing.

Zero-stock put boundaries reuse successful evaluations within the request, keyed
by the original slab endpoint words, next exercise word, time-step count and
integer step. The same enclosed evaluator runs on every miss. The local
arithmetic allowance is fixed and its recorded maximum error never decreases,
so reuse preserves both validation and the accumulated indicator. Discount
recurrences and rounded-time keys are not used. Positive-rate American puts
with immediate opening and calls skip this preparation.

Optional preparation consumes only surplus after the existing solver and event
metadata reservations: 128 bytes for the owner plus 256 bytes per entry and
8 bytes per time step, including conservative overhead for the supported
64-bit runtime. Each array must also fit the runtime array limit and the
request's maximum step count. The entry charge bounds the lookup list as well
as its arrays. When an entry does not fit, that slab uses the original evaluator;
workspace availability, logical work counts and cancellation points are
unchanged. See [qualification](results-bermudan-boundary.md).

Results retain method identity, refinement, residual, arithmetic, cash-mapping
and work diagnostics. Exercise regions are available only at a listed valuation
instant and only on a sampled numerical route. Cash-European premiums remain
unavailable. Resource exhaustion, cancellation, nonconvergence, unresolved
arithmetic and unmet refinement return explicit failures without partial prices.
A refinement target is not a bound on continuum price error.

## Independent evidence and limitations

The [frozen protocol](evidence/bermudan/protocol.md) and 32 original-input cases
were committed before reference execution and runtime changes. Independent
positive Gaussian quadrature uses only listed exercise dates, with three space/
time resolutions and zero/global-cap exterior comparisons. Analytical and
finite deterministic references use 80/160-digit original-input calculations;
a fixed discrete quadrature problem also has a separate precision replay.
These empirical uncertainties are not certified intervals.

Pinned QuantLib `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c` supplies a second
comparison. Unmodified Bermudan Spot results and an original side-aware
liquidator adapter are retained separately. QuantLib's ordinary cash handling
has different floor, coincident-payment and exercise-side conventions; those
values must not be presented as model-matched checks. Exact date-conversion
failures and endpoint/analytical exclusions are recorded per case. No QuantLib
code is imported into the runtime.

Reproduce scoring with `scripts/check_bermudan.py --executable
_build/default/test/bermudan.exe`, optionally `--refined --mode loose`.
The loose criterion is `max(S,K)/100`; the primary criterion is
`2^-16 max(S,K)`, both frozen before execution. Missing outputs and broad
references do not count as passes. See the [executed results](results-bermudan.md)
for all outcomes, compatibility, mutation witnesses and measured costs.
