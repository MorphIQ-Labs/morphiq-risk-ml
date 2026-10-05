# Cost characterization protocol

Freeze before collecting timing. Five fresh processes per workload, one warmup,
full major collection, then three timed prices using reused admission. Record
raw stdout/stderr, allocation, GC and per-child peak RSS, hardware/load, compiler,
source revisions/hashes and binary hashes. Finish task-owned builds, reference
runs, suites and mutation work before timing. Alternate baseline/candidate order.

Matched American regression uses the unchanged `bench/american_allocation.ml`
price phase, no cash and one cash payment, on #133 and this candidate. Reuse a
recorded source-bound #133 binary only after every recorded source hash is checked
against integration 9635803. European paths are untouched; ordinary numerical
suites remain required. No new latency threshold or deployment SLA is introduced.

Bermudan characterization uses `test/bermudan.ml --bench none/cash`, constant
S=K=100,r=.05,q=.02,vol=.2,T=1, first right .5, terminal right 1. Cash mode adds
D=5 at .5 and both event-side rights. Config: 128 cells/steps, two domain
expansions, tolerance 1, refined campaign resource limits. Admission and diagnostics
are excluded. American and Bermudan models are different; do not call their timing
ratio a speedup. A quiet shared host remains uncontrolled. #119 owns later tuning.
