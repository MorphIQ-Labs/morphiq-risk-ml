# Compiled fast price batches

`Batch.Fast` runs the existing fast European price kernels for BSM, Black-76,
displaced Black and Bachelier. Compile a frozen request array once to reuse
admission, then execute into a fresh ordered array. Use `run` for one-shot
requests or `evaluate` for one item.

```ocaml
open Morphiq_risk

let sigma = Result.get_ok (Vol.lognormal 0.2)
let inputs : Black.Bsm.inputs =
  { spot = 100.; strike = 95.; time_to_expiry = 1.;
    rate = 0.02; dividend_yield = 0.01 }
let requests =
  [| Batch.Fast.Price (Batch.Bsm, inputs, Side.Call, sigma) |]
let compiled = Batch.Fast.compile requests
let results = Batch.Fast.execute compiled
```

Each result is `Ok price`, `Error (Invalid_input refusal)`, or
`Error Numerical_failure`. Prices retain the scalar kernel's documented
[checked-input approximation scope](error-analysis.md). There is no absolute
error budget or runtime error certificate on this path. Mathematical admission
alone does not promise that a price is numerically available. The fast Black
kernel's existing severe-cancellation refinement remains part of that kernel;
compilation neither adds nor removes it.

## Types and failures

The existing `Batch.model` GADT ties each input record to its model and volatility
coordinate. A Bachelier normal volatility cannot construct a BSM request.
Unlike `Batch.Evaluate`, `Batch.Fast.Price` takes no accuracy limit and returns
no `Production.certified` value. Passing its successful float where a
certificate is required fails compilation. Certified Batch/Production APIs are
unchanged. Initial fast batch scope is price only; Greeks and IV retain their
existing scalar/certified APIs.

Compilation calls each model's existing scalar `admit`, storing its immutable
admitted value or its exact `Refusal.t` at the original index. Execution calls
that model's scalar `price`. It serves only finite nonnegative results, preserving
the exact binary64 word, including signed zero. Nonfinite or negative results
become `Numerical_failure`; they are never clamped or substituted. Other valid
items still execute. Expected failures are values; unexpected programming or
resource exceptions propagate rather than being mislabeled numerical failures.

For example, a mathematically admitted Bachelier expiry request with forward
`Float.max_float` and strike `-.Float.max_float` overflows its scalar payoff.
Compilation retains the admitted input, and execution reports numerical failure
at that index. An invalid spot reports the original input refusal instead.
These two categories are deliberately distinct.

## Frozen inputs, ownership and cost

The compiled batch fixes every input, side and volatility. It performs no
numerical pricing until execution. Changing market/model inputs requires a new
compile; this API does not accept later shocks or claim to cache a whole market.
Duplicate items remain separate. There is no cross-item common-expression or
result cache, SIMD transformation, worker pool or generated machine code.

Callers must not mutate the request array during `compile` or `run`. Compilation
maps it to private storage and retains no alias to the caller's array. Every
execution returns a new array; mutating it cannot affect the plan or later runs.
All retained model data are immutable. Execution has no shared mutable scratch,
so the same compiled batch can be reused concurrently. Separate callers own
their own results. Empty batches compile and execute as empty batches.

Compilation retains O(n) admitted entries and does O(n) admissions. Execution
allocates O(n) result slots plus scalar-kernel temporary allocations. The caller
controls n and available memory; allocation failure is not a per-item numerical
outcome. These are flat batches, not Cartesian scenario plans or a streaming
interface. Bounded fast scenario execution is tracked separately in #97.

A compiled batch removes repeated admission; it does not make the numerical
kernel itself faster. Account for request construction, compilation and output
extraction when evaluating one-shot use. The [measurement report](results-fast-batch.md) separates those
costs from reusable execution and pre-admitted scalar dispatch.

## Integration sequence

[Epic #95](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/95) owns this
capability. #96 supplies compiled price batches; #97 adds bounded fast-price
scenario execution; #98 qualifies the integrated package. Planner work must
keep its fast result/manifest types distinct from certified rows and totals.
Streaming-only fast plans are a valid initial scope; a weighted approximate
sum cannot be presented with the certified planner's absolute-error promise.
Existing scenario order, date conventions, grouping, cancellation and resource
limits remain obligations of that integration. No public planner signature
changes in the batch API delivery.
