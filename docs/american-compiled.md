# Compiled American and Bermudan requests

`Batch.American` and `Planner.American` are additive public orchestration APIs for
`Early_exercise.Bsm`. They use its existing models, numerical configuration,
estimated outcomes, supported exact reductions and explicit refusals. They do
not introduce a new pricing method. The [frozen protocol](evidence/american-compiled/protocol.md)
defines the implementation and measurement scope.

## Typed operations and fixed batches

A fixed batch takes immutable, already-admitted scalar models. Compilation
snapshots the request array, validates IDs and count/workspace policy, and records
canonical identity. It reuses those admissions on every execution. Numerical
acceptance happens at execution, separately for every requested operation.

```ocaml
module A = Morphiq_risk.Early_exercise.Bsm
module B = Morphiq_risk.Batch.American

(* admitted and pricing come from A.admit and A.configure. *)
let compile_put admitted pricing =
  B.compile
    ~limits:{ max_requests = 1; max_outputs = 1;
              max_solver_workspace_bytes = pricing.A.limits.max_workspace_bytes }
    [| B.Request {
         id = "put-1"; model = B.Constant admitted;
         side = Morphiq_risk.Side.Put;
         outputs = [B.Output (B.Price {
           pricing; premium = false; exercise_regions = false })]
       } |]
```

The [complete runnable example](../examples/american_batch.ml) constructs both
configuration and admission. `B.execute plan` returns fresh ordered rows. Match each `B.Outcome (operation,
result)` to recover its typed payload:

| Operation | Result | Models |
| --- | --- | --- |
| `Price` | `estimated_price`, including bounded diagnostics | Constant or piecewise |
| `Greeks` | `estimated_greeks`, with separate per-quantity outcomes | Constant or piecewise |
| `Implied` | Estimated constant-sigma interval | Constant only |
| `Certified_price` | Private certified reduction price | Constant only, scalar guard still applies |

The model parameter rules out piecewise IV/certification at compile time. An
estimated price cannot become a certificate. General stopping and Greeks remain
estimated-only. Cash-put IV remains unsupported; a cash record, including an
empty one, retains its scalar capability restrictions. A successful Greek bundle
may still contain unavailable or unresolved individual quantities. A certified
operation may fail for an unsupported stopping regime or an unmet error limit.

Scalar configurations and Greek/IV settings are readable private records/lists.
Use their validating constructors; callers cannot fabricate or update them.
Greek units remain spot delta/gamma, vega per unit annual volatility, rho per unit
annual rate, and theta per calendar day as defined by the scalar API. Selecting
ACT/360 for a dated plan does not redefine scalar theta's per-day unit.

## Dated plans

`Planner.American.compile` takes a frozen portfolio, spot factors, `Scenario.t`,
base day, day count, cash-at-valuation convention and resource policy. A position
carries its own typed constant/piecewise model, output list, fixed expiry and
exercise/cash dates. Different positions may request different outputs. The
[executable engineering example](../bench/american_compiled.ml) builds both fixed
and dated plans and matches their complete results against explicit scalar calls.

Dates are civil-day ordinals in [-1e9,1e9] on the qualified 64-bit runtimes.
Offsets are nonnegative, bounded by `Scenario`. Each remaining scalar time is
computed as `float (event_day - valuation_day) /. denominator`, once, with
365 for ACT/365F or 360 for ACT/360. These generated binary64 words define the
scalar model; a previously rounded year fraction is never rolled by subtraction.
The integer differences are exactly representable in binary64 on this domain.

- Spot and lognormal-volatility shocks start from the frozen snapshot. A
  volatility shock applies independently to each original retained coefficient
  level. Rates, yields, quotes and contractual dates stay fixed.
- The current coefficient is the last level whose knot is at or before valuation.
  Future knots retain their original dates. Knots are strictly inside the original
  lifetime, so expiry uses the last left level.
- American opening becomes the later of its contractual opening and valuation.
  Bermudan rights strictly before valuation are removed; rights at valuation
  remain. Neither rolling nor numerical grid refinement creates exercise rights.
- Past dividends are removed. A dividend at valuation remains in the scalar
  cash specification with `Before_payment` or `After_payment` explicitly selected.
  The supplied shocked spot already represents that side. The adapter does not
  debit past cash or debit a current after-payment spot again.
- At a cash date, `Before_cash` precedes `After_cash`. Valuation after the terminal
  exercise instant produces `Post_expiry`; no payoff or settlement is fabricated.
  Off cash dates the only valid event side is `Regular`.

