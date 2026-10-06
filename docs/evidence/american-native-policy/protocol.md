# Bounded native policy kernels and RSS investigation (#119)

Freeze on integration `d690ce76051807a3c129fc8ab1d1587edf006096` before runtime
changes or candidate scoring. Its tree equals PR #143 head
`eaa5e189015219dc489542c86fc654ee2f8bc904`; the already-built clean head may
supply baseline binaries with both identities recorded.

The prior standalone put profile identifies constant-slab row loops as the
largest CPU leaf. Execute policy selection, Thomas forward elimination/back
substitution and candidate copying in original-project, bounded C blocks.
Keep matrix preparation, boundary removal, policy iteration/stagnation logic,
independent original-system residual and every refinement in their current
owners. No LAPACK dependency, factor cache, approximate reciprocal, altered
financial model or additional supported domain is introduced.

Preserve the exact operation graph: three nested explicit FMAs for policy
selection; separately rounded products/subtractions/divisions for elimination
and substitution. Preserve strict comparisons, signed zero, nonfinite/pivot
check order, partial writes, failure labels, first failing row and integer
fingerprint modulo OCaml's immediate-integer width. No tolerance or requested
resolution changes. The original OCaml loop is the operation-compatibility
reference; exact-rational small systems and existing independently qualified
pricing/Greek/IV references separately check numerical meaning.

A call borrows exclusively owned arrays, all rooted, for at most 256 interior
rows. It does not allocate, call OCaml, retain pointers, release the runtime
lock, change the FP environment or start threads. Validate shapes/ranges and
writable aliasing before arithmetic. This extends the already qualified
bounded residual-kernel convention; general blocking/vendor calls still need
stable native storage and separate environment/ABI qualification. One OCaml
pre-row tick begins each block; cap following rows before the next callback or
resource edge. Return actual visited rows including a failing row, then restore
original logical accounting before raising the original failure. Reverse
substitution retains descending order. Small per-solve metadata must fit the
existing conservative workspace reservation; keep original arrays/counts.

Before acceptance: run native/bytecode block tests with chunk sizes 1, 7, 255,
256; ordinary/mixed masks, boundaries, fused-versus-unfused witnesses, signed
zero, subnormals, overflow, nonpositive pivots, malformed shapes/ranges/aliases,
partial failures and modular fingerprint wrap. Exercise GC around calls and
independent concurrent owners. Add compiled fault witnesses for the new
mechanisms. Preserve all 572 price payloads, 920 Greek rows, three 30-case IV
campaigns and 80 terminal checks, plus installed callback/resource traces.
Keep unresolved independent references and failures explicit. Default CI stays
five checks and seven core mutants.

Performance acceptance: unchanged `bench/american_iv.ml` and settings, five
alternating fresh-process pairs after owned qualification/profiling. Require
at least 25% lower median ordinary American put price, inverse and end-to-end
latency; allocation may increase at most 5%. Analytical/terminal controls allow
at most 10% latency and 5% allocation regression. Additional unchanged scalar
cash/zero/multiple-dividend price controls (`american_allocation`, three calls
per process, five alternating pairs) require at least 20% lower median latency
and at most 5% allocation regression. Record full kernel/dispatch/preparation
cost, GC and own-child RSS; no standalone-kernel result substitutes for these
whole requests. Retain failed candidates and original criteria.

RSS diagnosis separately replays pre/post-#143 libraries using one identical
instrumented public client: individual price/solve cases and the original mixed
order, warmed repeated requests, GC quick/full statistics and per-child RSS.
Check outcomes outside timings and vary order/collection only as labelled
causal probes. Do not impose global GC settings, silently change production
allocation policy or infer a leak solely from high-water RSS. A bounded/live
heap finding does not establish deployment-wide memory. Preserve unexplained
observations and select further probes from evidence. No predefined RSS target
or deployment SLA is invented.
