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

Compilation calls each model's existing scalar `admit`. It retains immutable
admitted values or exact refusals; selected Bachelier entries instead retain
private prepared coordinates. Execution uses the original scalar `price` or
the operation-preserving native middle-branch kernel described below.
It serves only finite nonnegative results, preserving
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
result cache, worker pool or generated machine code. Selected Bachelier rows
use a precompiled two-lane ARM64 kernel.

Callers must not mutate the request array during `compile` or `run`. Compilation
maps it to private storage and retains no alias to the caller's array. Every
execution returns a new array; mutating it cannot affect the plan or later runs.
All retained model data are immutable. Execution has no shared mutable scratch,
so the same compiled batch can be reused concurrently. Separate callers own
their own results. Empty batches compile and execute as empty batches.

Compilation retains O(n) private entries and does O(n) admissions. Selected
native rows use four binary64 arrays packed into one private allocation;
execution allocates a fresh numeric output array before restoring original
indices. Fallback rows retain scalar-kernel temporary allocations. The caller
controls n and available memory; allocation failure is not a per-item numerical
outcome. These are flat batches, not Cartesian scenario plans or a streaming
interface. Bounded fast scenario execution is tracked separately in #97.

A compiled batch removes repeated admission and can use the native kernel for
eligible Bachelier rows. Account for request construction, compilation and output
extraction when evaluating one-shot use. The [original measurement report](results-fast-batch.md)
describes the scalar implementation at its recorded revision.

## Native Bachelier selection

On ARM64 with the supported flat-float-array compiler, compilation considers
native packing only for batches with at least 32 Bachelier rows comprising at
least half the requests. At least 32 rows and half the batch must then satisfy
the fixed numerical gate: live OTM, positive normal volatility, absolute
distance/discount/standard-deviation high word in [2^-100,2^100], and corrected
standardized distance in [0.46875,4]. Other entries use their scalar path.
Small, sparse, unselected and non-ARM64 batches keep scalar execution.
If a dense Bachelier batch yields too few native rows, selected rows retain
their prepared coordinates for the identical OCaml scalar graph.
These size/density limits control packing cost, not financial validity or
numerical tolerances. The unchanged `run` and `evaluate` operations remain
scalar, avoiding packing overhead for one-shot/single requests.

The native kernel ports the existing rational and split exponential operation
graph, using only explicit FMAs and separately rounded multiplications. There
is no SLEEF dependency or host exponential substitution. A final odd row uses
the same C scalar graph. Private inputs are immutable; each invocation owns
its result buffer, retains no foreign pointers and does not release the OCaml
runtime lock. See [the integration contract](fast-simd-integration.md) for the
arithmetic and ownership obligations. Certified outputs, Greeks and IV do not
route through this kernel.

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

See [integrated qualification](fast-integration-qualification.md) for retained
fixture coverage, concurrency, memory measurements and platform evidence.
