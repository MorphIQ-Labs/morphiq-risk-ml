# Scalar American allocation optimization (#119)

The native American solver now specializes float comparisons and explicitly
inlines its finite/nonnegative checks. This removes temporary boxed floats from
the repeated row loops. It does not change the public API, solver policy,
arithmetic expressions, original-input enclosure arithmetic, or work limits.
Successful prices remain **Estimated_only**; this is not runtime certification.

## What changed and why

The [initial profile](evidence/american-allocation/profile-before.json) attributed
about 95% of sampled cash-request allocation to residual and time-step row loops.
Polymorphic `min`/`max` and non-inlined numeric checks required boxed float
arguments/results around each row. The replacement comparisons use the same
`if a >= b then a else b` / `if a <= b then a else b` selection as OCaml 5.3
Stdlib, including equal signed zeros and unordered operands. All finite checks
stay at their original sites. The multiplication rounding barrier and explicit
`Float.fma` calls are unchanged. The same pattern was checked throughout
`Early_exercise.Bsm`; integer limits/counters retain integer comparisons.

This lets Flambda eliminate temporary objects without skipping numerical work.
No factor caching, shared scratch, unsafe access, FFI, new dependency or weaker
refinement criterion is involved. Native allocation gains do not imply the same
gain under bytecode. European Fast/certified kernels are unchanged.

The [follow-up profile](evidence/american-allocation/profile-after.json) shows
the row-loop allocation largely removed. Remaining allocation is mainly the
enclosure operations used in coefficient/boundary calculations, time/event
coordinates and dividend interpolation. Original full sampled stacks are retained
as compressed text beside both profile summaries. Sampling is statistical and
profiler timings are excluded from the performance campaign.

## Matched measurements

The [protocol](evidence/american-allocation/protocol.md) was committed before
runtime changes. Its engineering targets are at least 90% lower cumulative
allocation for none/zero/cash and no more than 10% median latency regression.
These are local optimization criteria, not a deployment SLA.

Both builds price the same admitted ATM put: S=K=100, r=.05, q=.02, sigma=.2,
T=1, opens=0, tolerance=1, 128 cells/128 steps, two domain expansions and the
same explicit caps. Each request includes the entire refinement/boundary
program. Admission, reused price, and price with optional diagnostics are
measured separately. Cash is 5 at .5; zero cash is 0 at .5; multiple cash is
3 at .25 and 4 at .75. Unavailable cash premium diagnostics remain unavailable.

Apple M1 Pro, 16 GiB, macOS 27, OCaml 5.3.0 Flambda, release `-O3`.
One-minute host load ranged from **12.55 to 23.43**; this was a busy shared host.

| Schedule, price only | Before → after median | After range | Cumulative allocation before → after | Reduction | Speedup |
| --- | ---: | ---: | ---: | ---: | ---: |
| No cash | 254.1 → 157.7 ms | 151.4–183.6 ms | 625.4 → 48.3 MB | 92.3% | 1.61× |
| Zero payment | 743.6 → 461.6 ms | 451.7–543.6 ms | 1739.0 → 92.4 MB | 94.7% | 1.61× |
| One payment | 736.5 → 449.8 ms | 424.0–562.4 ms | 1755.1 → 115.5 MB | 93.4% | 1.64× |
| Two payments | 1144.9 → 707.5 ms | 654.2–748.3 ms | 2599.2 → 165.8 MB | 93.6% | 1.62× |

All frozen criteria pass for both price-only and requested diagnostics.
With diagnostics, allocation falls by 92.3–94.6% in the none/zero/cash controls;
candidate medians are 157.6, 450.8 and 450.2 ms respectively. Two payments with
diagnostics take 735.1 ms and allocate 165.8 MB. Cash premium remains explicitly
unavailable. Median admission costs are about 23 ns without cash and 53–61 ns
with cash, with unchanged measured allocation (about 419/797/818 bytes).
Small differences do not establish an admission speedup.

For none (three measured requests/process), baseline: 7.6 MB peak RSS, 898 minor/10 major collections; candidate: 7.7 MB peak RSS, 72 minor/9 major collections.
For cash (three measured requests/process), baseline: 7.3 MB peak RSS, 2516 minor/16 major collections; candidate: 7.7 MB peak RSS, 171 minor/17 major collections.

