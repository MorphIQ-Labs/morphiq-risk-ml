# Focused American allocation campaign

Freeze before modifying runtime code. Baseline is integration commit
732f6b61ff1d8be2cd16037adf4fc03ede76dc89 (#130). Initial Memprof evidence
attributes about 95% of sampled cash allocation to residual/step row loops.

This pass specializes float comparisons and explicitly inlines small numerical
checks. Keep the original conditional selection (including signed-zero ties),
operation ordering, multiplication barrier, explicit FMA, all finite checks,
refinement criteria, event phases and resource/cancellation accounting. No new
backend, foreign primitive, mathematical approximation or shared scratch.

Engineering acceptance: at least 90% lower allocated bytes for the identical
refined loose ATM none/zero/cash requests; repeated-process median latency
must not regress by more than 10%. These are this optimization's criteria,
not a deployment SLA. Retain multiple-payment measurements and analytical/
hard-case outcomes; do not relabel unavailable output as throughput.

Use S=K=100, r=.05,q=.02,sigma=.2,T=1,opens=0; no cash, cash0 at .5,
cash5 at .5, and cash3 at .25 plus cash4 at .75. Reuse admitted input/config;
128 cells/128 steps, 2 domain expansions, tolerance1; max nodes8192,
steps131072, policies1048576, row visits1e9, workspace8388608, policy iterations64.
Measure admission separately (opaque inputs, 100000 iterations), prices and
optional diagnostics (3 iterations/process, one warmup, full major GC).
Five fresh processes per mode/candidate; alternate baseline/candidate order.
Finish all task-owned builds/tests/profiling before timing. Record host load,
source/executable hashes, compiler/options, raw samples, GC counts and per-child
peak RSS via that child's own wait4. RSS is not allocation or live workspace.

Run the unchanged 41-case no-cash and 30-case cash primary and separately loose
corpora in initial/refined configurations, with independent reference scoring.
Compare every complete baseline/candidate outcome including failures and work/
refinement diagnostics. Any changed numerical result requires investigation
against original-input independent references; never widen an accuracy target.
Preserve all unresolved references. Verify native/bytecode controls, ordinary
tests, package/format and the five affected American mutants. Default CI remains
five jobs with seven core mutants. The broader #119 batch/native/algorithm
campaign stays open.
