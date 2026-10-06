# American workload and worker campaign

This #119 pass measures the compiled American API from #118 without changing production pricing. The frozen twelve-workload corpus checks complete scalar/fixed/planner outcomes and separates singleton latency, compilation, portfolio execution and program-wide managed allocation. Worker and tile choices apply only to these small portfolios and this host; this is not deployment acceptance or an accuracy qualification.

## Candidate and protocol

Measured source: `ff1cb75c5af6579de1e8223c6d76c3a8a945b6f0`; binary SHA-256 `20685df3fbb3d436e7f07643fbc0fa31c70bbb21e2de88f9a13a72ca50888d9f`. Source status: `clean`. Production `lib/` is unchanged from integration `403ea7cdeddc7b263bd88bc62cc1c7558cbe884b`. Final report/evidence publication is a documentation-only bridge; the source manifest retains every tracked/untracked unignored file hash.

Host: Apple M1 Pro, macOS-27.0-arm64-arm-64bit-Mach-O, 10 logical CPUs; OCaml 5.3.0 Flambda, release/O3. Recorded one-minute host load 5.87–29.50. Task-owned builds/tests finished before timing; the shared host was not isolated.

[Frozen protocol](evidence/american-workloads/protocol.md), [all summaries](evidence/american-workloads/summary.json), [raw logs, process records and source snapshot](evidence/american-workloads/raw.tar.gz), [SHA-256 manifest](evidence/american-workloads/manifest.json). Five fresh processes per workload/shape/phase, 245 in total. Each time sample has one warmup and one measured execution, with an untimed full major collection between them. Method order reverses each round. Zero-duration observations are retained as below clock resolution, without inferring infinite throughput. Compilation samples average 50 repetitions. Parent `wait4` supplies each individual child’s RSS; peaks include harness qualification and the whole process, not one isolated priced row.

Four positions × two scenarios make eight portfolio rows; tiles and workers each sweep 1/2/4. Singleton has one position, one scenario and one worker. The ordinary 64×64/tolerance=1 and strict 1e-12 configurations are fixed engineering workloads, not equal-accuracy comparisons with the earlier 128-grid scalar reports. Cash, exercise dates, piecewise knots, quotes, limits and Greek targets remain fixed. Scalar input rolls are constructed separately from planner rolls.

## Outcomes and singleton cost

Every process checks complete ordered payloads against direct scalar calls before measurement. All fixed/planner configurations agree. This is compatibility evidence, not an independent numerical accuracy result. Counts below refer to portfolio quantities; delta/gamma cases request sixteen quantities across eight rows. All refusal costs stay visible.

| Workload | Accepted / failed / unavailable quantities | Outcome | Reused singleton scalar ms, median (range) |
| --- | ---: | --- | ---: |
| call | 8 / 0 / 0 | estimated | 0.076 (0.076–0.083) |
| flat | 8 / 0 / 0 | estimated | 21.915 (21.242–22.792) |
| cash | 8 / 0 / 0 | estimated | 67.062 (66.637–122.207) |
| bermudan | 8 / 0 / 0 | estimated | 111.304 (105.659–114.707) |
| piecewise | 8 / 0 / 0 | estimated | 60.468 (58.318–61.201) |
| piecewise-cash | 8 / 0 / 0 | estimated | 83.869 (82.465–88.228) |
| greeks | 16 / 0 / 0 | estimated | 21.750 (21.570–22.328) |
| curve-greeks | 16 / 0 / 0 | estimated | 61.222 (58.263–82.633) |
| iv | 0 / 8 / 0 | iv-resource-limit | 15.538 (14.907–16.161) |
| certified | 8 / 0 / 0 | certified | 0.385 (0.377–0.398) |
| hard | 0 / 8 / 0 | arithmetic-unresolved | 0.449 (0.438–0.485) |
| mixed | 6 / 2 / 0 | arithmetic-unresolved, estimated | 22.188 (21.342–22.699) |

IV costs in this corpus are resource-limit refusals; strict price costs are arithmetic-unresolved refusals. Mixed portfolios retain their refused rows. No failed row counts as successful pricing throughput. Earlier independently qualified IV results remain in [the inverse report](results-american-iv-optimization.md); this campaign does not replace them.

## Eight-row execution and worker/tile choice

