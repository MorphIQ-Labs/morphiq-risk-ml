# Optional European Fast-batch SIMD experiment

This standalone ARM64 experiment compares public `Batch.Fast` with prepared
OCaml, native scalar, operation-preserving AdvSIMD, and SLEEF AdvSIMD kernels.
Only the bounded Bachelier OTM middle branch is selected. All other requests
use public Fast fallback. Nothing is installed into the public package.
Read the prospective [protocol](PROTOCOL.md) and [results](../../docs/results-fast-simd.md).

## Build

Use the project's OCaml 5.3.0 Flambda switch and an AArch64 C compiler with NEON
intrinsics (the recorded run uses Apple Clang). The C flags deliberately disable
implicit contraction, fast-math and automatic vectorization; explicit FMAs remain.
Ordinary builds/CI do not require SLEEF or compile this native executable.

Build the pinned external SLEEF dependency in a separate local directory:

```sh
git clone --branch 3.6.1 --depth 1 https://github.com/shibatch/sleef.git /tmp/morphiq-sleef-3.6.1
git -C /tmp/morphiq-sleef-3.6.1 rev-parse HEAD
# Must be 6ee14bcae5fe92c2ff8b000d5a01102dab08d774
cmake -S /tmp/morphiq-sleef-3.6.1 -B /tmp/morphiq-sleef-build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DSLEEF_BUILD_DFT=OFF -DSLEEF_BUILD_QUAD=OFF -DSLEEF_BUILD_TESTS=OFF \
  -DSLEEF_BUILD_GNUABI_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/tmp/morphiq-sleef-install
cmake --build /tmp/morphiq-sleef-build -j2
cmake --install /tmp/morphiq-sleef-build
MORPHIQ_SIMD_EXPERIMENT=true MORPHIQ_SLEEF_PREFIX=/tmp/morphiq-sleef-install \
  opam exec --switch=morphiq-risk-ml -- dune build --profile release \
  experiments/fast_simd/runner.exe
```

SLEEF's source is licensed under Boost Software License 1.0; retain its upstream
license if distributing it. This repo includes no SLEEF source, header or binary.
The inherited project kernel notices are retained in [NOTICE.txt](NOTICE.txt).
SLEEF's own test suite was not run in this campaign; the particular function
used here is exercised by the independent local comparisons.

## Reproduce

Run from the repository root, with a new evidence directory for each campaign:

```sh
python3 -m venv /tmp/morphiq-simd-python
/tmp/morphiq-simd-python/bin/pip install mpmath==1.3.0
mkdir /tmp/fast-simd-evidence
_build/default/experiments/fast_simd/runner.exe --controls
/tmp/morphiq-simd-python/bin/python experiments/fast_simd/campaign.py generate \
  /tmp/fast-simd-evidence/input.txt _build/default/experiments/fast_simd/runner.exe
_build/default/experiments/fast_simd/runner.exe --validate \
  /tmp/fast-simd-evidence/input.txt > /tmp/fast-simd-evidence/trace.jsonl
python3 experiments/fast_simd/campaign.py score /tmp/fast-simd-evidence/input.txt \
  /tmp/fast-simd-evidence/trace.jsonl /tmp/fast-simd-evidence/accuracy.json
/tmp/morphiq-simd-python/bin/python experiments/fast_simd/campaign.py adjudicate \
  /tmp/fast-simd-evidence/accuracy.json /tmp/fast-simd-evidence/adjudication.json
python3 experiments/fast_simd/test_campaign.py
# Finish all task-owned builds, tests and profiles before timing.
python3 experiments/fast_simd/campaign.py collect \
  _build/default/experiments/fast_simd/runner.exe /tmp/fast-simd-measurements
```

Generation includes the existing European/displaced fixtures, threshold and
exponent-reduction neighbors, fixed-seed random original inputs and every
Bachelier request used in timing. The six deliberate failure/limit inputs are
outcome-equivalence checks; they have no numerical reference. New references
use the closed-form Gaussian expectation at 100 and 200 decimal digits.
Refinement agreement is evidence, not a proof of reference rounding.
Scoring retains all changed rows and both numerical and compatibility decisions.
A SLEEF quality failure is recorded as a no-go in the report; it is not hidden
as an incomplete collector run. An operation-preserving mismatch is an error.

`--bench` compares n=1/32/256/4096 and three books. `--reverse` reverses backend
order; the collector runs forward/reverse/reverse/forward in separate processes.
Each phase has three warmup calls and five samples of max(2,8192/n) iterations.
The compile and one-shot phases start from already constructed typed requests;
execution includes fallback and outcome allocation. No prices are cached.
Dividing batch time by n measures amortized cost, not individual latency.
Native calls retain the OCaml runtime lock; this is not worker scaling evidence.
Allocation counts cover OCaml allocation, not process RSS or arbitrary native
allocation. Compiler/dependency provenance and CPU profiles accompany the
recorded report; profile separately with `--profile --family eligible --backend 0`
(backend numbers 0–4 correspond to the order above).

The Python scorer/collector controls run in ordinary CI without SLEEF. They
exercise malformed/missing outputs, startup/process errors, real timeout cleanup,
source changes and the explicit no-go decision. Native wrapper controls cover
odd/empty sizes, frozen input ownership, independent outputs, concurrent reads
and invalid native shapes. Cross-platform native qualification, full branch
coverage, runtime certificates and worker integration remain outside this experiment.
