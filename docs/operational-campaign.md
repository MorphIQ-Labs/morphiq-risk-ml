# Configurable planner operational campaign (#16)

This optional campaign measures application-facing planner work in persistent
native processes. The maintainer selected a configurable campaign with deployment
targets undecided. The checked-in [local specification](../bench/operational-local.json)
is a synthetic engineering diagnostic. Actual business representativeness,
target deployment, operational requirements and the responsible owner's
recommendation remain open under #16.

The [scalar shadow campaign](shadow-campaign.md) owns independent numerical and
canonical comparison evidence. The [worker/tile study](results-planner-workers.md)
owns its lower-level configuration comparison. This campaign adds concurrent
clients, plan lifecycle, output handling, per-request observations, cancellation
and process memory. It neither substitutes for independent arithmetic checks
nor changes the pricing library or its acceptance contracts.

## Run and preserve

From a checkout with unchanged library sources, build and finish other task-owned
validation before measuring:

```sh
opam exec --switch=morphiq-risk-ml -- dune build --profile release \
  --build-dir _build_release @install @bench/runtest bench/planner_load.exe
python3 scripts/operational_campaign.py \
  --config bench/operational-local.json \
  --binary _build_release/default/bench/planner_load.exe \
  --output /tmp/planner-operational-new-run
```

The output path must be new. The collector copies and hashes the specification
before starting children, records source/compiler/binary identity, and retains
raw worker stdout/stderr, each process run and the final report. It verifies
binary/configuration/harness identity again after measurement. Staged, unstaged and untracked library changes are rejected. The caller must
use the release build command above; source hashes and a supplied binary hash
are not an independent proof that the binary was built from those sources.

Partial evidence survives errors. A missing/failed child, malformed or truncated
protocol, inconsistent counts, changed replay, timeout or changed artifact
prevents `complete: true`. Timed-out direct worker processes are killed and
reaped; their OCaml domains are threads in those processes. The native worker
does not launch subprocesses. Each child has one owner for `wait4` and its RSS;
no cumulative `RUSAGE_CHILDREN` value is presented as an individual child's peak.
Only the owning run replaces its own temporary report file atomically.

Exit status is 0 for a completed campaign with no failed specified criterion,
1 for completed measurements that fail a specified criterion, and 2 for a tool,
protocol or configuration error. **Exit 0 is not deployment acceptance:** unset
criteria remain pending and `deployment_accepted` is always false. The existing
[candidate acceptance process](acceptance-and-change-control.md) owns approval.

## Workload and configuration

The versioned JSON schema rejects unknown fields, duplicate keys, nonfinite
numbers, invalid counts and inconsistent modes. Configuration contains a scope,
process repetitions, warmup and measured-request counts, per-phase timeout and
an ordered case list. Each case supplies:

| Field | Meaning |
| --- | --- |
| `positions`, `days` | Synthetic position count and explicit valuation-day offsets |
| `mode`, `outputs` | Fast prices, or certified price / all eleven price-and-Greek outputs |
| `allowance` | Positive absolute numerical allowance per certified quantity, in its own typed units |
| `workers`, `tile_rows`, `buffer_slots` | Explicit per-process planner execution and buffer policy |
| `concurrency` | Number of concurrently active client processes |
| `policy` | `reuse` a compiled plan or `recompile` inputs/plan for every request |
| `sink` | `count` inspects ordered rows/outcome classes; `digest` additionally serializes and hashes each event |
| `cancel_after_ms` | Null for ordinary execution, or a cancellation deadline relative to the end of request preparation |
| `requirements` | Predeclared limits, with null for every undecided criterion |

The synthetic corpus repeats BSM, Black-76, displaced Black and Bachelier, with
alternating blocks of calls/puts, four fixed market factors, unit quantities,
USD labels and expiry day 365. Exact construction is in
[`bench/planner_load.ml`](../bench/planner_load.ml). Sizes below four use a prefix
of that model pattern. The corpus has no private data, observed business
holdings, market-feed adapter or arbitrary trade-file importer. New business
inputs need their own captured specification and convention mapping before
claiming representativeness. Increasing position count repeats this pattern;
it does not increase economic diversity.

