# Scalar Greek optimization protocol (#119)

Frozen before profiling or runtime changes. Baseline source is PR #138 head
`112269958a5871182133990c7f885b0cb9d7dd56`; its runtime and measured drivers match
`09cde8d056ad8ee2dd5ef8ca70ef2158e68b7319`. If PR #138 is squash-merged while this
work proceeds, record the integration merge and verify tree equality before
using it as the final comparison base.

## Scope and frozen workloads

Optimize existing bounded estimated scalar American/Bermudan Greeks. Preserve
exact complete price/Greek values, diagnostics, uncertainty, refusals, logical
work and resource/cancellation semantics. No numerical tolerance, bump, mesh,
solver policy, precision or public meaning may change to earn a performance
pass. A changed numerical method needs separate derivation and qualification.
No global mutable cache, parallel request scheduling, dependency or FFI is
presupposed. Profile before choosing implementation work.

Use the existing `bench/american_greeks.ml` driver unchanged: constant ATM,
staggered piecewise coefficients, and joint coefficient/cash event. For each,
price, spatial delta/gamma/theta and all-five requests at the frozen 128/128
resolution and loose per-quantity targets. Retain constant delta's refusal;
a request is not five successful outputs merely because five were requested.
Whole-work limits scale with the driver's original fixed partition count.

Freeze these engineering improvement criteria before edits: for **both varying
all-five workloads**, at least 20% less median cumulative allocation and 10%
lower median latency versus the matched baseline. Constant all-five, spatial
and price controls must not exceed baseline by 5% allocation or 10% median
latency. These are optimization comparison criteria, not deployment budgets.
If unmet, retain the attempt and diagnose; do not relax criteria after seeing
results. Keep every raw sample and partial/failed campaign.

## Evidence and ownership

Collect allocation samples with OCaml Memprof and CPU stacks with source/build
identity, separately from unprofiled timing. Attribute repeated work before
selecting a cache or alternate implementation. A cache must define every
parameter, spatial/time-level, exercise/event and arithmetic dependency, bounded
live storage, call ownership and an uncached fallback when surplus is absent.
No operator or factor may survive a dependency change. Preserve logical visits
and cancellation even when successful arithmetic preparation is reused.

Retain all 572 existing complete price outcomes/scores and all four 230-row
Greek campaigns (independent and canonical classifications separate), including
strict failures and unresolved references. Add targeted changed-dependency,
small-workspace, ownership/cancellation and compiled numerical fault witnesses
for any reuse. Run applicable native/bytecode, development/release, package/
installed-client, format and ordinary controls; default CI remains five jobs
and seven core mutants. Full-catalog/source-artifact qualification stays #120.

After all owned builds/tests/profilers/reference sessions have exited, collect
five alternating fresh-process pairs per workload/request, one warmup and one
timed call, same compiler/driver/configuration and full outcome digest. Measure
GC, cumulative bytes and per-child peak RSS separately; record source revision,
binary hash, hardware/load and raw stdout/stderr. Preserve admitted-input and
quantity identities. Report shared-host variation and absolute remaining cost.
