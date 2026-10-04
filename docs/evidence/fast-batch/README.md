# Fast batch evidence

See [the report](../../results-fast-batch.md) and [API contract](../../fast-batch.md).
Implementation is `ac98eadd3f703a6ec90752c40e19cb52e2a7bb6c`.

`benchmark.json.gz` retains five fresh-process runs, exact outcome digests,
source/binary/toolchain identity, host load, timing, CPU and allocation samples.
`validation*.log.gz` retain full ordinary and final package-consumer checks;
`mutations.log.gz` retains a clean baseline and two compiled kills.
`installed-artifact.json` binds source archive/tree, installed notices and
native/bytecode external consumers. Source archive/build log are preserved in
the revision's local acceptance directory outside this checkout.

Reproduce with the pinned OCaml 5.3.0 Flambda switch:

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 bench/fast_batch.exe
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_fast_batch.py \
  --runs 5 --output /tmp/fast-batch-benchmark.json
```

The benchmark compares phases of one implementation using the same scalar
kernels, not a changed numerical algorithm. Do not run builds/tests/profilers
alongside timings. `SHA256.json` covers retained evidence except itself.
