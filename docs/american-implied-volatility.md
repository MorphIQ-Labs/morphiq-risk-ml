# Estimated American and Bermudan implied volatility (#117)

`Early_exercise.Bsm.Implied_volatility` inverts one **constant annual lognormal
volatility**, keeping the original quote and every other model field, cash event
side and exercise right fixed. It replaces the admitted seed sigma. The result
is an estimated volatility interval, not a point root, a uniqueness claim, a
rigorous enclosure or the European nearest-even `Iv.Root` contract.

## Supported families and use

| Contract | Capability |
| --- | --- |
| Constant coefficients, no cash, call or put | American window or finite Bermudan schedule |
| Constant coefficients, liquidator cash dividends, call | Original before/after cash and exercise order retained |
| Cash put, including empty/zero cash specifications | `Unsupported_cash_put` |
| Piecewise coefficients | Distinct admission type cannot enter; no one-parameter curve family supplied |

With an admitted contract and an existing estimated pricing configuration:

```ocaml
let inverse pricing admitted side quote_value =
  let module I = Early_exercise.Bsm.Implied_volatility in
  let ( let* ) = Result.bind in
  let* quote = I.quote quote_value in
  let lower = Result.get_ok (Vol.lognormal 0.05) in
  let upper = Result.get_ok (Vol.lognormal 0.6) in
  let* settings = I.configure ~pricing ~lower ~upper
      ~width:0.005 ~max_evaluations:64 in
  I.solve settings admitted side quote
```

The private quote is finite and nonnegative, in the contract's currency units.
The typed finite sigma endpoints must be strictly ordered; zero is permitted.
`width` is a positive finite **full interval width**, in annual lognormal sigma,
not a relative error, price residual or half-width. The settings and successful
intervals cannot be forged. Price accuracy settings and volatility width are
separate requirements. Changing the quote by one binary64 word changes the
quantity inverted; successful repricing to the same rounded evaluator is not
an independent reference.

Each endpoint retains sigma, the entire estimated price and its uncertainty
indicator. The result includes requested width, price-evaluation count and
`Estimated_only`. No conversion to the European root or a price certificate is
provided. Admission types preserve unsupported model distinctions.

## Why these families are monotone

Fix a finite set of exercise rights and partition at every cash event. Over a
no-cash transition of length dt, stock is s times a positive lognormal factor
with mean exp((r-q)dt). Increasing constant sigma gives a mean-preserving spread
of this factor (couple it with an independent mean-one lognormal multiplier).
For a convex continuation value, conditional Jensen gives a nondecreasing
expectation with sigma. The transition preserves convexity in s. Positive
discounting and the maximum with the convex call/put payoff preserve convexity.
Backward induction therefore gives a nondecreasing price in sigma for no-cash
calls and puts. This is not strict monotonicity: immediate exercise and
volatility-independent contracts can produce plateaus.

For a call, value is also nondecreasing in stock. Composing a convex,
nondecreasing continuation with the liquidator map max(s-D,0) preserves both
properties. Applying the cash map and exercise maximum in the admitted event
order extends the comparison to cash calls. For continuous American windows,
approximate stopping by nested finite exercise grids, including both permitted
sides of each deterministic event. Between the finitely many events, stock and
payoff paths are continuous. Lognormal finite-horizon moments and the downward
cash map give uniform integrability of the discounted payoffs; the finite-grid
values converge to the continuous stopping supremum, preserving the comparison.
No strictness or all-input numerical accuracy theorem follows.

A put is decreasing in stock: composition with max(s-D,0) need not be convex.
An explicit terminal-after-cash put with S=D=100, K=10, r=q=0, T=1 has value
`10 - Call(S,100,sigma) + Call(S,110,sigma)`. Independent Arb evaluation gives
10 at sigma=0, about 6.354416058 at sigma=0.5, and 9.999691258 at sigma=8.
The function decreases then increases, so quotes such as 8 have multiple roots.
This valid terminal-only American/Bermudan example defeats general cash-put
bisection. Its original-input interval evidence is retained in
[references.json](evidence/american-iv/reference-v1/references.json).

## Numerical classification and termination

For each estimated price, sum the observed refinement change, maximum roundoff
indicator and boundary-arithmetic indicator with outward arithmetic. With no
refinement record the refinement component is zero (analytic reduction).
Classify a price below/above the quote only when its entire indicator band is
strictly below/above. These empirical indicators do not certify the real PDE
price. Carrying them into inversion avoids discarding known uncertainty; it
does not turn them into rigorous bounds.

