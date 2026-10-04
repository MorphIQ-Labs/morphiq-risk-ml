# Local operational baseline — issue #16

The configurable [operational campaign](operational-campaign.md) completes its
local engineering run. Deployment hardware/workload and operational acceptance
targets remain undecided, as directed by the maintainer. The library and pricing
contracts are unchanged. This is a short, instrumented synthetic application
baseline, not a sustained-load test or deployment approval.

## Identity and protocol

- Final source: `07fd3ff86fe48f67127fe40243138d8216839c57`; library tree
  `0da7e7fda5ef50b4bd7696580829fd9a3adea598`, identical to candidate
  `f703546ea736d456f64e74be6ef9d2da2c10ef88`.
- Native runner SHA-256: `fb4145eca2d26cf248c8593933caea58ed506cf9f936bfedd33e27816fb8c2c4`.
  OCaml 5.3.0 Flambda, Dune release profile, unchanged library arithmetic flags.
  Full compiler configuration and source hashes are in the report.
- Apple M1 Pro, 10 logical CPUs, macOS 27 ARM64. Final collection:
  **2026-10-04T23:32:38Z–2026-10-04T23:32:44Z**; one-minute host load
  **6.42–6.54**. No task-owned build, test or profile ran
  during timing. The host was shared, with no pinned cores or frequency control.
- [Specification](../bench/operational-local.json), SHA-256
  `2d7491edb1a4074e2d08975dd92951d477e919ad57559752c838c9067a68aa60`, was copied before child startup. Seven cases each
  use three fresh-process repetitions, one cold request/client, two warmups and
  ten measured requests/client: **36 processes, 36 cold requests, 72 warmups and
  360 measured requests**. Cases run in specification order.
- Every case uses the documented fixed four-model corpus. Workers/tile/buffer,
  output set, sink, plan policy and concurrency are explicit in the specification.
  Certified numerical allowances are `1e-8` in each quantity's own units.
  Zero ordinary returned failures was fixed as a diagnostic criterion before
  scoring; it is not a business failure-rate policy.

The [final archive](evidence/operational-campaign/final.tar.gz) contains the exact
configuration, full report, all 21 process-group records and original per-child
stdout/stderr. It contains JSON/text evidence only. [Checksums](evidence/operational-campaign/SHA256.json)
cover both archives and the source-integrity controls.

The [initial archive](evidence/operational-campaign/initial.tar.gz) retains an
otherwise identical earlier campaign from `be4677cb986e802d459eb615d3695a2d536ef766`
at 23:25:48–23:25:54 UTC, load 9.94–10.20. It used the **same native binary**.
The final repeat follows stronger collector checks for staged/untracked library
sources; the workload and pricing implementation did not change. Its earlier
measurements remain intact. No implementation speedup is inferred from differences
between these two short host sessions.

## Observed requests

These are parent-observed command-to-response latencies, including local pipe,
diagnostic encoding and evidence-collection overhead. "Cold" is the first
request after each process eagerly compiles its baseline plan, not cold machine
startup. P95 is nearest-rank over only 30 or 60 measured requests, with no tail
confidence claim. Completed-request throughput is across the client group;
it excludes cancelled requests. RSS is the largest single-child lifetime peak,
including the post-timing replay check, not simultaneous application-wide memory.

| Case | Rows/request | Clients × workers | Cold median ms | Warm median ms | Observed p95 ms | Completed requests/s | Peak child MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fast-reuse-one-client | 4,096 | 1 × 4 | 2.970 | 2.800 | 3.106 | 350.61 | 17.06 |
| fast-reuse-two-clients | 4,096 | 2 × 4 | 3.721 | 3.271 | 3.521 | 588.12 | 17.48 |
| fast-recompile-digest | 4,096 | 2 × 4 | 6.734 | 6.378 | 6.646 | 308.99 | 15.14 |
| certified-price | 128 | 2 × 4 | 32.398 | 32.369 | 35.064 | 59.93 | 16.63 |
| certified-all | 32 | 2 × 2 | 31.758 | 31.595 | 31.920 | 63.19 | 11.57 |
| fast-cancellation | 65,536 | 2 × 4 | 2.855 | 2.712 | 2.918 | 0.00 | 29.87 |
| certified-boundaries | 24 | 1 × 2 | 8.575 | 8.126 | 8.281 | 123.16 | 10.91 |

