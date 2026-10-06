# Compiled American requests: qualification and costs (#118)

Adopt `Batch.American` and `Planner.American` as additive typed APIs on the
American integration branch. Fixed batches reuse immutable admissions; dated
plans stream bounded ordered outcomes with explicit rolls and assurance types.
On the fixed eight-row workload, two workers improve general put/Greek execution
by about 1.9× and call IV/certification by about 1.6×. Small analytical calls gain
little, and their first output arrives later with two workers. Fixed batching
primarily adds reusable admission and a stable contract; it does not accelerate
the underlying numerical method.

## Source, scope and correctness

The [protocol](evidence/american-compiled/protocol.md) was committed as `c7b45d0`
before runtime implementation; the concrete measurement matrix was frozen in
`3b9f3f4` before timing. Runtime implementation starts at `aca2224`. Qualification
includes the row-count fix `83d6a6bb05a5a55744a7e8d027f99073778a941b`.
Measured source is `22aa3fc3dde24fae4c63cc0ef3357df320787b5d`; its subsequent change from the
qualified runtime is documentation only. Exact tracked/untracked source hashes,
compiler configuration, driver hash and binary hash are in the
[source manifest](evidence/american-compiled/raw/source-manifest.json).

The original scalar numerical implementation and native policy kernels are
byte-identical to integration `ff4517b8632d0d866022570e9c0000e16141884c`.
No price algorithm, Greek definition, IV convergence policy, certificate limit,
operator cache or arithmetic backend changes. Scalar configurations gain private
read-only introspection for exact-word identity. New public contracts are in
[the API guide](american-compiled.md); the [example](../examples/american_batch.ml)
is built and executed by the ordinary suite.

