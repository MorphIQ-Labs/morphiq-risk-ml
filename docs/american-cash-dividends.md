# Scheduled cash dividends

`Early_exercise.Bsm.admit_cash` extends the scalar American model with scheduled
nominal cash payments and explicit event sides. Continuous yield remains a
separate input. Do not encode the same payment in both yield and the schedule.
The [financial contract](american-model-contract.md) and
[frozen numerical policy](american-solver-design.md) govern this implementation.
Every returned price remains **Estimated_only**.

Run the [complete cash pricing example](../examples/american_cash_price.ml) with
`dune exec examples/american_cash_price.exe`.

## Admission and event sides

Supply the usual `Bsm.inputs` and a `cash_specification`:

```ocaml
let cash : Early_exercise.Bsm.cash_specification = {
  valuation_side = Regular;
  opening_side = Regular;
  expiry_side = Regular;
  dividends = [| { time = 0.5; amount = 5. } |];
}
(* Early_exercise.Bsm.admit_cash inputs cash *)
```

Times are original binary64 year offsets from valuation. Amounts are finite,
nonnegative and in the same currency units as stock/strike. The schedule must
already be ordered, with every date in `[0,T]`; equal dates are allowed. Admission
copies the array and the accessor returns another copy. All input validation
precedes pricing, including zero maturity or zero stock. Admission allocates in
proportion to the supplied schedule; numerical work limits apply to pricing.

Use `Regular` exactly where there is no cash event. At an event use
`Before_cash` or `After_cash`, including at valuation, opening and expiry.
Even a zero payment has event identity. Physical time orders instants first;
`Before_cash` precedes `After_cash` at the same date. Valuation must not follow
opening, and opening must not follow expiry. An empty schedule uses the
ordinary no-cash route.

For example, at zero physical maturity with S=105, K=100 and cash 10, a call
worth 5 before the event is worth 0 if exercise opens only after it. A put
worth 0 before the event is worth 5 after it. If valuation is already
`After_cash`, supplied stock is ex-dividend: the event is not paid again.
Expiry `Before_cash` excludes the jump; expiry `After_cash` includes it and
any eligible pre-event exercise decision. No extra option-holder cashflow is added.

## Jump, stepping and diagnostics

All amounts at one date form one joint original-input sum D. The financial
transition is `J_D(S) = max(S-D,0)`: zero stock is absorbing, including when
cash exceeds stock. The engine encloses original sums/subtractions using the
existing expansion arithmetic. An overflowing or unresolved joint sum is a
numerical failure, never invalid financial admission or a silently rounded model.

Backward processing first permits eligible post-event exercise, evaluates that
value at `J_D(S)`, then permits eligible pre-event exercise. Every cash date and
exercise opening splits the time grid. No exercise is allowed between coincident
payment components. With zero volatility, original-input deterministic stopping
checks segment endpoints, both eligible event sides and interior `q*S(t)=r*K`.
A supremum approached immediately before an event remains an admissible stopping
value when the exercise window is already open.

Cash interpolation is positive piecewise linear interpolation, with explicitly
checked convex weights and a real zero node. A separate pre-jump sampling grid
evaluates the incoming PDE interpolant at the mapped stock; that sampled jump
function is then projected onto the PDE grid. Independent mapping refinements
use three sampling resolutions with PDE space/time fixed at their finest levels;
space refinement holds mapping resolution fixed. On matching fine grids, the
second projection is the identity. This extra projection intentionally exposes
mapping sensitivity, including at kinks.

Both event differences must meet the same epsilon/8 criterion as the space/time/
domain differences. The latest event difference also enters the epsilon/2 sum.
No frozen #109 threshold is widened. `refinement.event_changes` is `None` for
ordinary no-cash requests. `mapping` reports event applications across all solves,
maximum visited interpolation-cell width and enclosed interpolation arithmetic
error. These are diagnostics, not a price-error certificate or exercise-boundary
proof. Analytical cash routes have no sampled mapping diagnostic.

Immediate-payoff and global cap checks remain in force when applicable. Cash
requests do not use the no-cash European lower bound. The optional matching
cash-European premium currently returns `Unavailable`; a dedicated comparison
and broader numerical qualification remain tracked in #120. Exercise regions
at valuation are unavailable if the opening instant has not arrived, including
valuation-before/opening-after at the same physical date.

Bermudan schedules, varying coefficients, cash Greeks/IV and planner adapters
remain separate work. The API exposes no alternative dividend convention;
escrowed dividends and spot adjustment are not substitutes for this model.

## Work and memory

The same call-owned policy solver, caps and cancellation checkpoints apply.
Cash pricing reserves an additional `48*max_nodes + 1024*number_of_payments`
bytes beyond the ordinary conservative workspace reservation. This covers the
additional grids, map samples, event lists/enclosures and bounded temporaries;
it is not cumulative allocation or RSS. Schedule preparation and deterministic
cash visits share the request row budget. An event refinement adds two
boundary-pair configurations to the seven no-cash configurations, and each
additional event creates time slabs. Zero payments still split slabs and execute
mapping. Costs therefore depend on schedule, not just option count.

## Evidence and limits

The [30 original-word cases and protocol](evidence/american-cash/protocol.md)
were frozen in signed commit `4b10811` before reference or runtime execution.
Independent and canonical baselines were committed as `47f871f` before runtime
changes. The independent engine uses discounted three-point Gaussian quadrature,
positive interpolation and stopping decisions, without a PDE matrix or policy
solve. Its refinement radius is empirical. Supplementary 80/160-digit analytical
and fixed-discrete quadrature checks are precision agreement, not certificates;
exact-rational witnesses cover original joint sums and the liquidator boundary.

QuantLib is pinned to `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c`, reusing the
previous source-bound build after verifying all three artifact hashes. Its
unmodified Spot dividend engine floors mapped stock at its first positive mesh
node and selects one matching dividend entry. Those are different conventions.
An original research adapter supplies our joint liquidator jump, explicit zero
value and both event-side stopping decisions to QuantLib's FDM solver. The
adapter extends linearly between zero and its first positive node and retains
finite-domain error. Endpoint events, zero boundaries and deterministic cases
are explicitly excluded from this canonical adapter. No QuantLib implementation
is copied or linked into the OCaml runtime.

Reference/runner source hashes, every raw result, exceptions and per-case scoring
are retained in [the evidence directory](evidence/american-cash/). The original
baseline remains in `47f871f`; the later export fixes advisory radius-eligibility
metadata to use the frozen radius criterion (the first export used full width),
and corrects CLI help. All canonical/quadrature raw numerical streams remain
byte-identical. Acceptance always uses the shared independent scorer's radius
rule, never that advisory metadata. An initial scorer integration error rejected
the reference-kind label before scoring; its raw stream is retained separately.

Reproduce without private data or reference-tool dependencies:

```sh
opam exec --switch=morphiq-risk-ml -- dune build test/american_cash.exe
python3 scripts/check_american_cash.py \
  --executable _build/default/test/american_cash.exe \
  --mode primary --output /tmp/new-cash-campaign
# Add --refined and/or select --mode loose explicitly.
```

Ordinary CI runs native/bytecode controls, the initial primary corpus, provenance
and scorer failure controls. Larger campaigns, optional mutants and measurements
are retained local evidence. No default CI job or seven-mutant core is expanded.
