# Compiled fast batch measurements (#96)

`Batch.Fast` supplies a typed reusable admission boundary around the existing
fast scalar price kernels. [The contract](fast-batch.md) specifies frozen inputs,
plain approximate prices, per-item failures and concurrent ownership. This is
an additive API; existing fast and certified functions are unchanged.

Implementation revision: `ac98eadd3f703a6ec90752c40e19cb52e2a7bb6c`, based on
PR #94 merge `b1a0fa170f41a2c3f045691f9fbca6d345774938`. Subsequent changes retain
this evidence. [Raw results](evidence/fast-batch/README.md) bind sources,
binary, toolchain, inputs and outcomes.

## Throughput and allocation

Apple M1 Pro, macOS 27, OCaml 5.3.0 Flambda, Dune default profile with library
`-O3`. All task-owned tests/builds/profilers completed before timing. Other host
activity remained; recorded one-minute load was about 12.5. Five fresh processes
provide twenty-five batch means per size/phase, with three warmups, five samples
and `max(1,8192/n)` iterations per sample. Full major GC runs outside timing.
The phase order is fixed, not randomized; CPU and full ranges are retained.

The deterministic corpus mixes all four models, both sides and varying strikes
at one-year maturity. These per-item averages are not BSM-specific latency or
individual request percentiles. Pricing outcomes are checked exactly against
direct scalar calls outside timing; every measured request succeeds. Failure,
expiry and severe-cancellation correctness is covered separately by fixtures
and controls, not silently mixed into this ordinary-throughput claim.

| Batch size | Direct scalar admission + price, µs/item | Fast one-shot, µs/item | Compile, µs/item | Compiled execute, µs/item | Manually pre-admitted scalar, µs/item | Pack + compile + execute + extract, µs/item |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 32 | 1.879 | 1.870 | 0.934 | 0.938 | 0.940 | 1.919 |
| 256 | 1.871 | 1.873 | 1.064 | 0.930 | 0.935 | 2.068 |
| 1024 | 1.879 | 1.879 | 1.107 | 0.952 | 0.950 | 2.090 |

Compiled execution removes roughly half the repeated admission-plus-price
cost, matching manually pre-admitted scalar dispatch within these spreads.
There is no demonstrated faster numerical kernel or automatic cross-item
sharing. Compilation plus one execution costs more than one-shot evaluation;
using the median costs, it pays back by the second execution for each size.
This crossover applies to this frozen ordinary workload, not every model/regime.
Request construction and output extraction must still be counted in applications.

| Batch size | Compile allocated bytes/item | Execute allocated bytes/item | One-shot allocated bytes/item | Full request allocated bytes/item |
| --- | ---: | ---: | ---: | ---: |
| 32 | 6410.3 | 5787.3 | 12189.3 | 12298.0 |
| 256 | 6406.2 | 5647.1 | 12045.3 | 12153.4 |
| 1024 | 6405.9 | 5737.2 | 12135.0 | 12243.0 |

Allocation is measured through current-domain `Gc.counters` (minor + major -
promoted words, eight bytes/word). These are cumulative temporary allocations,
not retained plan size or RSS. The private plan stores O(n) admitted entries;
every execution creates a fresh result array. Full-request timing includes
request construction, admission, execution and extraction to a float array.
Pre-admitted scalar dispatch uses one closure per item prepared outside timing;
compiled dispatch uses the typed internal model variants. Both retain identical
numerical kernels and finite-output checks.

## Validation

- Public build/install, formatting and the complete ordinary suite pass.
- All 99,088 retained European/displaced price fixture rows match direct scalar
  result words/classes in one-shot and compiled execution. Existing independent
  price-oracle scoring runs separately in the ordinary suite; scalar agreement
  alone is not an independent accuracy proof.
- Native and bytecode controls check all four models, original-index failures,
  exact expiry payoff, overflowing admitted payoff refusal, empty input, source
  array isolation, result mutation isolation and concurrent immutable replay.
- Two compile-failure witnesses reject normal volatility in a BSM request and
  using a fast float result as a `Production.certified` value.
- Both targeted compiled mutations are killed after a clean baseline: accepting
  nonfinite prices and reversing compiled output order. Optional catalog: 92;
  default CI: seven reviewed mechanisms.
- Public numerical digest remains
  `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
- The immutable implementation source artifact installs and passes native and
  bytecode external consumers, including all four Fast models, fresh result
  ownership and existing certified Batch/Planner/Exchange checks. Ten installed
  notices match. Both installed Exchange consumers retain all 649 outcomes.

## Remaining integration

#97 owns bounded price-only fast scenario streaming with separate result and
manifest types; it will not fabricate certified aggregate bounds. #98 owns
integrated platform/workload qualification. The present API is a flat immutable
batch and has no scenario scheduler, Greeks, IV or approximate aggregation.
Three-platform ordinary CI is required before landing. Performance is measured
only on this shared M1 Pro. No version bump, release/tag or institutional
acceptance is implied by this additive feature.
