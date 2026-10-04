# Shared Greek intermediates (#8)

This round extends call-local reuse below `Production.evaluate_many`. Public
signatures, exact input meaning, formulas, arithmetic ordering and per-output
acceptance limits remain unchanged. Each request still has its own certificate
or error. The baseline is PR #91, `c5126db391b42529867e3716b5b9ef0b10ed43f6`.

## Dependencies and evaluation

One private evaluator fixes the immutable prepared model, side, binary64
volatility and owner-supplied rho convention. Its common Greek setup retains the
existing positive-maturity/volatility precondition and operation graph: total
volatility, standardized arguments, and weighted density (plus d squared for the
normal model). Model preparation already fixes original inputs, exact displaced
low words, carry, discount and maturity. No dependency can vary inside the call.

Construct the Greek evaluator only when an output reaches smooth-Greek numerical
evaluation. Price-only, invalid-accuracy, expiry and zero-volatility exclusions
must not force Greek setup. Cache common-setup success or arithmetic failure
only in this call. Scalar evaluation constructs a fresh evaluator per request.

Within an evaluator, defer quantity-specific expressions until a requesting
Greek needs them: signed CDFs, delta, gamma, vega, the Black maturity derivative,
half-inverse maturity and the existing price used by forward rho/normal theta.
Each memo holds the identical enclosure or exception produced by the old
expression; no radius, low word, arithmetic operation or guard is discarded.
If a deferred expression fails, only outputs depending on it fail. In particular,
a failed half-inverse maturity cannot poison a later vega, and a failed accuracy
limit is never stored as an intermediate result. Reuse changes the number of
identical evaluations, not the operations within one evaluation.

The original common setup intentionally remains common to every Greek. Its
arithmetic capability restrictions are documented; widening them would be a
separate numerical availability change. Do not eagerly evaluate branch-specific
expressions merely because another output might request them later.

Price and IV keep their existing evaluators. This round does not merge the price
and Greek operation graphs: their guards and standardized-argument assembly
have separate contracts. A price used internally by multiple Greeks may be
reused inside the Greek evaluator, but the standalone price request is unchanged.

All lazy cells belong to the synchronous caller/worker; they never escape through
a Production admission, plan or certificate. The unstable Internal evaluator is
explicitly worker-owned and must not be forced concurrently from multiple domains.
Independent public calls create independent cells. Storage is bounded by the
fixed finite set of intermediates, independent of the number of requested outputs.

## Evidence required

Before implementation, profile ten-Greek evaluation, representative quantities,
common standardized/density setup and CDF cost/allocation. Keep host load and
limits explicit. Then compare identical baseline/candidate portfolio workloads,
including one/two/eleven outputs and failures; retain every result and full spread.

Require unchanged independent certificate references, original-word before/after
replay, all models/rho conventions/sides, mixed/reordered/duplicate requests,
small-maturity partial failures followed by independent successes, concurrent
calls, planner aggregation and worker replay. Native and bytecode must agree.
Affected mutation witnesses must build and reject the intended numerical or
precondition defect after a clean baseline. No tolerance, reference, default CI
lane or numerical expectation may be widened to make the optimization pass.
