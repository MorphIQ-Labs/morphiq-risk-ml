# Certified reductions and general stopping limits (#116)

`Early_exercise.Bsm.Certified` certifies a deliberately narrow set of exact
reductions. The finite-difference American/Bermudan solver and its Greeks remain
estimated-only. A small residual, stable mesh sequence or successful European
comparison is not a continuum stopping-value bound.

## Delivered contract

Use the existing constant-input admission, then a separate validated absolute
currency-error limit:

```ocaml
let certified_call admitted =
  let module C = Early_exercise.Bsm.Certified in
  match C.absolute_error_limit 1e-10 with
  | Error error -> Error error
  | Ok max_error -> C.price admitted Side.Call ~max_error
```

A successful private record contains `value`, outward `absolute_error`, and the
specific `reduction`. Both numerical fields are finite, the error is nonnegative
and meets the requested limit. The limit is a private validated type, distinct
from the estimated solver's refinement configuration. Negative/nonfinite limits
are `Invalid_accuracy`; zero demands an exact certificate. Input validation
remains with `Bsm.admit` / `admit_bermudan`, before any numerical dispatch.

| Reduction | Enforced applicability | Exact quantity evaluated |
| --- | --- | --- |
| `Expiry` | No cash specification; T=0 | Positive part of the original exact spot/strike difference. |
| `Terminal_only` | No cash specification; opening=expiry | Matching European payoff expectation over the full original horizon T. Both call/put and signed rate/yield are supported. |
| `No_early_exercise_call` | No cash specification; call, q=0, r>=0 | Matching European call. American windows and finite Bermudan rights retain their declared identity. |

Any cash record, including an empty schedule or zero payments, returns
`Unsupported_capability Cash_specification`. General stopping outside these
reductions returns `Unsupported_capability General_stopping`, regardless of how
large an error limit the caller supplies. Negative yield is conservatively
outside the no-early-exercise guard even where a broader theorem could apply.
The distinct `Piecewise.admitted` type cannot enter this API. There is no new
American dispatcher in `Production` and no conversion from an estimated price
or Greek to this certificate.

`Arithmetic_unresolved` identifies an enclosure/domain failure;
`Accuracy_exceeded` identifies a finite bound larger than the requested limit.
Neither contains a fallback price. Cancellation is checked before work and
before returning the evaluation; callback exceptions propagate. There is no
PDE grid, refinement loop or caller-supplied PDE budget on this bounded
analytical path. Its component algorithms have the existing fixed work/domain
limits; an exhaustion/domain witness must fail explicitly. It is not a promise
of a particular wall-clock cancellation latency.

## Reduction derivations

### Expiry and terminal-only rights

With no cash event, T=0 has one available remaining instant because admission
requires 0<=opening<=T. Its real value is `max(±(S-K),0)`. Subtraction and sign
selection operate on the enclosure of original words; subtraction is not first
rounded into a substitute payoff.

For opening=T>0, the American exercise set is {T}. An admitted no-cash Bermudan
list begins at opening, ends at T and is strictly ordered, so opening=T also
forces one right. Its stopping supremum is the single terminal expectation.
The European horizon is **T**, not T-opening; the stock evolves before exercise
becomes available. Drift, discount, yield and volatility are unchanged original
inputs. This equality introduces zero exercise, discretization, truncation,
spatial-domain, mapping and solve errors.

### No-cash, zero-yield calls with nonnegative rate

For constant q=0, let `M_u=exp(-r*u) S_u` and
`Y_u=exp(-r*u)(S_u-K)+ = (M_u-K exp(-r*u))+`.
For finite constant volatility and finite horizon, M is a nonnegative
square-integrable martingale. This includes sigma=0 and the absorbing S=0
case. For deterministic u>=t, conditional Jensen gives

    E[Y_u | F_t] >= (M_t-K exp(-r*u))+ >= (M_t-K exp(-r*t))+ = Y_t,