Safeguarded point-price interpolation proposes interior probes, with endpoint
spacing and a midpoint every third step to prevent stagnation. The first
overlapping probe permits one bounded pair of nearby probes; quarter probes
remain the fallback. Only strict full-band signs may move an endpoint. If the
fallback cannot improve the bracket, return `Price_uncertainty_or_plateau`.
The [proposal derivation](evidence/american-iv-optimization/proposal-design.md)
explains the placement rules. A proposed location cannot establish a root or
an endpoint sign; no vega lower bound is assumed. A success requires outward full-width
comparison with `width` and rechecks both strict signs. Increasing-sigma prices
with disjoint reversed bands return `Inconsistent_prices`. Overlapping bands
cannot establish a violation. No sample history or mutable cross-request cache
is retained.

| Outcome | Meaning |
| --- | --- |
| `No_solution` | Proved quote below an available immediate payoff, above a global cap, or different from an enclosed volatility-independent value |
| `Non_identifiable` | Exact equality at expiry, absorbing stock or a zero-strike constant-price boundary |
| `Estimated_outside_search_range` | Endpoint indicator excludes the quote on one side of the supplied finite range; no global nonexistence claim |
| `Price_uncertainty_or_plateau` | Price information cannot identify a sufficiently narrow interval; may also contain a boundary root |
| `Pricing_failed` | Owning price resource, accuracy or arithmetic refusal; never a sign |
| `Evaluation_limit` / `Unrepresentable_progress` | Work exhausted or no binary64 interior sigma; no last-iterate success |
| `Cancelled` | Cooperative cancellation; caller callback exceptions still propagate |

For any allowed stopping time, conservative mathematical caps are
`S exp(max(0,-q)T)` for calls and `K exp(max(0,-r)T)` for puts. The discounted
cash-adjusted stock has downward jumps; the nonnegative normalized stock
supermartingale and bounded stopping give the call cap. The put payoff is at
most K and the greatest possible discount factor gives its cap. Cap arithmetic
is enclosed; inability to enclose it never proves nonexistence. The immediate
intrinsic floor is used only with no cash and opening=0, avoiding invented
rights at delayed openings or ambiguous cash instants.

Expiry uses original spot/strike and, when admission orders opening after a
valuation-time cash event, original cash amounts and the liquidator jump.
S=0 gives a zero call; a no-cash put chooses earliest exercise for r>=0 and
expiry otherwise. K=0 gives a zero put; a no-cash call chooses earliest exercise
for q>=0 and expiry otherwise. Exact equality yields nonidentifiability, strict
inequality no solution, and enclosure overlap uncertainty. Cash puts have already
been rejected; K=0 cash calls are conservatively left to the numerical solver.

## Work and accuracy settings

The supplied pricing step, policy-solve and row-visit allowances cover the entire
inverse: each is divided by `max_evaluations`, rounding down. Each price receives
that share, so aggregate work cannot exceed the original limit. Unused shares
are not redistributed. Zero shares fail explicitly. Node and policy-iteration
caps remain per solve; the workspace allowance reserves 64 KiB for a fixed
number of live inverse observations. It is not an allocation-volume or RSS cap.
No history proportional to the call count is allocated. Expiry cash scanning
checks the original row budget and cancellation.

Cancellation is checked before evaluations, within the existing price checks,
between search steps and before success. There is no hard wall-clock deadline.
Very large work allowances can increase conservative price roundoff indicators;
more permitted work is not guaranteed to increase numerical availability.

## Independent qualification

The [frozen protocol](evidence/american-iv/protocol.md) and independent references
were committed before runtime edits. Twenty-four no-cash analytical rows and
two terminal-after-cash call rows invert exact fixed quote words with Arb at
256/512 bits and 120 rational bisections. The cash identity uses exact K+D only
inside the independent reference, without changing runtime event semantics.
Four genuine stopping put rows use an original lattice at 1024/2048/4096 steps
and QuantLib at 256/512/1024, revision
`79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c`. The union of empirically expanded
refined root bands is an independent comparison, not a continuum proof.
All raw inputs, outputs, provenance and hashes remain in
[reference-v1](evidence/american-iv/reference-v1/manifest.json).

The initial 128-cell, two-domain-expansion, price-target-1, width-0.05 campaign
accepted 24 intervals and refused six prices on accuracy. The explicit
[domain-refinement addendum](evidence/american-iv/refinement-addendum.md) retains
that outcome and the incompatible node/workspace attempt. Three expansions,
with the original 8192-node/8 MiB limits and unchanged numerical targets,
accepted all 30; the tighter width-0.005 native challenge also accepted all 30.
Each accepted interval must contain the entire independent reference interval,
meet exact-rational full-width and endpoint-sign checks, and stay within 64 calls.
This small corpus is engineering evidence, not general calibration acceptance.

