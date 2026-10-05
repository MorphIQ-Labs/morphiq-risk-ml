# Fast-batch integration after the SIMD experiment

This work is staged under #8 on `feature/fast-simd-integration`, based on merged
PR #121. Three PRs land there in order: shared preparation, native Fast batches,
and bounded planner tiles. All five existing CI checks must pass for each PR;
combined qualification precedes an integration PR to `main`. SLEEF stays optional
research. The [original experiment](results-fast-simd.md) retains its measured
revision and limitations; its results do not qualify the integrated runtime.

## Shared preparation owner

Bachelier admission owns the exact-input DD distance, discount and DD square root.
It now evaluates the same pure square-root operation once and keeps both words.
The internal `Bachelier.Fast_middle` owner consumes that admitted value plus typed
normal volatility and side. It never recomputes admission coordinates or stores
a served price. The primary public Bachelier interface keeps its existing types
and operations; the testing view is `Internal.Bachelier_fast`.

Selection retains #121's fixed gate: live OTM, positive normal volatility,
absolute distance/discount/standard-deviation high word in [2^-100,2^100], and
corrected standardized distance in [0.46875,4]. Gate failure requests scalar
fallback; it does not reject a mathematically valid request. Selected parameters
are private immutable float records. The scalar prepared evaluator retains the
existing middle rational, split square, quotient residual and scaled exponential
operation order. This is preparation reuse, not a new approximation or proof.

The experiment now consumes the owning component's preparation, avoiding the
old admit/discard/recompute sequence and using the packed float record directly.
Scalar prices, IV, Greeks and certified quantities retain their numerical
operation graphs. First-stage tests cover fixture equivalence, selection
boundaries, immutable concurrent use and compile-time rejection of forged
parameters and access through the stable Bachelier surface.
The [first-stage evidence](results-bachelier-preparation.md) records exact
110,632-row compatibility, affected mutations and paired preparation measurements.

## Integration obligations

Native adoption must preserve original output indices, finite-result/failure
classification, signed zero, private scratch and concurrent plan reuse. Ordinary
scalar behavior remains the fallback for unsupported regimes and platforms.
Packing, preparation, native dispatch and result construction all belong in
end-to-end measurements. Performance routing limits are distinct from the frozen
numerical gate; they must not alter mathematical admission or quality budgets.

Planner integration operates within existing tile and worker memory bounds.
Shocked rows require fresh numerical preparation. Reused fixed-batch throughput
is not evidence of scenario speed; date rolls, invalid rows, cancellation,
sink failures and worker cleanup remain observable contracts. No shared mutable
scratch or materialized scenario cube is introduced. Target-host deployment
acceptance, independent review and release approval remain separate.
