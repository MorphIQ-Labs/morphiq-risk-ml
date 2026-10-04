# Fast-price scenario streaming

`Planner.Fast` compiles frozen portfolios, markets and scenarios for bounded,
ordered evaluation through the existing fast price kernels. It serves one
unweighted price per position/scenario pair. The successful value is a finite,
nonnegative approximation under the scalar model's documented accuracy scope;
it has no runtime error certificate. [Fast batch semantics](fast-batch.md)
own model admission and the numerical-result boundary.

The original `Planner` API continues to serve certified quantities and weighted
enclosures. Its signatures, plan encoding and manifests are unchanged.
Fast plans, tiles, rows and events have distinct public types. There is no
implicit mode switch on an existing plan and no fabricated zero error radius.
The initial fast interface has no aggregate-only mode, totals, Greeks or IV.

## Shared structural contract

Both modes use the same compilation owner for immutable snapshots, identities,
model/factor coordinates, scenario bindings, denomination checks, dates and
checked resource arithmetic. Fast compilation requests one price per row and
has no aggregation groups or caller-selected error budgets. It neither invokes
certified compilation with dummy limits nor precomputes the Cartesian cube.

Model, market, position and day-count types are the outer `Planner` types.
The [scenario convention](scenario-planner.md#financial-meaning-24) applies:
forward valuation-date rolls, fixed expiries, frozen markets, exactly one
binary64 year-fraction division, and independent shocks from original snapshot
words. Displacement remains a scalar-model term and is not rounded into the
forward by the planner. The shared typed transformation carries the model,
original scalar inputs and model-specific volatility into either evaluator.

Compilation freezes structure and bindings, not admission of all future shocked
rows. `Batch.Fast.evaluate` admits the complete inputs after each shock. A
negative normal forward may be valid; a nonpositive Black coordinate or negative
volatility is an explicit input refusal. Post-expiry takes precedence and is
reported as `Post_expiry`, without clamping time or inventing settlement.
Every row remains present, including invalid and zero-quantity positions.
Unexpected evaluation exceptions become worker failure, not invented prices.

## Values, identities and bounds

A row retains scenario/instrument index, instrument ID, factor, currency,
volatility coordinate, original position quantity and price outcome. The price
is **per unit**; quantity is metadata and is not applied implicitly. Consumers
that multiply or aggregate approximate prices own that additional numerical
and financial contract. A complete stream means all rows were delivered; it
does not mean every row priced successfully. Inspect each price outcome.

Fast limits cover instruments, scenarios, calculations, tile rows, maximum
workers and buffered result slots. A calculation is one requested price,
including failures and zero weights. At most

    min(instruments, tile_rows) * min(max_workers, tiles)

row slots are retained in a wave. Every product/sum is checked before use.
The explained raw value volume is eight bytes per calculation, a lower bound
excluding OCaml objects, identities, error values, input snapshots, scalar
scratch and the GC heap. It is not a process-RSS guarantee. Arrays for a whole
scenario cube are never created. Empty portfolios or zero scenarios complete
with no rows.

The fast convention identifies `unweighted-price-stream` and
`fast-approximate` assurance. Its canonical encoding uses a distinct convention
and output tag; original input bits, ordered inputs, scenarios, dates and policy
remain in the content identity. Manifest identity is not executable identity;
retain source/toolchain/binary hashes separately. Fast tiles are a distinct type
and evaluation also validates their identity and full logical extent. A tile
from another frozen fast plan is refused unless its content identity and extent
match exactly.

## Execution and ownership

The two modes share one bounded fork/join scheduler and sink-error owner. Workers
read immutable plans and own their arrays; every spawned handle is joined before
callbacks or return, including failure paths. Only the coordinating domain calls
the sink, in scenario-major/original-position order. Changing worker count cannot
change logical row order. No mutable pricing cache crosses workers.

Cancellation is checked between waves and before each committed row. Running
evaluations finish; there is no asynchronous worker interruption. Sink rejection
or exception stops delivery at the last accepted prefix. A broken sink cannot
be promised a `Finished` marker. Otherwise completion reports Complete,
Cancelled or Worker_failure, with committed row/calculation counts. There are
no summaries to flush, no retries and no durable resume. Reusing a plan requires
a fresh output destination. Callers must not mutate input arrays during compile;
later mutations cannot affect the frozen plan. Tile result arrays are fresh.

## Example

```ocaml
open Morphiq_risk
module P = Planner
module F = P.Fast

let sigma = Result.get_ok (Vol.lognormal 0.2)
let market = [| P.{ name = "S";
  market = Spot_market { spot = 100.; volatility = sigma } } |]
let portfolio = [| P.{ id = "call"; factor = "S"; rate_factor = "USD-rate";
  currency = "USD"; quantity = 10.; model = Bsm { dividend_yield = 0.01 };
  strike = 95.; expiry_day = 365; rate = 0.02; side = Side.Call } |]
let scenarios = Result.get_ok (Scenario.cartesian [Scenario.Time [|0; 30|]])
let plan = Result.get_ok (F.compile ~snapshot_id:"example" ~base_day:0
  ~day_count:P.Actual_365_fixed ~portfolio ~market ~scenarios
  ~limits:{ max_instruments = 1; max_scenarios = 2; max_calculations = 2;
            tile_rows = 1; max_workers = 1; max_buffered_results = 1 })
let completion = F.execute plan ~workers:1 ~cancellation:(P.cancellation ())
  ~sink:(function
    | F.Row row ->
        (match row.price with
         | Ok price -> Printf.printf "%s %d %.17g\n"
             row.instrument_id row.scenario_id price
         | Error _ -> Printf.printf "%s %d unavailable\n"
             row.instrument_id row.scenario_id);
        Ok ()
    | F.Finished _ -> Ok ())
```

This prints per-unit scenario valuations, not portfolio totals or economic P&L.
[Measurements and validation](results-fast-planner.md) cover this #97
implementation; #98 owns integrated qualification. The batch and
planner compilers reuse different work: `Batch.Fast` caches admission for fixed
requests, while `Planner.Fast` caches structural bindings and generates and admits
rows lazily to maintain scenario memory bounds. Neither changes the underlying
numerical kernel or guarantees a benefit from multiple workers on small jobs.

See [integrated qualification](fast-integration-qualification.md) for retained
fixture coverage, concurrency, memory measurements and platform evidence.