Ordinary CI exercises the 24 analytical rows, public type rejection, invalid
requests, budgets, uncertainty, plateau, finite-range and mathematical boundary
outcomes, exercise identity, cancellation and callback exceptions. Six expensive
rows are explicitly marked manual; no skipped row is an accuracy pass.
Default CI remains five jobs and seven core mutants.

Portfolio integration remains #118; further allocation/latency work is #119,
and source-artifact/cross-platform capability qualification is #120. General
cash-put inversion, one-parameter curve inversion and rigorous general stopping
inverse enclosures remain outside this API. No main release is implied.

## Executed validation and measured cost

Runtime source is `566e19096227dc920822660eb68c68cf89f1eef2`; final failure
controls are `c3f5f5e5a3b7801466fa8ddfefe1fc843ca04a9b`. The [qualification summary](evidence/american-iv/qualification/summary.json)
and [hashed raw records](evidence/american-iv/qualification/manifest.json) retain
commands, complete outcomes, failed attempts, source/compiler identity and timing.
No runtime changes followed the implementation commit; subsequent changes are
controls, documentation and evidence. Development/release ordinary suites,
format/install, and the final focused native/bytecode/type controls passed.

All 30 width-0.005 intervals contain their entire independent references in
native, bytecode and external installed-package native/bytecode clients. Complete
serialized outcomes agree across all four runs. This is local platform evidence;
CI's ordinary three-platform checks do not execute these six manual PDE rows.
The standalone source-artifact campaign remains #120.

Eleven affected mutation mechanisms are rejected after successful builds and
clean baselines. The first exercise-schedule and cancellation probes survived: terminal-only
rights cannot distinguish the two models, and pricing cancellation does not
exercise volatility-independent boundary dispatch. New three-date Bermudan
and pre-boundary cancellation controls reject both faults. The initial survivors
and successful targeted follow-up are retained. These probes establish
sensitivity of their witnesses, not universal numerical correctness.

Five fresh processes, each with one warmup per measured path and three rounds,
measure the fixed exact quotes at sigma range [0.05,0.6], full width 0.005,
128 space/time cells, three domain expansions and price refinement target 1.
Analytical rounds contain 20 requests; PDE rounds contain one. End-to-end includes
model admission and quote validation, with an already built configuration. Single
price cost is at sigma 0.2 under the corresponding per-evaluation work limits.
Primary numerical validation and mutation workers completed before timing. Hardware/load and raw variation
are retained; this shared-host measurement is not a deployment or tail-latency SLO.

| Case/path | Median wall time | Allocated bytes/request |
| --- | ---: | ---: |
| American put / end-to-end | 1125.654 ms | 121,295,904 |
| American put / price | 124.460 ms | 13,475,224 |
| American put / solve | 1123.202 ms | 121,295,432 |
| No-early call / end-to-end | 0.803 ms | 1,065,158 |
| No-early call / price | 0.088 ms | 116,662 |
| No-early call / solve | 0.813 ms | 1,064,686 |
| Cash terminal call / end-to-end | 1720.264 ms | 320,392,192 |
| Cash terminal call / price | 189.435 ms | 35,601,424 |
| Cash terminal call / solve | 1683.622 ms | 320,391,264 |

Allocation is cumulative OCaml allocation, including inverse price evaluations;
it is not retained workspace or peak RSS. General inverses intentionally reuse
no value surfaces across candidate sigma. Their cost makes dependency-safe
preparation reuse and pricing allocation a concrete #119 follow-up. Batch and
scenario integration (#118) must preserve whole-inverse budgets and per-row
estimated intervals/refusals, without promoting them to certified roots.

The final protocol audit found that the primary corpus exercised negative rates
but only nonnegative yields. A separate [two-quote Arb supplement](evidence/american-iv/negative-yield/manifest.json)
adds terminal call/put inverses with q=-0.02 and opposite-sign rates, each under
American and Bermudan admission. Its 256/512-bit, 120-step exact-quote inverses
were generated before adding the four checks. Native/bytecode development/release
checks and installed clients passed. This supplement was added after timing,
with no runtime or benchmark changes; its source is `624eb79da0c516887bc2c188db67ef0102140651`.
The original 30-row campaign and all its failures remain unchanged. Offline
manifest/export controls cover both corpora.

To reproduce the primary local campaign after building, run
`_build/default/test/american_iv.exe docs/evidence/american-iv/references.tsv all 0.005 3`.
Use `scripts/american_iv_campaign.py --minimum 30 --same LOGS...` to check complete
ordered outcomes and replay identity. `scripts/check_american_iv.py` checks both
reference manifests offline. Reference generators require the recorded optional
Arb/QuantLib environment; ordinary builds and CI do not.