The normal cases set zero returned numerical failures as a pre-run engineering
criterion. The local boundary case deliberately includes expiry and post-expiry;
unsupported Greeks and post-expiry outcomes stay visible. It has no invented
business failure allowance. The `all` output set contains no implied volatility;
existing scalar shadow evidence covers IV separately. Certified scenario
summaries remain in the event stream. Fast output is unweighted approximate
price, and no portfolio total or runtime certificate is invented.

## Request model and measurement windows

Each client is a separate process with its own OCaml heap and compiled plan.
The parent submits one request to every client, then waits for all responses
before the next wave. This is **synchronized closed-loop load**. It is not an
open-loop arrival-rate test, an HTTP service, a shared-process request pool,
queueing/tail-SLA qualification or durable output test. Requested worker capacity
can reach `concurrency * workers`; positive cancellation deadlines add one
controller domain per client. Oversubscription is visible, not automatically
corrected by a global scheduler.

Every process eagerly compiles a baseline plan before `ready`. The parent records
observed process-to-ready time, including initial compilation and orchestration.
The first request is recorded separately, followed by configured warmups and
measured requests. "Cold" means that process's first pricing request after
compilation; filesystem caches, library initialization and the machine are not
cold. No forced collection precedes each request. Under `recompile`, each
request additionally packs inputs and recompiles; initial baseline compilation
still occurs for the later replay check.

- Parent `transport_ms` spans command submission through receipt/parsing of the
  response, including local pipe traffic, diagnostic encoding and parent evidence collection. Sent/received
  monotonic timestamps are retained. This is the latency used for reported
  median and nearest-rank p95, not a batch mean divided into scalar latencies.
- Worker `request_ms` includes preparation, execution, sink handling and controller
  cleanup. `prepare_ms` includes the instrumentation prefix and optional input
  packing/compilation; it is not pure compiler time under `reuse`.
- `first_row_ms` is relative to request start, through processing the first row
  in the sink. The digest sink serializes/hashes one event at a time, keeping
  storage bounded. Its cost is measured sink work, not network or disk I/O.
- Process CPU includes pricing/worker/GC work. Allocation counters cover the
  coordinator only; they exclude spawned worker bodies and are not total
  allocation savings. GC collection counts are not pause durations.
- Per-child peak RSS covers the whole process lifetime, including setup and the
  post-timing replay check. The report's maximum is one process's peak, not
  simultaneous deployment-wide peak memory. The Python driver is excluded.

After timing, each process compares full ordered event/completion hashes with
one worker and the configured count. Processes/repetitions must agree. Completed
digest-sink requests must also match that replay. Count-sink requests check
logical row order, outcome counts and completion but do not hash every value
inside their timed sink. Replay establishes compatibility, not independent
numerical accuracy. Existing canonical/interval and planner fixture evidence
retains its original source scope.

## Cancellation and criteria

A zero deadline pre-cancels synchronously. Positive deadlines use a separate
controller that records when it actually sets cancellation. Running tiles finish;
the ordinary planner checkpoints determine the committed prefix. Every request
retains stop status, served outputs, classified refusals and uncommitted work.
A request can legitimately finish before cancellation is observed.

`cancel_issued_ms` and `cancel_schedule_lateness_ms` expose late controller
scheduling. `cancel_observation_ms` measures actual issuance to executor return;
controller join/cleanup also contributes to total request time. The cancellation
criterion uses only observed `Cancelled` requests. If none was observed, it
remains pending. This finite sample is not an interruption-time guarantee.
Completed-request throughput excludes cancelled requests; response throughput
is reported separately. A zero-output cancellation supplies no evidence about
numerical failure rate.

The optional criteria are warmed p95 response latency, minimum completed-request
throughput, maximum individual-process RSS, maximum returned-output failure
fraction and maximum observed cancellation latency. Unknown targets are null;
unknown observations cannot pass. Descriptive percentiles from a small sample
have no tail-confidence guarantee. Fix operational targets and intended inputs
before collecting acceptance evidence; do not fit targets to the results.

Only the small protocol/cleanup/replay controls run in ordinary CI via
`@bench/runtest`. The repeated performance campaign remains manual; no hardware
performance threshold or full mutation workload is added to PR CI.

The [local baseline](results-operational-campaign.md) records what was measured
and the remaining deployment decisions.
