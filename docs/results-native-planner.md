# Bounded native Fast planner tiles — integration stage 3

Eligible Bachelier scenario jobs now use the operation-preserving native Fast
batch kernel on ARM64 **single-worker** execution. Fresh preparation and packing
are included in the measured gain. Mixed models, small tiles, unsupported targets
and multiworker execution retain scalar evaluation. Direct `evaluate_tile` also
enables native batching. The [contract](fast-planner.md#native-bachelier-tiles)
defines routing and ownership; SLEEF remains optional research.

## Scope and implementation

Homogeneous Bachelier tiles of at least 32 rows are considered for batching.
The original date/shock transformation prepares requests once. A model-owned
rounded hint avoids packing clearly sparse/unselected inputs; it cannot admit a
request or supply native parameters. The existing typed admission, numerical
selector and selected-density checks remain authoritative. Refusals, post-expiry
priority, identities and original indices survive packing and restoration.

Preparation uses at most 256 rows at once. This follows the supported OCaml 5.3
`Max_young_wosize` of 256 and the observed large-array regression below. Most
temporary pointer/result arrays fit that limit; the four-span native SoA may
still use major allocation. Scratch stays bounded independently of the logical
tile; it is not an RSS guarantee. Logical output buffers, waves, cancellation
checks and callback timing retain their caller-selected granularity.

There is no scenario cube, shared mutable scratch, cached shocked price or new
financial approximation. The native arithmetic and source notices are owned by
[stage 2](fast-simd-integration.md#native-fast-batch-boundary). Certified planner
behavior and public signatures remain unchanged.

## Numerical and operational evidence

The full ordinary development and release suites pass, including formatting,
public type rejection, fixture provenance, determinism and collector controls.
The final runtime passes six affected mutations with a clean baseline, successful
mutated builds and designated behavioral witnesses: `native-planner-chunk-offset`,
`native-planner-order`, `fast-planner-tile`, `fast-planner-side`,
`planner-post-expiry` and `planner-snapshot-copy`. The catalog now has 100
mechanisms; default CI still runs its seven reviewed core mutants.

Focused native/bytecode tests compare every row with direct original-input scalar
evaluation. They cover call/put sides, metadata, date rolls, expiry, post-expiry
precedence, negative volatility and forward overflow. Tile sizes straddle
31/32/33 and 256/257/512/513; workers 1/2/4 preserve complete order. Cancellation
and sink-failure prefix checks exercise both serial native and parallel scalar
execution. Concurrent executions and direct-tile array mutation establish fresh
result ownership over the exercised cases. Stress instrumentation still wraps
both direct tile calls and execution's private dispatcher.

The same controls also run against a test-only copy of the actual planner source
with its platform routing gate enabled. This exercises chunk/index restoration
on x86 too, where the public batch owner still chooses scalar pricing. Both new
planner mutations target that copied source through generation; they cannot
silently become dormant on non-ARM64 full-catalog CI. The copy is not installed
and does not change public dispatch or claim SIMD execution on x86.

Both installed native public consumers replay all **49,152** benchmark outcomes
exactly across revisions, with full per-configuration checks across tile/worker
choices. Installed bytecode consumers replay the same 49,152 outcomes exactly.
The latter uses a custom runtime for the benchmark clock; ordinary bytecode
tests separately exercise dynamic stub loading. These are local ARM64 results;
the PR's Ubuntu x86-64, Ubuntu ARM64 and macOS CI are separate portability gates.

Independent references use the Gaussian-expectation formula from exact original
binary64 inputs, refined at 100 and 200 decimal digits with mpmath 1.3.0.
All **36,864 Bachelier rows**, including duplicate-input multiplicity and original
order, remain in the reference file: 144 unique tuples, zero unresolved rows.
Other models' 12,288 rows retain scalar/ordinary-fixture evidence and are not
counted as newly refined Bachelier references. The complete input SHA-256 is
`b72a71acfd4cbaa933fd80e1f9fc0bdf18fb537503d637d029b2e11f0d73cdf3`;
reference SHA-256 is
`2144871139dc77a81afc5dab44ee4c40aa1e576227d78478bd226b011047d91e`.

Every Bachelier reference passes existing 8-ULP / 4.3-epsilon scaled requirements;
the largest observed scalar error is 5 ULP and 0.0294 epsilon-scaled units.
All 24,576 selected native rows pass the same independent gates and match scalar
words exactly. Public selected-batch results are scored as well as the private
native scalar/SIMD controls. Replay proves sampled compatibility; precision
agreement and these observations are not universal numerical proofs. External
reference mode does not certify provenance: the retained generator metadata,
original-input dump and hashes establish the campaign's source chain.

## Final paired measurements

Baseline: `1055ff7e5c745d165a2e48a70adc01a57e5cd3b9` (stage 2), library tree
`093611b1e78261c5d96a4da90ae80b18eac7cc3e`.
Final measured runtime: `20d927b342bd53315e2f374033bee34447238b07`, library tree
`d1e40d7d20b1a5c9cb5294afe68492271d3fa0e3`.
Later test additions explicitly exercise native cancellation/concurrent reuse
and direct-tile ownership; documentation and evidence do not change this runtime.

Apple M1 Pro, ten cores, macOS 27 ARM64; OCaml 5.3.0 Flambda, release library
and identical installed public consumer at `-O3`, Apple Clang 21. Four time
scenarios (days 0/7/30/90), a fixed eligible/mixed/fallback-heavy corpus, and a
minimal ordered sink. Eligible inputs vary side and standardized distance;
mixed inputs contain all four European models; one quarter of fallback-heavy
inputs are eligible. All task-owned builds, tests and profilers finished before
timing. Source guards check staged, unstaged and untracked changes and binary
hashes before, throughout and after collection.

Eight fresh processes alternate revisions in A/B/B/A/B/A/A/B order, reverse
configuration order, warm up, and retain all **3,600** timing samples.
The one-minute host load ranged **24.0–46.3**: this remains a shared machine.
Values below are median-of-four-process-medians. Per-output numbers are amortized
cost, not latency of a single pricing request. Each job has four times as many
outputs as positions.

| Serial workload | Positions | Logical tile | Before ns/output | After ns/output | Before bytes/output | After bytes/output |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Eligible | 32 | 32 | 208.3 | 157.1 | 1298.6 | 1196.4 |
| Eligible | 256 | 256 | 208.0 | 151.6 | 1289.3 | 1171.6 |
| Eligible | 4096 | 256 | 209.8 | 153.0 | 1289.1 | 1171.3 |
| Eligible | 4096 | 1024 | 236.6 | 180.3 | 1288.3 | 1178.6 |
| Mixed | 4096 | 256 | 1575.3 | 1573.2 | 2605.1 | 2605.2 |
| Mixed | 4096 | 1024 | 1594.1 | 1590.4 | 2604.3 | 2604.3 |
| Fallback-heavy | 4096 | 256 | 333.8 | 341.7 | 1305.1 | 1329.8 |
| Fallback-heavy | 4096 | 1024 | 363.1 | 366.6 | 1304.3 | 1337.1 |

For 4,096 eligible positions/tile 256, reused complete execution falls
**3.438 → 2.506 ms (27.1%)**; compile-plus-execute falls **9.508 → 8.610 ms (9.4%)**.
Execution process medians span 3.419–3.444 ms before and 2.505–2.519 ms after.
This includes fresh numerical preparation for all 16,384 outputs; planner
compilation freezes structure, not these future admissions. Mean first-output
time falls 52 → 38 microseconds. At tile 1024 it falls 212 → 166 microseconds.
These are sample means, not tail/cancellation guarantees.

Mixed serial execution is essentially unchanged. Fallback-heavy large jobs cost
1.0–2.4% more time and 1.9–2.5% more allocation from the extra routing/entry work.
The full summary retains all sizes, compilation phases and first-output costs.
Allocation counters cover the **coordinating domain only**; with one worker this
includes all evaluation, but across multiple workers it excludes worker bodies.

## Superseded designs and parallel limits

All three timing campaigns are retained separately, not pooled. The initial
whole-tile implementation improved eligible tile-256 serial work but regressed
at tile 1024 (about 28% serial and 167% with four workers); fallback-heavy serial
tile-1024 work also regressed about 74%. This motivated bounded preparation and
the cheap eligibility hint. These were performance findings, not numerical
failures.

The bounded implementation at `5225af6` improved larger eligible serial jobs
23–27%, with essentially unchanged mixed/fallback-heavy serial time. Parallel
eligible jobs still regressed: about 25%/54% at tile 256 with two/four workers,
and about 99% at tile 1024 with four workers. Automatic native planner dispatch
therefore remains restricted to actual `workers:1`.

The final scalar parallel controls remain noisy: eligible four-worker medians
move about −18%, while fallback-heavy two/four-worker tile-256 medians move
+37%/+21%, despite retaining scalar evaluation and unchanged coordinator
allocation. These samples do not establish causality or a parallel improvement.
No repeated campaign is discarded because it is slower. A controlled target-host
comparison, representative books/sinks and a separate allocation/GC investigation
are required before adopting native preparation in parallel execution. The
existing worker/tile tuning guidance remains applicable.

## Disposition and reproduction

Adopt this bounded serial planner route on the temporary integration branch
after all five CI checks pass, then propose the combined three stages to main.
Keep SLEEF and automatic parallel native planner execution deferred under #8.
Do not transfer the historical `f703546` candidate's approval to this runtime;
target-host acceptance, independent review and release qualification remain
separate. No version, digest, tolerance or certified-output contract changes.

[Retained evidence](evidence/native-planner/README.md) includes raw samples,
superseded results, failed setup logs, references, installed consumer reports,
full source/toolchain identifiers and reproduction commands.
