# Native planner evidence — 2026-10-05 UTC

The [report](../../results-native-planner.md) identifies exact sources, scope,
tradeoffs and remaining qualification. `timings-summary.json` contains all 180
final groups, each with four process medians. The sibling `SHA256SUMS` hashes
that summary and `raw.tar.gz`; the archive contains its own per-member manifest.

The archive preserves three distinct campaigns:

- `initial-whole-tile/`: superseded whole-logical-tile preparation and all slower
  samples at larger tiles.
- `bounded-multiworker/`: superseded 256-row chunks with native parallel routing;
  serial gains and parallel regressions motivated the final dispatch restriction.
- `final-serial-dispatch/`: final runtime `20d927b342bd53315e2f374033bee34447238b07`,
  all 3,600 raw timing samples/stderr, identical original-input dumps, complete
  49,152-row native traces, source/binary guards, UTC/load, compiler/hardware,
  common consumer sources and installed bytecode report/traces.

`validation/` contains ordinary checks, six designated mutation kills, independent
reference scoring, refined original-input references/metadata, collector controls,
installed bytecode build commands and the prior two stages' CI records. Logs
whose names start `planner-serial-` cover the final runtime; `planner-final-controls-`
adds explicit native cancellation/concurrency and direct-tile ownership checks
without changing that runtime. Earlier chunk setup failures (type annotation,
Dune lock and private helper visibility in the instrumented wrapper) remain
visible and are **not** mutation kills. Corrected full profiles and the six
designated witnesses pass. Formatter promotion logs can exit nonzero while
applying formatting; the following format check passes.

`planner-portable-*` extends those checks to a test-only generated copy of the
planner with the platform gate enabled, so the chunk/order mutation witnesses
execute on scalar-default platforms as well. Production routing is unchanged.
Earlier `planner-routing-*` setup attempts exposed an unnecessary test-library
dependency on the Zarith stub and an overly strengthened module signature.
The final test copy uses only the runtime library and a generated public
signature; those failed builds/baselines are retained, not counted as kills.

No executables, installed dependency trees, third-party source payloads, source
archives or research PDFs are embedded. Build logs retain original local paths
as provenance. Timing, local installation, cross-platform CI and release/owner
acceptance are distinct evidence scopes.

From clean baseline/candidate worktrees, reproduce:

```sh
python3 scripts/benchmark_native_tiles.py prepare \
  BASE_ROOT CANDIDATE_ROOT NEW_PREPARED_DIRECTORY
# Complete all builds/tests/profiling before measurement.
python3 scripts/benchmark_native_tiles.py measure \
  NEW_PREPARED_DIRECTORY/prepared.json NEW_TIMING_DIRECTORY
python3 scripts/test_benchmark_native_tiles.py
opam exec --switch=morphiq-risk-ml -- dune build @install @fmt @runtest
opam exec --switch=morphiq-risk-ml -- dune build \
  --profile release --build-dir _build_release @install @runtest
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- \
  native-planner-chunk-offset native-planner-order fast-planner-tile \
  fast-planner-side planner-post-expiry planner-snapshot-copy
```

The benchmark uses only the installed public API. Its collector checks complete
input/output coverage, per-configuration replay, finite samples and source guards;
failure controls exercise malformed/truncated data, child startup/exit/timeout,
changed inputs/outputs and staged/unstaged/untracked source changes. Retain partial
output if collection fails; it is not a completed campaign.

Using optional Python mpmath **1.3.0**, refine the original-input dump and score
without changing ordinary fixture budgets:

```sh
python3 scripts/reference_native_tiles.py \
  NEW_TIMING_DIRECTORY/inputs-0.txt NEW_REFERENCE.txt
opam exec --switch=morphiq-risk-ml -- dune exec --profile release \
  test/oracle_price.exe -- NEW_REFERENCE.txt --external
opam exec --switch=morphiq-risk-ml -- dune exec --profile release \
  test/native_bachelier_reference.exe -- --external-reference NEW_REFERENCE.txt
```

The generator retains input/output/generator hashes, precisions, unique and total
row counts, and unresolved cases. It does not make precision agreement a proof.
All row multiplicities are preserved; no hard rows are dropped.
