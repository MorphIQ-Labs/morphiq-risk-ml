# Piecewise allocation protocol (#119)

Frozen before implementation, against integration baseline
`5155d64f4a01262e504cc757d5f392c77aec1e11`. The two workloads are the unchanged
`test/american_piecewise.ml --bench none|cash` from #114: staggered coefficients
and a cash event coincident with coefficient changes; reused scalar American put
pricing, 128 cells/steps, tolerance 1, 8 MiB workspace, one warmup and three calls.

Installed-library Memprof sampling (three calls, rate 0.0001, depth 24) identifies
upper-boundary exponentials and spatial stencil preparation as the principal
allocation sites. The driver and sampled category counts are retained beside
this protocol. Raw profiles, build identities and hashes accompany final evidence.

Implement bounded request-owned reuse of successful upper boundary scalars and
immutable coefficient stencils. Retain original arithmetic on cache misses,
exact dependency identities, logical stencil visits, numerical failures and
workspace fallback. No public API or numerical-method change is intended.

Acceptance, fixed before candidate measurement:

- Each piecewise workload: median allocation at most 50% of baseline and median
  latency at most 80% of baseline.
- Four existing constant American/Bermudan no-cash/cash workloads: allocation
  at most 105% and latency at most 110% of baseline.
- Five alternating fresh-process rounds per paired workload, same compiler and
  frozen drivers; retain all raw samples, GC counts, per-child RSS and host load.
  Finish owned builds/tests/profilers before timing. This shared host is not a
  deployment SLA or isolated environment.
- All 412 constant and 160 piecewise complete ordered outcomes, diagnostic
  fingerprints and independent classifications match baseline. Keep strict
  failures and four wide references explicit; equality is not accuracy proof.
- Ordinary development/release suites, package build, formatting, native and
  bytecode piecewise controls; affected numerical/dependency mutations with
  compiled faults and independent/precondition witnesses. Exercise constrained
  workspace fallback, cache key/ownership and work/cancellation behavior.

Keep #119, #120 and Epic #107 open: this is the focused piecewise allocation
follow-up, not qualification of later Greeks, IV or compiled batches.
