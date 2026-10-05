# Request-local American spatial preparation reuse (#119)

The [protocol](evidence/american-spatial-reuse/protocol.md) was fixed before
runtime changes, using #132 (`e6a816c6ce35fb2f5e579ddbe6b15286e895603e`)
as baseline. This pass extends immutable preparation reuse beyond a single
boundary pair to identical stock grids in the same scalar request.

## Dependency and ownership argument

`price` fixes admitted inputs, side, configuration, arithmetic precision and
local error allowance. `grid` depends on spot, strike, base space cells, node
capacity, spatial level and domain expansion. It deterministically inserts
anchors, balances, expands and bisects in the same order. Neither time steps,
cash-mapping level nor boundary choice changes those nodes. Resource/cancellation
failure aborts the request; only successfully constructed grids reach the solver.
For a fixed request, equal `(level, domain)` keys therefore mean identical node
words. Spatial bands additionally depend on the fixed volatility/rate/yield;
payoff depends on the fixed strike and side. Time-step matrices and boundary data
remain outside the cache. Piecewise model inputs would require revisiting this
dependency argument before extending the implementation.

One request-local reference owns a single entry containing a key and the
immutable left/right bands, payoff and switched-row count. Different keys release
the old preparation before constructing a new grid; returning to an evicted key
rebuilds it. Each request/domain owns a separate reference. No scratch or returned
estimate borrows or mutates these arrays. Preparation is published only after
all payoff and coefficient checks pass. Length checks reject inconsistent cached
bands explicitly before use; the key/dependency argument, not length equality,
establishes coordinate identity.

The three bands replace the current solve's three arrays and are never copied
for caching. They can remain live during reconstruction of an identical grid,
adding at most three float bands at that phase (24 bytes per maximum node plus
array headers). During solving they are the original three bands, so solve-time
peak storage is unchanged. Grid construction needs at most its capacity array,
returned grid and the cached bands, plus any retained mapping grid: fewer than
the 24 float bands already covered by the conservative 512 bytes/node workspace
reservation. A changed key drops old arrays before grid construction. No per-event
or per-refinement history is retained; existing cash metadata reservation and
policy/region/temporary allowances are unchanged.

Every original grid/payoff/stencil row visit and cancellation point remains.
Reuse contributes the original switched-row count, not zero. Boundary arithmetic
error is a request-wide monotone maximum, already containing the identical payoff
check. Limits, error allowances, operation graphs, matrices, policy iteration,
event sides, dividend interpolation and refinement acceptance are unchanged.
American successes remain estimated-only. Shared European numerical code is
unchanged.

## Qualification

All 284 complete American outcomes and independent scores match #132 across
primary/loose and initial/refined configurations. Prices, failures, refinement,
work counts and diagnostics retain identical full-outcome fingerprints. Replay
is compatibility evidence; independent reference scoring remains the accuracy
evidence. Strict-target availability and reference uncertainty are unchanged.
See the [complete comparison](evidence/american-spatial-reuse/compatibility.json).

Build/format and full development/release suites pass, including native/bytecode
American controls, concurrent independent calls, limits and cancellation. All
seven affected American mutants are rejected after a clean baseline. The new
wrong-grid key fault builds successfully and produces the explicit spatial-band
length refusal through the public capability witness; it is a precondition kill,
not a price-error or continuum-accuracy proof. The existing reversed-stencil
fault remains a separate numerical capability witness. Full catalog is 109;
default CI retains five jobs and seven core mutants. See the
[validation record](evidence/american-spatial-reuse/validation.json) and retained logs.

## Matched measurements

Same driver/configurations as #132: estimated ATM put, S=K=100, r=.05, q=.02,
sigma=.2, T=1, opens=0, tolerance=1, 128/128 base grid/time counts, full refinement
and the recorded caps. None, zero payment, payment 5 at .5, and payments 3 at .25
plus 4 at .75; price and requested diagnostics are measured separately from
100000 admissions. Five alternating fresh-process pairs, one warmup, three
measured prices per process. Task-owned builds/tests/profilers finished first.

Apple M1 Pro, 16 GiB, macOS 27, OCaml 5.3.0 Flambda, release `-O3`.
Shared-host one-minute load: 4.73–14.35. These are local engineering results,
not isolated-host latency or deployment capacity guarantees.

| Schedule, price only | Cumulative allocation before → after | Reduction | Median latency before → after | Candidate process-mean range |
| --- | ---: | ---: | ---: | ---: |
| none | 16.69 → 12.90 MB | 22.7% | 140.3 → 138.0 ms | 137.5–163.4 ms |
| zero | 37.01 → 29.41 MB | 20.5% | 396.9 → 392.4 ms | 390.6–477.2 ms |
| cash | 49.75 → 42.15 MB | 15.3% | 406.5 → 406.1 ms | 401.9–418.2 ms |
| multiple | 76.78 → 69.19 MB | 9.9% | 611.0 → 604.9 ms | 601.9–611.6 ms |

The original ≥10% allocation reduction / ≤10% median latency regression criteria
pass for none/zero/cash prices and requested diagnostics. Multiple-cash is a
retained control, with 9.9% less allocation. Admission allocation is unchanged.
Latency is broadly unchanged, with overlapping ranges; no speedup is claimed.
All samples, including the slower zero-cash candidate process, are retained.

Cash peak process RSS is about 8.1 → 8.0 MB; no cash 7.7 → 7.8 MB. Collections
per three measured cash prices fall from 76 minor/15 major to 64/14; no cash
26/9 → 21/8. MB means 1,000,000 bytes. Allocation uses Gc.counters
(minor + major − promoted); GC cycle counts use quick_stat. Per-child wait4
supplies RSS/CPU. Cumulative allocation, live numerical workspace and process
RSS are distinct. Approximately 42 MB per cash price is still material.

[All measured samples and build manifests](evidence/american-spatial-reuse/performance.json)
and compressed raw records are retained. The
[follow-up allocation profiles](evidence/american-spatial-reuse/profiles.json)
retain the exact candidate build and original Memprof stacks. Profiler timing
is excluded from performance evidence. Dividend interpolation and enclosed
boundary/time arithmetic remain separate allocation costs. This bounded pass
does not close broader #119, establish a deployment budget or complete #120.

## Reproduction

Baseline build is `aa65f19` (#132 runtime plus the frozen protocol); candidate
runtime is `a0b93a7`. Both complete revisions, source manifests, compiler options
and binary hashes are in performance.json. Later changes package documentation
and evidence only. Rebuild the recorded sources with the pinned switch/release
profile and retain separate executable copies of `bench/american_allocation.exe`,
`test/american_pricing.exe` and `test/american_cash.exe`. Capture new build manifests
using the retained schema; do not relabel historical binary hashes.

Run `scripts/check_american_runtime.py` and `scripts/check_american_cash.py` with
`MORPHIQ_AMERICAN_SNAPSHOT=1`, both primary/loose modes, with/without `--refined`,
and compare complete stdout and independent scores. After builds, tests and
profiling finish, run from the candidate worktree with a new output directory:

```sh
python3 scripts/benchmark_american_allocation.py \
  --baseline baseline-build.json --candidate candidate-build.json \
  --minimum-allocation-reduction .1 --maximum-latency-regression .1 \
  --output spatial-paired
```

The collector guards source/driver/compiler/binary identity, retains every raw
sample and fails incomplete or out-of-criterion campaigns. Broader batch/worker,
backend and algorithm evaluation remain under #119; no European Fast or certified
kernel changed in this pass.
