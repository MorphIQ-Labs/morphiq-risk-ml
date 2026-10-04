# Inverse-normal replacement qualification

Baseline: `42eb6d1245509927152d204598d1e553fb4b127c` (PR #68, CALERF
replacement). This is a separate stacked stage of #64. AS241's inverse tables,
regional reductions and operation graph are removed from `lib/normal.ml`.
The [construction](inverse-normal-replacement.md) derives a bounded Gaussian
inversion with six safeguarded iterations and a double-word correction over
the existing CDF component's supported domain. No third-party inverse
coefficient set is substituted. Historical attribution and notices remain;
this is not a clean-room claim, historical permission grant or release clearance.

## Numerical compatibility

The normal corpus grows from 128,320 to **130,394** rows, retaining every old
input/reference record exactly. All 2,074 new rows are inverse probabilities:
new switches, neighbors of 1/2, the first 128 positive subnormals, the final
128 values below one, forward-polynomial transitions and the |x|=6 correction
boundary. Generator, dependency and compressed-fixture hashes are in
`oracle/MANIFEST`; mpmath remains pinned at 1.3.0.

| Existing gate region | Rows | AS241 max ULP | Replacement max ULP | Unchanged gate | Changed outputs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Central, abs(p−1/2)<=0.425 | 6,030 | 4 | 0 | 4 | 3,768 |
| Tail | 5,349 | 6 | 2 | 8 | 3,501 |

The central-region label belongs to the existing accuracy gate; it is not the
new implementation's p=1/4 and 3/4 split. The [per-case comparison](evidence/inverse-normal-compatibility-changes.json.gz)
retains all **7,269** changes, with movement at most 5 ULP. The
[summary](evidence/inverse-normal-compatibility.json) records no sign or result-class
changes and no changes to any of the 119,015 non-inverse normal records.
Endpoint/domain behavior is retained, including +0 at p=1/2, infinities at
0 and 1, and NaN for invalid probabilities. The smallest positive probability
and largest probability below one remain finite.

The generator solves a high-precision log-tail equation. An independent check
uses `sqrt(2)*erfinv(2p-1)` at 160 and 320 decimal digits **plus** the decimal
exponent of the smaller tail, preserving that subtraction even for 2^-1074.
The [11,249-input refinement](evidence/inverse-normal-refined.json.gz) and
[130 correction-boundary refinements](evidence/inverse-normal-boundary-refined.json.gz)
retain every reference, before/after output and signed fractional-ULP error.
Both precision levels must recover the fixture's rounded word; fractional errors
must agree within 10^-12 ULP. No unresolved row may count as passing.
This is independent-formulation, precision-refined numerical evidence, not
interval certification of mpmath or a proof of universal correct rounding.

On these 11,379 sorted inputs, AS241 has three monotonicity reversals and the
replacement has none. The initial scalar-only replacement had two one-ULP
reversals near p=0.24 and 0.25 despite passing the ULP gates. The final
correction covers the entire existing Normal_dd domain, not just those inputs;
130 additional rows straddle its boundary. The ordinary oracle now checks
sampled inverse monotonicity. No global monotonicity claim is established.
The rational [bound checker](../oracle/inverse_normal_bounds.py) covers the
coarse iteration/correction analysis separately from the empirical 4/8-ULP gates.

This is a **minor numerical change** under [stability](stability.md).
There is no version bump or release in this change. The financial replay
remains `e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593`
over 6,069,960 bytes. A new direct inverse replay checks
`91bedc0a4352538aa60ae7c831f27bcaf16be0058a45daa3d6c33f2501344c19`
over 193,443 bytes, guarding all 11,379 inverse outputs in fixture order.
Both profiles match these digests; three-platform CI must also pass.

## IV consumers

An isolated diagnostic copy instruments the three LBR iteration exits and
certified-IV step/call counters. It preserves original arithmetic and prints
the result of every ordinary fixed-quote IV case. The instrumentation is
absent from the shipped library and timed benchmarks. Its source hashes,
complete output trace and scorer results are retained
[before](evidence/inverse-iterations-before.json.gz) and
[after](evidence/inverse-iterations-after.json.gz).

All **8,330 output rows are identical**, including classifications/refusals and
root words. All 5,579 independently referenced positive roots pass their
original exact-root/certificate checks. Instrumented process totals are identical:

| Counter | Before | After |
| --- | ---: | ---: |
| Calls through LBR's iterative branches | 4,540 | 4,540 |
| LBR Householder steps | 9,068 | 9,068 |
| Certified solver calls, including adaptive attempts | 8,948 | 8,948 |
| Certified solver steps | 4,373 | 4,373 |

These counts describe this fixed-quote corpus, not every admitted option.
Price and Greek arithmetic is unchanged; their ordinary reference checks and
the shared financial replay pass. Existing diagnostic enclosure rows that
cannot be certified remain explicitly unresolved in the validation log.

## Performance and cost