because K>=0 and r>=0. Thus Y is a submartingale. Its stopped family on [0,T]
is uniformly integrable: Y<=M and bounded-horizon lognormal M has finite second
moment (Doob's inequality supplies an integrable supremum). Optional sampling
therefore gives E[Y_tau]<=E[Y_T] for every admitted bounded stopping time tau.
Terminal exercise is always allowed, so the supremum equals E[Y_T]. The result
holds for every admitted opening window and every finite no-cash exercise list;
adding numerical steps is irrelevant. There is no dividend jump or cash-side
interpretation to pass through this proof.

At r<0, the discounted strike is increasing and the second inequality reverses.
For q!=0 the stated martingale identity changes. A put is not this submartingale.
These are applicability conditions, not measured heuristics. The corpus includes
deterministic immediate-exercise counterexamples for a put, a negative-rate call
and a positive-yield call. Negative-zero inputs denote zero and pass the guard;
the neighboring negative rate or nonzero yield does not.

### Original-input arithmetic and boundary admission

Strictly positive spot/strike use `Production.Bsm`'s original-input price
certificate. No rescaled spot, effective volatility, forward rounded by the
Fast API, or shortened time is supplied as the model. The existing certificate
covers the European arithmetic, analytic tails and final binary64 rounding;
the reduction adds exactly zero model error. Its existing applicability and
arithmetic limits remain in force.

European BSM admission requires positive spot and strike. The American owner
also admits zero, so its boundary reductions use the existing `Enclosure`
primitives directly. At expiry this is enclosed positive-part subtraction.
For terminal-only exercise, S=0 gives put `K exp(-rT)` and call zero; K=0 gives
call `S exp(-qT)` and put zero. The same formulas apply when a zero boundary
satisfies the no-early-exercise-call reduction. Products, exponents and final
radius use original words and outward arithmetic. A mathematically zero leg
does not evaluate an unnecessary exponential. Direct boundary exponentials have
the enclosure's |argument|<=256 limit; positive-spot/strike model exponentials
have the existing composition's |argument|<=1024 limit, plus its other guards.
No overflow, nonfinite radius or unresolved sign is accepted.

Certificates do not promise correctly rounded prices, certified Greeks,
certified early-exercise regions or a nearest-even implied-volatility root.
The source-bound tests are finite evidence under the repository's arithmetic
environment; they are not formal verification or independent human approval.

## Executed general-stopping feasibility and remaining obligations

The [offline probe](../scripts/check_american_certification.py) and its
[retained results](evidence/american-certification/feasibility.json) exercise
three original counterexamples/limitations against the independently enclosed
continuum call. These are research experiments, not claims that the current
estimated solver returns the deliberately constructed bad candidates.

1. With S=K=100 and r=0, the real elementary put enclosure [0,100] has midpoint
   radius 50, versus the existing engineering target 100/65536 and the new
   corpus's currency limit 100*2^-36. It is valid but uninformative at these
   targets; no coarse midpoint is silently returned as a useful certificate.
2. For r=q=0, sigma=the exact binary64 .8, T=1 and nodes [0,100,200], an implicit
   one-step call LCP with fixed upper boundary 100 has diagonal `1+sigma²`, RHS
   `50*sigma²`, and exact positive solution RHS/diagonal. Its rational residual
   is exactly zero while the independent continuum call is strictly larger.
   Boundary, space and time errors remain unqualified. Zero discrete solve
   error cannot bound their sum.
3. The candidate `w(t,s)=(s-100)+` dominates the terminal payoff and obstacle,
   has linear growth, and has zero PDE defect on each smooth patch for r=q=0.
   Yet w(t,100)=0 is below the strictly positive continuum call. The convex
   spatial join has derivative jump +1 and an unaccounted positive local-time
   contribution. Off-kink checks cannot validate the global supersolution.

The [#109 verification route](american-solver-design.md#7-full-price-enclosure-feasibility-and-the-116-gate)
remains a possible future method, not a delivered general certificate:

| Contribution | What is established | Gap before general certification |
| --- | --- | --- |
| Stopping model | Original-input, exercise and event contract | A proposed bound must honor that same model and every admitted event side. |
| Solve/coefficient arithmetic | Matrix/stability derivation and discrete diagnostics | Outward original coefficients, residuals and propagated inverse/comparison uncertainty. |
| Space and continuous exercise | Numerical refinements only | A proved global discretization bound, or globally verified super/subsolutions with feasible-strategy expectation bounds. |
| Infinite stock domain | Coarse real payoff/stock caps | Valid exterior patch/tail estimates and junction conditions, propagated through the interior. |
| Cash mapping | Monotonicity/Lipschitz derivation and empirical refinements | Outward joint jumps, incoming nodal errors, kink/interpolation bounds and discount accumulation. |
| Supersolution corrections | Smooth verification argument | Global derivative bounds, join/local-time signs, event and terminal dominance, growth and integrability. |
| Useful accuracy | Executed exact-reduction widths | A complete general bound meeting declared currency limits without replacing unknown terms by zero. |

**Engineering disposition:** adopt the guarded exact reductions; retain the
finite-difference/general stopping and Greek capability as estimated-only.
This is not an impossibility result for stronger certification. It completes
#116's supported-subset/disposition gate while preserving the proof gaps for
future work under Epic #107. #117 must define its own inverse uncertainty and
identifiability contract; #118 cannot promote estimated batch rows; #120 owns
final source-artifact/cross-platform qualification. Institutional acceptance and
independent review remain separate.

## Qualification and reproducibility

The [frozen protocol](evidence/american-certification/protocol.md) predates
implementation and scoring. [Reference v2](evidence/american-certification/reference-v2/manifest.json)
contains 354 identified cases: 337 independently enclosed reduction values,
16 explicit unsupported cases and one finite arithmetic-domain failure.
Each successful runtime interval must contain **both exact rational reference
endpoints**; there is no ULP allowance or subtraction of reference uncertainty.
Zero/tight limits, cancellation and type rejection exercise the public boundary.

References use python-flint 0.9.0 / Arb at recorded precision, with exact rational
payoffs where possible. The [generator](../scripts/generate_american_certification.py)
uses original binary64 inputs and an independent erfc-based formula, without
calling the runtime. Reference precision/attempts and complete source/payload
hashes are retained; ordinary builds consume committed endpoints and need no
Arb installation. The official [Arb interface](https://python-flint.readthedocs.io/en/stable/arb.html)
defines outward endpoints and exact mantissa/exponent extraction.

The preliminary reference retained a too-wide finite-precision interval for
extremely sparse expiry subtraction. V1 replaces those analytically exact
payoffs with exact rational endpoints before implementation. V1's exhaustion
input rT=512 was then found inside the documented model range (<=1024): v2
corrects that witness to 2048. V1, the preliminary data, their original generator
bytes and prototype failures remain retained. No accuracy criterion or valid
certificate containment requirement was weakened.

The outcome counts, compiled-fault results, installed-client checks and source
identity of the completed candidate are recorded in the qualification evidence.
