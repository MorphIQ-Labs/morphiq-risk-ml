# Native batch evidence — 2026-10-05 UTC

See the [report](../../results-native-bachelier-batches.md) for decisions and
limitations. `timings-summary.json` retains all 360 final comparison groups,
including four process medians each. `raw.tar.gz` contains only project evidence:

- `timing/`: final 7,200 raw samples, all stderr, exact timed inputs, source and
  executable hashes, UTC/load observations and complete summaries.
- `initial-timing/`: superseded retained-admission implementation, including all
  slower samples and its source guards. Do not mix it into the final summary.
- `validation/`: development/release tests, four named mutations, native and
  public reference checks, formatting corrections, build logs and disassembly.
  Earlier checks remain visible; `native-retention-*` identifies the final runtime.
- `installed/`: final immutable-source package/install report and build log,
  including native/bytecode public consumers and all 649 Exchange replay cases.
  `initial-installed/` covers the earlier runtime, not the final candidate.
- `provenance.json` and `SHA256SUMS`: input identity, source scope and every
  archived member's uncompressed hash.

The sibling manifest hashes the summary and archive. No binaries, source
archives, third-party implementation payloads or research PDFs are redistributed
inside this evidence archive. Public original-input references remain in
[the previous experiment archive](../fast-simd/README.md). Later additions to
the selected reference test exercise the public API without changing runtime code.

Reproduce with the [experiment build commands](../../../experiments/fast_simd/README.md)
at the two recorded clean revisions, followed by:

```sh
python3 experiments/fast_simd/compare.py \
  BASE_ROOT BASE_BINARY CANDIDATE_ROOT CANDIDATE_BINARY NEW_OUTPUT_DIRECTORY
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- \
  native-bachelier-exponent native-bachelier-mode fast-batch-order fast-batch-finite
python3 scripts/candidate_artifact.py \
  --commit 131983f46dec346f05585a800ca6ccaa6b3ef196 --output NEW_ARTIFACT_DIRECTORY
```

The optional driver uses external SLEEF for its research comparison. The native
library and ordinary tests require no SLEEF. All task-owned builds/tests finish
before timing. Shared-host timing, local packaging evidence, platform CI,
independent review and deployment acceptance remain distinct.