The [raw paired campaign](evidence/inverse-normal-benchmark.json) records an
Apple M1 Pro, macOS 27.0, OCaml 5.3.0 Flambda, library/benchmarks at -O3.
Identical harnesses use 20,000 primitive/proposal inputs, one warm-up and nine
batches; three alternating AB/BA/AB comparisons run in separate sequential
processes. Development and release profiles are both measured. The release
application harness uses 64 contracts per model/regime and seven timed batches.
Allocations, GC, batch spread, source/harness hashes and host loads are retained.
All 768 application IV outcomes are roots in every run.

All task-owned builds, checks, diagnostics and reference refinements finished
before the final campaign. LBR inputs have positive quotes below their finite
maximum; total volatility is at least abs(log-moneyness)/8, avoiding a quote
that has underflowed to zero outside the proposal's stated domain. Other work
on the shared host continued; 1-minute load at run starts ranged from
8.15 to 17.58. Timings are provisional.

Release primitive medians, ns/call (median of three run medians):

| Operation | AS241 | Replacement | Ratio | Allocated words, before→after |
| --- | ---: | ---: | ---: | ---: |
| inverse_central | 25.4 | 2,662.0 | 104.8× | 6.0→835.6 |
| inverse_tail | 37.0 | 4,271.9 | 115.4× | 12.3→1,493.1 |
| inverse_extreme | 64.0 | 1,558.7 | 24.4× | 27.9→412.5 |
| lbr_proposal | 854.8 | 4,405.9 | 5.2× | 318.1→1,699.6 |

Direct inverse normal is **substantially slower**, especially in the central
and ordinary-tail regimes where the double-word correction runs. This is a
structural cost, also visible in allocations. Development ratios are 135×
central, 149× ordinary tail, 25× extreme tail and 6.2× LBR proposal. A caller
whose workload is direct normal inversion must account for this regression.
The new six-step solver establishes a qualified reference construction;
reproducibly generated inverse approximations are a separate optimization
opportunity under the replacement plan, with fresh bounds and qualification.

Release application medians, ns/call:

| Model / regime | IV, before→after | IV change | Complete workflow, before→after | Workflow change |
| --- | ---: | ---: | ---: | ---: |
| bsm / atm | 694,141→691,547 | -0.4% | 716,125→702,609 | -1.9% |
| bsm / itm | 515,078→521,094 | +1.2% | 533,391→542,469 | +1.7% |
| bsm / otm | 1,065,625→1,069,219 | +0.3% | 1,078,437→1,080,703 | +0.2% |
| black76 / atm | 623,047→623,078 | +0.0% | 636,328→636,016 | -0.0% |
| black76 / itm | 541,891→544,000 | +0.4% | 554,391→561,266 | +1.2% |
| black76 / otm | 1,183,281→1,060,359 | -10.4% | 1,813,547→1,078,359 | -40.5% |
| displaced / atm | 668,938→663,859 | -0.8% | 678,453→673,297 | -0.8% |
| displaced / itm | 533,281→540,906 | +1.4% | 555,172→556,172 | +0.2% |
| displaced / otm | 1,084,875→1,077,438 | -0.7% | 1,083,516→1,092,016 | +0.8% |
| bachelier / atm | 508,844→515,516 | +1.3% | 516,312→516,203 | -0.0% |
| bachelier / itm | 405,609→446,687 | +10.1% | 413,437→414,156 | +0.2% |
| bachelier / otm | 608,859→611,797 | +0.5% | 620,391→675,250 | +8.8% |

Complete workflows range from -40.5% to +8.8%; IV alone ranges from -10.4% to
+10.1%. These ranges are too noisy to quantify an end-to-end regression. These
workflows are dominated by certified root acceptance. Changes in
unchanged price/Greek/admission timings demonstrate shared-host variation;
this campaign does not establish a dedicated-host regression bound or throughput
guarantee. The Black-76 OTM baseline has run medians of 1.07, 1.81 and
1.94 ms while the replacement spans 1.07–1.24 ms, explaining the apparent
40.5% speedup as a contention warning, not an optimization result. The large direct-inverse/proposal cost remains explicit regardless
of the application timing variation.

## Repeat after reduced host activity

The maintainer reported that the machine was quieter and requested another
measurement. The [repeat campaign](evidence/inverse-normal-benchmark-repeat.json.gz)
uses the **same binaries, arithmetic source hashes, harness hashes and inputs**.
All task-owned computation had finished; no optimization was made. It retains
three AB/BA/AB pairs in both profiles, batch spreads, allocations and outcomes.
All 768 application IV outcomes remain roots in every run. One-minute load at
run starts ranges from 7.77 to 9.81, versus 8.15–17.58 in the preceding campaign.
This remains a shared workstation rather than a dedicated benchmark host.

Release primitive medians, ns/call:

| Operation | AS241 | Replacement | Ratio |
| --- | ---: | ---: | ---: |
| inverse_central | 25.1 | 2,712.8 | 108.3× |
| inverse_tail | 35.8 | 4,379.7 | 122.2× |
| inverse_extreme | 64.3 | 1,571.2 | 24.4× |
| lbr_proposal | 839.2 | 4,502.1 | 5.4× |