Original schedules and the original base model are validated before filtering,
even if every requested scenario rolls past a malformed event. Cash and Bermudan
rights must lie in [base,expiry]; an American opening may precede base. Original
base validation uses before-payment valuation to preserve all same-day rights;
each actual row then uses the selected convention. Bad shocked inputs remain
per-output typed admission failures. Unsupported scenario coordinates and missing
factor bindings are structural compilation errors. Quantity and currency are
metadata; emitted scalar values are unweighted. There is no aggregate, settlement
or economic P&L mode on this surface.

## Identity, reuse and memory

`explain` exposes the stable plan ID, convention, workload and buffer bounds;
`manifest` retains canonical exact-word inputs/settings plus runtime metadata.
The versioned encoding includes model kind, all original input words and dates,
event sides, cash-presence distinction, operation order, Greek units/bumps/limits,
IV quote/search policy, assurance kind, scenario order, valuation convention,
metadata and resource limits. IDs are not numerical certificates or security
capabilities. They are not a portable serialized executable-plan format.

Fixed batches reuse immutable admitted models. Dated plans freeze arrays and
factor bindings; each row prepares/admit its rolled model once for all requested
operations. Compatible prepared grids, event schedules and coefficients continue
to be reused inside their existing scalar owners, with their existing dependency
checks. Mutable solver scratch belongs to one call/worker. This change does not
share a factorization or solved surface across rows. Any such future cache must
check the entire grid, coefficients, step size, event/policy and payoff dependency
set; matching contract IDs alone is insufficient. Cross-row caching and workload
crossover optimization remain [#119](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/119).

Checked arithmetic bounds positions, market factors, scenarios, output operations,
tiles and in-flight result slots. `max_schedule_events` bounds the sum of cash,
exercise and coefficient records **per position**, before copying them. An
American opening counts as one event. A Greek bundle counts as one output slot,
containing its explicitly requested per-quantity results and scalar diagnostics.
Zero-output rows still reserve one buffer slot for metadata. The reported bound is
`min(instruments,tile_rows) * min(max_workers,tiles) * max(1,max_outputs_per_row)`.
No full Cartesian result cube is constructed by compilation or streaming.

`max_solver_workspace_bytes` caps each operation's configured PDE allowance.
It is not a bound on cumulative allocation, heap size, RSS, private certificate
arithmetic or retained output diagnostics. Scalar work limits still bound each
solve/refinement/inverse; multiple operations execute separately. Peak working
storage also includes up to `workers` scalar calls, frozen plan/schedule storage,
retained diagnostics in buffered rows and whatever the caller keeps in its sink.
Concurrent executions multiply these costs. Fixed batches return the entire
explicitly bounded result array; use the planner for bounded streaming.

## Execution, cancellation and failures

The planner uses the existing bounded fork/join executor. Only the coordinator
calls the sink, in scenario-major, original-position order. Every execution gets
its own scratch, token and destination; concurrent uses share immutable inputs.
The caller must not mutate input arrays concurrently with compilation.

`Row` carries stable scenario/instrument/factor IDs and typed operation outcomes.
`Finished` carries a stop reason and sink-accepted row/calculation counts. Each
counter advances only after that row's sink call returns `Ok ()`. If a row's
scalar operation fails, it is still a committed result when accepted by the sink.
An interrupted row is not emitted. Cancellation checks reach scalar work and
calendar preparation; workers join before return and computed but uncommitted
rows are discarded. Cancellation responsiveness also depends on scalar checkpoint
granularity and controller scheduling. There is no fixed latency guarantee.

Sink refusal/exception returns `Sink_failure` with the previously accepted prefix;
no `Finished` event is guaranteed after a broken sink. Worker exceptions become
explicit worker failure. Invalid worker counts, empty plans, foreign tiles and
post-expiry rows retain distinct outcomes. `evaluate_tile` returns a fresh array
for a tile belonging to that exact plan and has no cancellation token.

The direct `Batch.American` API has no streaming completion marker: its callback
is forwarded to each scalar operation and cancelled operations return their
scalar failure. Callback exceptions propagate. It does not claim that the
returned array is a successfully priced prefix.

## Qualification

See [the qualification report](results-american-compiled.md). Contract tests cover
scalar equivalence, date/payoff controls, immutable/concurrent use, worker order,
resource rejection, cancellation and sink prefixes. Negative compilation tests
exercise model/assurance/configuration boundaries. Mutation witnesses exercise
those numerical/precondition properties; replay equality is compatibility evidence,
not independent model accuracy. Scalar numerical owners and their existing
independent references remain unchanged. Final source-artifact and broader
workload qualification remain #120 and #119 respectively.
