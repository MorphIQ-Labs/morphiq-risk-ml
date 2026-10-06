# Remaining American allocation attribution (#119)

Baseline: integration `9fae37a6f6eb13d09db99f658d8432a84c3421f6`, after the
actual-policy backend comparison. Keep the existing bounded native solver.
This first step identifies current allocation owners; it does not change
production arithmetic or claim a speedup.

Use the frozen #147 singleton inputs/configuration through `Backend_inputs`,
including request id 0, 64 initial space cells/time steps and the unchanged
work/accuracy limits. Capture flat, cash, Bermudan, piecewise, piecewise-cash,
delta/gamma, IV and strict requests. Refused outputs remain in the corpus.
Compare native/bytecode complete request digests before profiling.

Run three fresh native processes per workload, 20 calls per phase, reversing
case order on the middle round. Record unprofiled main-domain managed allocation
from `Gc.counters` separately from `Gc.Memprof` attribution at sampling rate
0.0001 and stack depth 20. No workers are created. Keep full raw stacks and
sample counts; sampled shares are estimates, not exact allocation budgets.
Profiler overhead/timing must never substitute for ordinary request latency.

Record compiler, source status/patch and binary identities; finish task-owned
builds before collection. Reject missing completion, changed request replay,
failed children and source/binary drift. Retain per-child RSS with its profiling
scope explicit. Do not interpret it as an unprofiled deployment peak.

Choose any implementation follow-up from these profiles. Before changing
production code, freeze its exact dependency/safety argument and matched
before/after campaign. Arithmetic changes require independent evidence; smaller
allocation does not justify widening tolerances, hiding refusals, or weakening
work/cancellation boundaries. Complete #120 qualification follows the resulting
performance decision; deployment acceptance still needs owner-supplied targets.