Release complete workflows, ns/call. Parentheses show the minimum and maximum
of the three process-level medians, not per-request latency percentiles:

| Model / regime | Before: median (range) | After: median (range) | Median change |
| --- | ---: | ---: | ---: |
| bsm / atm | 690,250 (688,641–711,906) | 711,531 (699,016–717,562) | +3.1% |
| bsm / itm | 521,875 (521,328–524,078) | 539,750 (523,641–551,125) | +3.4% |
| bsm / otm | 1,061,359 (1,054,750–1,083,812) | 1,092,406 (1,059,547–1,099,484) | +2.9% |
| black76 / atm | 624,078 (620,750–626,922) | 645,453 (641,688–732,984) | +3.4% |
| black76 / itm | 545,906 (544,875–554,578) | 570,781 (566,875–582,062) | +4.6% |
| black76 / otm | 1,052,297 (1,049,828–1,058,719) | 1,097,125 (1,082,828–1,140,938) | +4.3% |
| displaced / atm | 665,547 (663,438–671,828) | 690,375 (682,547–694,969) | +3.7% |
| displaced / itm | 541,813 (540,062–544,812) | 559,734 (558,875–570,047) | +3.3% |
| displaced / otm | 1,067,547 (1,067,328–1,068,359) | 1,110,266 (1,108,563–1,111,094) | +4.0% |
| bachelier / atm | 509,531 (506,016–527,219) | 527,844 (520,078–532,625) | +3.6% |
| bachelier / itm | 405,875 (404,875–417,391) | 421,563 (417,109–423,187) | +3.9% |
| bachelier / otm | 605,516 (603,875–618,234) | 630,359 (623,766–646,891) | +4.1% |

Complete workflow medians now range from **+2.9% to +4.6%**, with the large
contention spikes absent. The direct-inverse and LBR costs remain substantial
and consistent with the preceding campaign. However, Bachelier does not call
`Normal.norm_inv`, and its unchanged workflow also moves by about 4%; unchanged
price/Greek/admission paths move too. The full workflow difference therefore
cannot all be attributed to replacing AS241. This is a more consistent shared-
host comparison, not an isolated causal estimate or a regression upper bound.
Both campaigns are retained; the post-merge optimization round will report
standalone and application costs separately against this qualified baseline.

## Validation and disposition

The [validation log](evidence/inverse-normal-validation.txt) records passing
full ordinary suites in development and release, package builds and format.
The [two affected mutations](evidence/inverse-normal-mutations.log) both build
and are rejected by numerical witnesses after a clean mutation-profile baseline:
too few iterations fails the inverse oracle; removing the double-word correction
fails sampled monotonicity. A replay mismatch is not used as a mutation kill.
The seven core CI selections are unchanged; the optional full catalog has 58.

An isolated installed package is checked with native and bytecode consumers,
including endpoint/domain behavior and the complete inverse replay. Installed
notices and documentation are compared byte-for-byte with the source;
[the installation record](evidence/inverse-normal-install.json) retains evidence.
The [source scan](evidence/inverse-normal-source-audit.json) finds no former
AS241 module reference or any of its 45 distinct long coefficient literals in
tracked OCaml/Python/C sources. That scan is supporting provenance evidence,
not a legal opinion or a claim to detect every possible adaptation.

The maintainer requested a separate performance round **after this replacement
lands**. Track that work in [#8](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/8):
profile the correction and allocations, remove redundant work first, and assess
project-generated inverse approximations only with fresh derivation and
qualification. Preserve this replacement as the before/after reference.

Retain for PR review, dependent on PR #68 and required CI. #64 remains open for
integration, final current-source/artifact provenance review and qualification
of the exact main-branch candidate. No merge, tag, release or operational
acceptance is implied.

Reproduction (two prepared worktrees, identical benchmark harnesses):

```sh
python3 oracle/inverse_normal_bounds.py
opam exec --switch=morphiq-risk-ml -- dune build -j 2 @install @fmt @runtest
opam exec --switch=morphiq-risk-ml -- dune build -j 2 --profile release --build-dir _build-release @install @runtest
# Collect normal traces with MORPHIQ_ORACLE_TRACE using test/oracle_normal.exe.
python3 scripts/compare_exponential_traces.py --normal-only BEFORE_PREFIX AFTER_PREFIX COMPARISON
oracle/.venv/bin/python scripts/qualify_inverse_normal.py --before BEFORE-normal.tsv --after AFTER-normal.tsv --output REFINED.json.gz
python3 scripts/measure_inverse_iterations.py --root BASELINE --output BEFORE-IV.json.gz
python3 scripts/measure_inverse_iterations.py --root . --output AFTER-IV.json.gz
# Build the inverse_normal and assurance benchmarks in both profiles/trees first.
# Quiesce task-owned computation before timing.
python3 scripts/benchmark_inverse_normal.py --baseline BASELINE --replacement . --output BENCH.json
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- inverse-iteration-count inverse-dd-refinement
```