All values are median whole-portfolio milliseconds. “Lowest observed” selects from nine configurations and is descriptive, not a validated automatic policy. Scalar and fixed batching return arrays; planner execution includes a minimal row-counting sink and first-row clocks, with no transport or durable storage. Compilation is excluded here and retained separately in the machine-readable summary. Across workloads, per-case median compile costs are 3.18–8.94 μs for singleton fixed batches and 7.14–12.22 μs for singleton tile1 planners; eight-row costs are 20.72–66.00 μs and 17.08–34.04 μs respectively.

| Workload | Scalar | Fixed batch | Planner tile1/worker1 | Lowest observed tile/workers | Lowest observed ms (range) | First row ms at that setting | Accepted quantities/s |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| call | 0.722 | 0.708 | 0.726 | 2/4 | 0.466 (0.414–0.605) | 0.463 | 17167.4 |
| flat | 190.591 | 190.035 | 189.768 | 1/4 | 51.422 (48.085–196.110) | 24.189 | 155.6 |
| cash | 561.099 | 559.932 | 561.267 | 1/4 | 154.178 (152.066–169.651) | 72.444 | 51.9 |
| bermudan | 907.830 | 892.150 | 886.942 | 1/4 | 245.495 (228.753–278.601) | 120.301 | 32.6 |
| piecewise | 498.407 | 498.801 | 503.155 | 2/4 | 135.142 (133.151–147.787) | 135.137 | 59.2 |
| piecewise-cash | 699.125 | 695.458 | 690.866 | 1/4 | 184.674 (181.337–315.159) | 90.621 | 43.3 |
| greeks | 189.588 | 186.844 | 187.584 | 1/4 | 50.879 (48.712–52.399) | 24.183 | 314.5 |
| curve-greeks | 513.123 | 510.254 | 504.452 | 1/4 | 135.413 (130.490–353.228) | 66.137 | 118.2 |
| iv | 122.947 | 122.169 | 122.373 | 2/4 | 33.703 (33.344–35.656) | 33.698 | 0.0 |
| certified | 4.154 | 4.287 | 4.329 | 2/4 | 1.724 (1.621–2.168) | 1.717 | 4640.4 |
| hard | 3.839 | 3.971 | 3.906 | 2/4 | 1.649 (1.526–2.253) | 1.646 | 0.0 |
| mixed | 362.908 | 361.576 | 369.791 | 2/4 | 103.633 (101.237–115.666) | 103.628 | 57.9 |

Accepted-quantity throughput divides accepted quantities by whole execution time, including failed work; refused quantities never enter the numerator. The summary retains every tile/worker result, first-row latency, CPU time, admission-only and end-to-end scalar measurement. More workers cannot create parallelism when too few logical tiles exist; larger waves also delay delivery until the wave joins. These results do not justify changing caller-selected defaults or sharing solver factors between rows. For example, flat-put four-worker execution has a 51.4 ms median but spans 48.1–196.1 ms on this shared host. Wider timing ranges preclude a stable latency guarantee; larger target portfolios and concurrent service traffic still need their own campaign.

## Allocation and process memory

Whole-program `Gc.stat` snapshots bracket each complete execution after workers join. Unlike coordinator `Gc.counters`, these include workers. Independent known-size allocations and per-domain counter deltas qualify the scope for 1/2/4 joined domains in both native and bytecode builds; replacing totals with coordinator counters fails that witness. `Gc.stat` forces full collections, so memory measurements run in separate fresh processes from ordinary latency. Snapshot/runtime overhead is included; managed bytes exclude untracked native memory. Collections include the forced snapshots and are not pause durations.

Median cumulative MB per eight-row execution (decimal MB), distinct from live workspace and peak RSS:

