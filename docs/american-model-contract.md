# American and Bermudan financial contract

**Design for #108 under [Epic #107](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/107).
No American runtime API is implemented by this document.** It fixes the real
quantity, event semantics and ownership that #109–#120 must implement and qualify.
The general schedule names in the API sketch remain proposed; #111/#112 supply
the [constant-coefficient scalar API](american-pricing.md), including
[scheduled cash dividends](american-cash-dividends.md). #113 adds
[explicit finite Bermudan schedules](bermudan-pricing.md) through
`Bsm.admit_bermudan`; the broader coefficient-schedule sketch remains proposed.
Existing European
definitions, certificates and served values are unchanged.

Work is staged on `feature/american-integration`, created from main at
`bab3ffda321f8df2cd83a5bc982aa3b76a7fdf51`. Focused PRs target that temporary
branch; each must pass the existing five CI checks before landing. #108 precedes
solver/assurance design (#109) and independent references (#110); both precede
runtime pricing (#111). A later combined PR to main must identify its exact
qualification scope. The branch does not confer release or deployment approval.

## 1. Target quantity and units

Price one unexercised, unit-notional call or put on one stock, in the same currency
as spot, strike and cash dividends. Exercise settles the positive payoff
immediately, with no settlement lag, fees, transaction costs, tax, funding spread,
FX conversion or additional option-holder dividend payment:

    g_call(s) = max(s - K, 0),  g_put(s) = max(K - s, 0).

This is the cash value of immediate exercise. Physical delivery, subsequent
stock ownership and realised cashflows are not simulated. The option holder
receives exactly one payoff; exercising before a dividend does not add that
dividend separately to g(s).

Between dividend events, under the specified risk-neutral measure:

    dS(u) = (r(u) - q(u)) S(u) du + sigma(u) S(u) dW(u).
    discount(a,b) = exp(-integral_a^b r(u) du).

The deterministic coefficients are finite piecewise-constant functions. `r` and
`q` are continuously compounded annual rates; `sigma` is nonnegative lognormal
volatility per square-root year. `q` describes continuous carry/yield and may be
negative. Scheduled cash distributions are additional, distinct model inputs.
The caller must not put the same dividend into both q and the cash schedule.
There is one rate for both discounting and risk-neutral stock drift; separate
repo/collateral curves are outside this contract.

For the admissible exercise set E and nonanticipating stopping rules taking
values in E, the value at the declared valuation instant v is

    V(v,s) = sup_tau E[discount(time(v), time(tau)) g(S(tau)) | S(v)=s].

The state at a dividend instant is explicitly before or after the jump, as
defined below. Both sides have the same physical time and discount factor.
The filtration contains no future Brownian information; a decision immediately
before a known dividend uses the observed pre-jump stock. E always includes the
contract's terminal exercise instant. A zero terminal payoff expires worthless.
Using a supremum avoids assuming a unique optimal stopping rule.

Every binary64 financial input denotes its exact real value, as in
[the European model contract](model-contracts.md). Integrals, products, sums,
jumps and payoffs in this definition are real operations; intermediate rounding
is implementation error. The intended price is the nearest-even binary64 value
of this real stopping value, but an estimated solver result does **not** promise
correct rounding or a rigorous error bound. Numerical acceptance is a separate
contract owned by #109/#116.

## 2. Time, exercise styles and event sides

The scalar kernel receives year offsets from valuation, whose physical time is
zero. Times are finite, nonnegative exact binary64 coordinates; negative zero
is canonicalised to zero. Dates, holidays, exchange hours and business-day
adjustments do not enter the scalar model implicitly.

An **instant** is one of:

- `Regular(t)`: time t with no cash-dividend event;
- `Before_cash(t)`: immediately before the joint cash event at t;
- `After_cash(t)`: immediately after it.

Compare physical times first, then `Before_cash(t) < After_cash(t)` at a cash
event. `Regular(t)` at a cash event is invalid; either cash-side tag without an
event at t is invalid. Rate/yield/volatility knots alone use `Regular(t)` and do
not create a stock jump or two exercise instants. Time comparisons are exact
comparisons of admitted input coordinates, with no epsilon-based coalescing.

Valuation includes its still-available exercise opportunity. At a cash event at
time zero, the caller must supply the spot corresponding to the declared side:
pre-dividend for `Before_cash(0)`, ex-dividend for `After_cash(0)`. The latter
does not subtract the dividend again. The event remains in the frozen metadata
so the side can be validated, but pre-event rights have passed.

| Exercise specification | Admissible remaining opportunities |
| --- | --- |
| European | One terminal instant |
| Bermudan | A nonempty, strictly increasing list of distinct instants; its last instant is expiry |
| American | Every instant in a closed interval from `opens_at` through `expires_at`, inclusive |

Constructors keep these styles distinct. A one-date Bermudan or a degenerate
American window has the same mathematical value as the matching European
contract, while retaining its declared style in the input identity. Bermudan
dates are not silently sorted, deduplicated or augmented with an expiry. Both
cash sides at the same physical time are distinct admissible Bermudan entries.
An American interval spanning a dividend contains both sides unless an endpoint
excludes one: opening after the cash event excludes pre-dividend exercise, and
expiring before it excludes post-dividend exercise.

The active scalar specification contains only remaining rights: valuation must
not follow `opens_at` or any Bermudan entry, and expiry must not precede valuation.
The future date adapter explicitly intersects an original American window with
the remaining horizon (an already-open window starts at valuation), removes
passed Bermudan rights, and reports `Post_expiry` once terminal exercise has
passed. It must not resurrect a passed cash-side right or silently clamp an
expired option into a live zero-maturity contract. This is valuation of an option
known still to be outstanding; prior exercise/settlement history is not inferred.

The scalar time input is authoritative. A future civil-date adapter owns and
records day-count conversion, event-side choices and original dates. Each year
offset is calculated directly from that valuation date using the selected
convention, rather than subtracting previously rounded offsets repeatedly.
Its resulting binary64 words become exact scalar inputs. Distinct date events
that collapse to one binary64 time require an explicit conversion failure,
not an invented ordering. The existing European `Scenario.Time` convention is
unchanged; American scenario integration and roll policies belong to #118.

## 3. Cash dividends and coincident events

Select the **liquidator model with limited liability**. At a scheduled event u,
let D be the exact sum of all nonnegative nominal cash amounts assigned to u:

    paid(s,D) = min(D,s),
    S(u+) = J_D(S(u-)) = max(S(u-) - D, 0).

The stock is strictly positive between events when it starts positive, but a
cash event may reach zero. Zero is absorbing thereafter. The specification is
therefore nonnegative, not strictly positive on every path. If s < D, the company
pays s, the unpaid D-s does not become debt, and no negative stock is created.
The nominal schedule is not a guarantee of full payment in those states.
This is a deliberate model choice, not an error-recovery clamp.

This convention is described in [Healy's dividend-policy discussion, §4.1](https://arxiv.org/html/2106.12971v1#S4.SS1).
The project's immediate-settlement, continuous-yield and event-side conventions
above are stated independently; the paper's European settlement setup is not
silently imported. Neither a survivor policy nor an escrowed/spot-minus-PV model
is interchangeable with this transition. Future alternatives need different
model identity and independent qualification.

Cash entries must have finite nonnegative amounts and nondecreasing times in
[0,T], where T is expiry's physical time. Entries sharing a time form **one joint
event** with an exact real sum D. There is no exercise opportunity between its
individual components. Never sequentially round away small cash amounts or
replace an unrepresentable sum with infinity. Inability to evaluate the admitted
event is a numerical capability/failure outcome. Preserve the original entries
and words in the snapshot. Zero-amount events retain their side labels and have
an identity stock transition.

At each joint event, forward financial order is:

1. Reach the pre-dividend stock; honour `Before_cash` exercise if permitted.
2. For the still-unexercised option, apply J_D once.
3. Honour `After_cash` exercise if permitted; continue under the coefficients
   for the following time interval.

There is no elapsed time, discount accrual or diffusion between steps. A
coincident coefficient knot changes the following interval, not either payoff.
Multiple cash amounts, a rate knot and a Bermudan right cannot rely on array
insertion order to choose financial semantics.

Equivalently, V_after includes any post-event exercise opportunity. If the
contract survives the event, its backward jump condition is

    V_before(s) = max(g(s), V_after(J_D(s)))   if pre-event exercise is allowed,
                  V_after(J_D(s))            otherwise.

This identity does not choose an interpolation method or bound its error.
At expiry `Before_cash(T)`, the terminal value is g(s) before the jump and the
post-event option no longer exists. At expiry `After_cash(T)`, apply the jump
before terminal payoff; a permitted pre-event exercise competes with that value.
The schedule may retain the event at T to identify the side even if expiry is
before it. Later events are outside the scalar active horizon.

## 4. Piecewise coefficients

Each of r, q and sigma has its own initial level at time zero and a finite list
of strictly increasing change times in (0,T). A level applies on a half-open
interval [knot_i,knot_(i+1)); a knot takes effect to its right. No interpolation
between levels, volatility averaging, implicit flat-tail extrapolation or
conversion from zero-rate quotes is performed. The last level covers the rest
of the active horizon. T=0 still requires finite initial levels for validation.
An adapter must explicitly trim knots at or beyond expiry when constructing
the active specification. Coincident knots across different curves are valid;
duplicate knots within one curve are not.

Coefficients are finite at every level, sigma >= 0, with arbitrary finite signs
for r and q. A zero-volatility interval is deterministic conditional on its
entering stock, but does not make an otherwise stochastic contract deterministic.
All curves and cash/exercise schedules are frozen by admission. Splitting an
interval into identical levels does not change the real quantity, though a
solver still needs its own compatibility and numerical checks.

For a no-cash European terminal contract, the real reduction uses
R=integral r, Q=integral q and A=integral sigma². This is a useful independent
check. For American exercise, equal terminal R/Q/A does **not** make different
time profiles interchangeable: intermediate exercise opportunities matter.

## 5. Admission, boundaries and numerical capability

Mathematical input validation owns finite S >= 0, K >= 0, times, coefficients,
cash amounts, curve coverage and exercise/event consistency. Validate the whole
specification before a convenient boundary path; expiry does not excuse a NaN
rate or an invalid schedule. Original zero and small positive quantities remain
distinct. A rounded variance underflow is not evidence of zero volatility.

| Case | Required real target or outcome |
| --- | --- |
| Valuation instant equals terminal instant | g(S), once, with no discounting or additional jump |
| T=0 but valuation is before cash and expiry is after cash | Process the zero-duration event and remaining exercise rights; this need not equal the pre-event payoff |
| S=0 | Absorbing stock: call zero; put K times the largest discount(0,t) over permitted remaining exercise instants |
| K=0 | Put zero; call retains its stopping problem (not universally S when q may be negative) |
| All remaining sigma levels are exactly zero | Deterministic optimal stopping along the drift/jump path, not automatic immediate or terminal exercise |
| Negative rates/yields | Financially valid; no universal cap at K for puts or S for calls, and no assumed single exercise boundary |
| Empty/reversed/inconsistent active exercise schedule, negative cash/spot/strike/volatility, or nonfinite inputs | Invalid input, identifying the field/event |
| Valid cash/Bermudan/curve feature not yet implemented, or a valid numerical regime excluded by the solver | Explicit unsupported capability, not financial invalidity |
| Resource limit, cancellation, nonconvergence, unrepresentable output or unresolved arithmetic | Explicit corresponding failure/incomplete outcome, without a usable price |

Negative rates can create two exercise boundaries, as analysed in
[Healy, §§2–3](https://arxiv.org/html/2109.15157v1#S2). Exercise diagnostics must
allow multiple intervals, empty regions and unresolved locations; do not encode
the entire contract as one critical stock price. Sampled grid equality is not
proof of exact indifference or of the continuum exercise region.

For the deterministic case, between jumps
S(t)=S(a) exp(integral_a^t (r-q)). Maximise discount(0,t) g(S(t)) over allowed
instants, including dividend sides. For an American window and piecewise
constants, endpoint-only sampling is insufficient: within a smooth in-the-money
interval, the stationary condition is **q S(t) = r K** (for either side).
Inspect admissible interior stationary points as well as interval endpoints,
payoff kinks and event sides; handle constant/degenerate segments explicitly.
This is a derivation of the financial target. A finite-precision implementation
and its acceptance/failure rules still require #109/#110 evidence.

## 6. Proposed API ownership and results

Use an additive `Early_exercise.Bsm` namespace, with opaque admitted contracts
and validated immutable exercise, cash and coefficient schedules. Keep the
existing `Side.t` and typed `Vol.lognormal Vol.t` coordinates; do not repurpose
`Bachelier`, `Black76` or the European admission types. This design sketch is
not an installed interface:

```ocaml
(* Design only: private constructors validate and freeze these inputs. *)
type instant                         (* physical time and validated event side *)
type exercise =
  | European of instant
  | Bermudan of instant array        (* nonempty, ordered, distinct *)
  | American of { opens_at : instant; expires_at : instant }

type coefficient_schedules           (* independent r, q, lognormal-vol curves *)
type cash_schedule                   (* nominal amounts; liquidator convention *)
type admitted                        (* original inputs, style and event identity *)
type estimated_price                 (* finite value and labelled diagnostics *)
type certified_price                 (* separate, only if #116 justifies it *)
```

The enum above describes constructor input; raw arrays are not retained through
writable aliases and cannot forge an admitted contract. One admission owner
checks cross-schedule consistency and freezes the full specification. Solver
configuration (grid/refinement policy, work/memory limits, requested diagnostics)
is separate from the financial model. It belongs in executable/plan identity
without changing the mathematical target.

| Owner | Responsibility |
| --- | --- |
| Model admission | Units, exact original inputs, finite/domain checks, exercise/cash/curve consistency and immutable storage |
| Date/scenario adapter (#118) | Dates/day count, event sides, remaining-rights projection, frozen-input shocks and post-expiry outcome |
| Numerical solver (#109/#111) | Discretization, finite resource limits, convergence/refinement diagnostics and numerical failure |
| Assurance boundary (#116) | Any justified continuum price bound, its supported domain and requested currency tolerance |
| Risk/inverse owners (#115/#117) | Defined perturbations/inverse family, non-differentiability/nonidentifiability and per-output uncertainty |
| Batch/planner owner (#118) | Dependency-aware reuse, worker-owned scratch, bounded ordered output and cancellation/cleanup |

Estimated results require a finite nonnegative value, an explicit
`Estimated_only` assurance label, and identified diagnostics such as refinement
differences and solver residuals. A diagnostic may be unavailable; it must not
default to a zero error radius. A refinement estimate is not a bound. No
`Production` certificate, existing European `Iv.Root`, weighted enclosure or
certified aggregation may be manufactured from an estimated result. Financial
inequalities detect errors; clipping an inaccurate result to them is not
numerical acceptance. #109 must freeze acceptance criteria before scoring.

Price, exercise-region and early-exercise-premium diagnostics have separate
availability/uncertainty outcomes. The premium compares with European exercise
at the **same terminal instant and on the same stock/dividend/curve model**.
Subtracting the existing no-cash BSM price from a cash-dividend American price
is not the early-exercise premium. Numerical exercise decisions must be labelled
estimated or unresolved unless their stronger status has been established.

The intended output sequence is:

| Issue | Planned capability (none is delivered by #108) |
| --- | --- |
| #111 | Constant-coefficient, no-cash American call/put prices, including delayed opening; optional exercise/premium diagnostics and matching European terminal comparison |
| #112 | Cash dividends under the declared jump and event-side contract |
| #113 | Finite Bermudan schedules |
| #114 | Piecewise-constant coefficient schedules |
| #115 | Delta/gamma, then vega/rho/theta where defined and qualified |
| #116 | Justified certified subset, or an explicit estimated-only disposition |
| #117 | Uncertainty-aware scalar IV with nonidentifiability outcomes |
| #118 | Compiled requests and scenario execution for delivered combinations |
| #119/#120 | End-to-end performance and final capability qualification |

Delta/gamma vary the declared-side spot, holding the contract, schedules and
numerical target fixed. Vega is a parallel **additive** shift of annual
lognormal volatility levels; rho is a parallel additive shift of rate levels,
affecting both discount and drift, with q held fixed. Per-bucket risk is deferred.
At a zero volatility level, ordinary two-sided vega may be outside the domain;
any one-sided value must be explicitly named and qualified. No generic zero
Greek is implied by a successful boundary price.

Theta measures passage of valuation time with fixed absolute future events and
spot held fixed. Its model-year derivative is divided by 365 to match the
existing per-day sensitivity unit. An actual date-roll calculation follows the
adapter's declared day count; a one-day Actual/360 roll is not identified with
this 1/365-scaled derivative. Theta is a smooth valuation-time derivative, not a finite difference straddling a
dividend, exercise endpoint or coefficient event, and not economic P&L. At such
events #115 must return the declared one-sided quantity or an unavailable
outcome; pre/post event values remain different financial observations.

IV initially varies one constant annual sigma while all other inputs and exact
quote remain fixed. One price cannot identify a full volatility curve. A future
piecewise inverse needs an explicitly named one-parameter family and its domain;
none is implied here. Exercise plateaus, expiry and unresolved price uncertainty
must not produce a falsely precise unique root. Unlike existing European IV,
estimated American IV does not inherit a nearest-even root certificate.

Existing European enums and exhaustive outcome types are unchanged. New batch
and planner namespaces/types can represent these specifications additively;
inserting variants into existing public enums requires the normal
[compatibility review](stability.md). Model/calculation identity includes exact
input words, event phases, every curve/cash/exercise entry, dividend convention,
units, requested outputs/assurance and numerical policy. No numerical cache is
shared merely because requests have the same expiry or nominal grid size.

## 7. Identities and design examples

These are requirements for #110 and later extension fixtures, not claims that
an American implementation has passed them:

- Inclusion of exercise sets on the same model and terminal instant cannot
  decrease the exact value. Thus European <= Bermudan <= American when the
  respective sets are actually nested.
- V >= g(S) only if exercise is available at valuation. Delayed-opening American
  and future-only Bermudan contracts do not inherit that immediate-payoff floor.
- Values are nonnegative. For puts, V <= K max_(t in E) discount(0,t); this is
  not the bound K when rates may be negative.
- Without cash dividends, with q=0 and r>=0 throughout, the call reduces to the
  matching European terminal value. Negative r invalidates this shortcut.
- A one-instant exercise set equals the matching European stopping problem.
  Without cash and with constant coefficients on the existing BSM domain, it
  equals the existing BSM real model; numerical equality requires its own check.
- Zero cash amounts leave the stock path unchanged; collapsing their phase
  labels consistently leaves value unchanged. Adding cash amounts at a joint
  event is invariant under permutation of those components in real arithmetic.
- Scaling S, K and all nominal cash amounts by the same positive factor scales
  value by that factor. Keep times, coefficients and rights fixed; rounded
  rescaling is a different set of exact inputs if products are not representable.
- European put-call parity must not be used as an American identity. A
  cash-dividend comparator must share this jump rule and settlement convention.

Unless specified otherwise, examples below use r=q=sigma=0, valuation
`Regular(0)`, unit notional, and immediate-settlement call/put payoffs. Numbers
are exact targets or symbolic expressions, not measured runtime outputs.

| Input / exercise | Exact expected value or classification |
| --- | --- |
| S=105, K=100, terminal `Regular(0)` | Call 5, put 0 for all three styles with only that remaining right |
| S=100, K=90, cash 20 at 1/2, terminal `Regular(1)`, American open now | Call 10: exercise before the cash event |
| Same, Bermudan `[After_cash(1/2); Regular(1)]` | Call 0; adding `Before_cash(1/2)` raises it to 10 |
| Same, American opens `After_cash(1/2)` | Call 0; immediate payoff 10 at valuation is not a valid lower bound |
| S=100, K=110, cash 20 at T=1/2, European expiry `Before_cash(T)` / `After_cash(T)` | Put 10 / 30; no extra option-holder dividend is added |
| S=3, K=2, cash 5 at 1/2, European terminal at 1 | Paid cash 3, post-event stock 0; call 0, put 2 |
| S=3, K=2, cash components 1 and 4 at 1/2, same terminal | Same result as joint nominal cash 5; no exercise between components |
| S=100, K=110, cash 20 at 0, valuation `Before_cash(0)`, terminal `After_cash(0)` | Put 30; zero physical maturity is not the pre-event payoff 10 |
| Same event, valuation and expiry `After_cash(0)`, supplied ex-dividend S=80 | Put 30; do not subtract 20 again |
| S=0, K=100, r=-1/8, q=0, sigma arbitrary, American open now through T=2 | Put 100 exp(1/4), greater than K; wait until T |
| S=100, K=90, r=-1/8, q=sigma=0, American open now through T=1 | Call 10 by immediate exercise; matching European call 0 |
| S=100, K=90, r=1/4, q=1/8, sigma=0, American open now through T=8 | Call 250/9, attained at interior t=8 log(9/5), not at either endpoint |
| Cash at T but exercise uses `Regular(T)` | Invalid ambiguous event side |
| Duplicate identical Bermudan instant, or unsorted coefficient knots | Invalid specification; no silent sorting/deduplication |
| Finite negative r with no implemented solver support | Unsupported numerical capability, not invalid rate |

For the interior example, discounted call payoff is
100 exp(-t/8) - 90 exp(-t/4). Its derivative vanishes when exp(t/8)=9/5;
at that time it is 100(5/9)-90(25/81)=250/9. The positive payoff increases
before that point and decreases afterwards. This supplies a deterministic
counterexample to using only immediate and terminal zero-volatility payoffs.

An estimated-price response would report `Estimated_only { value; diagnostics }`
with separately labelled refinement/residual information. The current scalar
API cannot express Bermudan or varying-coefficient schedules. A future general
adapter must return an explicit unsupported outcome for undelivered capabilities;
a grid cap reached mid-solve returns a failure/incomplete outcome, not
the last iterate dressed as a price. Exact expiry/deterministic examples do not
by themselves authorize a runtime certificate or an implementation shortcut.

## 8. Sources, limits and handoff

The stopping quantity, event ordering, limited-liability choice, deterministic
derivation and ownership rules above are the project's specification. Supporting
source observations and exact versions are in
[the source record](evidence/american-contract/sources.json):

- Jherek Healy, *Pricing American options under negative rates*, arXiv
  **2109.15157v1**, §§2–3: rate/yield assumptions and multiple exercise boundaries.
- Jherek Healy, *The Pricing of Vanilla Options with Cash Dividends as a Classic
  Vanilla Basket Option Problem*, arXiv **2106.12971v1**, §§2 and 4.1: cash jumps
  and the need for an explicit low-stock dividend policy. Its approximation
  formulas are not adopted.
- QuantLib **79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c**, exercise definitions and
  dividend handler: reviewed as comparator conventions, not imported code or a
  numerical reference run. Its handler interpolates with a positive mesh floor
  and looks up one matching dividend entry. #110/#112 must explicitly reconcile
  joint events, low-stock boundaries, time conversion and settlement before
  claiming model-matched comparisons. No upstream behavior overrides this model.

The arXiv versioned HTML sections were inspected online; no PDF was acquired in
this design task and no paper bytes are redistributed. Later source acquisitions
must follow the [research preservation policy](research/README.md). Public
builds do not depend on a private paper archive. The source record distinguishes
inspection from source reuse, canonical execution and proved numerical bounds.

The [#109 solver design](american-solver-design.md) selects discretization, boundary
truncation, solver/backend ownership, acceptance budgets and the continuum
certification gate. #110 owns executable independent references and failure
controls. Neither a finite-difference grid
nor an empirical refinement estimate is part of the real model defined here.

This epic does not include futures-style margining, Black-76/displaced/normal
early-exercise models, stochastic rates/volatility, jumps other than specified
cash dividends, local-volatility surfaces, multiple factors, path-dependent
exercise, transaction costs, higher-order Greeks or a collection of approximation
engines. A no-dividend European reduction does not silently extend any of those
capabilities. Institutional acceptance remains under #15/#16/#17/#27.
