# Residual operation-graph experiment after the first campaign

The first complete 90-process campaign met the allocation targets but failed the
unchanged latency criterion: varying no-cash allocation fell 29.3% and cash
23.8%, while median latency fell only 4.2%/3.1%. All samples, profiles, complete
compatibility results and failed acceptance remain retained. Criteria are not
changed. The baseline CPU sample attributes substantial time to the original
slab and residual row loops after the earlier boxing/stencil improvements.

Evaluate a narrow C implementation of the existing residual row arithmetic.
This is original project code, not an imported solver or a new numerical
method. The reference remains the exact OCaml operation graph: three nested
explicit FMAs, the same operand-selecting min/max (including signed zero/NaN),
the same sequential magnitude sum with separately rounded products, and the
same roundoff-screen calculation. Preserve finite checks in their original
order, first-worst-row tie handling and the running maximum indicator.
The existing C flags disable contraction, reassociation and auto-vectorization;
explicit fma is the sole fused operation. No libm approximation is introduced.

Borrow checked float-array pointers only during the foreign call. Validate all
array tags/lengths, interval bounds and state shapes before reading/writing;
retain OCaml roots, allocate nothing after validation, make no callback, retain
no pointer, and do not release the runtime lock. State is request-owned: on the supported 64-bit runtimes the wrapper record,
six-reference band array, two-double metrics and three-integer indices occupy
144 bytes including headers. This fits the existing 64 KiB fixed solver
metadata reservation. Band payloads are borrowed, not copied. No row-sized
foreign buffer, retained pointer or global mutable state is introduced.

A call processes only a contiguous block before the next original cancellation
checkpoint or row-budget edge. The OCaml owner performs the first tick before
the call and accounts for the exact number of rows actually evaluated, including
a failing row. It cannot move a cancellation callback after its original row or
move resource exhaustion before earlier numerical failure. The original scalar
row implementation remains the independently executed operation-graph control.
Test normal/adversarial/overflow/subnormal rows, obstacle/continuation modes,
chunking, failure order, shape rejection and input ownership in native/bytecode.
Require unchanged complete price/Greek campaigns and affected compiled faults
before performance acceptance. Three-platform CI and installed-package checks
must pass before this experiment can land.
