# Shared certified model preparation (#8)

The new multi-output operation is defined as an ordered list of existing scalar
Production evaluations for one immutable admitted model, side and typed volatility.
Each quantity carries its own typed absolute limit and returns its own typed
certificate or error. Empty lists return empty lists; duplicates retain separate
results. No error in one output suppresses later outputs.

Model_enclosure.black/normal depends only on the original admitted descriptor:
original spot/forward/strike and exact displaced low words, maturity, rate and
yield. It does not depend on requested quantity, side, volatility or error limit.
Reuse only that exact preparation, with unchanged operations and ordering. Price,
Greek formulas, final radius calculation and acceptance remain the scalar owner.
No CDF/Greek-specific expression is hoisted in this change: doing that eagerly
could introduce failures for outputs that never required it.

A fresh memo belongs to one synchronous multi-output call and cannot escape.
The first output that reaches live numerical evaluation prepares the model;
later outputs reuse its immutable value or the same Enclosure.Unresolved result.
Invalid accuracy, expiry-Greek and zero-volatility-Greek checks precede access.
Thus a preparation failure cannot replace those earlier errors. Quantity-specific
failures and Accuracy_exceeded are not cached. No memo is stored on an admitted
value or plan; concurrent calls create separate state. The scratch bound is one
prepared-model result per invocation, independent of output count.

Batch delegates admission once for the fixed model/input group, preserving
Invalid_input on each requested output. Planner invokes the grouped operation
within one position/scenario row. Post_expiry and invalid shocked-volatility
precedence stay ahead of model admission. Empty output rows remain empty and
retain existing row/summary accounting. No reuse crosses rows, scenarios,
instruments or workers; original input words and rho conventions remain owned
by the existing model. Aggregation and output order are unchanged.

The existing scalar MODEL module type stays unchanged. An additive
MULTI_OUTPUT_MODEL signature and typed Production request/outcome witnesses
expose evaluate_many for built-in models; Batch.evaluate_many supplies dispatch.
Existing homogeneous Batch.run semantics stay unchanged.

Qualification uses unchanged independent references plus scalar/value/radius/error
replay, mixed limits, exact/invalid/unsupported/failing cases, duplicates, empty
lists, all models, both sides and concurrent calls on the same admission. Planner
reference and worker/cancellation/partial-total tests remain required. Benchmarks
compare identical portfolio harnesses before and after, with one/two/eleven outputs,
explicit failure rows, compile/execution/end-to-end phases and allocations.
No expected value, radius, limit, reference or digest may change for this optimization.

Example (limits here are caller-selected examples, not defaults):

```ocaml
let outputs = Production.[
  Request (Price, 1e-8);
  Request (Delta, 1e-9);
  Request (Theta, Units.time_rate 1e-10);
] in
Production.Bsm.evaluate_many admitted Side.Call volatility outputs
```

Pattern matching each `Outcome` on its quantity recovers the result's units.
The output list uses O(number of requests) storage, as do the scalar results it
replaces; this API is a fixed-model group, not a full-portfolio result cube.
