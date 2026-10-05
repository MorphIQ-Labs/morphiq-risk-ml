# Request-local American spatial preparation reuse (#119)

The [protocol](evidence/american-spatial-reuse/protocol.md) was fixed before
runtime changes, using #132 (`e6a816c6ce35fb2f5e579ddbe6b15286e895603e`)
as baseline. This pass extends immutable preparation reuse beyond a single
boundary pair to identical stock grids in the same scalar request.

## Dependency and ownership argument

`price` fixes admitted inputs, side, configuration, arithmetic precision and
local error allowance. `grid` depends on spot, strike, base space cells, node
capacity, spatial level and domain expansion. It deterministically inserts
anchors, balances, expands and bisects in the same order. Neither time steps,
cash-mapping level nor boundary choice changes those nodes. Resource/cancellation
failure aborts the request; only successfully constructed grids reach the solver.
For a fixed request, equal `(level, domain)` keys therefore mean identical node
words. Spatial bands additionally depend on the fixed volatility/rate/yield;
payoff depends on the fixed strike and side. Time-step matrices and boundary data
remain outside the cache. Piecewise model inputs would require revisiting this
dependency argument before extending the implementation.

One request-local reference owns a single entry containing a key and the
immutable left/right bands, payoff and switched-row count. Different keys release
the old preparation before constructing a new grid; returning to an evicted key
rebuilds it. Each request/domain owns a separate reference. No scratch or returned
estimate borrows or mutates these arrays. Preparation is published only after
all payoff and coefficient checks pass. Length checks reject inconsistent cached
bands explicitly before use; the key/dependency argument, not length equality,
establishes coordinate identity.

The three bands replace the current solve's three arrays and are never copied
for caching. They can remain live during reconstruction of an identical grid,
adding at most three float bands at that phase (24 bytes per maximum node plus
array headers). During solving they are the original three bands, so solve-time
peak storage is unchanged. Grid construction needs at most its capacity array,
returned grid and the cached bands, plus any retained mapping grid: fewer than
the 24 float bands already covered by the conservative 512 bytes/node workspace
reservation. A changed key drops old arrays before grid construction. No per-event
or per-refinement history is retained; existing cash metadata reservation and
policy/region/temporary allowances are unchanged.

Every original grid/payoff/stencil row visit and cancellation point remains.
Reuse contributes the original switched-row count, not zero. Boundary arithmetic
error is a request-wide monotone maximum, already containing the identical payoff
check. Limits, error allowances, operation graphs, matrices, policy iteration,
event sides, dividend interpolation and refinement acceptance are unchanged.
American successes remain estimated-only. Shared European numerical code is
unchanged.

## Qualification

Pending execution of the frozen campaign. Exact-outcome replay is compatibility
evidence; independent reference scoring remains the accuracy evidence. No result
here extends strict-target availability or resolves reference uncertainty.
