# Reproduction and evidence scope

The [protocol](protocol.md) was committed before runtime edits; the original
Arb generator and exact-input references were committed next. The
[report](../../results-american-forward-optimization.md) distinguishes unchanged
replay, independent reference errors, supplementary canonical comparisons and
performance evidence.

Regenerate the optional independent references with the recorded python-flint /
FLINT versions in `reference-v1/references.json`:

```sh
python scripts/generate_terminal_cash.py --output /tmp/terminal-reference-replay
python3 scripts/check_terminal_cash.py
opam exec --switch=morphiq-risk-ml -- dune test
```

The ordinary build uses the committed references and Python's standard library;
it requires neither python-flint, QuantLib nor private research access.

`raw.tar.gz` contains original project drivers and logs, including all 572 price
snapshots and 920 Greek rows on both builds, inverse endpoints, installed native
and bytecode clients, mutation outcomes, allocation/CPU profiles and every timing
sample. Scratch `.ml` drivers are stored as `.ml.txt`; rename only when building
external clients. Driver paths identify the actual local worktrees. For another
machine, replace those roots with clean worktrees at the revisions in
`raw/source-map.json`, retaining the original settings and failure controls.
Build each with the locked OCaml 5.3 Flambda toolchain in release mode. The
piecewise/profile clients link the public library and, for timings,
`bench/assurance_clock.c`. The fixed principal benchmark is `bench/american_iv.ml`.

The canonical adapter links an external QuantLib 1.44.0 checkout at the recorded
revision, compiled with Clang `-O3 -std=c++17 -ffp-contract=off`. Supply source and
build include directories and the pinned built library via `-I`, `-L`, `-lQuantLib`
and the platform's runtime library path. Input files, schemes, forced
recalculation, exclusions and binary/source/compiler hashes are retained.
QuantLib is available under its BSD-style redistribution terms; this archive
contains neither its source/binary nor third-party research documents. The
original adapter is Apache-2.0 project work. Full original ALO paper acquisition
and production implementation qualification remain explicitly pending.

The source map preserves the failed client-build setup and the supplementary
canonical recheck. No failed startup, unqualified reference, initial exploratory
timing, or cached NPV is counted as successful acceptance evidence.
`SHA256.json` binds the published raw archive, summaries, protocol and references.
