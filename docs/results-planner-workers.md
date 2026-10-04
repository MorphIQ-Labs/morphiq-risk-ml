# Planner worker/tile crossover — issue #8

The existing scheduler scales on this corpus when enough work is assigned per
tile. Four workers with 4,096-row tiles execute 65,536 fast prices in **29.25 ms**,
versus **95.46 ms** with one worker at the same tile size (3.26× throughput).
Four workers with 32-row tiles take **195.45 ms** on the same prices. The small
32-position fast book still favors one worker. Certified prices amortize startup
at much smaller tiles: 512 prices take **398.61 → 106.12 ms** at tile size 32.

This round adds a reproducible measurement harness and [caller tuning guidance](planner-worker-tuning.md).
It changes no library code, numerical contract, scheduler, default or public API.
It establishes a useful throughput improvement through existing explicit policy.
It does not close #8's target-workload/operational acceptance requirements.

## Source and protocol

- Source commit: `97d203f3c89be11e6b06a88fe1c6f4acbf721b05` (PR #103).
  The library is identical to qualified candidate `f703546ea736d456f64e74be6ef9d2da2c10ef88`;
  library tree: `0da7e7fda5ef50b4bd7696580829fd9a3adea598`.
- New harness: [`bench/planner_workers.ml`](../bench/planner_workers.ml), SHA-256
  `d3f0f10bbab812c3bfadf31705ae2ce79e406b2e44819ef836f3f974cda8d943`.
- Collector: [`scripts/measure_planner_workers.py` at the measured revision](https://github.com/MorphIQ-Labs/morphiq-risk-ml/blob/8b374bf0c599393e23a6042f4bc55946e7364d5d/scripts/measure_planner_workers.py), SHA-256
  `1fc7b97855d2439de1c7bb8e1071f1a7ab18b9f91669a69c48e35acae76ebff4`.
- Native binary SHA-256: `30e6aeac8d8a47cff1098d397f1269cb87c61fe08da38af67473fb5d4e16139b`.
  Compiler: OCaml 5.3.0 Flambda, Dune release profile, unchanged library `-O3`
  and arithmetic flags. Full compiler configuration is in the raw evidence.
- Apple M1 Pro, 10 logical CPUs, macOS 27 ARM64. Collection:
  2026-10-04 22:52:46–22:55:57 UTC. Recorded one-minute load: **3.74–9.73**.
  Task-owned builds, tests and profilers were idle during timing. This remains
  a shared workstation; no exclusive cores or fixed frequency were imposed.
- Fixed four-model, alternating call/put corpus, four valuation-day scenarios
  (0, 7, 30, 90), expiry day 365. Original inputs are in the harness. Certified
  mode requests price only with absolute scalar allowance `1e-8`, streamed rows
  and the API's normal scenario summaries. Fast mode streams unweighted prices.
  The modes have different assurance/output contracts; do not compare their
  timings as interchangeable services.
- Three warmups and five samples per configuration/process. Four serial
  process passes use forward/reverse/reverse/forward configuration order;
  worker order alternates within each process. Fast samples repeat
  `max(1, 4096 / positions)` executions; certified samples execute once.
  Full major GC precedes each sample, outside its timer. Execution includes
  cancellation construction, ordinary scheduler work and a minimal row sink.
- Every process checks full ordered event/completion replay across 1/2/4
  workers, all ordinary outcomes successful and complete counts. The collector
  checks identical replay across tile sizes/processes. Validation is outside
  timing. All **64 configurations/processes** passed. Wall timing uses the
  existing monotonic benchmark clock; CPU includes runtime/GC work.

[Raw samples, hashes, commands, loads and replay digests](evidence/planner-workers/sweep.json.gz)
retain all 960 execution samples, 320 compilation samples and 640 empty-wave
samples, including the variable small-tile four-worker cases. Values below are
means of four process medians; brackets show the minimum/maximum process median.
They are batch means, not per-request percentiles or an SLA. No outliers were
removed. This is a configuration comparison of one binary, not a before/after
implementation comparison.

## Reused execution

All times are milliseconds per complete four-scenario execution. Each `N`
position book emits `4N` rows. First-row columns give the mean of process medians
for four workers; slot bounds use the compiled maximum of four workers.

### Fast prices

| Positions | Tile rows | 1 worker ms [range] | 2 workers ms [range] | 4 workers ms [range] | First row, 4 workers ms | Slot bound |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 8 | 0.184 [0.182–0.186] | 0.529 [0.519–0.548] | 1.347 [1.143–1.493] | 0.288 | 32 |
| 32 | 32 | 0.183 [0.182–0.183] | 0.239 [0.233–0.244] | 0.448 [0.385–0.500] | 0.270 | 128 |
| 1,024 | 32 | 5.856 [5.829–5.907] | 7.667 [7.445–7.847] | 14.742 [11.815–20.182] | 0.256 | 128 |
| 1,024 | 256 | 5.923 [5.878–5.976] | 4.166 [4.105–4.201] | 2.776 [2.707–2.917] | 0.722 | 1,024 |
| 1,024 | 1,024 | 5.965 [5.913–6.021] | 3.686 [3.655–3.713] | 2.243 [2.208–2.285] | 2.225 | 4,096 |
| 16,384 | 32 | 94.369 [93.806–95.055] | 121.625 [119.530–123.780] | 195.446 [162.355–263.708] | 0.302 | 128 |
| 16,384 | 256 | 94.495 [93.780–96.203] | 66.438 [66.103–67.031] | 44.284 [43.778–44.856] | 0.744 | 1,024 |
| 16,384 | 1,024 | 95.631 [95.192–96.243] | 58.314 [57.780–58.685] | 35.325 [35.049–35.692] | 2.223 | 4,096 |
| 16,384 | 4,096 | 95.463 [95.171–95.730] | 52.845 [52.592–53.144] | 29.248 [29.141–29.387] | 7.245 | 16,384 |

### Certified prices

| Positions | Tile rows | 1 worker ms [range] | 2 workers ms [range] | 4 workers ms [range] | First row, 4 workers ms | Slot bound |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | 1 | 49.774 [49.696–49.916] | 32.750 [32.624–32.952] | 18.270 [18.108–18.410] | 1.098 | 4 |
| 16 | 4 | 49.736 [49.524–49.995] | 27.467 [27.275–27.820] | 14.798 [14.646–14.888] | 3.517 | 16 |
| 16 | 16 | 49.647 [49.384–49.776] | 26.669 [26.605–26.712] | 13.755 [13.681–13.879] | 13.743 | 64 |
| 128 | 1 | 397.163 [396.475–397.819] | 262.428 [261.507–264.135] | 145.922 [145.765–146.237] | 1.128 | 4 |
| 128 | 8 | 397.047 [396.174–397.937] | 211.531 [210.896–212.020] | 111.442 [111.167–111.912] | 6.624 | 32 |
| 128 | 32 | 398.611 [396.956–401.184] | 206.755 [205.750–208.214] | 106.121 [105.389–107.632] | 24.948 | 128 |
| 128 | 128 | 397.875 [396.393–401.260] | 209.156 [208.712–210.101] | 106.873 [105.947–107.302] | 106.802 | 512 |

The 16,384-position fast case exposes the tradeoff: tile 32 → 4,096 reduces
four-worker execution 195.45 → 29.25 ms but grows the slot bound 128 → 16,384
and first-row time 0.302 → 7.245 ms. With certified 128-position prices, tile
8 → 32 improves throughput only about 5% while first output moves
6.624 → 24.948 ms. Tile 128 offers no clear throughput improvement over 32
and delays first output to 106.802 ms. The largest tile is not a universal
recommendation. These first-output measurements do not establish cancellation
bounds under heterogeneous work or host interference.

## Startup, compilation and allocation

The empty-wave control creates and joins one or three domains with empty
bodies, in batches of 100. Across the 64 process medians, the median one-domain
wave costs **57.5 µs** (range 45.9–72.3); a three-domain wave costs **182.5 µs**
(range 125.0–547.7). These controls support startup/join overhead as a material
small-tile cost, but cannot isolate thread creation from runtime registration,
teardown, GC synchronization or OS scheduling. Do not subtract them from
pricing measurements as an additive model.

For the 65,536-row job, tile 32 dispatches 2,048 logical tiles in 512 waves,
creating 1,536 domains; tile 4,096 dispatches 16 tiles in four waves, creating
12 domains. The counterexample is certified pricing: even one row per tile
contains enough work for four workers to beat one on this corpus.

Compilation is measured separately. Across tile sizes, mean process medians
are about 0.057 ms for 32 fast positions, 1.62–1.64 ms for 1,024 and
26.20–26.40 ms for 16,384. Certified compile medians are about 0.045–0.047 ms
for 16 positions and 0.224–0.228 ms for 128. These separately timed phases must
not be added and presented as measured end-to-end latency; plan reuse and
transport costs depend on the application.

Raw records retain current-domain allocation, minor/major collection counts and
process CPU time. Allocation is **coordinator-only**. For the large fast case
at tile 4,096 it is about 173.15 MB with one worker and 44.08 MB with four;
the latter excludes worker bodies and is not a 75% total-allocation saving.
Counts are per timed batch, whereas wall/CPU/allocation are normalized per
execution. The separate existing instrumentation checks worker lifecycle and
bounded slots; its instrumented timings are excluded from the comparison.

## Validation and disposition

The unchanged scheduler retains all joined-before-callback guarantees,
coordinator-only sink ownership, deterministic row/reduction order, per-row and
between-wave cancellation, and one-wave buffering. Focused validation records
are retained beside the measurements:

- Development/release package and harness builds, formatter and diff checks pass.
- Native/bytecode fast planner contract tests pass; the development harness also
  passes small fast/certified replay smoke runs.
- [Three stress subprocesses](evidence/planner-workers/stress.json) each pass all
  44 fault/schedule checks; [six instrumented memory/failure cases](evidence/planner-workers/metrics.jsonl)
  stay within slot bounds and join every worker before returning.
- [CLI/collector controls](evidence/planner-workers/validation.json) reject bad
  arguments, failed/truncated children and changed tile replay, preserve
  incomplete evidence, and refuse to overwrite existing output.

The full ordinary suite is left to required three-platform development/release
CI for this harness/documentation change. No numerical mutation mechanism changes;
no new approximation, threshold or error-budget adjustment is involved.

Keep explicit caller-selected workers/tiles. The data supports tuning these
parameters before adding scheduler machinery for throughput. A persistent
worker design remains a possible follow-up where small tiles are required by
memory or first-output/cancellation constraints: it would need an explicit
quiescence/ownership contract, guaranteed cleanup on every failure and new
stress witnesses. That is a separate design, not an inferred safe replacement
for joining domains before callbacks. Remaining #8 work includes target-host
business inputs, sink/transport costs, latency/memory requirements and repeatable
operational acceptance. This campaign does not requalify a new runtime candidate
or authorize a release.
