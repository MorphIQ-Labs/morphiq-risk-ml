# Bermudan boundary-discount reuse (#119)

The scalar solver reuses successful zero-stock put boundary values within a
price request. Its original slab/time-grid key preserves the enclosed evaluator;
optional preparation fits within surplus workspace and falls back when it cannot
fit. Calls and immediate-opening, nonnegative-rate American puts skip the cache.
The [contract](bermudan-pricing.md) describes ownership, validation and resource
accounting. Outputs remain estimated-only.

The [protocol](evidence/bermudan-boundary/protocol.md) was frozen at `a6b4dc9`
before runtime edits. Baseline build is `a6b4dc987831b0db26dd715702297387f2774f2a` (runtime identical to
integration `6ce0645`); candidate is `6b6e45a318d303dae2cc4e79bb020dddfd88bce1`. Build manifests bind
library, driver and collector sources, compiler settings and binary hashes.
Later documentation commits do not requalify changed runtime code.

## Numerical compatibility and assurance

All **412 complete outcomes** match: 128 Bermudan and 284 American, across
initial/refined grids and primary/loose targets. The unchanged independent
references are reused and rescored, not regenerated. Every failure and uncertain
reference remains present in [the paired record](evidence/bermudan-boundary/compatibility.json).
Refined loose Bermudan coverage stays at 26 independent passes, five references
too wide and one runtime refusal; refined primary stays at 16 passes/16 refusals.

Resource controls compare absent, partial and ample cache capacity, cancellation
counts, positive/negative rates and a cash event between irregular rights. An
oversized optional array must fall back without throwing an allocation-size
exception. Existing concurrent-call controls exercise request ownership.

The cache-key mutant drops the slab endpoints and next-right word. Its final
numerical witness uses high diffusion so the zero-stock boundary is observable
at the refined spot anchor. Before the first exercise/cash date, with r,q >= 0,
`K exp(-r*(opening-t)) - S` is a backward-Euler subsolution:
`exp(-r*h)*(1+r*h) <= 1`, and the linear stock term contributes `-h*q*S <= 0`.
Payoff and exterior values dominate it. The test allows accumulated residual
and arithmetic screens; it does not subtract observed refinement changes from
this bound. The initially looser witness could mask the faulty price behind
those changes, although compatibility already rejected it. Earlier attempts
are retained alongside the final successfully built mutant, which fails
`cached irregular feasible stopping lower`. No runtime tolerance was widened.
This discrete regression is not a continuum certificate.

Development and release ordinary suites, package/format checks and mutation
harness controls pass. Eleven affected named mutants are killed; the added
numerical witness has its own clean baseline and successful mutated build.
The catalog has 113 entries; default CI remains five jobs/seven core mutants.
Full-catalog execution and source-artifact release qualification are not claimed.

## Paired cost and remaining scope

| Workload | Median latency, baseline → candidate | Allocation / price | Reduction |
|---|---:|---:|---:|
| American, none | 146.25 → 147.04 ms | 12.898 → 12.898 MB | -0.00% |
| American, cash | 431.78 → 427.29 ms | 42.154 → 42.154 MB | -0.00% |
| Bermudan, none | 402.29 → 297.97 ms | 178.895 → 40.525 MB | 77.35% |
| Bermudan, cash | 588.22 → 439.41 ms | 259.142 → 63.986 MB | 75.31% |

Both Bermudan workloads pass the frozen ≥60% allocation / ≥20% latency
improvement criteria. Median latency falls 25.9% without cash and 25.3% with
cash. American allocation changes by only 216/264 bytes; its median timing
changes by +0.54%/-1.04%, within the frozen regression gates.

The host is Apple M1 Pro, macOS 27, OCaml 5.3.0 Flambda with the recorded
release flags. Load during timing is 14.64–19.98. Bermudan latency ranges are
recorded per variant in the raw report; per-process peak RSS across the entire
campaign is 5.93–8.39 MB, including admission processes.

Five fresh processes per variant/workload alternate order, with one warmup,
a full major collection and three measured prices per process (100,000 calls for admission). Pricing reuses
admission; American admission and diagnostics are reported separately.
[Raw samples and manifests](evidence/bermudan-boundary/performance.json) include
GC counts and per-child peak RSS. Task-owned compute finished before timing;
this remains a shared host. Cumulative allocation is not live memory or RSS.
The frozen improvement criteria are engineering gates, not deployment budgets.

Remaining boundary exponentials account for about 60% of no-cash and 37% of
cash sampled allocation; cash interpolation accounts for another 28% in the
cash profile. These are samples of allocation volume, not latency attribution.
The unchanged source-bound profiling driver uses the same library source and
records its installed archive hashes. Residual 40.5/64.0 MB allocation is still
material and is not an accepted deployment budget.

The first collector attempt used three admissions, which rounded elapsed time
to zero. The collector correctly rejected that sample; the raw failed attempt
is preserved in the archive. Admission now follows the existing American
harness's 100,000-call convention. Price workloads and acceptance thresholds
are unchanged.

Reproduce with `scripts/benchmark_bermudan_boundary.py --baseline BASE.json
--candidate CANDIDATE.json --output NEW_DIRECTORY`, using clean source-bound
release builds recorded by the retained capture script. The compatibility archive
contains all inputs, outputs and independent scorer results; the performance
archive contains stdout, stderr and per-process resources. Artifact hashes are
recorded in the evidence manifest.

This closes the focused boundary-discount follow-up only. Broader compiled
workloads, Greek/IV execution, native backend evaluation and deployment acceptance
remain under #119/#120 and their dependencies. American integration remains
separate from main; no release or independent-review acceptance is implied.
