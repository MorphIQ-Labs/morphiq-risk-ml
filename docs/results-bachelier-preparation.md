# Shared Bachelier preparation — integration stage 1

The internal batch preparation now consumes Bachelier's admitted distance,
discount and square-root words. Admission computes its pure square root once
instead of twice. The optional experiment no longer admits, discards and
recomputes those coordinates. This stage introduces no public native backend
and changes no numerical gate, price operation graph or public API operation.
See the [integration contract](fast-simd-integration.md).

## Correctness and controls

The development and release ordinary suites, package build and format checks
passed on the local ARM64 host. The three affected mutations were killed by
their designated independent witnesses: `split-root-scale` by `dd_reference`,
`quotient-remainder` by `numerical_regressions`, and `bachelier-distance` by
`oracle_price`. Each mutated build succeeded; replay mismatch was not a kill.
New tests cover 466 selected existing fixture rows, gate boundaries, immutable
concurrent preparation and compile-time rejection of forged/private parameters.

The complete 110,632-row experiment trace is byte-for-byte identical to PR #121's
retained final trace. That includes all five paths, 8,220 selected rows, 102,412
fallback rows and five failure outcomes. Operation-preserving paths remain exact
matches, with worst rounded-reference distance 7 ULP and normwise error
0.547689 epsilon times scale, inside the unchanged 8-ULP / 4.3-epsilon gates.
The optional SLEEF path retains exactly its previous changed rows and remains
deferred. References, source inputs and refinement limitations are described in
the [original report](results-fast-simd.md).

The paired collector completed 7,200 samples across eight fresh processes,
alternating source revisions and backend order. Its 18 control groups exercise
startup, malformed/truncated output, partial failures, timeout kill/reap,
changed source, differing inputs and complete sample coverage. Source guards
include staged, unstaged and untracked changes and executable hashes.

## Local performance evidence

Measured baseline: `bd55133f0483aa7c4660307b3987e1621f1221fd` (PR #121 head).
Measured candidate: `852821bfd566c430f096fde8ddf486a7ab708ba2`.
The corresponding library trees are `0da7e7fda5ef50b4bd7696580829fd9a3adea598`
and `10b92a9c2a56bbfa68754cf7ec7be59dfec003ec`.
Both use OCaml 5.3.0 Flambda, release builds with library `-O3`, Apple Clang 21,
the same external SLEEF 3.6.1 and Apple M1 Pro (10 cores), macOS 27 ARM64.
The C arithmetic flags and warm-up/sample protocol are unchanged from #121.

Task-owned builds, tests and profilers finished before timing. Nevertheless,
the shared host's recorded one-minute load was about 189–213, far above its
core count. **These timings are provisional engineering observations, not
quiet-host qualification or a deployment performance guarantee.** All process
samples, including slower runs, are retained. Allocation changes are useful
evidence independent of interpreting small timing differences.

For 4,096 outputs, each value below is amortized per output; it is not a
single-request latency. Time is the median of four process medians per revision.

| Workload/path | Phase | Before ns | After ns | Before bytes | After bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| Eligible public Fast | Compile | 131.5 | 126.9 | 517.7 | 445.7 |
| Eligible public Fast | Execute | 115.1 | 113.2 | 480.0 | 480.0 |
| Eligible public Fast | One-shot | 194.8 | 179.8 | 989.7 | 917.7 |
| Eligible prototype SIMD | Compile | 252.3 | 124.2 | 1074.4 | 709.8 |
| Eligible prototype SIMD | Execute | 15.1 | 15.0 | 48.0 | 48.0 |
| Eligible prototype SIMD | One-shot | 276.4 | 146.5 | 1122.4 | 757.8 |
| Mixed prototype SIMD | One-shot | 1749.1 | 1721.4 | 2389.2 | 2302.1 |
| Fallback-heavy prototype SIMD | One-shot | 475.7 | 394.7 | 1796.7 | 1390.1 |

The eligible prototype's repeated-execution work is unchanged. Preparation
reuse removes 72 bytes per public Bachelier admission and about 365 bytes per
eligible prototype compilation. At size 32 the prototype one-shot observation
falls from 174.7 to 108.0 ns/output; at size one it falls from 265.8 to 209.8 ns,
still slower than public Fast at 175.9 ns. Fallback-heavy prototype one-shot
execution still loses to public Fast (394.7 versus 208.7 ns/output at size 4,096).
These costs support keeping explicit small/sparse fallback policies in the next
stage; they do not justify routing every request through native packing.

## Reproduction and disposition

The [retained evidence](evidence/bachelier-preparation/README.md) includes all
samples, validation traces, build/test/mutation logs, hashes and toolchain data.
Build each clean revision using the [experiment commands](../experiments/fast_simd/README.md),
then run the candidate's collector with separate existing roots and binaries:

```sh
python3 experiments/fast_simd/compare.py \
  BASE_ROOT BASE_BINARY CANDIDATE_ROOT CANDIDATE_BINARY NEW_OUTPUT_DIRECTORY
```

This stage is suitable for review on the temporary integration branch. Native
Fast-batch ownership/packaging/platform checks and planner end-to-end evidence
remain separate stages. Changed runtime code has no transferred release or
independent-review approval; deployment acceptance remains pending.
