# Experimental exchange-price qualification (#61)

The scalar `Exchange` implementation at
`6226b8a8cb35c765c83c97c02dd58d8d15bcde40` (merged #86) has been exercised
against 649 frozen original-word requests. **All 625 served certificates
contain both complete independent reference intervals and meet their original
currency error limits.** Fifteen requests fail explicitly and nine reject
invalid inputs/accuracy. No runtime operation, requested limit or error allowance
changed during this qualification. The full remote mutation lane is pending;
this report does not yet close the qualification gate.

This is finite experimental engineering evidence, not institutional approval,
a release, a universal numerical proof or independent human review. The
[API contract](exchange-prices.md), [selected model](first-model-extension.md)
and [runtime method](evidence/exchange-implementation/method.md) retain their
capability restrictions. Only scalar prices are included; there are no exchange
Greeks, inverse parameters or portfolio adapters. The previous
[experimental baseline](experimental-baseline.md) and its artifacts are preserved.

## Scope and outcome accounting

The [protocol](evidence/exchange-qualification/protocol.md) and
[cases](evidence/exchange-qualification/cases-v1.json) were committed before
scoring. The corpus preserves all 66 implementation controls and adds reversed
asset pairs, correlation endpoints/neighbors, equal/unequal/negative carry,
zero/equal/unequal volatilities, maturity variation, dyadic currency scaling,
extreme volatility and discount-domain neighbors. The three mandatory ordinary
sentinels and eight exact boundary controls all succeed.

| Outcome | Requests |
| --- | ---: |
| Served; both full independent intervals contained | 625 |
| Numerical failure | 10 |
| Requested accuracy exceeded | 5 |
| Invalid input construction/admission | 7 |
| Invalid accuracy | 2 |
| Unadjudicated served results after refinement | 0 |
| Total | 649 |

The [per-case score](evidence/exchange-qualification/score-final.json) retains
all classifications. All **270 reversal/parity pairs** and **20 exact dyadic
currency-scaling consistency checks** pass; their
[property record](evidence/exchange-qualification/properties.json) is separate
from independent numerical containment. Parity uses an independent Arb interval
for the original-input discounted asset difference. Scaling compares interval
overlap after exact rational dyadic scaling; that consistency alone is not an
accuracy proof. No row is dropped for difficult arithmetic or a reference failure.

## Independent expectation references and findings

The first route computes covariance as an exact rational of original binary64
words, then evaluates the closed form with Arb exp/log/erfc. The second route
rigorously integrates the positive payoff, retaining the uncertain strike strip,
quadrature and Mills tail bounds. Degenerate cases use independent exact
identities or discount intervals. Both routes run at pinned Python 3.14.8,
python-flint 0.9.0 / FLINT 3.6.0, with bounded precision and work as specified
in the protocol. Production functions are never imported into the references.

The broader corpus exposed reference/scoring limitations; these were corrected
without modifying the implementation or increasing runtime allowances:

- The original relative reference goal and 100-digit output were too coarse
  for some prices near exact intrinsic. The initial run retained 39 failed
  containment comparisons and 28 unresolved references. These were not counted
  as runtime bugs or accuracy passes. The refined route targets a*2^-1200 and
  retains 1400 decimal digits with outward uncertainty.
- Asking for unused 2048-bit quadrature precision at 4096-bit arithmetic could
  exhaust the fixed 20,000-evaluation cap. The recorded v2 diagnostic was
  stopped. V3 requests at most 1280 quadrature bits, providing 80 guard bits
  beyond the 1200-bit reference goal; the work cap stays unchanged. Every row
  was rerun under that single generator version.
- For six very large-variance rows, the direct inequality
  `0<=a-C<=(a+b)*exp(-800)/(40*sqrt(2*pi))`, derived by splitting
  `E[min(X,b)]` at Z=40 for s>=80, fits inside the runtime certificate even
  though it misses the deliberately stronger quadrature resolution goal.
  These are explicitly marked direct analytical adjudications with
  `resolution_goal_met=false`, not quadrature precision passes. They include
  the previously unadjudicated `volatility-49` implementation case.
- The remaining intermediate-variance row uses independently integrated
  positive payoff-deficit terms, with an explicit [0,64] truncation bound.
  It meets the original strengthened reference goal and full containment.
- A scorer attempted to materialize an astronomically small Arb tail as a
  rational denominator and aborted. The corrected scorer keeps reference
  exponents in Arb and compares against exact dyadic certificate endpoints at
  4096 bits; those endpoints require at most 2099 bits. Eight failure controls
  verify bad prices, radii, limits, unresolved accounting and this sparse-tail
  path. Tool failure never becomes an accuracy pass.

Original results, the aborted diagnostic, subsequent references and the
adjudication provenance chain are retained. The
[final reference archive](evidence/exchange-qualification/references-final.json.gz)
contains every original case and its final interval; previous unresolved
records remain attached to the supplemented rows. The bound derivations and
resource changes are explicit in the protocol. These are independent
formulations sharing Arb arithmetic, not fully independent arithmetic stacks.

The pinned QuantLib comparator was also run for every case at three common
rates: 1,947 outputs comprise 1,776 finite results, 144 nonfinite results and
27 explicit input/date-mapping exclusions. The
[per-case differences](evidence/exchange-qualification/canonical-comparison.json.gz)
retain its same-date expiry convention and covariance/carry rounding effects.
QuantLib agreement is not certificate acceptance; the original exact model
and independently bounded expectations define that test.

## Artifacts, platforms and compatibility

The manual [candidate workflow](https://github.com/MorphIQ-Labs/morphiq-risk-ml/actions/runs/37215290973)
uses immutable source `6226b8a...`, OCaml 5.3.0 Flambda, the locked dependency
graph and the library's -O3 setting. Ubuntu x86-64, Ubuntu ARM64 and macOS ARM64
all pass source-artifact build/install, native/bytecode public consumers,
ordinary tests and canonical portfolio replay. Their reports are retained as
[Linux x86](evidence/exchange-qualification/artifact-ubuntu-24.04.json),
[Linux ARM](evidence/exchange-qualification/artifact-ubuntu-24.04-arm.json) and
[macOS ARM](evidence/exchange-qualification/artifact-macos-15.json).

All three remote source archives and an independent local archive have SHA-256
`2f17a40c81375b31309facf93498fa86e03010d6662bfac5c7c3cd2db2d0dfe5`.
Installed notices match source bytes. The remote source-bound consumer exercises
the prior Batch/Scenario/Planner contract; supplemental local installed-package
consumers explicitly exercise Exchange in native and bytecode. The 649-case
extended campaign is a local macOS ARM64 observation, not a claim that that
whole corpus ran on every platform. The smaller committed exchange suite runs
on all three supported platforms. Binary artifacts are not claimed reproducible
across platforms.

The qualification harness adds no runtime change: `lib/` remains identical to
the pinned candidate. The full local ordinary suite and format/build pass,
and the old public digest remains
`5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
Default PR CI still selects seven core mutants. The candidate's complete
83-mutant lane is pending; its final receipt is required before closing #61.

## Costs and remaining limits

Seven paired rounds alternate pre-admitted evaluation and end-to-end order on
identical inputs, with 20 warmup calls, 100 evaluations per round and 20,000
admissions. Host load was 6.40/6.80/6.34 on the same Apple M1 Pro/macOS 27.0.
[Raw samples](evidence/exchange-qualification/performance.txt) and
[summary/ranges](evidence/exchange-qualification/performance-summary.json) retain
allocation and timing variability.

| Case | Median evaluation | Median end-to-end | Evaluation allocation |
| --- | ---: | ---: | ---: |
| Ordinary | 1.953 ms | 1.663 ms | 21.4 MB/call |
| Near singular correlation | 0.803 ms | 0.824 ms | 9.68 MB/call |
| Deep OTM | 5.413 ms | 5.528 ms | 63.6 MB/call |
| Discount-domain failure | 41 ns | 50 ns | 353 bytes/call |

Admission is about 6 ns and 56 bytes. End-to-end admission adds 56 allocated
bytes. The ordinary timing inversion demonstrates host/sample variability;
it is not evidence that adding admission makes evaluation faster. These
loaded-host costs do not establish an SLA or speedup. Full expansion allocation
is substantial and remains an optimization opportunity under unchanged
certificate contracts. Certified evaluation already includes certification;
there is no unchecked Exchange evaluator whose separate cost is measured.
Batch/Scenario/Planner costs are inapplicable to this scalar-only extension.

Mathematical admission still does not guarantee availability. Tiny positive
variance, subnormal restoration, discount-domain limits and strict requested
currency errors can cause explicit failures. Finite corpus success does not
prove every admitted covariance, discount cancellation or platform. Human
review and institutional acceptance remain separate open work.