`certified-all` and `certified-boundaries` request eleven outputs per row;
other cases request one price. The recompile/digest case changes both plan
lifecycle and sink work, so its difference cannot be attributed to either one
alone. Single-client and two-client cases are sequential short sessions; these
numbers do not establish linear scaling or a fixed service capacity.

All five ordinary cases returned **643,200 successful measured outputs and zero
failures**. Their complete request counts and full post-timing replay agree
across processes, repeats and worker counts. The three comparable fast workload
cases also have identical replay digests despite lifecycle/sink differences.
Count-sink timed requests enforce order/counts without hashing values; their
full value replay runs separately after timing.

The boundary case retains **2,400 unsupported expiry Greek outcomes and 2,640
post-expiry outcomes**, alongside 2,880 served outputs. These refusals are not
reported as accuracy successes. They are expected capability outcomes for the
explicit diagnostic input and remain outside any approved business failure policy.

All **60 measured cancellation requests** report `Cancelled`, with 122,880
committed rows and **3,809,280 uncommitted calculations** retained in aggregate.
The maximum observed actual-cancellation-to-executor-return interval is
**0.657 ms** in the final run (1.020 ms in the retained initial run). Controller
issuance and scheduling lateness are separately recorded. This is finite
schedule evidence, not a cancellation bound. Zero completed-request throughput
in that case is intentional; response throughput is a separate raw statistic.
The post-timing full replay contributes to the cancellation case's lifetime RSS.

Coordinator allocation and GC counters, process CPU, first-row observations,
startup/initial compilation, parent submission/receipt timestamps and all request
records remain in the archives. Coordinator-only allocation excludes pricing in
spawned domains and is not a total-allocation estimate. Collection counts are
not GC pause time. Results retain the distinction between compilation, reuse,
output handling and the parent's instrumented response path.

## Validation and remaining scope

Both development and release package builds, formatting and the new ordinary
`@bench/runtest` controls pass. Seven test groups cover fast reuse/recompile replay,
certified expiry/post-expiry classes, cancellation accounting, unobserved
cancellation remaining pending, malformed/duplicate/nonfinite configuration,
invalid or fabricated result counts, changed completed-request replay, EOF,
truncation, timeout/reaping, failed startup, destination preservation and CLI
handling. They impose no machine-speed threshold.

The retained [source-integrity controls](evidence/operational-campaign/integrity-controls.json)
use an isolated temporary Git fixture: staged, unstaged and untracked library
changes are each refused before pricing. A deliberately impossible zero-latency
criterion produces exit 1 with complete measurements and no deployment approval.
The [control source](evidence/operational-campaign/integrity-controls.py) is retained
for reproduction from the repository root after the release build. The earlier
worker/tile collector now uses the same staged/untracked source safeguard; its
historical evidence keeps the original collector hash and measured revision.

Required CI still runs the full ordinary suites in development/release on three
platforms plus seven core mutations. Local numerical suites and the full mutation
catalog were not repeated for this benchmark/tooling-only change. No kernel,
public API, numerical threshold or package-version change; no release artifact
was generated.

The report correctly sets **`deployment_accepted: false`**. Latency, throughput,
RSS and cancellation criteria are pending because their targets are null. The
completed ordinary failure checks do not supply those decisions. #16 remains
open for intended business inputs, deployment environment, operational targets
and the responsible owner's recommendation. #15's independent review and #17's
exact-candidate acceptance remain separate obligations. No release or tag.
