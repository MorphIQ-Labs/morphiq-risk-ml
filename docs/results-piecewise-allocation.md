# Piecewise allocation reuse (#119)

This pass reuses successful upper-boundary scalars and immutable spatial
stencils within one scalar American/Bermudan price request. The numerical
method, estimated-only contract and public API are unchanged. Misses still use
the original enclosed evaluator. The [piecewise contract](piecewise-american.md)
defines identities, ownership and the shared surplus-workspace accounting.

The [protocol](piecewise-allocation-protocol.md) was frozen at `4965425` after
baseline profiling and before runtime edits. The baseline is integration
`5155d64f4a01262e504cc757d5f392c77aec1e11`; candidate build manifests bind source,
compiler, immutable binaries and frozen benchmark drivers. No reference is
regenerated or tolerance widened for this optimization.

## Why these changes

Three-call Memprof samples (rate 0.0001, stack depth 24) attribute about 59% of
no-cash allocation and 48% of cash allocation to upper-boundary exponentials.
Repeated stencil preparation is another large contributor. These are allocation
samples, not CPU-time attribution. The two frozen workloads are staggered
coefficients and a cash event coincident with coefficient changes.

Successful upper values depend on the immutable request, exact original slab
endpoints, step count and original boundary scale. Calls retain the stock-grid
endpoint; puts retain strike. Zero and upper entries are separate. Cache hits
follow a previous successful boundary check under the same local allowance;
the request's maximum boundary-error diagnostic only increases.

Stencils retain all original coefficient words and only one grid key at a time.
Snapshots copy the working bands, so later coefficient changes cannot mutate
prior entries. Logical stencil-row visits, cancellation polling and upwind
counts remain in place. Both caches share one checked surplus budget; stencil
charges are released on grid changes. Insufficient capacity falls back to the
original evaluation, without a new workspace admission requirement.

## Qualification

All **572 complete outcomes** match baseline: 412 constant American/cash/Bermudan
and 160 piecewise outcomes, across initial/refined grids and primary/loose
targets. Ordered outputs, full-outcome fingerprints and independent scores match.
Refined loose piecewise coverage remains 36 independent passes and four references
too wide; refined primary remains 14 passes and 26 runtime refusals. Equality is
compatibility evidence, not a continuum accuracy proof.

The new structural controls use 32/32 grids and compare absent, partial and ample
cache capacity for varying
volatility, staggered rates/yields/volatility and a coincident cash event, for
puts and calls. They preserve complete results and cancellation cadence. The
existing concurrent-request test checks ownership. Three optional faults target
coefficient identity, mutable snapshot aliasing and the call-grid endpoint.
An initial test-harness attempt used redundant 128/128 bytecode solves for these
structural checks and was stopped for cost; its partial logs are retained. The
independent refined witness, all frozen cases and tolerances were unchanged.
The final campaign passes development and release ordinary suites, package
build, formatting, native/bytecode controls and the installed native public
profiling client. It kills 19 affected compiled mutations, including the four
new dependency faults. The catalog contains 121 mechanisms; default PR CI
retains seven core mutants and five jobs. Full-catalog and supported-platform
source-artifact qualification remain separate obligations.

The first paired campaign met the allocation targets (60–63% reduction) but
failed the unchanged latency targets: only 14–15% lower medians. All 60 raw
samples and its failed collector result are retained under `iteration-1` in the
archive. Five-second macOS CPU samples of the installed native driver attributed
47% of no-cash leaf samples to constant-slab work, 19% to residual evaluation and
18% to row-visit checks. Sampling stacks are incomplete; these percentages are
local attribution, not a timing guarantee.

That evidence motivates inlining the unchanged row check and reusing original
matrix bands within each constant slab. The first step keeps the original
arithmetic, RHS update and dominance check order. Later steps keep every logical
visit and RHS update; policy elimination does not mutate the retained bands.
Each new slab rebuilds for its own coefficients and width/step count. A new
fault deliberately keeps stale bands across slabs. Acceptance criteria,
reference tolerances, work accounting and public outcomes remain unchanged.

## Paired performance

Baseline is `5155d64f4a01262e504cc757d5f392c77aec1e11`; final candidate is
`c0013da` (full source/binary hashes in the qualification record). Apple M1 Pro,
macOS 27 arm64, OCaml 5.3.0 Flambda; unchanged release compiler settings and
benchmark bodies. Five alternating fresh-process rounds per variant/workload,
one warmup then three reused-admission prices, give these medians:

| Workload | Baseline ms/price | Candidate ms/price | Baseline MB allocated/price | Candidate MB allocated/price |
|---|---:|---:|---:|---:|

| american none | 145.70 | 130.41 | 12.905 | 12.909 |
| american cash | 425.85 | 380.31 | 42.164 | 42.171 |
| bermudan none | 294.46 | 264.71 | 40.532 | 40.538 |
| bermudan cash | 434.50 | 391.10 | 63.996 | 64.003 |
| piecewise none | 886.78 | 676.77 | 340.841 | 127.025 |
| piecewise cash | 538.71 | 412.69 | 218.944 | 87.050 |

Both piecewise workloads meet the predeclared ≥50% allocation and ≥20% latency
improvement criteria: allocation falls **62.73% / 60.24%**, latency **23.68% /
23.39%**, without/with cash. Constant-path allocation increases by at most 0.031%
and latency falls about 10%; all four constant regression criteria pass.

Candidate piecewise per-child peak RSS is 8.06–8.26 MB,
including warmup and three prices; this is distinct from cumulative allocation.
Host load during final timing ranges from 11.53 to 23.65.
All owned test/build/profile sessions had returned successfully before the
accepted campaign. A prematurely started partial run was stopped and retained
as invalid because the release/profile pipeline was still active. Neither that
partial run nor the failed first campaign counts as acceptance. This shared-host
comparison is not a deployment SLA.

[Qualification records](evidence/piecewise-allocation/qualification.json) retain
all 572 compatibility counts and independent classifications, source/compiler/
binary identities, every final timing sample, GC counts, RSS and variation.
The [raw archive](evidence/piecewise-allocation/qualification-raw.tar.gz) includes
the failed and invalid partial timing attempts, CPU/allocation profiles,
reference outputs and test logs. Its members and archive have SHA-256 hashes.

Reproduce final timing with `python3 scripts/benchmark_piecewise_allocation.py
--baseline BASELINE.json --candidate CANDIDATE.json --output NEW_DIRECTORY`.
Build clean immutable revisions with the frozen release drivers; the archived
`capture.py` documents source/binary manifest construction. `compare.py` executes
all four unchanged scorers at both targets and configurations. Profiling uses
the retained installed-public-API driver; profile data is not timing acceptance.

## Remaining scope

The remaining **87–127 MB allocated per piecewise price** is still material,
and these measurements cover two scalar American workloads. Constant Bermudan
costs are regression controls; varying Bermudan throughput, Greeks, IV, compiled
batches and deployment budgets are not qualified by these measurements. Existing
strict-target failures and wide references remain explicit. #119, #120 and
Epic #107 stay open; the focused piecewise allocation follow-up is complete.
