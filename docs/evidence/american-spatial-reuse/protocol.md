# Request-local spatial preparation reuse (#119)

Frozen before runtime changes. Baseline is PR #132 integration commit
`e6a816c6ce35fb2f5e579ddbe6b15286e895603e`.

The retained post-#132 Memprof samples attribute 373/651 no-cash samples and
486/1832 cash samples to spatial coefficients/preparation. These are sampled
allocation counts, not exact attribution percentages or timing. Interpolation
remains a separate cash hotspot. Investigate sharing immutable spatial bands
and payoff across sequential refinement runs whose stock grids are identical.

One price request fixes the model, side and configuration. The deterministic
stock grid depends on those fixed inputs plus spatial refinement level and
domain expansion. A single-entry cache may reuse preparation only for the same
(level, domain) key, independent of time count, mapping grid and boundary choice.
No reuse across requests, mutable solution/policy arrays, global cache, native
backend, numerical-operation changes or altered refinement is permitted. Keep
original row ticks, cancellation sites, switched-row diagnostics and failure
checks. Derive the live-storage bound before implementation.

Engineering criteria: at least 10% less cumulative allocation on none/zero/cash
price and requested-diagnostics workloads, no more than 10% median latency
regression. Retain multiple-cash and admission controls, and report any failure
against the original criteria. This is an improvement threshold, not a deployment
memory budget or SLA. Use the unchanged #132 allocation driver and collector,
exact configurations, five alternating fresh-process pairs, warmup, three price
calls, 100000 admissions, Gc.counters, own-child wait4 RSS/CPU, source/binary hashes
and host load. Finish task-owned builds/tests/profiling before timing.

Require unchanged complete outcomes and independent scoring for all 284 original
American cases/configurations, including failure/refinement/work diagnostics.
Run build/format and full development/release ordinary suites, native/bytecode
coverage and affected American mutations. Add a fault witness for wrong-grid
reuse. No new tolerance, reference, digest or classification is authorized to
make the optimization pass. The five default CI jobs and seven core mutants
remain unchanged. Broader #119 and numerical/source-artifact #120 stay open.
