# American compiled workload and worker campaign (#119)

Freeze against integration403ea7cdeddc7b263bd88bc62cc1c7558cbe884b before
implementation or performance collection. This pass extends the #118 engineering
baseline; it does not modify production pricing or select a new solver/backend.
Actual policy-matrix/backend crossover and residual scalar optimization remain
separate #119 obligations. No deployment targets or acceptance are inferred.

## Fixed workload

Cases: analytical call, flat put, one-cash put, cash Bermudan put, piecewise put,
piecewise cash put, constant delta/gamma, piecewise delta/gamma, general put IV,
certified call, strict put, heterogeneous price portfolio. Base S=K=100, r=.05,
q=.02, sigma=.2, expiry day365, valuation day0, ACT/365F. Analytical and certified
calls use q=0. Cash pays5 on day180. Bermudan rights are90,180Before,180After,365.
Piecewise levels change on day180 to r=-.03, q=.08, sigma=.35. The mixed portfolio
cycles flat/cash/piecewise-cash/strict puts in original order. Quotes remain fixed.
General-put IV uses the existing independent/discrete reference quote
`0x1.aa45024c11b87p+2`; its quoted target is not an independent pricing certificate.

Ordinary price configuration:64 space cells,64 time steps,two domain expansions,
tolerance1,8192 nodes,131072 steps,1048576 policy solves,100000000 row visits,
8MiB workspace,64 policy iterations. Strict put changes only tolerance to1e-12.
Greek delta/gamma tolerances are10 with default bumps. IV uses the same pricing
configuration, search[.05,.6], width.01 and32 evaluations. Certificate limit1e-9.
All settings are engineering workloads, not newly qualified numerical accuracy
claims. Refusals and per-Greek unavailability are recorded, never dropped or
counted as successful-price throughput. Do not widen settings to make cases pass.

Singleton:one position,base scenario,one worker/tile. Portfolio:four positions,
base plus day30/spot101 scenario, tiles1/2/4 and workers1/2/4. Original dates stay
fixed. Explicit scalar inputs are separately constructed from integer-day
fractions for both scenarios. Compare entire rows, outcomes and completion across
scalar/fixed-batch/planner configurations outside timing. Retain classifications
and digests across processes. Replay equality is compatibility, not accuracy.

## Measurement and accounting

Five fresh processes per case/shape/phase, alternating configuration and method
order. Time phase:one warmup and one measured full execution per configuration,
plus50 repetitions for compilation after one warmup. Include explicit scalar,
fixed compiled batch and dated planner costs. Singleton timing is separate from
amortized portfolio cost. First-row clocks and a minimal classification sink are
included in planner timing; no transport/retained-result sink is implied.

Allocation phase runs separately from timing. Use `Gc.stat` before/after each
complete execution to collect program-wide managed allocation including joined
workers. Its forced full collections are outside timing and disclosed as part
of this allocation experiment. Retain coordinator `Gc.counters` separately; the
remainder includes worker/runtime/snapshot overhead, not a precisely isolated
worker-body counter. Qualify the total scope first with explicit known-size
allocations and independent per-domain counter deltas for1/2/4 joined domains.
An intentionally coordinator-only substitute must fail the scope witness.
Cumulative managed allocation excludes untracked native/runtime memory. Use each
child's own wait4 for peak RSS; never cumulative child statistics. Time-phase
RSS and allocation-phase RSS have different GC histories and stay separate.

Additional five fresh general-put portfolio cancellation processes sweep workers
and tiles. Request cancellation after5ms and report actual issuance, controller
scheduling delay, return latency, completion and committed prefix. Do not assume
the controller delay proves the exact solver phase; the deterministic #118
callback-count witness separately proves in-solver cancellation forwarding.
Preserve completed-before-cancellation outcomes if they occur. No latency SLA.

Finish owned builds/tests/profilers before time collection; record all source
files (including untracked), binary/driver hashes, compiler/options, OS/hardware,
host load, every process and raw sample. Collector controls reject malformed,
truncated, nonfinite, duplicated, changed-replay and failed-process evidence;
exercise failed startup and timeout/reaping. No automated performance threshold
is added to default CI. Benchmarks stay manual; small counter/collector controls
run in ordinary CI. Recommend worker/tile settings only for measured workloads.
