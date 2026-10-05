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

## Native Fast-batch boundary

The [stage-2 evidence](results-native-bachelier-batches.md) records independent
reference scoring, ownership/packaging controls, affected mutations and paired
compilation/execution costs.

`Bachelier_native` owns the foreign boundary. Its input is an array of private
`Fast_middle.t` values, so ordinary typed code cannot supply unadmitted raw
coordinates. Compilation copies them into a private SoA array with four
contiguous `n`-element spans: standardized distance high word, residual,
standard deviation high word and discount. Currency scaling and side have
already been resolved by the owning Bachelier preparation. No exact displaced
sums or lognormal models cross this boundary.

Each execution allocates a fresh `n`-element numeric result array. The C primitive
checks dispatch mode, flat-array tags and the `4*n` input length before indexing;
the OCaml owner bounds `4*n` before allocation. Empty arrays are supported.
Array pointers are borrowed only for that call, registered as OCaml roots, never
retained and never passed through a callback or runtime-lock release. Inputs are
read-only, outputs are invocation-private, and NEON loads/stores permit the
ordinary array alignment. Concurrent executions therefore share no scratch.
Non-flat-array configurations retain private typed values and use OCaml scalar
execution. Unsupported platforms keep the public scalar batch layout.

ARM64 uses two lanes, with an odd final selected row evaluated by the same C
scalar template. The scalar C instantiation is also an explicit private
assurance control on supported x86-64. It is not enabled as the public default
there without performance evidence. Both native and bytecode public consumers
link the installed stub library; SLEEF is not a build or runtime dependency.

### Arithmetic and source ownership

`bachelier_operation_graph.h` ports the already reviewed experiment graph from
PR #121, originating in this project's `Normalised_black.y_prime`, `Split.square`,
`Split.scaled_exp_neg` and `Elementary.exp`. Coefficients retain their binary64
words and expression grouping. Full inherited Jäckel and Sun notices accompany
the native sources and installed project notices. No new external coefficient
source or elementary approximation is introduced.

| Operation | Preserved implementation |
| --- | --- |
| Middle rational | Same numerator/denominator Horner grouping and ordinary division; no reciprocal approximation |
| Square/residual | Separate `q*q`, then explicit fused `fma(q,q,-square)` |
| Scale | `((discount*s)*inv_sqrt_2pi)*Y_prime(-(q+low))` |
| Exponent | Same half-square high/low words, logarithm split, floor and explicit reduction FMAs |
| Reduced exponential | Same polynomial coefficients, rounded reduction and explicit FMAs |
| Exponent restoration | Scalar `ldexp`; ARM64 multiplication by exactly constructed normal powers of two |

The fixed gate bounds the rational argument and exponent integers. Its rational
numerator/denominator are positive and restoration remains normal; no subnormal
rescaling branch is selected. The reduced exponential's tiny-argument case
rounds its Horner accumulator to one, preserving `1+x`. These restricted-domain
arguments are inherited from the [operation audit](results-fast-simd.md#scope-and-arithmetic),
not a whole-domain proof of the native compiler. C flags disable implicit
contraction, reassociation/fast-math and automatic vectorization; only explicit
FMA intrinsics fuse. Native reference tests independently score original-input
fixtures before checking served bits.

`Batch.Fast` restores original indices and owns conversion to finite,
nonnegative successful prices or numerical failures. Invalid admissions and
unselected entries retain scalar behavior. It only packs batches with at least
32 selected rows and selected density at least one half, after an inexpensive
Bachelier-count check; size/density dispatch cannot change admission or numerical
quality gates. `run` and `evaluate` remain scalar. No price is cached at compile
time. Selected admitted temporaries are discarded as soon as their private
coordinates are prepared, avoiding a second live copy through packing. If too few
rows select the native path, their prepared coordinates still feed the identical
OCaml scalar graph rather than being discarded. Unselected rows retain their
original scalar pricing path.

## Bounded planner integration

Stage 3 routes eligible homogeneous Bachelier scenario tiles through the compiled
Fast-batch owner. Automatic adoption is limited to ARM64 `execute ~workers:1`;
direct `evaluate_tile` also uses the native route. Multiworker execution remains
scalar because the retained trials did not establish a stable benefit. Mixed
models and tiles smaller than 32 rows retain their scalar path.

The original shock/date transformation runs once per row. A model-owned rounded
hint avoids clearly unsuitable packing, but only admitted `Fast_middle.prepare`
can select a native row. Private chunks contain at most 256 rows, matching the
supported OCaml 5.3 minor-array allocation threshold; the four-span native input
can still allocate in the major heap. This bounds scratch independently of the
caller's logical tile. Scheduling, cancellation checks, sink delivery and public
tile identity retain their existing granularity. Private scratch does not change
the explained logical output-slot bound or establish an RSS bound.

The [stage-3 report](results-native-planner.md) retains independent original-input
references, exact ordered outcomes, chunk-boundary and failure controls, six
affected mutations, installed consumers and complete paired jobs. Shared-host
multiworker variation and superseded regressions remain visible. SLEEF and
parallel native planner adoption remain deferred.

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
