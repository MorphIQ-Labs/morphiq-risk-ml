# Certification allocation evidence

See [the report](../../results-certification-allocation.md) for conclusions,
compatibility and limits. Baseline is `13087ffc4d6169ee976fe4b50b0aef560aff8fb6`;
implementation is `5c5cc5256a03f175831b42000cd76524e23b5e31`. Later commits only
retain documentation/evidence. These files record an October 4, 2026 shared
Apple M1 Pro session with OCaml 5.3.0 Flambda and the library's `-O3` setting.

- `scalar-abba.json.gz` and `portfolio-abba.json.gz` retain two ABBA rounds,
  all outcomes, sample timings/allocation, toolchain and source/binary hashes.
  Scalar v2 also records minor/major collection counts per whole sample batch.
- `exchange-abba.json.gz` and `assurance-abba.json.gz` retain one ABBA campaign
  each, including failures and the IV timing regressions. The assurance harness
  measures ordinary fast price/Greeks and certified IV separately.
- `profile-*.txt.gz` retain unprofiled counter totals followed by independent
  sampled allocation stacks. `allocation-sites-final.json` sums estimates by
  the first frame after each `SAMPLES` line; estimates are not exact site counts.
- `metadata.json` binds all numerical sources, relevant harnesses and binaries.
  `baseline-instrumentation.patch.gz` records tracked benchmark-only changes;
  the new untracked baseline `bench/allocation_profile.ml` was copied byte for
  byte from the implementation revision and is bound by its metadata hash.
- `validation*.log.gz`, `mutations.log.gz`, `replay.json` and
  `installed-artifact.json` retain local suite completion, eleven compiled
  mutation kills, exact outcome compatibility and installed native/bytecode
  consumers. The empty final validation log reflects a successful cached build.
  Finite checks and reused references do not establish universal correctness.

The immutable source archive and its build log remain outside the public
checkout, under the implementation revision's local acceptance directory.
Its archive/tree hashes and installed notice hashes are in the artifact report.

## Reproduction

Use separate baseline/candidate worktrees and the pinned opam switch. Copy the
candidate benchmark sources to baseline (`certified_scalar.ml`,
`allocation_profile.ml`, and the relevant `bench/dune` declarations); numerical
baseline sources must remain unchanged. Build all binaries before timing:

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 \
  bench/certified_scalar.exe bench/shared_portfolio.exe \
  bench/exchange_qualification_bench.exe bench/assurance.exe \
  bench/allocation_profile.exe bench/shadow.exe
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_certified_scalar.py \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --output /tmp/scalar-abba.json
opam exec --switch=morphiq-risk-ml -- python3 scripts/benchmark_shared_portfolio.py \
  --baseline-source /path/to/baseline --candidate-source /path/to/candidate \
  --output /tmp/portfolio-abba.json
python3 scripts/benchmark_exchange_allocation.py \
  --baseline /path/to/baseline/_build/default/bench/exchange_qualification_bench.exe \
  --candidate /path/to/candidate/_build/default/bench/exchange_qualification_bench.exe \
  --baseline-revision 13087ffc4d6169ee976fe4b50b0aef560aff8fb6 \
  --output /tmp/exchange-abba.json
python3 scripts/benchmark_assurance.py \
  --baseline /path/to/baseline/_build/default/bench/assurance.exe \
  --candidate /path/to/candidate/_build/default/bench/assurance.exe \
  --baseline-revision 13087ffc4d6169ee976fe4b50b0aef560aff8fb6 \
  --same-contract --count 32 --runs 5 --output /tmp/assurance-abba.json
```

Run profiling separately with each variant's
`_build/default/bench/allocation_profile.exe --calls 100`; do not use its
instrumented elapsed time as a performance measurement. `SHA256.json` covers
all retained evidence files except itself. No artifact publishes or tags a release.
