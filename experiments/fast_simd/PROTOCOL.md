# Optional Fast-batch SIMD experiment (#8)

This experiment leaves the runtime library and public API unchanged. The first
candidate targets Bachelier out-of-the-money prices only, with scalar fallback
for every other request. It is not a new supported backend or certificate.

The gate is fixed before scoring: positive maturity/volatility; nonpositive
signed exact distance; finite discount and DD standard-deviation high word in
[2^-100, 2^100]; absolute distance in [2^-100, 2^100]; and the rounded corrected
standardized absolute distance in [0.46875, 4]. These endpoints select the
existing middle Y-prime rational branch. Gate failures use the existing public
Fast evaluator, including invalid and numerical-failure outcomes. No threshold
will be fitted to results. Expiry, ITM, ATM/central, remote tails and exponent
extremes remain explicit fallback cases.

Compilation uses public admission and the existing Internal arithmetic owners
to prepare DD distance, sqrt(time), total standard deviation, corrected quotient
and discount. This does more immutable preparation than Batch.Fast.compile.
Report this cost separately; compare prepared OCaml scalar, native scalar and
SIMD to separate hoisting/FFI from vectorization. No prices are cached.

The operation-preserving kernel evaluates the same middle Y-prime rational,
split square, reduced exponential and final scaling as Bachelier.otm. Ordinary
multiplications remain separate; only existing explicit FMAs fuse. AArch64
AdvSIMD uses two binary64 lanes. The gate keeps exponent restoration normal,
where multiplication by the constructed power of two is exact like ldexp.
No fast-math or FTZ/DAZ is allowed. Odd lanes are padded with a valid neutral
input and discarded; fallback ordering is restored at original indices.

A second SIMD candidate replaces only Elementary.exp(-r) on the reduced
argument with SLEEF's expd2_u10advsimd. It retains the cancellation-aware rational
and split exponent. SLEEF 3.6.1, commit
6ee14bcae5fe92c2ff8b000d5a01102dab08d774, is an external optional build input.
Its advertised exp accuracy is 1 ULP, not a bound on the whole price. This is
an unqualified changed-operation candidate pending independent scoring.

Before adoption, require exact outcome/bit agreement for operation-preserving
candidates; preserve the existing Bachelier 8-ULP and 4.3-epsilon normwise gates
for SLEEF and report every changed row, regional maxima and baseline comparisons.
New synthetic references refine from original dyadic inputs independently of
the kernel. Unresolved references remain visible. A scalar replay is not an
independent accuracy proof. Changes in served bits require compatibility review.

Run allocation/CPU attribution and correctness controls separately from timings.
Measure n=1, 32, 256 and 4096, selected-only, fallback-heavy and mixed-model books,
compilation, reused execution and one-shot execution with the same outcome
allocation/extraction contract. Retain fresh-process repeated samples and
alternate backend order, source/compiler/binary/dependency hashes and host load.
No task-owned builds, tests or profilers run alongside timings. No SLA or
cross-platform conformance follows from a local ARM64 experiment.

Native functions operate synchronously on private packed float arrays, allocate
no OCaml values, retain no pointers and do not release the runtime lock. The
wrapper validates lengths and backend selection before entering C. Separate
plans/calls own their output arrays; scratch is not shared. Native timing must
include packing and result construction at the appropriate phase.

Decision: adopt only after numerical conformance, portability and reproducible
end-to-end benefit justify the additional backend. A promising local result may
remain experimental; an unfavorable or numerically incompatible result is a
valid completed experiment. #8's separate deployment acceptance stays open.