MB here means 1,000,000 bytes. Allocation uses differences of OCaml
`Gc.quick_stat` minor + major − promoted words, so small GC-accounting
variation is retained in the raw ranges. It is cumulative allocated volume,
not simultaneous live memory. Peak RSS covers the whole child, including
startup, warmup and explicit GC. Post-collection live words/heap sizes are
also retained; neither is the peak numerical workspace.

Five fresh processes per workload/build alternate comparison order. Each warms
up once, collects a full major GC, and averages three price requests (100,000
for admission). The OCaml driver measures elapsed wall time; the collector
retains each child's CPU use and peak RSS from its own `wait4`. Ranges are
process means, not single-request tail percentiles. All task-owned builds,
tests and profilers finish before timing. This shared host is not isolated.

The [complete performance record](evidence/american-allocation/performance.json)
contains source revisions/hashes, compiler/configuration, executable hashes,
host/load, every sample, GC counts and acceptance results. Raw child output and
resource records are retained in `performance-raw.json.gz` beside it. Source
guards include staged, unstaged and untracked runtime/benchmark inputs.
Historical #111 and #112 measurements retain their original hosts/configurations;
the comparator here is the matched #130 runtime, not #111's 256-step workload.

## Numerical and failure compatibility

The [compatibility record](evidence/american-allocation/compatibility.json)
retains all 41 no-cash and 30 cash cases, primary and separately loose targets,
in initial/refined configurations: **284 complete outcomes**. Prices, errors,
refinement/mapping/region/premium fields and work diagnostics have identical
OCaml 5.3 `Marshal.No_sharing` fingerprints before and after. Replay equality
is regression evidence; independent reference scoring remains the accuracy
check. No tolerance or reference was changed, and all unavailability and
unresolved-reference classifications remain visible.

| Corpus / configuration | Primary: pass / unresolved reference / unavailable | Loose: pass / unresolved reference / unavailable |
| --- | ---: | ---: |
| No cash, initial | 18 / 1 / 22 | 19 / 4 / 18 |
| No cash, refined | 17 / 1 / 23 | 32 / 6 / 3 |
| Cash, initial | 9 / 0 / 21 | 11 / 0 / 19 |
| Cash, refined | 10 / 0 / 20 | 29 / 0 / 1 |

The corpora include deterministic/boundary, delayed opening, negative-rate,
multiple/coincident dividend and hard cases. Corpus replay uses default optional
diagnostics; dedicated controls also exercise requested regions/premiums,
cancellation before/during work, limits, nonconvergence and call-owned scratch.
Cancellation behavior is checked; cancellation response latency is not measured
in this scalar campaign.

Native development/release ordinary suites, package build, formatting, bytecode
American controls and the five affected American mutants are recorded in
`validation.json` in the evidence directory. Mutation kills require the named
numerical/semantic witness after a clean baseline and successful mutated build.
Default CI remains five jobs and seven core mutants.

## Reproduction and remaining work

Build the recorded baseline and candidate revisions with the recorded OCaml
5.3.0 Flambda switch and Dune release profile. Build
`bench/american_allocation.exe`, `test/american_pricing.exe` and
`test/american_cash.exe`; keep separate immutable executable copies and capture
the source and binary hashes in build manifests with the schema retained in
the performance record. Paths can be relocated; hashes must still match.

Run the two existing independent scorers with `MORPHIQ_AMERICAN_SNAPSHOT=1`,
`--mode primary|loose`, with/without `--refined`, and compare their complete
`stdout.tsv` outputs. For profiling, run the allocation driver with
`--mode none|cash` without `--measure`. After completing all validation:

```sh
python3 scripts/benchmark_american_allocation.py \
  --baseline /path/to/baseline-build.json \
  --candidate /path/to/candidate-build.json --output /new/evidence/directory
```

The collector checks the candidate checkout and both recorded source revisions,
requires identical compiler/driver, preserves partial output on failure, rejects
incomplete/malformed samples, and enforces the frozen criteria. Its failure
controls run in ordinary CI; machine-dependent timing does not.

This completes the focused scalar boxing pass, not all of #119. Remaining
enclosure allocation is still material. Reducing it needs its own profile-led,
numerically qualified work. Compiled workloads depend on #118; worker/tile
measurements, native tridiagonal candidates and the bounded algorithm evaluation
remain open. Strict accuracy limitations and independent source-artifact
qualification remain under #120. No production SLA or new numerical capability
is established here.
