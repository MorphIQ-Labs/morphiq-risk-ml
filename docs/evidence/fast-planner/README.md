# Fast planner evidence

See [the report](../../results-fast-planner.md) and [API contract](../../fast-planner.md).
Implementation is `e5bf63a51e692b2432f7dc1bcb0654609c64e2aa`.

- `metadata.json` binds implementation, baseline and tested source hashes.
- `benchmark.json.gz` retains five fresh-process fast campaigns: outcomes,
  sources/binary/toolchain, loads, elapsed/CPU and allocation samples. Four-worker
  allocation covers only the coordinating domain, not the complete job.
- `certified-abba.json.gz` retains two sequential ABBA rounds against PR #99,
  including exact certificate/aggregate/failure replay digests. Shared-host load
  was high; timing is not evidence of a stable performance improvement.
- `certified-identity.json` records three unchanged certified plan identities.
  Timing in these identity controls is not performance evidence.
- `validation.log.gz` retains the complete ordinary suite, including the
  shared scheduler's 44 fault/stress cases. `final-build.log.gz` is the final
  successful build/format log (empty when Dune has nothing to print).
- `mutations.log.gz` retains a clean baseline and six targeted kills.
- `installed-artifact.json` binds the immutable source archive/tree, ten
  matching installed notices and native/bytecode external consumers. The
  archive/build log are preserved in the implementation revision's local
  acceptance directory outside the checkout.

Reproduce using OCaml 5.3.0 Flambda and the pinned dependencies:

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 bench/fast_planner.exe
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_fast_planner.py \
  --runs 5 --output /tmp/fast-planner-benchmark.json
```

For certified comparison, build `bench/shared_portfolio.exe` in each revision
and run `scripts/benchmark_shared_portfolio.py --baseline-source BASELINE
--candidate-source CANDIDATE --output /tmp/certified-abba.json` inside the same
opam environment. Use the exact revisions above and in the report. Do not run
task-owned tests/builds/profilers alongside timings. All byte counters measure
cumulative allocation, not RSS or retained plan size. `SHA256.json` covers
retained evidence except itself.
