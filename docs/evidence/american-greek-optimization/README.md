# Focused Greek optimization evidence (#119)

Read the [qualification report](../../results-american-greek-optimization.md),
[frozen protocol](protocol.md), [boundary derivation](reuse-design.md),
[residual operation/safety argument](native-residual-design.md) and
[standalone price controls](price-controls.md).

`raw-evidence.tar.gz` contains original text/JSON profiles, disassembly, collector
sources, build/source manifests, full compatibility snapshots, validation logs,
all timing samples and historical failed attempts. `archive.json` identifies the
archive; its internal `MANIFEST.json` gives every entry's size and SHA-256.
Compiled executables remain local; their source revisions and binary hashes are
retained. Absolute scratch paths identify the measured local builds and must be
rebased when reproducing elsewhere.

- `baseline-build.json` and `baseline-integration-identity.json`: unchanged #115
  baseline and its integration-tree equivalence.
- `profile-baseline*`, `profile-candidate*`, `cpu-*`: allocation/CPU attribution.
  The candidate profiles describe the first, boundary-only iteration. Profiling
  counters are not controlled latency measurements.
- `iteration1/`, `performance-iteration1/`: first candidate, complete numerical
  replay, binary-preservation mapping and all 90 samples. Allocation improved;
  latency failed the frozen criterion. Historical paths/hashes are preserved.
- `candidate-build.json`, `native-toolchain.json`, `native-residual-object.json`:
  final measured source, compiler, native object and binary identities.
- `compatibility.json`, `reference-candidate/`, `qualified-*`: final 572-price and
  920-Greek replay, complete public snapshots, independent/canonical scores and
  immutable baseline consumers. Unresolved references stay unresolved.
- `native-*.log`, `work-order.*`, `work-order-*.txt`: development/release,
  native/bytecode, format/package, 12 compiled faults and 54 installed-client
  callback/resource traces. Loader setup failures are retained separately.
- `timing-native-preflight.json`, `performance-native/`, `performance-prices/`:
  final workload campaigns after owned validation exited, including source
  guards, raw stdout/stderr, per-child resource usage and host load.

For another machine, build immutable baseline and candidate worktrees with the
recorded OCaml 5.3.0 Flambda toolchain and release profile. Use `capture.py` as a
manifest-generation example, checking source and compiler identity rather than
editing hashes to accept a different binary. Run the recorded `work_order.py`
and `replay_native.py` comparisons before timing. The latter reuses immutable
baseline full snapshots built by `build_baseline_snapshot.py`; keep the original
printed rows and independent/canonical scoring too. After owned compute ends:

```sh
python3 scripts/benchmark_american_greek_optimization.py \
  --baseline /path/to/baseline-build.json \
  --candidate /path/to/candidate-build.json --output /new/output/directory
```

The separate retained `benchmark_price_compatibility.py` runs six standalone
controls (five alternating pairs each); set its checkout root and Python import
path to the candidate's `scripts/`. Do not overwrite an existing campaign or
relax the protocol's limits after collecting results. Local performance and
finite replay do not establish deployment acceptance or continuum certificates.
