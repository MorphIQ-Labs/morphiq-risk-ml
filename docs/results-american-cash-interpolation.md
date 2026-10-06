# Cash interpolation: allocation qualification

**Defer adoption:** the fixed follow-up does not clear every latency gate. The proposed runtime change remains unmerged.

The repeat fails 12 latency checks; pooling every A/B sample still fails 4. All allocation gates pass. Exact failures and complete samples remain in the machine-readable summary.

| Failed pooled gate | Baseline ms | Candidate ms | Increase |
| --- | ---: | ---: | ---: |
| cash/4 / scalar | 561.14 | 674.06 | 20.1% |
| cash/4 / planner4 | 151.62 | 176.62 | 16.5% |
| bermudan/4 / scalar | 889.58 | 1186.10 | 33.3% |
| bermudan/4 / batch | 892.85 | 1049.28 | 17.5% |

Bounded private scratch and within-call numerator reuse reduce cash allocation
with unchanged complete numerical outcomes. The first timing campaign failed
six batch-latency limits. The fixed follow-up and its disposition are recorded
below; an allocation improvement alone is insufficient for adoption.

## Scope and storage argument

The [previous allocation profile](results-american-remaining-allocation.md)
and post-#148 cash profile identify interpolation as about 45% of sampled cash
allocation. The first scratch candidate saved about 8%, and explicit inlining
raised that to about 9%; both exploratory observations fell short of the frozen
10% cash target. Their raw profiles/source patches remain in the archive.
The proposed implementation also reuses the immutable `point-lower` enclosure
already computed for endpoint comparison. No target was relaxed.

