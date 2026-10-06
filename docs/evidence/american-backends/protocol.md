# Actual American policy-system backend comparison (#119)

Frozen from integration `69c8f4c76574c304c430d57deabaa50a3401cc45`, before
candidate implementation or timing. This is an isolated experiment: production
`lib/`, dependencies and served values remain unchanged. Default CI remains
five jobs and seven core mutants; numerical/performance campaigns are manual.

## Candidates and boundary

Compare the existing bounded native Thomas elimination/substitution with its
existing OCaml operation reference and Reference LAPACK 3.12.1 `DGTSV`, commit
`6ec7f2bc4ecf4c4a93496aa2fa519575bc0e39ca`. Build the pinned source locally
using recorded Fortran compiler/options, no fast math or implicit contraction.
DGTSV calls no BLAS routines: the reference implementation is single-threaded.
Do not substitute a vendor library or mutate global thread settings. Retain
source hashes and the upstream redistribution notice; no upstream source is
silently relicensed. Public build/test/install must require neither Fortran nor
network access. Optional experiment construction happens in a fresh directory.

An isolated copy substitutes the internal policy owner; assembly, policy
selection, original-system residual, event mapping and refinements retain their
existing owners. Stable per-owner Bigarray buffers hold DGTSV's destructive
lower/diagonal/upper/RHS storage. Include buffer creation, packing, dispatch,
factorization, solve and output copying in full-request costs. No factors are
reused between different policy systems. Check LP64 dimensions, finite inputs,
shapes, writable aliases, rounding/underflow environment, INFO and finite outputs.
Preserve/restore the caller's floating-point environment on all vendor-call exits.

The whole-system LAPACK call cannot reproduce the existing 256-row callback
boundaries or partial native failure writes. Its isolated adapter is explicitly
a cost/solution experiment, not a conformant production replacement. Retain
this limitation and exercise cancellation/resource traces; never label an
unchanged logical counter as proof of identical physical work or responsiveness.

## Actual matrices and independent checks

Capture effective interior policy matrices after identity-row selection and
boundary elimination, before factorization, from unchanged scalar workloads:
flat, cash, Bermudan, piecewise-cash, Greeks, IV and strict puts, plus analytic
and certified controls. Use the #146 inputs and 64x64 ordinary/strict settings;
a separate flat/cash 256-cell capture supplies larger actual matrices. Retain
all reached dimensions; do not fabricate financial matrices to fill missing
sizes. For each dimension capture policy ordinals 1,2,8,32,128,512. Record original
binary64 coefficients/RHS, selected mask, baseline solution and local residual
allowance. Sampling is fixed independently of observed errors or timings.

For each captured matrix, independently evaluate `A*x-b` using exact rational
arithmetic on the original binary64 words. Record finite results, sign structure,
exact strict row-dominance margin m, residual and the rigorous fixed-linear-system
bound `||x-x_exact||_inf <= ||A*x-b||_inf/m` when m>0. This follows from the
M-matrix comparison bound in the solver design. Compare the exact residual with
the already-frozen owner allowance; retain every violation, not a fitted new
threshold. This says nothing about continuum discretization or Greek accuracy.
Report exact-word changes separately. Include identity-row, zero-pivot, pivoting,
nonfinite, shape/alias, environment and independent concurrent-owner controls;
pivot-only synthetic controls are not part of the financial timing corpus.

Microbenchmarks sweep every captured dimension and batches of 1/8/64 systems
with fresh RHS/factors for every solve. Measure preparation/copies separately
and complete copy+solve+original-system-residual costs. No cached-factor timing
may substitute for the actual changing-policy workload.

## Complete requests and collection

Reuse #146's dated inputs and 64x64 settings: call, flat, cash, Bermudan,
piecewise-cash, delta/gamma, general IV, certified and strict. Measure singleton
scalar, fixed-batch and eight-row planner execution at tile1/workers1 and4.
Retain compilation and admission separately. Record every outcome, including
refusals and unavailable quantities; failed work is not successful throughput.
Use five fresh processes per candidate/workload/shape, alternating candidate and
method order. One warmup precedes each measured execution; untimed full major
collection follows warmup. Separate program-wide allocation snapshots from
latency; disclose forced-GC snapshots, native scratch bytes and whole-process
RSS. Per-child wait4 supplies RSS, not cumulative child statistics.

Finish task-owned builds, tests and matrix/reference generation before timing.
Capture source/patch/toolchain/binary/upstream identities and raw observations;
reject source drift, malformed/truncated/duplicate/nonfinite output, failed
startup, timeout and missing cases. Preserve failed attempts. Small collector
controls belong in ordinary CI; no hardware-dependent timing thresholds do.

## Decision

Select no production backend from a microbenchmark. Compare total-request
benefit with numerical, cancellation/resource, platform, build and license costs.
A follow-on adoption proposal needs full independent pricing/Greek/IV and
native/bytecode/platform qualification, with any changed numerical graph derived
and scored. For prioritizing that proposal, require at least 10% lower median
complete-request latency on three stochastic price/risk workloads, no more than
5% latency/allocation regression on controls, and no silently weakened work or
accuracy contract. A faster nonconformant proxy is not delivered acceleration.
Keep the current backend if its complete-cost advantage and lower integration
burden justify it. Residual enclosure allocation and deployment acceptance remain
separate #119 obligations; #120 owns final American capability qualification.