| Workload | Scalar total | Planner 1/1 total | Planner 1/4 total | Planner 1/4 coordinator only | Time-process RSS MB range | Memory-process RSS MB range |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| call | 1.063 | 1.073 | 1.076 | 0.272 | 9.86–10.55 | 9.40–9.58 |
| flat | 57.252 | 57.261 | 57.265 | 14.319 | 22.77–25.74 | 23.41–28.38 |
| cash | 185.221 | 185.237 | 185.240 | 46.313 | 21.71–28.85 | 22.25–25.17 |
| bermudan | 343.225 | 343.247 | 343.251 | 85.815 | 23.15–24.69 | 22.53–23.84 |
| piecewise | 270.603 | 270.631 | 270.634 | 67.661 | 21.71–23.79 | 21.36–22.74 |
| piecewise-cash | 371.245 | 371.279 | 371.283 | 92.823 | 23.12–24.84 | 22.74–24.23 |
| greeks | 58.664 | 58.673 | 58.677 | 14.672 | 24.79–25.67 | 24.02–25.07 |
| curve-greeks | 272.014 | 272.043 | 272.046 | 68.014 | 22.53–26.74 | 22.04–23.56 |
| iv | 50.291 | 50.301 | 50.304 | 12.579 | 23.13–24.31 | 23.23–23.77 |
| certified | 3.887 | 3.897 | 3.900 | 0.978 | 11.62–12.57 | 11.70–12.06 |
| hard | 7.532 | 7.542 | 7.546 | 1.889 | 17.30–18.22 | 17.30–18.28 |
| mixed | 155.313 | 155.330 | 155.333 | 14.319 | 22.90–24.67 | 22.94–25.03 |

Parallel workers redistribute allocation; coordinator-only reductions must not be described as whole-request savings. This pass does not optimize allocation or claim that cumulative allocation is an acceptable deployment budget. The residual enclosure allocation question remains in #119.

## Cancellation

Five separate flat-put portfolio processes request cancellation after a nominal 5 ms controller sleep. The following ranges span all five rounds. Latency starts at the controller’s actual issuance timestamp, and controller delay is reported separately. These are small-sample observations, not request percentiles or an SLA; elapsed time alone does not establish the active solver phase. The deterministic #118 callback-count test separately verifies in-solver cancellation forwarding.

| Tile/workers | Stops | Issue ms range | Return after issue μs range | Committed rows range |
| --- | --- | ---: | ---: | ---: |
| 1/1 | {'cancelled': 5} | 5.671–6.480 | 1.0–4.0 | 0–0 |
| 1/2 | {'cancelled': 5} | 6.332–6.352 | 55.0–125.0 | 0–0 |
| 1/4 | {'cancelled': 5} | 6.341–6.384 | 123.0–487.0 | 0–0 |
| 2/1 | {'cancelled': 5} | 5.238–6.402 | 1.0–6.0 | 0–0 |
| 2/2 | {'cancelled': 5} | 6.093–6.402 | 82.0–167.0 | 0–0 |
| 2/4 | {'cancelled': 5} | 6.335–6.460 | 139.0–288.0 | 0–0 |
| 4/1 | {'cancelled': 5} | 6.329–6.385 | 2.0–4.0 | 0–0 |
| 4/2 | {'cancelled': 5} | 6.322–6.462 | 79.0–236.0 | 0–0 |
| 4/4 | {'cancelled': 5} | 5.438–6.331 | 94.0–180.0 | 0–0 |

## Validation and remaining work

Development and release ordinary suites, package builds and format checks pass. Native and bytecode counter/collector controls pass. Collector negative controls cover malformed/truncated/duplicate/nonfinite records, inconsistent allocation scope, changed replay, classification mismatches, cancellation prefixes, unsuccessful children, failed startup and timeout/reaping. Small controls join the existing ordinary suite; the 245-process campaign is manual. No CI job or core-mutation selection changes. Production source is unchanged, so this harness-only pass does not requalify modified numerics or require new numerical mutants.

This completes the bounded workload and worker-accounting portion of #119. Actual policy-matrix/tridiagonal/LAPACK crossover, residual scalar allocation decisions, backend adoption/defer evidence and deployment requirements remain open. No new numerical backend or cache is selected. #120 still owns final American integration qualification.

## Reproduction

```sh
opam exec --switch=morphiq-risk-ml -- dune build --profile release bench/american_workloads.exe bench/american_workloads.bc.exe
python3 scripts/test_american_workloads.py _build/default/bench/american_workloads.exe
python3 scripts/test_american_workloads.py _build/default/bench/american_workloads.bc.exe
# Finish task-owned validation before the manual campaign.
python3 scripts/measure_american_workloads.py \
  --binary _build/default/bench/american_workloads.exe \
  --output /tmp/american-workloads-new-run
```
