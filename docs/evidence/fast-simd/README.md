# Fast-batch SIMD evidence — 2026-10-05 UTC

See [the report](../../results-fast-simd.md) for the decision and scope, and
[the executable protocol](../../../experiments/fast_simd/README.md) to reproduce.
The production library is unchanged. The optional native experiment was measured
locally on ARM64; ordinary CI does not establish native cross-platform conformance.

- `timings-summary.json`: all 180 family/size/backend/phase combinations, with
  four process medians, allocation and selected-row count.
- `accuracy-summary.json`: numerical and compatibility decisions without the
  bulky changed-row list. Full changed-row evidence is in the archive.
- `raw.tar.gz`: retained raw inputs, outputs, samples, profiles, checks and build
  provenance. Its internal `SHA256SUMS` identifies every evidence member's uncompressed
  content (excluding the manifest itself). No native binaries, third-party sources, headers, libraries or research
  PDFs are distributed in this archive.
- `SHA256SUMS`: hashes for these three sibling artifacts (not this README or
  the manifest itself).

Archive layout:

| Location | Meaning |
| --- | --- |
| `timing/before.json`, `after.json`, `run-*-host.json` | Source/status, experiment-file hashes, executable hash, UTC and load records |
| `timing/run-*.jsonl`, `.stderr` | All 3,600 samples and process stderr, including slower results |
| `validation/input-qualified.txt`, `.json` | Complete final 110,632-row corpus, original fixture hashes and reference-generation metadata |
| `validation/trace-qualified.jsonl` | All five backend outcomes and selected/fallback status for every final row |
| `validation/accuracy-qualified.json`, `adjudication.json` | Every changed row and independent 100/200-digit original-input refinement |
| `validation/qualified-profile-*` | Final executable CPU samples and its source/hash/command provenance |
| `validation/kernels-assembly.txt` | Native scalar and AdvSIMD operation inspection |
| `validation/*checks*.txt`, `*controls*.txt`, `validation-status.json`, `mutations.txt` | Local verification and explicit outcomes/limits |
| `validation/sleef-*`, `*-version.txt`, `hardware.txt`, `os.txt`, `ocaml-config.txt` | Pinned dependency hashes, CMake/Ninja configuration/logs, toolchain and host |

Historical/partial artifacts are deliberately retained:

- `input.txt`, `trace.jsonl`, `accuracy.json` are the initial 101,350-row campaign;
  they are superseded by the larger qualified corpus.
- `input-final.txt` is an intermediate 101,416-row generation before adding every
  timed Bachelier input. It was not the final scored/timed population.
- `profile-*` and `final-profile-*` are preliminary profiles. The first setup
  lost access to the executable when a concurrent format/build invocation removed
  it; an empty mixed-profile output remains. A stable copied executable was then
  sampled. Those preliminary profiles have weaker source provenance and are not
  used for the final report. The `qualified-profile-*` rerun uses the exact measured
  executable after timing ended and records source/status/hash. All profilers
  finished before the timing campaign, or ran separately after it.
- `release-checks.txt` includes the initially rejected Dune formatting; the
  subsequent aggregate release check passes. `format-final.txt` records the
  formatter's correction, which can itself return a nonzero status on promotion.
- `scorer-controls.txt` and `collector-controls.txt` predate the final ordinary
  check's eleven control groups; the final timeout control allows two seconds
  for child startup before killing/reaping its deliberately sleeping process.

The library's qualified tree is
`0da7e7fda5ef50b4bd7696580829fd9a3adea598`. The measured experiment revision is
`b78eef6cd0f1027fefc9a8e4d68f208d6f46102d`; later changes add the report/evidence.
Four existing scalar preparation/fallback mutation witnesses are retained.
They do not qualify every native operation or establish a uniform SLEEF error
bound. Deployment acceptance and production adoption remain separate decisions.
