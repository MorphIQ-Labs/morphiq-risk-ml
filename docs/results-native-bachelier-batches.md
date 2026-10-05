# Native compiled Fast batches — integration stage 2

`Batch.Fast.compile` now packs eligible Bachelier rows for an operation-preserving
ARM64 kernel. Reused execution improves substantially in the local eligible
workload; compilation and fallback-heavy workloads have distinct costs.
`Batch.Fast.run` and `evaluate` remain scalar. This is a Fast approximate-price
optimization, not runtime certification or a new financial model. SLEEF remains
optional research and is not a dependency of the installed library.

The [batch contract](fast-batch.md) defines selection and ownership. The
[integration assessment](fast-simd-integration.md#native-fast-batch-boundary)
records the arithmetic, finite-domain argument, source notices and foreign
boundary. Native use requires at least 32 selected rows and selected density
at least one half, after a Bachelier model-count prefilter. Unsupported platforms
keep public scalar execution. The fixed numerical gate is unchanged from #121.

## Numerical, ownership and packaging evidence

Development/release ordinary suites and build/format checks passed locally.
The native scalar and AdvSIMD variants independently passed the unchanged
8-ULP / 4.3-epsilon original-input requirements for 466 selected committed-fixture
rows. They also passed all 8,220 selected cases from the prior 110,632-row
refined experiment corpus. Every selected result matches the owning OCaml
scalar graph exactly. The added public API check compiles the entire selected
population through `Batch.Fast`, scores the same independent gates and checks
exact replay in both development and release builds. Reference provenance is
retained in the [original experiment archive](evidence/fast-simd/README.md);
external-reference mode alone does not establish provenance.

Tests cover empty/single/odd arrays, packing and density boundaries, finite
result conversion, original-index errors, frozen input storage, fresh outputs,
simultaneous executions, malformed mode/shape rejection and native/bytecode
loading. The expanded isolated installed consumer exercises 65 eligible rows
plus invalid/expiry fallbacks, odd-tail execution and concurrent public reuse.
Source-artifact installation, notice checks and both consumer modes pass on
the recorded local ARM64 host. All 649 existing Exchange cases also replay
through each installed mode. These local results do not substitute for the
PR's three-platform CI or exact-candidate release qualification.

Four affected mutations pass their required baseline/build/witness protocol:
`native-bachelier-exponent`, `native-bachelier-mode`, `fast-batch-finite` and
`fast-batch-order`. The new exponent guard checks independent references before
replay; replay identity is disabled in the mutation profile. The full catalog
contains 98 mechanisms, while default CI still selects seven. Assembly inspection
records separate rational multiplies/divides and explicit vector FMA operations.

## Paired local measurements

The final measured runtime is `131983f46dec346f05585a800ca6ccaa6b3ef196`, library
tree `093611b1e78261c5d96a4da90ae80b18eac7cc3e`. The baseline is stage 1 at
`a92c38067f131c05e5f9c0c2ff2f9614d830cc91`, tree
`10b92a9c2a56bbfa68754cf7ec7be59dfec003ec`. Later additions extend public-reference
tests and record evidence; they do not change the measured runtime.

Hardware/toolchain: Apple M1 Pro, 10 cores, macOS 27 ARM64; OCaml 5.3.0 Flambda,
release profile, library `-O3`, Apple Clang 21, explicit native arithmetic flags.
The same optional experiment driver and timed original inputs are used for
both revisions. Eight fresh processes alternate revisions/backend order,
retaining all 7,200 samples. No task-owned builds, tests or profilers run during
timing. Recorded one-minute load is 13.3–19.4: this is still a shared host.

Times below are median-of-four-process-medians, amortized **ns per output**,
not single-request latency. Allocation is **bytes per output**.

| Workload and size | Phase | Before ns | After ns | Before bytes | After bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| Eligible, 1 | Execute | 110.5 | 109.9 | 504.0 | 504.0 |
| Eligible, 32 | Compile | 62.9 | 95.0 | 445.0 | 716.0 |
| Eligible, 32 | Execute | 99.1 | 11.0 | 480.3 | 49.5 |
| Eligible, 256 | Compile | 66.6 | 92.6 | 445.6 | 710.5 |
| Eligible, 256 | Execute | 100.9 | 9.9 | 480.0 | 48.2 |
| Eligible, 4,096 | Compile | 126.3 | 124.7 | 445.7 | 709.8 |
| Eligible, 4,096 | Execute | 109.5 | 22.1 | 480.0 | 48.0 |
| Eligible, 4,096 | Scalar `run` | 179.4 | 178.3 | 917.7 | 917.7 |
| Mixed, 4,096 | Compile | 825.3 | 826.1 | 1496.6 | 1496.6 |
| Mixed, 4,096 | Execute | 813.8 | 818.1 | 769.4 | 769.4 |
| Fallback-heavy, 4,096 | Compile | 123.9 | 177.8 | 445.7 | 591.7 |
| Fallback-heavy, 4,096 | Execute | 130.4 | 121.5 | 504.0 | 462.0 |

Eligible repeated execution is about 5× faster at size 4,096 and 10× at 256,
with approximately 90% less execution allocation. Packing allocates more at
compile time; at small eligible sizes compilation also takes longer. Sparse
mixed books retain effectively unchanged costs. Fallback-heavy compilation
increases about 44% at size 4,096; retaining selected coordinates for the OCaml
scalar graph recovers about 7% during each execution. Several reuses may be
needed to repay that preparation. The scalar one-shot API avoids this tradeoff.
Adding separately measured phase times is not an end-to-end latency measurement;
planner adoption requires its own complete-job experiment.

An initial implementation retained all admitted objects through packing. Its
eligible 4,096-row compilation cost was 260.6 ns/output in the earlier paired
run. The final implementation discards selected admission temporaries immediately
and retains only private coordinates. Both campaigns and every slower sample
remain in the evidence; their different host loads preclude treating the
between-campaign change as an isolated timing estimate. The final comparison
against stage 1 is the reported paired result.

## Disposition

Land this stage on the temporary integration branch after its five CI checks
pass. Keep small/non-ARM64/sparse books scalar and keep SLEEF deferred. Planner
tile integration must measure fresh preparation, packing and sinks together;
these reused-batch gains are not a claim about scenario execution. No numerical
budget, digest, package version, independent approval or release acceptance
changes. [Retained evidence and reproduction](evidence/native-bachelier-batches/README.md)
identify the exact tested and timed sources.
