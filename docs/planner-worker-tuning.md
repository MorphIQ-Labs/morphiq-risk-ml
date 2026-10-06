# Choosing planner workers and tiles

Choose `workers` and `tile_rows` together for the actual pricing mode, portfolio,
output set and sink. The planner has an explicit caller-selected resource policy;
there is no universal optimal tile size. The [measured crossover](results-planner-workers.md)
compares one, two and four workers on the same library and input corpus.

Start with one worker as the reference. Sweep larger tiles with two and four
workers, preserving the same ordered outputs. Fast approximate prices can be
cheap enough that domain startup dominates a small tile. Certified prices do
more work per row and can amortize startup with smaller tiles. Hard numerical
cases, multiple certified outputs, heterogeneous costs and slow sinks can move
the crossover; the ordinary price-only corpus does not cover those workloads.

On ARM64, eligible homogeneous Bachelier Fast tiles now use native batching for
`execute ~workers:1`. Multiworker execution retains scalar pricing until separate
performance qualification supports adoption. The [native planner comparison](results-native-planner.md)
includes preparation, packing, rows and a minimal sink; reused fixed-batch kernel
throughput is not a scenario-throughput estimate. Re-establish the one-worker
reference when choosing workers for this backend.

## What a tile changes

For `N` instruments and `S` scenarios, the planner creates
`S * ceil(N / tile_rows)` logical tiles when both dimensions are nonempty.
A tile stays within one scenario. A wave evaluates up to `workers` tiles:
the coordinator evaluates the first and spawns one domain for each remaining
tile. It joins every handle before delivering the wave in logical order.
With `T` tiles and `W` valid requested workers, this means
`T - ceil(T / W)` domain creations per complete execution. Domains are recreated
for each wave. Larger tiles reduce these startup/join cycles.

The tradeoffs are explicit:

- **Throughput:** too little work per domain can cost more than serial execution.
  Too few tiles can leave workers idle; skewed tile costs wait for the slowest
  tile in a wave. Multiple scenarios can occupy workers even when each scenario
  fits in one tile.
- **First output and cancellation:** every tile in a wave finishes before the
  first row is delivered. Bigger tiles can delay the first callback and observing
  cancellation. Cancellation remains checked between waves and before each
  committed row. European running scalar work is not interrupted;
  `Planner.American` also forwards cancellation into its bounded scalar solvers. Time to first row is
  diagnostic evidence, not a cancellation-latency guarantee.
- **Memory:** the compiled limit must accommodate the larger wave. Fast row
  slots are bounded by `min(N, tile_rows) * min(max_workers, T)`. Certified
  output slots also account for requested quantities. Use `explain` and retain
  compile refusals; do not bypass `max_buffered_results`. Slot bounds are not
  process RSS or scalar scratch bounds.
- **Sink cost:** callbacks run serially on the coordinator. A slow sink prevents
  dispatch of the next wave. Increasing workers cannot parallelize the sink.

Plans include their resource policy in their identity. Changing tile size means
compiling another plan; retain its manifest with the source/toolchain identity.
Reuse a plan for comparable executions and measure compilation separately when
assessing amortization.

Native Bachelier preparation internally caps chunks at 256 rows. That cap does
not change the caller's logical tiles, wave count, callback timing or cancellation
granularity. The logical tile's output array still uses the caller-selected row
limit. Private packing/SoA scratch is additional to the explained value bytes;
neither the chunk cap nor the output-slot bound is a heap/RSS guarantee.

## Reproduce the sweep

Build before starting timing, then keep task-owned builds, tests and profilers
idle during collection:

```sh
opam exec --switch=morphiq-risk-ml -- dune build --profile release bench/planner_workers.exe
_build/default/bench/planner_workers.exe --mode fast --size 16384 --tile-rows 1024
_build/default/bench/planner_workers.exe --mode certified --size 128 --tile-rows 8
python3 scripts/measure_planner_workers.py \
  --binary _build/default/bench/planner_workers.exe --output /tmp/planner-workers.json.gz
```

The harness uses four time scenarios and a fixed four-model, call/put corpus.
Each configuration checks full ordered event/completion replay across worker
counts outside timing, checks every ordinary price succeeds, warms each worker
count, and alternates worker measurement order. The collector checks replay
across tile sizes and processes, reverses configuration order over four passes,
and retains all raw samples, host load and hashes. Output must be a new path.
The collector assumes the supplied binary was built with the stated release
command; its hash identifies the actual measured artifact.

Compilation and reused execution are distinct phases. Execution includes row
construction and a minimal sink, not transport or durable storage. Wall/CPU
values are per-execution batch means. `first_row_ns` measures the first callback
of the first execution in each sample. It is neither cold-start time nor a
request percentile. The empty-wave control measures domain creation/join with
empty worker bodies; it is a diagnostic, not a subtractable cost model for GC
and pricing together.

Allocation counters cover the **coordinating domain only**, including the
coordinator's tile and output handling. They exclude worker-body allocation
and cannot be compared across worker counts as total allocation savings.
Collection counts cover the whole timed batch and are not pause durations.
The [instrumented memory qualification](fast-integration-qualification.md)
separately reports worker-body allocation and bounds. No production SLA,
automatic worker policy or quiet-host guarantee follows from this sweep.