The [storage derivation](runtime-enclosures.md#interpolation-owned-scratch)
covers one checked array per call, overwritten used prefixes and immutable
returned fields. General division retains its geometric correction/tail and
ordinary fresh-storage entry point. Scalar fusions retain exact-scalar word
order. Reusing the identical point/node subtraction removes duplicate work
without changing its inputs, error or failure. Explicit inlining removes boxing.
No interpolation result borrows scratch; independent calls/domains own storage.

Grid search, exact endpoint values/zero signs, strict convex-weight checks,
weighted-sum order, local error screen, mapping diagnostics, event sides,
refinement and ticks remain unchanged. This does not introduce slope-form
arithmetic, a cache, factor reuse, FFI, weakened tolerance or new financial model.
The additive primitive lives under the unstable internal enclosure interface;
public pricing signatures are unchanged.

## Frozen campaign and provenance

The [protocol](evidence/american-cash-interpolation/protocol.md) and generic
reference composition/tests were committed before runtime optimization. Baseline
pricing still uses its original inline composition; the added generic primitive
is unused by that baseline's pricing runtime. The original freeze commit
`3291da2` (full ID in the archive) and published rebased baseline have the
same complete Git tree; the bridge record and original freeze patch are retained.

Baseline: `1e6cdf70777462da7b1613e360d60d5d21a18e3c`. Candidate: `b9aa4e00e36e6ef9673583f04d70a8f52801869d`.
The candidate is rebased onto PR #148's identical integration merge tree
`4959ab44d861a52e9db84c3d96e0dc0c701cb3e2`. Historical qualification and timing
use identical runtime/test/oracle source hashes. Evidence publication changes
no runtime source. The initial mutation attempt stopped because its numerical-only
option was treated as a fixture; no fault was scored. The corrected dispatcher
has an explicit argument-passing control and a successful fresh mutation baseline.
Both attempt logs are retained.

[Complete summary](evidence/american-cash-interpolation/results/summary.json),
[archive inventory and hashes](evidence/american-cash-interpolation/results/manifest.json),
and [raw results/source patches](evidence/american-cash-interpolation/results/raw.tar.gz).

The unchanged #148 request corpus/drivers run ten singleton cases, three
eight-row cash cases and eight European certified cases in five alternating
fresh process pairs per campaign. The first campaign has 140 processes; the
single confirmatory repeat adds 140. Twelve separate same-binary diagnostic
processes bring the total to 292. Every first-campaign observation is retained.
Eight rows mean four positions × two dated
scenarios. Fixed batching and one/four-worker planners use tile one and a no-op
sink. Compilation/admission, first output and reused execution remain separate.
Every process and method preserves complete replay. Guards cover tracked,
staged, unstaged, untracked source and executable hashes.

Both complete A/B campaigns start after task-owned builds, reference campaigns,
mutants, ordinary tests and profiles finish. Each timed operation warms up and collects first; whole-program
allocation runs (including joined workers) are separate from latency. The
European harness contributes the mean of five inner samples per process.

Host: Apple M1 Pro, 10 logical CPUs, `macOS-27.0-arm64-arm-64bit-Mach-O`,
OCaml 5.3.0 Flambda, release `-O3`; confirmatory campaign began `2026-10-06T23:26:35.263199+00:00`.
Recorded one-minute load spans **15.54–70.22**. This is a shared host, not an isolated SLA campaign.

Frozen criteria require at least 10% less singleton cash allocation and 5% less
Bermudan/piecewise-cash allocation. Other pricing methods may grow no more than
5%; all American/European price/end-to-end medians may regress no more than 10%.
Compile/admission costs are retained without fitted thresholds.

The [fixed follow-up](evidence/american-cash-interpolation/followup-protocol.md)
was specified before its collection: exactly twelve same-binary processes, one
full repeat, and gates on both that repeat and the pooled medians of every sample
from the two campaigns. No observations are removed and no thresholds change.
Same-binary three-pair medians falsely indicate substantial slowdowns: baseline
batch 1.56× and planner1 1.54×; candidate batch 1.67×, planner1 1.45× and planner4
1.78× for the second label versus the identical first binary. This demonstrates
large timing variability; it does not prove that every A/B difference is external.
The first campaign remains failed regardless of the follow-up result. A small
Python pooling-control test overlapped the separate same-binary diagnostic
(about 0.11 seconds), a deviation from that diagnostic's isolation condition.
The archive records it explicitly; the confirmatory A/B campaign began after
the control finished. Same-binary observations are not sole-cause attribution.

## Singleton scalar observations

Times are milliseconds; parentheses give observed minimum–maximum across all ten
process observations, not tail-latency guarantees. Decimal MB is cumulative managed bytes,
not live memory. Refused IV and strict requests are not successful throughput.

| Workload | Baseline ms (range) | Candidate ms (range) | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| Analytical call | 0.079 (0.077–0.085) | 0.079 (0.076–3.907) | 0.104 | 0.104 |
| Flat put | 22.034 (21.501–26.940) | 21.747 (21.266–32.316) | 6.967 | 6.967 |
| Cash put | 66.885 (65.065–109.660) | 65.690 (64.907–81.243) | 22.574 | 20.180 |
| Bermudan with cash | 107.117 (106.483–163.537) | 109.809 (103.060–165.896) | 36.705 | 34.311 |
| Piecewise | 59.547 (58.391–77.405) | 59.364 (57.574–79.913) | 26.366 | 26.366 |
| Piecewise-cash | 89.277 (83.308–135.392) | 83.853 (82.755–167.654) | 38.543 | 36.150 |
| Delta/gamma | 22.196 (21.747–106.955) | 22.074 (21.713–37.507) | 7.146 | 7.146 |
| IV work-limit refusal | 15.332 (15.145–19.211) | 15.286 (15.143–17.833) | 6.225 | 6.225 |
| Certified reduction | 0.401 (0.384–0.414) | 0.394 (0.378–0.583) | 0.351 | 0.351 |
| Strict arithmetic refusal | 0.455 (0.440–0.460) | 0.460 (0.441–0.500) | 0.902 | 0.902 |

## Eight-row planners

Whole-request latency and whole-program allocation include all eight rows.
Amortized time per row is not singleton latency.

| Workload/workers | Baseline ms (range) | Candidate ms (range) | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| Cash put / 1 | 580.863 (548.165–936.986) | 630.634 (549.076–1822.698) | 185.237 | 165.353 |
| Cash put / 4 | 151.624 (141.574–461.965) | 176.617 (141.116–525.108) | 185.240 | 165.357 |
| Bermudan with cash / 1 | 888.959 (883.474–1311.134) | 904.782 (879.029–1016.064) | 298.261 | 278.378 |
| Bermudan with cash / 4 | 236.757 (228.922–541.776) | 243.359 (226.583–491.429) | 298.265 | 278.381 |
| Piecewise-cash / 1 | 705.470 (692.120–1346.024) | 715.077 (684.502–1296.052) | 316.117 | 296.234 |
| Piecewise-cash / 4 | 198.358 (180.270–444.215) | 203.769 (180.971–574.525) | 316.121 | 296.238 |

The complete summary retains scalar/fixed/planner, first output and compilation.
Baseline per-child peak RSS spans 5.87–28.44 MB across the campaign.
Candidate per-child peak RSS spans 6.03–30.29 MB across the campaign.
These peaks include harness/warmups/memory experiments and do not measure
simultaneous deployment-wide memory. Cumulative allocation remains material.

## European controls

Shared division plumbing requires European regression controls even though the
new interpolation primitive is not used by these models. Price-only medians of
ten process means follow; admission/end-to-end and ranges are retained in the
summary. CHECK records, including accuracy refusal, remain identical. Fast
pricing kernels are unchanged.

| Case | Baseline μs | Candidate μs | Baseline kB | Candidate kB |
| --- | ---: | ---: | ---: | ---: |
| black76 | 754.882 | 753.605 | 555.691 | 555.691 |
| bsm-accuracy-failure | 809.298 | 850.313 | 558.627 | 558.627 |
| bsm-expiry | 0.095 | 0.088 | 0.267 | 0.267 |
| bsm-ordinary | 811.890 | 817.400 | 558.683 | 558.683 |
| bsm-short | 298.552 | 298.023 | 304.531 | 304.531 |
| bsm-tail | 3027.150 | 2995.497 | 2231.771 | 2231.771 |
| displaced | 765.720 | 755.215 | 540.899 | 540.899 |
| normal | 262.025 | 260.845 | 238.179 | 238.179 |

## Correctness and failure evidence

- Full development/release install, format and ordinary suites pass. The existing
  determinism digest remains
  `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`
  over 6,069,960 bytes; no expected value changes.
- Primitive qualification retains 1,192 complete-field/endpoint/failure cases
  per precision, identical in baseline/candidate native and bytecode. Full
  digest: `474878836d491dc2d8f9d8b46b026d14`; Fast:
  `d8adb108399cce5d3b27fed7925be314`. Signed endpoints, adjacent/subnormal/extreme
  nodes, uncertain points, invalid widths, retained results and independent
  domains are included.
- An independent exact-rational affine formula checks **992 containment cases**
  over both precisions, including uncertain points, increasing/decreasing values
  and non-single-word widths. The interval image is the ordered pair of affine
  values at the original point interval's endpoints; it does not reuse the
  production finite-expansion quotient.
- All **572 historical price outcomes, 920 Greek rows and three 30-case inverse
  campaigns** retain identical full payloads and independent scores. Refusals,
  wide references and unresolved references remain explicit, never accuracy passes.
- **17 targeted mutants** are killed after a clean compiled baseline: the two
  new interpolation prefix/complement faults, scalar radius/scratch length,
  product guard, exponential prefix/tail, sum order/finiteness, grow residual,
  retained/discarded word, normal exponent, FMA underflow, and cash liquidator,
  opening side and mapping refinement. The new guard runs `--numerical-only`;
  compatibility fingerprints cannot count as its kill. No full catalog run is claimed.
- Existing collector failure controls and two new cash-target/latency controls
  pass. The optional catalog has 179 entries; default CI remains five jobs and
  seven core mutants. Timings are manual evidence, not a new CI performance gate.

## Disposition and reproduction

The adoption decision is stated at the top and reflected in the machine-readable
summary. These observations do not establish a deployed memory/latency budget
or general American certification. #119 retains unset
deployment requirements; #120 owns final integration qualification. Further
optimization should be driven by fresh profiles against explicit workloads,
not by treating these engineering thresholds as production acceptance.

Build the recorded revisions in separate worktrees, then stop other task-owned
compute before running the collector from the candidate:

```sh
opam exec --switch=morphiq-risk-ml -- dune build --profile release \
  bench/backend_requests.exe bench/certified_scalar.exe
python3 scripts/measure_cash_interpolation.py \
  --baseline /path/to/baseline --output /path/outside/source-trees
```

The output path must be new. Partial failures are retained. Historical qualification
and publication scripts, changed sources and all raw observations are archived;
recorded local paths require adjustment in another workspace.