- Complete development and release ordinary suites, install/build/format and
  installed native/bytecode contract consumers pass. The ordinary determinism
  digest remains `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
- Typed scalar/batch/plan equivalence covers constant, cash, Bermudan and
  piecewise prices/Greeks, supported certified reductions and estimated IV,
  and explicit unsupported/refusal paths. Per-quantity Greek failures stay typed.
- Separate numerical/precondition controls cover terminal payoffs before/after
  cash, no duplicate after-payment debit, today's Bermudan right, no invented
  future rights, active/future curve knots, frozen inputs and ACT/365F/ACT/360
  integer-day conversion. Explicit scalar inputs are constructed independently
  of the adapter. Replay equality supplies compatibility evidence, not an
  independent accuracy proof; scalar accuracy remains covered by its owning
  contracts and the existing ordinary reference suites.
- Repeated and concurrent immutable plan use, 1/2/3-worker ordered outcomes,
  fresh arrays, foreign tiles, count/workspace/schedule/buffer bounds, callback
  exceptions, in-solve scalar cancellation, cancelled prefixes, sink refusal and
  sink exceptions pass. The common executor's existing forced spawn/domain/tile
  failure and joining controls also pass. No new compiler-enforced ownership
  guarantee is claimed.
- Three negative type witnesses reject piecewise inverse requests, estimated
  prices used as certificates, and fabrication of private solver settings.
- All nine new optional compiled mutants have a clean baseline, successful
  mutated build and a designated numerical/precondition rejection: current cash,
  current right, active knot, tolerance identity, workspace cap, buffer cap,
  cancellation forwarding, sink prefix and cash snapshot ownership. Default CI
  remains five jobs/seven core mutants; the optional catalog is 176.

Review found a real integer-accounting edge case in both American and European
planners: five zero-output positions × 10^18 scenarios could pass calculation
and tile limits while overflowing the total row count. Independent row-product
checks now reject these plans. Both regression cases fail before their respective
fixes and pass afterward. This deliberately tightens structural admission;
ordinary pricing and existing numerical digests remain unchanged.

The first full attempt also found test-harness integration problems: a European
instrumentation locator matched the new executor, and generated wrappers needed
the encoding helper through the unstable internal surface. Both are corrected.
A mutation startup copied a tracked Dune stanza before its new untracked module
was staged; a separate startup encountered a Dune lock. Neither was scored as a
kill. Initial failures, the original cash-fixture correction, wrapper repairs and
final successful logs are retained in the raw archive. The manual 572-price/
920-Greek scalar optimization replay was not rerun: this change does not modify
those scalar numerical owners; final artifact-wide qualification remains #120.

## Fixed local performance campaign

Apple M1 Pro, 16 GiB RAM, `macOS-27.0-arm64-arm-64bit-Mach-O`, OCaml 5.3.0 with Flambda,
native release/O3. All task-owned builds/tests/mutations/installed checks finished
before measurement. This is a shared host; one-minute load samples range
8.85–15.26, including decay from earlier jobs. No isolated-host
or deployment SLA claim is made.

Four positions × two scenarios (spot 100/101) produce **eight rows per execution**.
K=100, r=.05, q=0, sigma=.2, one year, no cash, full American rights. Price settings
are 64×64, two domains, tolerance 1; Greeks request delta/gamma with tolerance 10.
Call IV uses the independently fixed quote from the existing reference corpus;
quotes stay fixed under the spot shock. Certification uses absolute limit 1e-9.
The complete limits and inverse settings are frozen in the protocol. These are
not the 128×128 scalar optimization workloads, so their times are not a new
before/after scalar speedup.

Five fresh processes alternate mode and workload order. Each execution mode has
two warmups and five measured executions per process. Compilation has two warmups
and 100 measured repetitions. Each process checks full scalar/fixed/one-worker/
two-worker outcomes outside timing; every requested quantity is accepted.
The sink retains no rows and records its first arrival using the same monotonic
clock. Numbers below are median process means, with minimum–maximum process means
in parentheses. Batch time divided by eight is amortized throughput cost, not
single-request latency.

| Eight-row workload | Explicit scalar, ms | Fixed batch, ms | Planner 1 worker, ms | Planner 2 workers, ms |
| --- | ---: | ---: | ---: | ---: |
| Estimated analytical call | 0.696 (0.677–0.752) | 0.715 (0.684–0.739) | 0.712 (0.700–0.821) | 0.693 (0.625–0.816) |
| Estimated general put | 186.906 (183.140–188.709) | 186.508 (182.388–189.044) | 187.104 (185.410–196.773) | 97.032 (94.539–103.207) |
| Put delta + gamma bundle | 191.096 (187.643–197.600) | 185.465 (183.344–188.765) | 186.201 (183.334–189.239) | 98.218 (95.261–99.005) |
| Estimated call IV | 4.433 (4.404–4.585) | 4.421 (4.275–4.497) | 4.446 (4.296–4.508) | 2.819 (2.708–3.231) |
| Certified call reduction | 4.474 (4.396–5.137) | 4.428 (4.391–4.525) | 4.466 (4.385–4.582) | 2.827 (2.720–3.061) |

Compilation is separate from all execution measurements:

| Workload | Fixed batch compile, μs | Dated plan compile, μs |
| --- | ---: | ---: |
| Estimated analytical call | 33.83 | 22.46 |
| Estimated general put | 34.30 | 23.92 |
| Put delta + gamma bundle | 41.05 | 27.17 |
| Estimated call IV | 40.58 | 27.19 |
| Certified call reduction | 21.03 | 16.77 |

Fixed compilation takes pre-admitted scalar requests; dated compilation includes
base-model admission and schedule checks. Neither includes constructing the
caller's original records/scenario description. Dated execution includes fresh
scenario admission. No compilation timing includes numerical output acceptance.

## Allocation, GC, first output and cancellation

The following are **cumulative coordinator-domain counter deltas**, MB per
complete eight-row execution. With one worker they include all numerical work;
with two they omit worker bodies. OCaml's counters may include previous domain
ownership and are not a process-wide allocation API. The apparent halving in
the last column is not evidence of lower total allocation.

| Workload | Explicit scalar | Fixed batch | Planner 1 worker | Planner 2 workers, coordinator only |
| --- | ---: | ---: | ---: | ---: |
| Estimated analytical call | 1.038 | 1.038 | 1.048 | 0.526 |
| Estimated general put | 57.131 | 57.131 | 57.141 | 28.573 |
| Put delta + gamma bundle | 58.533 | 58.534 | 58.543 | 29.274 |
| Estimated call IV | 6.300 | 6.300 | 6.309 | 3.157 |
| Certified call reduction | 3.869 | 3.870 | 3.879 | 1.942 |

Fixed batches add approximately 456 bytes per eight-row execution in this corpus;
serial planning adds about 9.7 KB over the explicit pre-admitted scalar loop.
General-put cumulative allocation remains about 7.14 MB per row at these settings;
this feature does not resolve the remaining scalar enclosure-allocation work.
GC counts are retained as process-wide sampled diagnostics, outside any claim
of exact instantaneous allocation. No GC tuning was introduced.

Each fresh child's own `wait4` reports whole-process peak RSS, including workers,
all workloads and warmups. The five peaks are
16.29, 18.99, 16.01, 18.97, 16.09 MB.
They are not path-specific peaks, live workspace or simultaneous deployment
memory. Reverse-order processes have higher peaks here; long-lived concurrent
memory still needs qualification.

| Workload | First row, 1 worker, ms | First row, 2 workers, ms |
| --- | ---: | ---: |
| Estimated analytical call | 0.082 | 0.157 |
| Estimated general put | 21.781 | 22.609 |
| Put delta + gamma bundle | 21.927 | 22.871 |
| Estimated call IV | 0.529 | 0.671 |
| Certified call reduction | 0.403 | 0.560 |

Five separate in-solve cancellation probes requested cancellation after a 5 ms
controller delay. Actual issuance occurred 5.935–6.460 ms after launch; the extra
0.935–1.460 ms is controller scheduling/startup delay. Return occurred 77–152 μs after
actual issuance, with a zero-row/zero-calculation committed prefix and explicit
`Cancelled` each time. These are observations at this request/checkpoint size,
not a worst-case responsiveness guarantee. Interrupted work is excluded from
completed-request throughput.

The collector rejects incomplete, unknown, duplicate and nonfinite output and
checks its own failed-startup, nonzero-exit and kill/reap timeout controls.
No measured process failed, no requested output was dropped, and source/binary
hashes were unchanged across the campaign. All raw process means, CPU/GC/load
records, cancellation measurements and collector controls are retained.

## Disposition and remaining work

Use the compiled API for immutable request ownership, explicit date semantics,
reusable admission and bounded ordered streaming. Two workers help these eight-row
PDE/Greek/IV/certified workloads, but this does not choose a universal worker/tile
policy. Cross-row grid/operator/factor caching has not been added. Existing
scalar-owned compatible-grid/event/operator reuse continues with its qualified
dependency checks; solved value surfaces are never shared between shocked rows.

#119 retains cash/piecewise/hard-case batch campaigns, worker/tile sweeps,
whole-worker allocation collection, residual scalar allocation and actual-matrix/
backend crossover work. #120 retains final immutable source-artifact qualification,
independent-review/acceptance scope and platform-wide closeout. General American
certification, certified aggregates, settlement and economic P&L remain outside
this API. Neither issue nor the parent epic is completed by this campaign.

[Raw evidence archive](evidence/american-compiled/raw.tar.gz),
[SHA-256 manifest](evidence/american-compiled/manifest.json), and
[structured results](evidence/american-compiled/raw/timing.json).
