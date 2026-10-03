# Focused DD exponential optimization

Date: 2026-10-03. Partial implementation of [#64](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/64), in [PR #67](https://github.com/MorphIQ-Labs/morphiq-risk-ml/pull/67).

The focused pass recovers the initial replacement's release-build slowdown on
the measured host and reduces temporary allocation. It also reduces the worst
observed Black zero-variance price error from 3 to 2 ULP. This remains a minor
numerical change: the original QD baseline's worst error in that region was
1 ULP. No accuracy budget, fixture, model, API or failure convention is relaxed.

## Candidate and derivation

The initial degree-24 candidate is `a186cb251aceee06c536d47fe67b406ee1eba218`;
its [historical qualification](results-dd-exponential.md) and evidence remain.
The original QD comparison uses `3260a56217a2270005f12717bc9a15e4a016d48f`,
subsequently squash-merged in the audit as `e9591b29bb5d75e5bd90c110308a2c6557bbff39`.
The [benchmark record](evidence/dd-exponential-optimization-bench.json) pins
all three `lib/dd.ml` SHA-256 values; the optimized source was measured before
commit, so its recorded Git head is the initial candidate, not its source identity.

Three changes are retained:

1. Inline the Fast2Sum/product-residual helpers and selected DD Horner calls so
   Flambda can eliminate temporary records. The separately rounded multiplication
   boundary and explicit FMA remain. Global helper inlining also benefits other
   DD callers; both development and release profiles receive full validation.
2. Reduce the directly evaluated polynomial from degree 24 to 22, using the same
   exact-rational factorial coefficient generator. This is justified analytically
   before scoring, rather than by fitting an observed error envelope.
3. Evaluate `r + r² * (1/2 + r * (1/3! + ... + r/22!))`. The leading input `r`
   is preserved; the exactly representable coefficient `1/2` uses DD-plus-float
   addition. The reduced helper needs 22 DD multiplies, 20 DD additions and one
   DD-plus-float addition, versus 24 multiplies and 23 DD additions initially.

For |r| < R = 0.347, the same conservative coefficient-weighted rounding
argument counts at most k multiply roundings and k additions for the r^k term,
including the separately rounded square and tail product. The full omitted
Taylor tail contributes
`R^22 / (23! (1−R/24) (1−R) u²)` in relative-u² units. The checked combined
majorant is **19.875907520 u² < 80 u²**. The published expm1 budget remains
80 u² and exp remains (40+3|x|)u². The tiny-input branch, range reduction,
finite-exponent scaling and additive subnormal allowances are unchanged.
See the [normative derivation](error-analysis.md#12-double-word-exp-and-expm1)
and exact-rational checks in `oracle/verify_bounds.py`.

The [probe ledger](evidence/dd-exponential-optimization-probes.json) preserves
source patches, screening timings and decisions. Straight-line loop unrolling
was slower and rejected. Forced cross-module inlining of `Split.two_sum` failed
with the development profile's `-opaque` boundary; this is a rejected build,
not numerical evidence, and no warning was disabled. A degree-24 specialization
passed all DD and European price rows with identical outputs to the initial
candidate. Shortening that factored version to degree 22 changed DD low words
but no European prices. The retained leading-r grouping improves the observed
zero-variance maximum. These screens are separate from final qualification.

The replacement remains independently derived after examining the previous
implementation, with no clean-room claim. Historical QD evidence and notices
remain. AS241 and CALERF are unchanged and still outstanding under #64.

## Numerical compatibility

All 86,145 DD rows (47,719 nonzero low words), 99,088 European/displaced prices,
66,400 ordinary Greek rows and 2,506 extra-bit Greek references were traced.
Fixture bytes and generators are unchanged from the initial replacement; its
report retains their hashes. The DD worst fractions of the unchanged bounds
remain exp 0.718825 and expm1 0.282185. The exp maximum includes underflow
allowances and is not a pure relative-error estimate.

The [final-versus-QD summary](evidence/dd-exponential-final.json) and
[compressed changed rows](evidence/dd-exponential-final-changes.json.gz) retain
exact inputs, references and both outputs. The separate
[optimization comparison](evidence/dd-exponential-optimization.json) and
[changed rows](evidence/dd-exponential-optimization-changes.json.gz) compare
against the initial degree-24 replacement.

| Corpus | Rows | Changed vs original QD | Largest scalar movement vs QD | Changed vs initial replacement |
| --- | ---: | ---: | ---: | ---: |
| dd | 86,145 | 37,190 | two-word changes | 12,859 |
| european | 57,320 | 28 | 2 ULP | 24 |
| displaced | 41,768 | 0 | 0 ULP | 0 |
| greeks | 66,400 | 0 | 0 ULP | 0 |
| greek_bits | 2,506 | 1 | 1 ULP | 0 |

There are no observed scalar sign, class or refusal changes. Relative to QD,
28 prices change in Black deep-ITM, extreme-scale, tiny-variance and zero-variance
regions, and one near-zero BSM theta changes by 1 ULP. All 29 served changes have
[220/440-digit refinement](evidence/dd-exponential-final-refined.json), with
additional input-dependent precision; theta also agrees with independent price
differentiation. The 24 price changes relative to the initial replacement are
at most 1 ULP and have their own [refinement record](evidence/dd-exponential-optimization-refined.json).
Every committed reference is confirmed. Agreement between implementations is
not used as the accuracy oracle.

Per-region worst price error, combining European and displaced fixtures:

| Family / region | Original QD ULP | Initial replacement ULP | Optimized ULP |
| --- | ---: | ---: | ---: |
| bachelier price deep_itm | 2 | 2 | 2 |
| bachelier price itm | 3 | 3 | 3 |
| bachelier price near_atm_tiny_variance | 2 | 2 | 2 |
| bachelier price otm | 5 | 5 | 5 |
| bachelier price zero_variance | 0 | 0 | 0 |
| black price deep_itm | 2 | 2 | 2 |
| black price extreme_scale | 18 | 18 | 18 |
| black price itm | 8 | 8 | 8 |
| black price near_atm_tiny_variance | 6 | 6 | 6 |
| black price otm | 22 | 22 | 22 |
| black price zero_variance | 1 | 3 | 2 |

The zero-variance budget is still 4 ULP; its worst excess beyond final rounding
is 0.000912 of the analytical error allowance, versus 0.00182 initially.
All ordinary Greek regional maxima are unchanged; the extra-bit Greek worst
certificate fraction stays 0.95761. The full IV checks continue to pass their
exact-model acceptance requirements. The public determinism digest remains
`f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b`
over 6,069,960 bytes in both development and release builds. That corpus does
not contain every changed oracle row.

**Compatibility classification:** minor numerical change under the existing
stability policy. No version bump or release is performed.

## Performance and host limits

Apple M1 Pro, macOS 27.0, OCaml 5.3.0 Flambda; library and benchmark use `-O3`.
Development builds also use Dune's `-opaque` boundary; release builds permit
cross-module optimization. The earlier report used development builds. Its
allocation and timing figures must not be compared directly to release results.
The new campaign measures both profiles against identical harness sources.

`scripts/benchmark_dd_optimization.py` runs three rotating implementation orders,
sequentially, after all task-owned tests and builds finish. Each primitive run
has a warm-up and nine batches of 20,000 fixed inputs; each application run has
64 contracts per model/regime, a first batch, seven warm batches and separate
request-latency samples. Raw data retain within-run minimum/maximum, CPU time,
allocation, GC counters, request latencies, outcomes and start/end load averages.
Primitive timing uses the existing wall clock; application timing uses the
existing monotonic harness. No dedicated-host or cross-platform speed guarantee
is inferred. Short admission/price timings are quantized and susceptible to noise.

Recorded load-average ranges (1/5/15 minutes): 2.62–3.46, 8.77–11.14, 23.06–25.59. The machine remained a shared host with other work.

Release primitive time below is the median of the three run medians; brackets
show the range of those run medians, in ns/call. All individual batch spreads
remain in the [raw record](evidence/dd-exponential-optimization-bench.json).

| Function | Original QD ns | Initial replacement ns | Optimized ns | Change vs initial |
| --- | ---: | ---: | ---: | ---: |
| exp_reduced | 490.9 [486.2–492.6] | 608.4 [606.5–615.8] | 425.6 [425.2–433.8] | -30.0% |
| exp_wide | 487.6 [487.4–497.7] | 615.8 [609.5–618.5] | 434.9 [427.8–439.4] | -29.4% |
| expm1_reduced | 446.9 [446.3–450.7] | 587.4 [574.2–588.4] | 423.5 [421.6–428.4] | -27.9% |
| expm1_wide | 496.9 [491.1–502.3] | 619.6 [618.1–625.1] | 488.3 [486.8–493.2] | -21.2% |

Release DD calls are 21–30% faster than the initial replacement and 2–13%
faster than QD in this campaign. Allocation is the stronger structural result:

| Function | Original QD words/call | Initial words/call | Optimized words/call |
| --- | ---: | ---: | ---: |
| exp_reduced | 316.2 | 326.0 | 81.0 |
| exp_wide | 316.2 | 326.0 | 81.0 |
| expm1_reduced | 299.2 | 309.0 | 69.0 |
| expm1_wide | 319.2 | 329.0 | 84.0 |

`exp` allocation falls about 75% relative to the initial release candidate.
The development profile improves by 13–19% against the initial candidate;
relative to QD its medians range from about 2% faster to 6% slower. In particular,
development reduced `expm1` remains about 6% slower. This pass does not claim
uniform speed superiority for every build profile or input distribution.

Release application medians, ns/call (same model/regime fixtures in all runs):

| Model / regime | Price QD / initial / optimized | Greeks QD / initial / optimized | Complete workflow QD / initial / optimized |
| --- | ---: | ---: | ---: |
| bsm / atm | 937 / 1,219 / 953 | 8,891 / 10,500 / 8,219 | 667,766 / 680,328 / 668,875 |
| bsm / itm | 1,422 / 1,781 / 1,359 | 15,687 / 17,984 / 13,750 | 527,531 / 542,500 / 525,734 |
| bsm / otm | 188 / 187 / 187 | 12,875 / 13,297 / 10,594 | 1,040,422 / 1,058,547 / 1,040,469 |
| black76 / atm | 953 / 1,203 / 922 | 8,812 / 10,438 / 8,516 | 596,359 / 604,344 / 599,469 |
| black76 / itm | 1,406 / 1,781 / 1,438 | 15,594 / 17,797 / 13,609 | 551,891 / 555,672 / 552,766 |
| black76 / otm | 187 / 187 / 187 | 12,844 / 13,391 / 10,844 | 1,030,391 / 1,036,969 / 1,031,031 |
| displaced / atm | 953 / 1,203 / 937 | 8,766 / 10,719 / 8,141 | 624,953 / 625,859 / 637,281 |
| displaced / itm | 1,422 / 1,781 / 1,391 | 16,187 / 17,312 / 14,109 | 547,687 / 551,188 / 542,063 |
| displaced / otm | 187 / 188 / 187 | 12,531 / 13,328 / 10,937 | 1,043,859 / 1,052,531 / 1,056,531 |
| bachelier / atm | 406 / 469 / 391 | 5,766 / 6,516 / 5,188 | 510,234 / 510,469 / 505,437 |
| bachelier / itm | 578 / 734 / 594 | 10,094 / 11,359 / 8,812 | 399,859 / 402,719 / 395,500 |
| bachelier / otm | 94 / 109 / 94 | 8,922 / 9,141 / 7,422 | 601,859 / 597,844 / 591,234 |

ATM/ITM price medians improve 17–24% versus the initial replacement and sit
between 4.4% faster and 2.8% slower than QD. Greek batches improve 18–24%
versus the initial replacement and 3–18% versus QD. Admission, IV and complete
workflows are measured separately in the raw record; no admission speedup is
claimed. Certified IV dominates the complete workflows: their medians stay
within roughly −2% to +2% of QD (−3.1% to +1.8% versus the initial candidate).
All 768 benchmark contract IV outcomes are `root` in every run. This is local
comparative evidence, not production performance acceptance.

## Qualification and decision

The complete ordinary suite passes in both development and release profiles,
including fixed-budget references, exact primitive/replay checks, runtime
acceptance, type rejection, fixture provenance and determinism. Build/install
and formatting pass. Existing unresolved diagnostic enclosure rows remain
explicit; they are not promoted to certified results. See the
[validation log](evidence/dd-exponential-optimization-validation.txt).

All three affected local mutations (`expm1-tiny`, `dd-exp-degree` and
`dd-scale-nonoverlap`) are killed after a clean baseline and successful
mutated builds, by failure of the independent designated guard. The seven
core CI mutants and optional full-catalog policy remain unchanged.

**Decision:** retain this focused optimization for PR review, subject to its
required three-platform CI. It improves observed cancellation accuracy and
allocation without weakening the derived contract; additional numerical
reassociation or degree reduction would need a separate derivation and
qualification. AS241/CALERF replacement and release acceptance remain separate
work. The current and historical reports and original third-party notices are
included in the installed documentation.

Reproduce against prepared worktrees with identical fixture/harness sources:

```sh
opam exec --switch=morphiq-risk-ml -- dune build -j 2 @install @fmt @runtest bench/dd_exponential.exe bench/assurance.exe
opam exec --switch=morphiq-risk-ml -- dune build --profile release --build-dir _build-release -j 2 @install @runtest bench/dd_exponential.exe bench/assurance.exe
# Build both benchmark profiles in the original and initial worktrees too.
# Wait for all task-owned builds/tests before timing.
python3 scripts/benchmark_dd_optimization.py --original ORIGINAL --initial INITIAL --optimized . --output RESULTS.json
python3 scripts/compare_exponential_traces.py BEFORE_TRACE_PREFIX AFTER_TRACE_PREFIX COMPARISON_PREFIX
oracle/.venv/bin/python scripts/audit_exponential_changes.py --changes COMPARISON_PREFIX-changes.json.gz --output REFINED.json
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- expm1-tiny dd-exp-degree dd-scale-nonoverlap
```
