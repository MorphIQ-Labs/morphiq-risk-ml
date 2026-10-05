# Boundary reuse optimization protocol (#119)

Frozen before runtime edits, against integration `6ce0645ef5ec8f51ff0f67af162ca70275cb4e9e`.
This is a scalar, estimated-price optimization, not compiled execution or a
change to the finite exercise model. Main remains outside this integration work.

## Numerical and compatibility requirements

Reuse the unchanged 32-case Bermudan corpus and independent analytical,
quadrature and canonical evidence in `../bermudan/`. Run its existing scorer
before runtime edits and after them at initial/refined grids and primary/loose
targets. Sparse, dense, irregular, before/after/both cash sides, positive/negative
rates and unavailable/uncertain rows remain in scope. Do not regenerate matching
references merely to fit a candidate. Retain all 128 complete outcome snapshots
and classifications. Also compare all 284 American no-cash/cash outcomes at the
same two targets and configurations. Require complete serialized equality,
including failures, arithmetic indicators and logical work counters; numerical
accuracy remains a separate comparison to the independent references.

Add cache-specific resource-fallback, cancellation, request-isolation and key
regressions. An affected mutation must build and fail a numerical or
precondition witness; replay mismatch alone is not a kill. Run the full ordinary
development/release suites, install/format and affected named mutations.

## Design constraints

Reuse only successful zero-stock boundary evaluations within one price request.
Keys retain original slab endpoints, next exercise instant and time-step count;
each entry is indexed by the original integer step, never rounded time alone.
The fixed request owns model, side and numerical allowance. Preserve original
enclosed arithmetic on a miss, its validation and the monotonically accumulated
boundary error. Preserve every cancellation point and logical work counter.

Reserve cache bytes from surplus after existing conservative solver, cash and
exercise metadata reservations. Bound both entry count and arrays, check sizes
before multiplication/allocation, and fall back to unchanged evaluation when
space is unavailable. No new resource refusal for an optional cache. Audit the
shared American path (delayed opening and negative rates) as well as Bermudan.
No global cache, changed exponential, discount recurrence or new API.

## Performance requirements and measurement

Keep the unchanged `test/bermudan.ml --bench none|cash` price workloads and
`bench/american_allocation.ml` admission/price/diagnostics workloads as the
source-bound comparisons. Reused admission is excluded from Bermudan price
timing; admission itself is unchanged. Five fresh processes per variant/workload,
alternating order, one warmup, full major GC and three measured prices. Finish
task-owned builds/tests/profilers first. Record all raw output, build sources,
binary hashes, compiler/options, host/load, GC and per-child peak RSS.

Engineering go/no-go: at least 60% less cumulative allocation and 20% lower
median latency for each Bermudan workload. American none/cash price allocation
must not increase by more than 5%, median latency by more than 10%. Report spread
and investigate noise rather than widening these thresholds. These are focused
improvement criteria, not deployment SLAs or universal allocation budgets.
Record admission/diagnostics separately and report remaining bottlenecks.
