# Cash interpolation allocation pass (#119)

Frozen before runtime optimization. The prerequisite is PR #148, measured/runtime
head `6d3ef1c7e44f107c7074906ae0a2372802a19e99`, to be rebased onto its identical
integration merge tree before publication. Its cash profile attributes about
45% of sampled managed allocation to interpolation. Ordinary singleton cash
still allocates about 22.57 MB; the eight-row planner allocates 185.24 MB.

## Arithmetic and storage contract

Introduce an internal, model-independent enclosed linear-interpolation primitive.
First commit its generic operation composition and independent tests; cash pricing
still uses the existing composition at that baseline. Then specialize storage
and route cash interpolation through the primitive. Grid search, exact endpoint
shortcuts (including returned zero signs), event order, mapping refinements,
width/error diagnostics, arithmetic limits and logical ticks stay at their owners.

For point p and nodes l/u, preserve endpoint comparisons first, then width u-l,
weight (p-l)/(u-l), strict enclosure checks 0<w<1, and the ordered expression
(1-w)*v_l + w*v_u. No slope-form substitution, reassociation, fused arithmetic,
rounded width, reduced precision or widened error bound. Preserve complete
fields and failures. Endpoint results bypass interior arithmetic/diagnostics;
unresolved weight remains a distinct result mapped to the original cash failure.

Each primitive call owns one checked array of max(8,2*words*words) floats.
Subtractions/comparisons need at most 2*words, scalar products 4*words, generic
products 2*words*words, quotient proposals/suboperations eight, and denominator
lower parts words-1. Each operation overwrites its used prefix; packing copies
retained fields into immutable records. General division retains original
validation, geometric correction and tail bounds; its ordinary caller keeps
fresh allocation, while interpolation reuses private scratch. Scalar fusions
must match the original exact-scalar graph including zero padding and validation.
No scratch/callback escapes, no cross-call/worker reuse or new cache/FFI.

## Qualification

Compare the primitive with its original composition, complete five fields,
endpoint signs and exceptions, both precisions/native/bytecode, seeded values,
uncertain points, adjacent/subnormal/extreme nodes, invalid widths, retained
results and independent domains. Exact-rational linear interpolation bounds
supply independent containment evidence on finite ordered nodes/points; retain
explicit unresolved weights and arithmetic refusals. Test general divisions
and unchanged European consumers because allocator plumbing is shared.

Full development/release install/format/ordinary suites, unchanged determinism,
affected targeted numerical mutants, and the historical 572 price outcomes,
920 Greek rows and three 30-case inverse campaigns must pass. Preserve all
refusals, unresolved references and complete work/diagnostic payloads. Cash
liquidator/event/refinement fault witnesses remain required. No full optional
mutation catalog is added to CI; five jobs/seven core mutants remain unchanged.

## Frozen measurements and engineering criteria

Reuse the #148 140-process driver/corpus: ten singleton cases, three eight-row
cash/Bermudan/piecewise-cash cases (scalar/fixed/planner1/planner4, tile one),
eight European certified cases, five alternating fresh process pairs, reversed
job/method order on alternate rounds. Compilation/admission are separate.
Warmups/full collection precede timed operations; allocation runs and optional
profiles are separate. Finish all owned compute first. Retain all raw samples,
load, per-child RSS and source/binary guards; reject changed complete replay.

Require at least **10% lower singleton scalar managed allocation for cash**, and
**5% lower for Bermudan with cash and piecewise-cash**. All other pricing methods
must have at most 5% allocation growth; every American/European price/end-to-end
median must regress no more than 10%. Compilation/admission are reported without
a threshold. Failure retains evidence and prompts a revised implementation or
deferral, never a relaxed criterion. These targets are local engineering criteria,
not deployment budgets or SLA acceptance. #119/#120 remain open.
