# Fast integration evidence

[Qualification report](../../fast-integration-qualification.md).
Production implementation: `e7eca36ca1acf848e8946708cd84ef1ff7d3c8f2`.
Qualification source: `1f6dd3b1cbd76287657c88b227cb0af4e66bb473`.
Later report/evidence commits leave qualified source files unchanged.

`metadata.json` binds source files and local validation scope.
`validation.log.gz` records the complete ordinary suite; `final-validation.log.gz`
records the incremental final edge/fault controls. `mutations.log.gz` records a
clean baseline and both fast-planner kills. The full baseline includes the final
ordinary tests. Instrumentation is test-only and is not a numerical oracle.

`memory.json` retains six fresh-process bounded-slot/live-heap/allocation probes.
Allocation sums coordinator plus worker-body OCaml counters, including probe
overhead; runtime initialization/stacks are excluded. Sampled live heap is not
peak RSS. `batch.json.gz` and `tile*.json.gz` retain five fresh-process fast
campaigns with exact checks, source/toolchain/binary identity, loads and samples.
Their four-worker counters cover the coordinator only. `certified-abba.json.gz`
retains two rounds of paired certified comparison, including full result hashes.
Host load was high; these reports do not establish idle-host performance.

`implementation-ci.json` binds all five successful PR #100 checks to its head
and merge. The qualification PR separately requires all five checks before
landing. `installed-artifact.json` binds the immutable archive/tree, matching
notices and isolated native/bytecode consumers. Source archive and build log are
preserved in the qualification revision's local acceptance directory.

Reproduce after installing the pinned OCaml 5.3.0 Flambda dependencies:

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 @install @fmt @runtest \
  test/fast_planner_metrics.exe bench/fast_batch.exe bench/fast_planner.exe \
  bench/shared_portfolio.exe
opam exec --switch=morphiq-risk-ml -- python3 scripts/measure_fast_planner_memory.py \
  --output /tmp/fast-memory.json
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_fast_batch.py \
  --output /tmp/fast-batch.json
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_fast_planner.py \
  --size 4096 --tile-rows 32 --output /tmp/fast-tile32.json
```

Repeat the final command with tile rows 256 and 1024 and separate outputs.
For ABBA, build `bench/shared_portfolio.exe` at PR #99 head and the qualification
source, then run `scripts/benchmark_shared_portfolio.py --baseline-source BASELINE
--candidate-source CANDIDATE --output /tmp/fast-certified-abba.json` in the same
opam environment. Finish task-owned builds/tests/probes before timing and run
campaigns sequentially. `SHA256.json` covers retained evidence except itself.
