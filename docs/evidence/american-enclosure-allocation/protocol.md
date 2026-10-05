# Second scalar American allocation pass (#119)

Freeze before runtime edits. Baseline runtime is American integration
1d1b35623003c226d017a924055c090de4642629 (#131). Three-request Memprof profiles
at sampling_rate=.0001 and stack depth12 confirm that enclosure construction,
packing arrays and arithmetic dominate remaining allocation. Retain the raw
profiles; profiler timing is not latency evidence.

First investigate fused scalar enclosure operations and explicit inlining.
Avoid intermediate exact/negated records while retaining logical word sequence,
signed-zero shortcut results, product/residual/error accumulation order, all
finite checks, radius bounds, precision and series lengths. The scope includes
both enclosure precisions and their European users; no American-only shadow
arithmetic, global mutable cache, unsafe operations or new FFI.

Engineering criteria, chosen before comparison: reduce allocation by at least
50% versus #131 on matched no/zero/one-cash requests, with and without optional
diagnostics; at most 10% median latency regression. Retain two-cash results.
This is an improvement criterion, not an acceptable deployment allocation budget
or SLA. Further measured opportunities may be needed before portfolio scaling.

Reuse #131's exact inputs, 128/128 grids, full refinement program, work limits,
five alternating fresh-process pairs, one warmup, three price calls and 100000
admissions. Allocation now uses Gc.counters rather than approximate quick_stat
word totals, for both builds; retain quick_stat GC counts, per-child wait4 RSS,
host load, source/binary hashes and all raw records. Finish task-owned builds,
tests/profiling before final timing. Run the collector with
--minimum-allocation-reduction .5 --maximum-latency-regression .1.

Retain all 284 original American complete outcomes (41 no cash +30 cash,
primary/loose, initial/refined), independent reference scoring, all failure and
unresolved classifications, and native/bytecode controls. For shared enclosure
changes, add exact-rational and full-field differential tests over scalar
specializations, signed zeros, subnormals, thresholds, overflow and error radii;
the generic operations are a compatibility comparator, not the accuracy oracle.
Run full development/release suites and affected enclosure/American mutants.
Never widen a numerical tolerance or weaken refusal to improve performance.

Also compare the existing European certified_scalar workload in five alternating
fresh-process pairs: require unchanged complete CHECK records, no >10% median
price/end-to-end latency regression or allocation increase per case. Retain all
eight cases and their five inner samples. Ordinary Fast/reference/determinism
tests remain required. Certification coverage and public APIs are unchanged.
Default CI stays five jobs/seven core mutants; broader #119 remains open.
