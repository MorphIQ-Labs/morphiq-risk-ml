# Error-function replacement qualification

Baseline: `d799144fa2783185f038b1f9730a23863173804b` (merged PR #67).
This replaces the CALERF implementation and all of its stored tables with
[project-derived polynomials](error-function-replacement.md), without changing
published budgets or the public API. `Cody` remains an Internal module name.
AS241 is unchanged and remains the next stage of #64. Historical source notices
and unresolved historical terms remain explicit; this is not a clean-room claim.

## Construction and independent references

The coefficient generator uses exact fractions, Gaussian integrals, positive
moment ratios and the erfcx differential equation. Every coefficient has a
rational rounding witness. Local anchors retain a generated low word.
The largest derived positive-erfcx relative bound is 3.144418u, below the
unchanged 40u ceiling. Small erf is bounded by 3.366957u, below 26u.

The expanded normal oracle has 128,320 rows, including all 82,000 original
records unchanged. New rows exercise direct erf/erfc and representable neighbors
of all new cuts, negative overflow and positive erfc underflow. References use
mpmath 1.3.0 at 80/160 digits with escalation; large erfcx uses Tricomi U.
The original financial/DD fixtures are unchanged. `oracle/MANIFEST` pins the
transitive generators and fixture bytes. These independent evaluations and
rational checks establish different evidence, not universal certification.

## Fixed-reference output comparison

| Fixture | Rows | Changed result records |
| --- | ---: | ---: |
| dd | 86,145 | 835 |
| displaced | 41,768 | 2,504 |
| european | 57,320 | 2,306 |
| greek_bits | 2,506 | 76 |
| greeks | 66,400 | 1,528 |
| normal | 128,320 | 9,354 |

There are no observed financial sign, outcome-class or refusal changes on these
fixed-reference corpora. Normal-function public outputs likewise keep their
classes. Internal erfc restores 111 nonzero tails previously flushed to zero;
Internal erfcx restores seven finite outputs previously infinite. The old
implementation fails 102 direct-erfc and eight erfcx expanded checks (110 total);
zero/nonzero changes within a few subnormal quanta are not all ULP-gate failures.
The replacement passes every expanded check. Sampled monotonicity has zero
violations for cdf, erf, erfc and erfcx across the expanded ordered corpus;
this is sampled evidence, not a whole-domain monotonicity proof.

The following tables combine European/displaced prices and ordinary/extra-bit
Greek regions. Worst errors use rounded scalar references; extra-bit Greek
references are scored separately by their existing analytical certificates.
Forward-model rho uses the price-composed absolute allowance, not the displayed
ordinary 16-ULP BSM-rho budget. Positive logcdf uses its existing composition
bound; its nominal 4-ULP label applies to the non-composed path.

| Changed region | Worst before, ULP | Worst after, ULP | Largest output movement, ULP |
| --- | ---: | ---: | ---: |
| bachelier delta | 4 | 3 | 4 |
| bachelier price deep_itm | 2 | 2 | 1 |
| bachelier price itm | 3 | 3 | 1 |
| bachelier price otm | 5 | 5 | 2 |
| bachelier rho | 4 | 4 | 1 |
| black charm | 4 | 4 | 1 |
| black delta | 6 | 6 | 4 |
| black price deep_itm | 2 | 2 | 2 |
| black price extreme_scale | 18 | 7 | 15 |
| black price itm | 8 | 7 | 7 |
| black price near_atm_tiny_variance | 6 | 6 | 2 |
| black price otm | 22 | 10 | 28 |
| black rho | 23 | 8 | 17 |
| black theta | 8 | 8 | 3 |
| normal cdf body | 6 | 3 | 5 |
| normal cdf tail | 4 | 5 | 3 |
| normal logcdf | 5 | 4 | 5 |

Scalar erf improves 3→1 ULP; erfc is now at most 4 ULP and erfcx at most 2.
Unchanged regions, including inverse normal and all fixed-quote IV roots,
retain their original results. The full Greek corpus has 65,980 finite
certificate checks, 13,625 below-binary64 outcomes and 420 payoff-kink refusals.
The 2,506 extra-bit Greek references pass their existing bounds.

The first, uncompensated local polynomial failed one cancelling BSM theta:
18 ULP against an 8-ULP budget. The generated leading-coefficient residual
reduces that witness to 4 ULP; the full Black-theta maximum remains 8.
The initial failure, exact input and corrected score are retained in evidence.
No tolerance or input-specific branch was introduced.

## Replay and compatibility disposition

The [fixture comparison](evidence/error-functions-compatibility.json) and
[changed records](evidence/error-functions-compatibility-changes.json.gz) retain
exact inputs/references and both results. All 15,768 changed scalar/financial
rows have [220/440-digit refinement](evidence/error-functions-refined.json.gz),
with input-dependent additional precision; every committed reference is
confirmed: 10,260 changed rows move closer to the real reference and 5,508
move farther away, all within their unchanged gates. Each changed Greek also agrees with independent price differentiation.
DD/component records are covered by their ordinary extra-bit certificate checks.
The raw baseline/final scoreboards and failed/corrected theta witness are
retained as `docs/evidence/error-functions-*.log`.

The [public replay comparison](evidence/error-functions-replay.json) has
30,240 model records and 5,723 changed words, with no class/refusal/sign changes.
[Changed words](evidence/error-functions-replay-changes.json.gz) retain record
indices in `test/determinism.ml` order. Maximum price movements are 14 ULP
BSM, 16 displaced and 2 Bachelier; Greek movements are at most 6 except
forward rho (16). There are 741 changed IV words, at most 12 ULP; each solver
receives its implementation's changed served quote. This is not a fixed-quote
IV regression. All 8,330 ordinary fixed-quote IV outcomes still pass, including
5,579 correctly rounded positive roots. Replay equality is a compatibility
check, not an independent accuracy oracle.

**Compatibility classification:** minor numerical change under the existing
stability policy on the qualified corpora. Fixed-input public movements remain
within their regional/composed allowances; no public type/model/failure rule
changes. Internal tail class corrections are documented separately. No version
bump or release is performed. The intentional digest changes from
`f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b` to
`e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593`,
still over 6,069,960 bytes, after the reference and replay audits.

## Performance and validation

Apple M1 Pro, macOS 27.0, OCaml 5.3.0 Flambda, library/benchmark `-O3`.
Development uses the `-opaque` boundary; release permits cross-module
optimization. The [raw paired record](evidence/error-functions-bench.json)
pins harness and implementation source hashes, both profiles, within-run
spreads, host load, allocations and all application outcomes. Both working
trees report the baseline Git head because measurements preceded this commit;
the individual file hashes identify the actual sources.

Three AB/BA/AB rounds ran sequentially after all task-owned builds, tests and
refinements completed. Primitive runs warm up and measure nine batches of
20,000 inputs. Application runs use 64 contracts per model/regime, seven warm
batches and separate request-latency samples. Primitive timing uses the existing
wall-clock style; application timing uses its monotonic harness. CPU time,
GC and allocations are retained. All 768 IV outcomes are `root` in every run.
The machine remained shared; timing differences are provisional.

Load-average ranges (1/5/15 minutes): 4.17–5.62, 16.68–19.75, 32.02–34.24.

Release primitive medians in ns/call (median of three run medians):

| Function | CALERF | Replacement | Change | Allocated words, before→after |
| --- | ---: | ---: | ---: | ---: |
| erfcx_small | 45.6 | 28.4 | -37.7% | 18.1→4.0 |
| erfcx_middle | 19.5 | 27.8 | +42.4% | 4.0→4.0 |
| erfcx_tail | 17.6 | 22.3 | +26.6% | 4.0→4.0 |
| erfcx_negative | 83.0 | 523.6 | +530.8% | 36.2→93.0 |
| erf | 81.8 | 70.1 | -14.3% | 36.0→28.4 |
| erfc | 78.6 | 66.8 | -15.0% | 35.7→27.6 |
| cdf | 66.1 | 71.8 | +8.5% | 35.4→35.3 |

The middle/tail erfcx polynomial costs about 8/5 ns more per call; direct CDF
costs about 6 ns more. Small erfcx, erf and erfc are faster in this campaign.
Negative erfcx is a deliberate cost increase: about 6.3× slower in release,
using the qualified DD exponential for the exact square and overflow boundary.
Its allocation rises from 36.2 to 93.0 words/call. That Internal path is not the
nonnegative erfcx path used by the Gaussian tails. Development shows the same
positive-path direction (CDF +10.4%, middle erfcx +40.8%); negative erfcx is
8.3× slower and allocates 587.2 words with the cross-module boundary.

Release application medians, ns/call (CALERF→replacement):

| Model / regime | Price | Greeks | Complete workflow | Workflow change |
| --- | ---: | ---: | ---: | ---: |
| bsm / atm | 937→937 | 8,391→8,156 | 677,531→693,063 | +2.3% |
| bsm / itm | 1,391→1,406 | 13,984→14,094 | 535,063→524,078 | -2.1% |
| bsm / otm | 187→187 | 10,641→10,625 | 1,053,219→1,054,563 | +0.1% |
| black76 / atm | 937→891 | 8,406→8,344 | 605,781→624,750 | +3.1% |
| black76 / itm | 1,438→1,375 | 13,969→13,922 | 559,984→548,469 | -2.1% |
| black76 / otm | 187→187 | 10,750→10,906 | 1,043,234→1,059,125 | +1.5% |
| displaced / atm | 922→922 | 8,422→8,328 | 632,813→667,609 | +5.5% |
| displaced / itm | 1,391→1,391 | 13,984→13,969 | 548,156→544,672 | -0.6% |
| displaced / otm | 187→188 | 10,859→10,906 | 1,058,719→1,068,563 | +0.9% |
| bachelier / atm | 406→375 | 5,266→5,422 | 515,516→509,547 | -1.2% |
| bachelier / itm | 609→625 | 8,984→9,188 | 403,266→408,437 | +1.3% |
| bachelier / otm | 94→109 | 7,437→7,422 | 601,828→605,703 | +0.6% |

Complete workflows range from −2.1% to +5.5%. They are dominated by certified
IV work. Admission also moves despite unchanged admission code, and the tiny
Bachelier OTM price moves by one timing quantum (94→109 ns); these illustrate
measurement noise. This campaign does not establish a dedicated-host throughput
regression or guarantee. It does expose the structural negative-erfcx allocation
cost. Further changes to that reconstruction or polynomial evaluation require
separate numerical/performance qualification.

## Validation and decision

The complete ordinary suite passes in development and release profiles with
the same new replay digest. Build/install and formatting pass. The
[validation log](evidence/error-functions-validation.txt) retains commands and
results, including the existing unresolved diagnostic enclosure rows; those
rows are not promoted to certified outputs. All seven affected mutations are
[killed](evidence/error-functions-mutations.log) after a clean baseline and
successful mutated builds: leading residual, local degree, tail degree, erf
degree, erfc square split, Gaussian square split and scaled exponential prefactor.
The seven core CI mechanisms remain unchanged; the full optional catalog is 56.
An isolated installation passes native and bytecode consumer checks, including
new error-function paths; their output words agree. All 18 installed document,
license and notice files match their source bytes. The
[installation record](evidence/error-functions-install.json) retains the consumer
source, outputs and installed document hashes.

Retain this implementation for PR review, subject to the required five checks
including three-platform replay equality. AS241, final release provenance audit
and candidate-specific acceptance remain outstanding. No numerical gate is
relaxed, and no merge or release is implied by this report.

Reproduce against prepared baseline/replacement worktrees with identical
benchmark harnesses:

```sh
python3 oracle/erf_coefficients.py --check
python3 oracle/erf_certificates.py
opam exec --switch=morphiq-risk-ml -- dune build -j 2 @install @fmt @runtest bench/error_functions.exe bench/assurance.exe
opam exec --switch=morphiq-risk-ml -- dune build -j 2 --profile release --build-dir _build-release @install @runtest bench/error_functions.exe bench/assurance.exe
# Build both baseline benchmark profiles; stop task-owned computation before timing.
python3 scripts/benchmark_error_functions.py --baseline BASELINE --replacement . --output BENCH.json
# Scorers emit aligned traces when MORPHIQ_ORACLE_TRACE is set.
python3 scripts/compare_exponential_traces.py --normal BEFORE_PREFIX AFTER_PREFIX COMPARISON
oracle/.venv/bin/python scripts/audit_error_function_changes.py --changes COMPARISON-changes.json.gz --output REFINED.json.gz
# determinism.exe accepts an optional second argument for its raw replay dump.
python3 scripts/compare_error_function_replay.py BEFORE_REPLAY AFTER_REPLAY REPLAY_COMPARISON
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- erfcx-leading-residual erfcx-local-degree erfcx-tail-degree erf-series-degree erfc-square-split gaussian-split scaled-exp-prefactor
```
