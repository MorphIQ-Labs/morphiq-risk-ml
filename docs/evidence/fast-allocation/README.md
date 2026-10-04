# Fast allocation evidence

Read [the report](../../results-fast-allocation.md) for scope and interpretation.
Implementation commit: `75999776291370412dc0ffe3b4504b17e7979e3c`.
Baseline: `ff602ee21949663025e6cbfbe044fb5a539cccf6`, whose tree matches the
PR #101 merge `8ab5b8ce052a9b0753d10e1d7d5567aec52bd756`.
Evidence commits change no production arithmetic. `SHA256SUMS` binds the
retained files; hashes inside reports identify inputs, binaries and sources.

- `abba.json.gz`: full sequential paired native benchmark output, individual
  samples, summary medians/ranges, load, hardware, compiler and source hashes.
  Two ABBA rounds per profile yield 20 batch-mean samples per variant/phase.
  Separate development/release binaries use identical benchmark sources.
- `profiles.tar.gz`: 64 model/phase/native-or-bytecode/profile/revision stack
  logs and their index. Singleton GC counts are measured before sampling;
  sampling is not used for timing. Price output words and source revisions are identified in the index.
- `dd-words.json`: complete 86,145-row, eight-way direct production word replay
  membership, fixture, harness, binary and result hashes.
- `code-size.json`: Mach-O object text and total object bytes for DD/Split.
- `development.log.gz`, `release.log.gz`: full local ordinary checks, including
  independent numerical references and unchanged determinism.
- `mutations.log`: clean baseline plus seven designated numerical kills.
- `installed-report.json`: pinned source archive and installed package hashes,
  ten notice checks, public-API native/bytecode consumers and Exchange replays.
- `protocol_controls.py` and `protocol-controls.log`: rejection of truncated,
  duplicate, nonfinite and missing benchmark samples; missing/reordered DD
  inputs and changed output words. Run against the decompressed ABBA JSON.
- `validation.json`: validation command/status and tooling/failure-control record.

The immutable `source.tar.gz`, `report.json` and `build.log` are also preserved
in the maintainer's acceptance store under this full implementation SHA.
The public source archive is reproducible from Git; no private research
access is needed. Logs and profiles are project-generated evidence, not
third-party implementation material.

## Reproduction

Use upstream OCaml 5.3.0 Flambda, the locked dependencies, and ocamlformat
0.27.0. Create separate baseline/candidate worktrees. Copy these measurement
files from the implementation commit into the baseline worktree:
`bench/fast_allocation_profile.ml`, `test/dd_word_replay.ml`, and their new
executable stanzas in `bench/dune` and `test/dune`. Leave baseline `lib/`
unchanged. Both measurement executables declare `(modes byte exe)`.

In each worktree:

```sh
opam exec --switch=morphiq-risk-ml -- dune build \
  bench/fast_allocation_profile.exe bench/fast_allocation_profile.bc \
  bench/fast_batch.exe bench/fast_planner.exe bench/shared_portfolio.exe \
  test/dd_word_replay.exe test/dd_word_replay.bc oracle/fixtures/dd.txt
opam exec --switch=morphiq-risk-ml -- dune build --profile release \
  --build-dir _build_release \
  bench/fast_allocation_profile.exe bench/fast_allocation_profile.bc \
  bench/fast_batch.exe bench/fast_planner.exe bench/shared_portfolio.exe \
  test/dd_word_replay.exe test/dd_word_replay.bc oracle/fixtures/dd.txt
```

Run the profiler for `--model bsm`, `black76`, `displaced`, `bachelier` and
`--phase compile`, `execute` in both build directories and both executable
modes. Default 2,000 calls follows five warmups. For bytecode, set
`CAML_LD_LIBRARY_PATH` to that build directory's absolute `default/lib/fp`.
The `MODEL` line reports uninstrumented GC allocation and price word; the
`SAMPLES` lines identify allocation sites. These synthetic singleton cases
are distinct from mixed benchmark workloads.

From the candidate worktree (replace the absolute worktree/output paths):

```sh
opam exec --switch=morphiq-risk-ml -- python3 scripts/compare_dd_words.py \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --output /tmp/dd-words.json
opam exec --switch=morphiq-risk-ml -- python3 scripts/candidate_artifact.py \
  --commit 75999776291370412dc0ffe3b4504b17e7979e3c \
  --output /tmp/fast-allocation-installed
```

Finish all task-owned builds/tests/profilers before timing:

```sh
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_fast_allocation.py \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --output /tmp/abba.json --rounds 2
```

Ordinary correctness and designated mutations remain separate from exact
replay and performance instrumentation. An identical finite trace is not a
universal error proof; shared-host means are not deployment tail latency.
