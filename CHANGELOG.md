# Changelog


Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Numerical changes carry evidence per [docs/stability.md](docs/stability.md).

## [Unreleased]

### American solver and assurance design (#109)

- Define the American solver architecture and estimated-only assurance contract
  for #109, including monotonicity/time-step guards, bounded policy solves,
  tridiagonal backend ownership, frozen refinement/reference acceptance and the
  #116 certification gate. Add reproducible exact-rational design witnesses;
  no American runtime API or existing European numerical behavior changes.

### American/Bermudan contract design (#108)

- Define the planned BSM stopping model, immediate settlement, explicit exercise
  and dividend-event sides, limited-liability cash dividends, piecewise inputs
  and deterministic/negative-rate boundaries.
- Record additive API ownership, distinct estimated/certified outcomes and
  analytical examples in the [design](docs/american-model-contract.md).
  This documentation adds no runtime capability or numerical changes.

### Bounded native Fast planner tiles (#8)

- Batch eligible homogeneous Bachelier scenario rows on ARM64 single-worker
  execution, with invocation-private preparation chunks capped at 256 rows.
  Preserve logical tiles, ordered failures, cancellation and sink boundaries.
- Paired 4,096-position/four-scenario eligible execution improves 24–27% and
  allocates about 9% less; mixed books are essentially unchanged. Fallback-heavy
  serial jobs cost 1–2% more. Multiworker execution retains scalar pricing after
  inconsistent native results. See [complete evidence](docs/results-native-planner.md).
- Preserve numerical gates and exact served words; extend chunk, ownership,
  failure and mutation controls. No SLEEF dependency or certification change.

### Native compiled Bachelier Fast batches (#8)

- Reuse private admitted Bachelier coordinates and pack sufficiently dense,
  bounded OTM batches for an operation-preserving ARM64 kernel. Other models,
  unsupported targets and one-shot `run`/`evaluate` retain scalar execution.
- Preserve selected scalar words and existing accuracy gates; retain independent
  references, foreign-boundary controls, native/bytecode packaging and paired
  performance evidence. Compilation cost and reused throughput are separate.
  See [qualification](docs/results-native-bachelier-batches.md). SLEEF remains
  optional research; certified APIs and release acceptance are unchanged.

### Integrated candidate qualification (#17)

- Retain the exact-source qualification of `f703546`: three-platform package
  installation and native/bytecode consumers, canonical and Exchange replay,
  development/release ordinary CI, and the complete 96-mutant manual campaign.
- Refresh the review handoff and record pending institutional decisions against
  this candidate. Historical approvals/qualifications keep their original scope.
  No runtime, package version, release or deployment decision changes. See
  [the candidate dossier](docs/candidate-fast-optimized.md).

### Fast pricing allocation (#8)

- Keep DD Horner loop words in scalar accumulators and inline the existing
  TwoSum primitive without changing arithmetic order, coefficients or budgets.
  All 86,145 direct DD replay rows match across revisions, profiles and modes;
  independent full suites retain their original requirements.
- Release mixed compiled batch allocation falls 45.7% (1,283 → 697 bytes/price)
  and single-worker scenario allocation falls 36.0% (4,145 → 2,651 bytes/row).
  Paired execution medians improve 7.4%/9.2% on the measured shared M1 Pro.
- Gains depend on native compiler visibility. Development gains are smaller;
  sampled bytecode ITM execution allocates 5.1% more. Four-worker timings do
  not establish a scaling improvement. See [profiles, spread and tradeoffs](docs/results-fast-allocation.md).
- Add release-profile ordinary tests to the existing three-platform CI jobs;
  required check names and the seven-mutant default lane remain unchanged.

### Integrated fast pricing qualification (#98)

- Retain exact scalar equivalence for all 99,088 batch fixture outcomes and
  77,744 planner outcomes whose original maturities fit the civil-day API.
  Nonrepresentable maturities remain explicit; independent reference scoring
  continues separately.
- Add concurrent/reentrant planner reuse, tile-array ownership, sink exception,
  carry-cancellation, overflow and worker-failure cleanup controls. Measure
  bounded output, sampled live heap and allocation across pricing domains.
- Production sources and numerical semantics are unchanged. See
  [integrated qualification and limitations](docs/fast-integration-qualification.md).

### Fast-price scenario streaming (#97)

- Add `Planner.Fast` frozen plans with bounded ordered price streaming and
  explicit row failures. Fast plan/tile/result types remain separate from
  certified outputs; values are unweighted approximate prices, with position
  quantity retained as metadata. No synthetic error radius or aggregate total.
- Share structural validation, date/shock transformation, sink-failure handling
  and the bounded scheduler with the certified planner. Existing certified
  signatures, numerical formulas and replay identities remain unchanged.
- Additive API without a version bump or release. See the
  [contract, ownership and usage](docs/fast-planner.md) and
  [validation, measured costs and host-load limits](docs/results-fast-planner.md).

### Compiled fast price batches (#96)

- Add `Batch.Fast` one-shot and immutable compiled price batches for all four
  European models. Reuse model admission across executions; preserve ordered
  per-item failures and fresh output ownership, including concurrent reuse.
- Fast results are finite nonnegative approximate prices with no runtime error
  certificate. Nonfinite/negative scalar outputs become explicit numerical
  failures. Existing scalar and certified APIs remain unchanged. Coordinate
  and certificate separation are checked by compile-failure witnesses.
- Additive public API; no version bump or release. See the
  [contract and ownership](docs/fast-batch.md) and
  [qualification and measured costs](docs/results-fast-batch.md).

### Packed certification storage (#8)

- Replace boxed enclosure lists/tuples with immutable all-float records and
  private checked buffers; extract normal product exponents without mantissa
  tuples. Retained words, arithmetic order, bounds and acceptance are unchanged.
- Representative certified BSM allocation falls 77.1% (5.71 to 1.31 MB/price)
  and paired elapsed time falls 11.4% (1.005 to 0.890 ms). IV allocation also
  falls 69–72%, with mixed timing including modest regressions. Ordinary fast
  pricing is unchanged; its severe-cancellation enclosure fallback also benefits.
- Stable public APIs remain unchanged. Unstable `Internal.Enclosure.S.t`
  replaces the list-valued `tail` with `third`/`fourth` fields. Exact certificate
  replays, the full ordinary suite and eleven targeted mutations pass.
  [Measurements, compatibility and remaining costs](docs/results-certification-allocation.md).

### Certified expansion sums (#8)

- Use explicitly magnitude-ordered FastTwoSum in runtime enclosure growth,
  with a final residual check enforcing finite arithmetic. Exact residuals,
  retained words, radius propagation and requested accuracy limits are preserved.
- Representative certified BSM price time falls from 1.143 to 1.022 ms (10.6%)
  in paired shared-host measurements. Other measured live scalar prices improve
  10–13%; allocation is essentially unchanged. Exact-rational guards, complete
  certificate replays and nine targeted mutations pass.
  [Derivation, measurements and limits](docs/results-certified-expansion-sums.md).

### Shared Greek intermediates (#8)

- Reuse common smooth-Greek setup and lazily evaluated CDF/derivative terms
  within each multi-output call. Every output retains its own certificate,
  accuracy limit and failure; unrelated expressions remain deferred.
- Public signatures and numerical operation graphs are unchanged. The private
  evaluator is owned by one caller/worker; no cache persists on admissions or
  plans. [Dependency and failure contract](docs/shared-greek-intermediates.md).
- Eleven-output portfolios measure another 1.88× faster execution and 46.3% less
  allocation relative to PR #91. Independent certificates and captured results
  are unchanged. [Full evidence and limits](docs/results-shared-greeks.md).

### Shared certified model preparation (#8)

- Add typed `evaluate_many` operations to each built-in Production model and
  `Batch.evaluate_many` dispatch. Each output keeps its own accuracy limit and
  certificate or error; existing scalar APIs and the `MODEL` signature remain.
- Planner admits and prepares one fixed model per position/scenario row, then
  reuses that immutable preparation across requested outputs. No arithmetic,
  reference, error bound or acceptance threshold changes. Caches remain private
  to one invocation. [Contract and validation](docs/shared-certification.md).
- Eleven-output ordinary portfolios use 46.8% less allocation and measure 1.78×
  faster in paired shared-host runs; one-output timing shows no reliable gain.
  [Measurements and limits](docs/results-shared-certification.md).
- Additive minor API change; no version bump, release or deployment approval.

### Certificate allocation (#8)

- Replace temporary expansion lists with private checked float scratch while
  preserving arithmetic order, retained words and error radii. No public API,
  accuracy limit or numerical method changes.
- Shared-host paired measurements reduce exchange allocation 65–74% and
  evaluation time 14–22%; IV allocation falls 46–52%. Qualified exchange and
  shadow value/radius replays and the public determinism digest are unchanged.
  [Evidence, safety argument and measurement limits](docs/results-certificate-allocation.md).

### Exchange qualification (#61)

- Retain 649 frozen original-word requests: 625 served certificates contain
  both full independent expectation intervals, with 15 explicit numerical or
  accuracy failures and nine invalid controls. All 270 parity pairs and 20
  currency-scaling checks pass; no runtime change or allowance widening.
- Resolve reference precision/serialization and sparse-tail limitations through
  retained, independently bounded payoff formulations. Record three-platform
  artifact/portfolio compatibility, local installed native/bytecode exchange
  replay and loaded-host paired cost/allocation measurements.
  [Dossier and qualification gate status](docs/exchange-qualification.md).

### Certified scalar exchange prices (#60)

- Add `Exchange`: two typed asset legs, abstract correlation, opaque admission
  and private currency price/error certificates with a required absolute limit.
  Expiry and zero covariance retain their exact original-input identities;
  unresolved arithmetic and insufficient accuracy return explicit failures.
- Scale covariance before products and carry total-volatility uncertainty into
  the CDF enclosure. No rounded effective volatility is treated as exact input.
- Additive minor API change; existing values, error variants and portfolio
  behavior are unchanged. No release/tag or version bump is implied. No Greeks,
  inverse parameters or portfolio adapters are included. [Evidence and limits](docs/exchange-prices.md).
  Broader qualification remains #61; this does not expand institutional approval.

### First extension selection (#59)

- Select certified scalar European exchange-option prices as the bounded first
  model extension. Record original-input conventions, degeneracy/failure
  semantics, reference and error-analysis plans, and qualification gates.
  [Selection contract](docs/first-model-extension.md). This is a design decision;
  implementation and qualification remain #60/#61, with existing behavior unchanged.

### Adversarial assurance handoff (#57)

- Retain strict numerical/reference/planner reruns, finding dispositions and
  explicit unresolved/availability outcomes at source `76128fd`.
- Add four independently proved normal-range rho regressions after the full
  mutation run exposed two old guards masked by subnormal refinement. Runtime
  arithmetic, allowances and committed reference fixtures are unchanged.
- Refresh the independent-review package for scalar, Batch, Scenario and Planner,
  with source deltas and theorem/call-site questions. This is engineering evidence,
  not independent human sign-off, institutional acceptance or a release.
  [Campaign adjudication](docs/adversarial-assurance-closeout.md).

### Subnormal BSM rho rounding (#77)

- Refine zero/subnormal/smallest-normal BSM rho proposals from original-input
  enclosures, preserving the one-sided correction at half-subnormal midpoints.
  Unresolved cells return field-specific `Numerical_failure`; proved zeros use
  inexpensive analytical bounds. No accuracy allowance is widened.
- **Major outcome/numerical change** (minor while 0.y.z). Version-1 original-input
  Arb references cover 11,630 requests. Of 480 baseline rounding differences
  (at most two ULP, within the old 16-ULP allowance), 408 become checked values
  and 72 explicit failures; another 72 previously checked values become
  unavailable. Available selected outputs have zero ULP reference error.
- The 66,400-row ordinary Greek trace and public replay digest are unchanged.
  [Derivation, per-row evidence, uncertainty and performance](docs/results-rho-midpoint.md).

### Greek cancellation and zero-variance theta (#80)

- Refuse all fast Black-family Greeks when carry cancellation exhausts DD
  coordinate precision, or a computed zero lacks original-input ATM identity.
  Unresolved smooth-theta component cancellation refuses that field alone.
  These are numerical capability limits, not payoff kinks.
- Preserve cancelling zero-variance theta terms through a DD identity. Among
  1,013 changed public replay words, independent original-input Arb references
  improve the worst error from 13,458,194 ULP to at most 1 ULP. Other replay
  quantities are unchanged; the existing 66,400 Greek oracle rows are unchanged.
- **Major outcome/numerical change** (minor while 0.y.z). The 10,760-request
  challenge changes 437 inaccurate values into 9 checked values and 428 explicit
  failures; 32 wrong classes become failures. Another 738 previously within-budget
  values become unavailable. No accuracy budget was widened.
- The public digest becomes
  `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
  [Derivation, original-input reference provenance, per-row outcomes and timing](docs/results-greek-cancellation.md).

### Severe carry-cancellation price refinement (#76)

- Recompute selected Black-family prices from original-input enclosures when
  carry cancellation exhausts DD coordinate precision. Zero variance uses a
  stable `expm1` identity; an unresolved rounding cell returns NaN.
- The original BSM witness improves from 9,007,199,254,740,994 ULP error to zero.
  On 2,748 independently referenced neighbors, 185 accuracy excursions become
  84 checked values and 101 failures; 21 other formerly within-budget values
  also become failures. All zero-volatility rows remain available.
- **Major numerical/outcome change** (minor while 0.y.z). Existing 99,088 price
  and 66,400 Greek trace rows and the determinism digest are unchanged. No
  accuracy allowance was widened. Ordinary pricing timings are within observed
  variation; the selected fallback is substantially slower.
- The sibling search found inaccurate finite outputs in all ten fast Greeks
  for a tiny-positive-volatility witness; [#80](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/80)
  owns the separate sensitivity correction. This price fix does not resolve it.
- [Method, provenance, compatibility, mutation and timing evidence](docs/results-carry-cancellation.md).

### Planner stress assurance (#56)

- Exercise worker/tile schedules, real-domain failure cleanup, concurrent
  cancellation, sink transactions and checked resource boundaries through
  test-only instrumentation of the exact planner source.
- Retain repeated stress and separate fresh-process memory observations in
  [the campaign report](docs/planner-stress-results.md). Runtime code and public
  APIs are unchanged; finite stress results do not prove race freedom.

### Numerical boundary campaign (#54)

- Add deterministic boundary/scale/cancellation and IV-cell challenges with
  independent rational/Arb references and per-region availability accounting.
- Gate 2,511 smoke requests and scorer controls in ordinary CI; retain a manual
  7,095-request campaign with two fast-API findings (#76, #77), explicit
  uncertainty and no observed contract violations.
- [Evidence and reproduction](docs/numerical-campaign-results.md). Test/tooling
  only; runtime arithmetic and existing numerical allowances are unchanged.

### Oracle assurance (#55)

- Replace six signed-overflow ULP scorers with a shared exact finite-distance
  owner; distinguish numeric budgets from NaN/infinity classifications.
- Verify complete fixture snapshots before scoring; reference-input and worker
  failures cannot become successful comparisons or numerical mutation kills.
- Retain an independently resolved, bounded reduction of the historical false
  precision-agreement witness, including unsuccessful and unresolved attempts.
- [Evidence and reproduction](docs/oracle-assurance.md). Test/tooling change;
  runtime arithmetic, numerical allowances and committed fixtures are unchanged.

### Sound fast Greek outcomes (#62)

- Reject nonfinite results independently in all ten fast Greek fields, including
  zero-variance and expiry paths. `Greeks.Numerical_failure` now covers these
  arithmetic failures; finite acceptance alone remains no accuracy certificate.
- Correct BSM rho when a subnormal maturity underflows before currency scaling:
  two exact-input witnesses improve from 27 ULP error to correctly rounded values,
  against the unchanged 16-ULP gate. A nonfinite intrinsic now propagates NaN
  through the float-returning fast price instead of becoming a false zero; the
  Greek API reports an explicit failure for dependent unresolved values.
- **Major outcome/numerical change** under the stability policy (minor while
  0.y.z): some successful nonfinite/finite-zero results become refusals, and the
  rho correction exceeds its old error budget. No variant or version changes.
- [Derivation and qualification](docs/finite-greek-results.md) retain independent
  exact-input references, per-case changes, fixed allowances, mutation controls,
  package checks and measured overhead. Correctness takes priority over baseline
  compatibility and availability.

### Planner compilation group count

- Remove the per-position full aggregation-map traversal. Count only new keys,
  with a checked limit, preserving duplicate and signed-zero grouping, first
  representatives, plan identities, ordered summaries and numerical outputs.
- Patch-level performance change: 40,000 distinct-group compilation measures
  2.318 s → 116 ms (about 20× faster); homogeneous books remain effectively
  unchanged. The one-output corpus allocates six additional words per position.
- [Qualification and reproduction](docs/results-planner-compilation.md) retain
  boundary/fault controls, full-suite results and sequential repeated timings
  with source/toolchain/host provenance. Long scale campaigns remain manual.

### Inverse-normal operation reuse

- Reuse identical density/square values in inverse refinement and prepare the
  existing DD divisor intermediates for the normal series. Preserve numerical
  operations, error allowances, all reference outputs and both replay digests.
- Patch-level performance change: measured release central/tail inversion takes
  39%/35% less time, LBR proposals 32% less, with 42–48% fewer allocated words.
  Greek batches improve 15–37%; full workflows remain within about ±2% on the
  shared host. The immutable table adds about 34.4 KiB of live heap.
- [Qualification](docs/results-inverse-optimization.md) retains source hashes,
  exact-rational checks, full replay, mutations, installed-package checks and
  repeated timing/startup evidence. No version bump or accuracy-budget change.

### Project-derived inverse normal

- Replace AS241's tables and regional reductions with bounded Gaussian-integral
  inversion and a double-word refinement. Historical attribution/notices remain;
  final current-source provenance and exact-candidate acceptance under #64 remain.
- Minor numerical change: 7,269 of 11,379 inverse outputs change, with no sign
  or classification changes. Central worst error improves 4→0 ULP and tail 6→2,
  within unchanged 4/8-ULP gates. Sampled monotonicity violations improve 3→0.
  The expanded 130,394-row corpus preserves all 128,320 earlier records; two
  independent high-precision formulations support the new inverse evidence.
- All 8,330 fixed-quote IV outputs and measured iteration counts are unchanged;
  the financial replay digest is unchanged. A separate direct-inverse digest
  now covers the complete inverse fixture on each CI platform.
- Direct inverse calls are 24–122× slower in release (about 1.6–4.4 µs in the
  measured regimes); LBR proposals are 5.4× slower. A repeat after reduced host
  activity measures complete workflows +2.9–4.6%; unchanged Bachelier paths
  also move about 4%, so this is not an isolated AS241 regression estimate.
  These costs and allocation increases are explicit tradeoffs; no accuracy
  gate is relaxed.
- [Qualification and reproduction](docs/results-inverse-normal.md) retain
  per-case changes, reference refinements, counts, timings, source provenance
  and limitations. No release or version change is made here.

### Project-generated error functions

- Replace CALERF's implementation and tables with polynomials derived from
  Gaussian integrals, exact-rational generated coefficients and explicit error
  bounds. Preserve historical provenance; AS241 remains open under #64.
- Extend normal references to 128,320 rows, retaining all 82,000 old records.
  Restore Internal erfc subnormal tails and finite negative erfcx near overflow.
  All existing numerical budgets remain unchanged.
- Minor numerical change: 4,810 price records, 1,528 ordinary Greek records,
  76 extra-bit Greek records and 9,354 scalar records change. No financial or
  public-normal sign/class/refusal changes are observed. Combined Black price
  maxima improve OTM 22→10, extreme-scale 18→7 and ITM 8→7 ULP; other price
  regions keep their maxima. Bachelier delta improves 4→3 and Black rho 23→8
  (the forward-rho allowance composes price error). Other Greek maxima stay
  unchanged. CDF body improves 6→3; CDF tail changes 4→5 within budget 6.
  Logcdf improves 5→4. Inverse normal and fixed-quote IV roots are unchanged.
- The [qualification report](docs/results-error-functions.md) retains complete
  regional tables, generator/fixture provenance, 220/440-digit refinement of
  every changed scalar/financial reference row, replay changes and performance.
  After this audit the 6,069,960-byte replay digest becomes
  `e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593`.
  The 741 changed replay IV words arise from changed served input quotes.
  Shared-host release measurements show complete workflows between −2.1% and
  +5.5%; direct CDF is +8.5%, while Internal negative erfcx is 6.3× slower
  because it now uses the qualified DD exponential. Allocation and timing
  limitations are explicit in the report. No release, acceptance signature
  or version bump is implied.

### Independently derived DD exponential

- Replace QD-derived `Dd.exp`/`Dd.expm1` with a direct degree-22 polynomial
  and exact-rational generated coefficients; retain historical provenance
  and notices. AS241 and CALERF remain pending under #64.
- Preserve all error budgets; extend the DD oracle to 86,145 rows. Complete
  ordinary checks pass in development and release profiles; the public
  determinism digest is unchanged.
- Minor numerical change versus the QD baseline: 28 European prices move by
  at most 2 ULP and one near-zero BSM theta by 1 ULP, without observed scalar
  sign/class/refusal changes. Affected Black regions are deep ITM, extreme
  scale, tiny variance and zero variance. Zero-variance worst error is
  1 → 2 ULP (existing budget 4); other regional maxima are unchanged.
  The [current qualification](docs/results-dd-exponential-optimization.md)
  retains per-row precision refinement, regional error tables and fixture
  provenance; the initial degree-24 report remains historical evidence.
- Focused inlining, exact-coefficient specialization and preserving the leading
  reduced argument recover the initial replacement's measured slowdown.
  Release DD calls are 21–30% faster than that candidate on the shared M1 Pro
  host; exp allocation falls from 326 to 81 words/call. ATM/ITM price medians
  return to within about −4% to +3% of QD; complete IV-dominated workflows
  remain within roughly ±2%. Timings are provisional, with both build
  profiles, repeated runs, host load and allocations recorded in the report.
  No release or version bump is made here.

### Numerical-source provenance and replacement planning

- Identify the actual StatLib AS241, Netlib CALERF and author-hosted QD 2.3.24
  sources from the original development record and retained download hashes.
- Replace the mismatched QD GitHub notices with the original tarball's COPYING
  and BSD-LBNL-License document, preserve the StatLib distribution notice, and
  install the corrected notices with the source-provenance report.
- Plan qualified replacements for all three unresolved components under #64.
  Source identification does not establish unrestricted redistribution rights;
  that issue remains open. No numerical operations or served values change.

### Public project documentation and licensing

- Replace the internal-experiment introduction with installation instructions,
  a certified pricing example, current capabilities and explicit limitations.
  Add OCaml-specific contribution guidance and a documentation/evidence index.
- License original contributions under Apache-2.0; preserve third-party notices
  in source and installed documentation. Record the remaining AS241, CALERF,
  and QD provenance questions explicitly in `THIRD_PARTY_NOTICES.md`.
- Retire the original `SLICE.md` proposal to Git history. Remove research PDFs
  from the tracked tree while retaining local copies, original-source links,
  acquisition metadata, and hashes. Historical commits are unchanged.
- No numerical code, API, reference fixture, dependency pin, or served value
  changes. This cleanup does not publish a release or assert distribution
  clearance for unresolved third-party material.

### 0.3.0 — scenario-planner integration (unreleased)

- Add typed scalar-equivalent batches, deterministic paired/Cartesian scenario
  ranges, immutable compile/explain plans, bounded sequential/parallel execution,
  streamed outcomes and enclosure-based weighted aggregation (#20/#21/#24–#26).
- Scenario dates roll forward against fixed expiries with explicit Actual/365
  Fixed or Actual/360 and frozen market inputs. Post-expiry settlement is
  explicitly unsupported; IV batching preserves the existing root contract.
- No scalar pricing operation, formula, tolerance, outcome or reference fixture
  changes. The scalar determinism digest remains unchanged. Planner certificate
  checks use independent Arb price/series derivatives and exact-rational sums.
- This is an unreleased feature candidate, not an accepted
  institutional version. See [the contract](docs/scenario-planner.md).



### 0.2.0 candidate and migration

- Candidate metadata advances to 0.2.0 because the public IV/Greek outcome additions, typed financial boundaries and corrected zero-volatility refusal classes below are breaking changes under the `0.y.z` stability policy. Callers must handle the expanded exhaustive error variants and use the declared volatility/time units. The `Production` API requires explicit accuracy limits and handling of every refusal; admission alone never guarantees an output.
- This version selection changes no numerical algorithm or result word. The replay digest remains `f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b`. Numerical compatibility and reference provenance for the earlier changes remain recorded below and in the linked reports.
- A manual candidate workflow accepts only a full commit already on main, validates all three supported platforms, installs its source artifact into an isolated prefix, tests native/bytecode consumers and retains the full mutation catalog separately from default CI. Artifact identity and installed/package versions are checked; passing this workflow does not publish a release or manufacture an acceptance decision.
- The owner-authorized 720-row canonical portfolio passes 7,920 independent price/Greek certificate checks and 720 IV rounding-cell checks across nine identical repetitions. All material comparator findings, including the initial failed gate and subsequent rho adjudication, are retained in [the report](docs/results-canonical-dataset.md).

### Intrinsic midpoint reference rounding

- Fixed a price-oracle mechanism where two mpmath precisions could agree on the wrong binary64 reference after losing a positive time value at an exact intrinsic midpoint. European/displaced price generation and IV quote construction now use an exact rational, one-sided tail certificate where it resolves rounding. Unresolved rows fail regeneration rather than being dropped.
- All prior fixture rows are unchanged. Added 24 European, eight displaced and 16 IV cases covering the minimized counterexample and sibling models. Library arithmetic, served values, replay and acceptance budgets are unchanged; a production regression checks that an error bound cannot erase the tiny positive increment.
- The independent Arb campaign certifies all 99,088 price and 59,200 smooth-Greek reference cells, plus 5,579 positive IV roots, without unresolved cases. Thirty-two price comparisons use a separately implemented one-sided argument; 7,200 expiry-Greek rows remain explicitly outside analytic series scope. See [derivation and evidence](docs/oracle-midpoint-rounding.md).

### Enforced production numerical boundary

- Added `Production.Bsm`, `Black76`, `Displaced` and `Bachelier` with model-specific admission tokens. Prices and smooth Greeks require explicit typed absolute limits; successful private certificates retain finite values and outward error bounds meeting those limits. No empirical default, unchecked fast fallback or silent failure value is used.
- Added original-input runtime enclosures for all ten smooth derivatives, with BSM/forward rho and time conventions derived explicitly. Expiry/zero-volatility Greeks are explicitly unsupported by this initial adapter. Invalid input, invalid accuracy, unsupported capability, numerical failure and exceeded accuracy remain distinct. Existing fast price/Greek and certified IV behavior is unchanged.
- Public certificate tests cover 4,176 extra-bit references and 3,932 exact acceptance-limit controls; 2,376 interior requests satisfy a fixed test limit. Four negative compiler witnesses enforce certificate/model/unit boundaries. FLINT/Arb formal price-series differentiation independently validates all 2,506 smooth Greek references at 256–2048 bits without unresolved cases.
- This supplies runtime numerical enforcement for #13, not institutional approval. Intended-use/materiality sign-off, independent human review and representative portfolio/operational acceptance remain required under Epic #27. See [the boundary specification](docs/production-boundary-design.md).

### Zero-volatility ATM Greek semantics

- At positive maturity and zero volatility, Black-76/displaced/Bachelier ATM rho and theta are now zero instead of `Payoff_kink`. Their veta exists and is evaluated from the time derivative of right vega. BSM with S=K and r=q has the same theta/veta identity; its rho remains a kink because varying r holds q fixed.
- Newly served boundary veta requires a finite nearest-even runtime enclosure certificate. `Greeks.Numerical_failure` distinguishes unresolved arithmetic/rounding from an undefined derivative. This adds an exhaustive public variant and changes refusal classes: it is a breaking change under the stability policy. Other fast Greeks keep their current assurance scope.
- Replay changes only 350 theta, 270 rho and 350 veta fields from refusal to value; prices, IVs and all previously served Greek values are unchanged. The new digest is `f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b`. FLINT/Arb independently verifies all 532 reference rounding cells.
- The new generator differentiates ATM prices at 400/800 digits and cross-checks the closed form, retaining 532 references including cancellation, exact displaced sums and extreme maturities. The prior positive-maturity Greek corpus skipped zero volatility and therefore did not cover this defect. See [the derivation and compatibility evidence](docs/zero-volatility-greeks.md).

### Adaptive certified implied volatility

- A two-word enclosed attempt precedes the existing four-word evaluator. Both enforce the same exact-input root rounding and boundary certificates; unresolved first attempts retry at full precision. Arithmetic and model code share derived residual/tail identities with immutable configurations and separate scalar types.
- Controlled A/B/B/A measurement reduces certified IV from 4–17 ms to 0.39–1.03 ms on the recorded shared host, with all benchmark outcomes retained. See [performance evidence](docs/performance.md).
- Inlining removes temporary arithmetic boxes, and an exponent-derived product shortcut avoids two frexp allocations without changing its underflow allowance. No acceptance budget or reference fixture changes.
- Both configurations pass independent primitive, elementary and original-input model checks. The full ordinary suite and all 17 affected mutations pass; all 5,575 positive roots and the replay digest are unchanged. Three optional mechanisms bring the catalog to 40; default CI still runs seven. See [adaptive derivations and evidence](docs/adaptive-certification.md).

### Certified public implied volatility

- Positive public IV roots now require a runtime certificate of nearest-even binary64 rounding of the exact-input model's real inverse. The fast inverses supply proposals only. Boundary classifications use original inputs, including both words of displaced sums; unresolved arithmetic returns `Numerical_failure`. See [the derivation](docs/certified-iv.md).
- Runtime arithmetic retains four-word expansions with outward truncation and underflow allowances. Quote-scaled inverse residuals preserve information before tail probabilities underflow. Shewchuk's original paper is archived; executing the unchanged canonical expansion implementation passes 32,009 exact-rational postconditions.
- All 5,575 positive reference roots are correctly rounded. The existing near-maximum regressions, 96 self-consistency cases and recovery property also pass. This establishes exercised availability, not success for every finite input or institutional acceptance.
- FLINT/Arb independently encloses the rounding-cell residual signs for all 5,575 reference roots at 256-bit precision, with no unresolved rows. This strengthens reference validation beyond agreement of two mpmath precisions; it is not independent human review.
- Five former IV mutations survive because certified acceptance repairs proposal changes or makes their historical root-error witness ineffective. They remain explicit probes. The default seven replace `iv-beta-bar` with `certified-rounding-cell`; the curated catalog has 37 mechanisms. The harness runs the full baseline once and each compiled mutant's designated guard, with missing-input/crash controls.
- The replay digest changes to `029a559e0d6360c69c4039b32d1f9123f0c0ae8e2c5811bc2dd4e57fd17b0651`. Across 30,240 model records, 6,272 IV values change; prices, Greeks and outcome categories are unchanged. Earlier IV timing tables below concern the proposal solver and do not describe the new runtime certificate's cost.
- A controlled-order scalar comparison records a material cost increase: about 4–17 ms per certified IV versus 4–8 µs for the proposal-only baseline on the recorded shared M1 Pro host. All 768 benchmark cases succeed in every run. The new monotonic-clock harness retains current-domain allocation, sampled GC and request-latency evidence; this is not production performance acceptance. See [performance evidence](docs/performance.md).

### Runtime model enclosure foundation

- Added internal Black-family and Bachelier price enclosures from original inputs, a derived pi enclosure, a normal integral series with an explicit tail and NIST's bracketing Mills-ratio continued fraction. This is not yet wired into the public inverse or a production acceptance policy.
- Added 1,670 three-word model references, refined at 110/220 digits or 400/800 digits for sparse inputs. The enclosure test also checks all 7,940 existing extra-bit normal rows. A new optional normalization mutant brings the catalog to 39; default CI retains seven core mutants.

### Runtime enclosure foundation

- Added internal finite arithmetic balls with derived residual, underflow and analytic-series remainders for arithmetic, square root, exponential and logarithm. This is infrastructure for runtime decisions; financial integration and production acceptance remain outstanding. Runtime dependencies and pricing results are unchanged.
- Independent exact-rational checks cover 757 deterministic primitive cases and 2,000 generated compositions; 19,058 existing extra-bit elementary references cover the documented domain. Added an optional fused-residual-underflow mutant (38 total); the default core remains seven.

### Financial type boundaries

- Veta now retains both the time unit and volatility coordinate, preventing normal/lognormal veta mixing and accidental use as theta. Added `Units.annualise_volatility` and three compiler-rejection witnesses. This is a breaking public field-type change under the stability policy; its private-float representation and served numerical values are unchanged.
- Documented every public construction/extraction boundary and each Greek's units. Raw unit-label constructors explicitly do not validate values or caller-selected tags. Model admission remains distinct from numerical certification and production-domain enforcement.

### Numerical backend conformance

- Defined the arithmetic, optimization, AD and foreign-backend contract, including separate model, numerical-error and replay obligations. Retained the existing multiplication boundary after a worked contraction assessment.
- Added native and bytecode IEEE witnesses to ordinary CI. No pricing implementation, served value, dependency, compiler choice or default mutation selection changes in this step.

### IV termination and computational failure

- Added `Iv.Non_convergence` and `Iv.Numerical_failure`. This breaks exhaustive caller matches and is a major-class API change (a minor-version increment while at `0.y.z`); no release is tagged here.
- Bachelier no longer returns the last iterate at a cap or accepts a small Newton step alone. Both inverse families check an evaluator match or adjacent-float residual bracket; safeguarded binary64-encoding bisection gives a finite arithmetic termination bound. Nonfinite arithmetic and failed positive-root conversion no longer claim mathematical non-existence.
- Exact-root and recovery scorers now execute analytical price/vega transport certificates alongside unchanged historical quality gates. The certificates are a posteriori test evidence, not runtime error enclosures.
- On the unchanged IV fixture, baseline `7b93c2a` versus this change, worst root errors in ULPs are BSM 4→5, Black-76 4→4, displaced 5→5, and Bachelier 8,992,716,596→6,084,654,728 (subnormal-quote conditioning). All 5,575 root rows pass their existing quality gates and the added certificates. Generators and provenance in `oracle/MANIFEST` are unchanged. See [the audit](docs/iv-termination-audit.md) for scope and remaining blockers.
- Added two optional mutation mechanisms for exhaustion and nonfinite evaluator output (37 total); the default core remains seven. The complement-correction witness is now the independent near-maximum regression.
- The intentional IV changes update the determinism digest to `a7748579580fce931e2b271d66f2822f99f1fa1e737d5738209d3b282b57a5e4`; price and Greek implementations are unchanged.

### PR #12 source and assumption audit

- Default CI now runs seven core numerical mutation checks; the full 35-mutant catalog runs separately on manual dispatch or a weekly schedule. Full accuracy and certification tests remain in ordinary CI. See `docs/mutation-policy.md` for selection and local commands.
- Compared DD algorithms with their original papers and later formalization, and recorded primary source versions and hashes. Corrected the negative-expm1 tail normalization, the scaled exponential's ln(2) split dependency, the erfcx derivative interval and a Greek denominator lower bound. The existing component ceilings still hold.
- Added test-only exact rational primitive witnesses and enforced DD nonoverlap. Regenerated the 48,203-row DD fixture after fixing input normalization at binade boundaries; 22,425 rows retain nonzero low words.
- Fixed DD/split quotient normalization after subnormal low-word scaling, and added the published final Fast2Sum to split square root. The public determinism corpus is byte-for-byte unchanged against 76c3cc5. Two new mutation guards cover normalization, bringing the catalog to 35.
- Pinned transitive generator dependencies and made partial fixture rebuilds preserve unrelated provenance. Missing, duplicate and stale records now fail. These checks do not assert a universal finite-exponent theorem or resolve the outstanding IV convergence obligations.

### Rounded-kernel and Greek certification

- Added exact-rational differential-residual certificates for the rounded Cody erfcx and Jäckel Y′ kernels, integral remainder bounds for both Black expansions, and analytical Normal_dd bounds (200u² relative for density, 512u² absolute for CDF). Operation-by-operation propagation now checks all 99,056 price and 65,980 finite Greek rows independently of the historical measured quality budgets.
- Expanded the component fixture to 48,203 rows (22,425 nonzero low words), added 2,506 three-word Greek references including 51 contracts near Greek zeros, and expanded the mutation catalog to 33. Mutation builds disable replay-identity assertions so numerical mutants must fail their independent numerical guard. The intrinsic-guard probe still survives provisionally.
- Fixed premature Gaussian underflow when a large prefactor rescues the result, normalized extreme split root/quotient inputs, and restored quotient-pair nonoverlap with Fast2Sum. Six historical Bachelier contracts change from false-zero tail prices to positive values within 1–6 ULP of the independent oracle. The public-model digest changes; detailed affected inputs and 4,936 subsequent quotient-normalization differences are recorded in `docs/results-slice.md`. European Black near-ATM worst error improves from 6 to 5 ULP; every other price-region maximum is unchanged in fresh baseline/current runs (`docs/results-slice.md`). All current region quality gates pass. Oracle generators and hashes are pinned in `oracle/MANIFEST`.
- These fixes include served-value/class changes beyond the previous budget: a major numerical change, expressed as a minor release during 0.y.z. No release or version bump is performed here. IV scorers still use their historical conditional kernel envelopes; this work does not claim universal finite-input or finite-iteration certification.

### Initial numerical assurance audit (through 3f5b0db)

- Fixed DD division on subnormal operands (`minsub/(3*minsub)`: 0.5 → correctly rounded 1/3), normalized DD square root, and preserved tiny expm1 arguments before division by 512.
- Fixed early underflow of tiny zero-variance intrinsics. For BSM S=K=2^1000, T=2^-1074, r=1, q=0, σ=0, the call changes from 0 to 2^-74. Tests cover both sides, three scales and three rates. A displaced F=2^-573, K=2^-574, d=2^500 contract also changes from 0 to its exact zero-volatility call value 2^-574. This is a served-value change beyond the published budget: a major numerical change, expressed as a minor release while version 0.y.z. No release/version bump is performed here.
- Replaced the DD 2^-100 measured envelopes with analytical majorants and exact-rational inequality checks. Added 24,451 generated DD cases with nonzero low words and 2,005 direct coordinate/near-maximum IV regressions, pinned in `oracle/MANIFEST`.
- Fixed fail-open NaN scoring, rho's binade-dependent error propagation and log-CDF's reference-rounding/minimum-denominator composition. Missing normal fixtures now fail.
- Removed the price scorer's 4-ULP bypass. Bachelier's norm includes its volatility time value. Its IV scorer now transports price error through vega instead of accepting rounding-cell membership.
- Corrected the log1p derivation to 0.14u|y|; the former 0.085 estimate omitted a denominator rounding and lacked margin.
- Included maximum-leg error divided by the complement gap in the IV budget, replaced the arbitrary threshold guard with normalization uncertainty, and removed the unsupported negligible-Newton-remainder claim. At this checkpoint the kernel/Greek envelopes remained measured premises; `docs/error-analysis.md` lists the remaining proof obligations explicitly.
- Against the unchanged six public-model fixture files, all rows pass and the determinism digest is unchanged from 15b5f7a. New boundary cases expose changes beyond that historical corpus. Fixture generators and hashes are recorded in `oracle/MANIFEST`; this does not claim universal correctness over all admitted inputs.

### Added
- **Deterministic elementary functions** (`Internal.Elementary`: exp, expm1, log, log1p, cbrt) from IEEE basic operations and fma, each within 1 ULP. The library no longer calls the platform libm.
- **A cross-platform determinism digest** (`test/determinism.ml`, docs/determinism.md).
- The public surface is `Morphiq_risk` minus `Internal`. Numerical building blocks moved under `Morphiq_risk.Internal`, outside the stability policy.
- `Morphiq_risk.version`, a stability policy and this changelog.

- **This project's own oracles for every layer** (docs/oracles.md): elementary functions, the normal distribution, European and displaced prices, implied volatility with exact roots and rounding cells, and Greeks by two independent routes. They are committed as fixtures with a SHA-256 manifest (`scripts/manifest.py check`), so the tests no longer depend on downloaded external reference data.
- **Property-based tests** (`test/properties.ml`, QCheck, fixed seed): bounds, parity, monotonicity, Greek signs, exact homogeneity, translation invariance, IV accuracy and finite differences.
- **An error analysis** (docs/error-analysis.md).

### Fixed
- **Platform-dependent rounding.** OCaml's arm64 backend contracted `a +. b *. c` into fused multiply-adds (about 500 in the library), so Linux x86-64 served different bits; CI's new platform matrix found it. Every multiplication in `lib/` is now an explicitly rounded product (`Morphiq_fp`), and fused multiply-adds are explicit `Float.fma`: this project's Horner helper, and the exact remainders. docs/determinism.md, which claimed OCaml never contracts, is corrected. The determinism digest is re-recorded and must match on all three CI platforms.
- **Budgets composed from their inputs:**
  - `logcdf` (from the CDF's budget through 1/(1 − Q) or 1/Φ);
  - forward-model rho: RN(−T·V) bit for bit, within the price error transported through multiplication by T, plus output/reference rounding.

  Each replaced a fixed budget smaller than its input's own, which held only under contraction.

### Changed
- **CI** (`.github/workflows/ci.yml`): the whole suite on Linux x86-64, Linux arm64 and macOS arm64 with locked dependencies and flambda required, the format check, and the mutation catalog.
- **The fixture manifest is checked in OCaml.** `oracle/MANIFEST` records BLAKE2b-256 hashes, and `test/manifest.ml` (part of `dune test`) verifies them with `Digest.BLAKE256`. This replaces `scripts/manifest.py check` and `oracle/MANIFEST.json`.
- **Budgets derived from the error analysis replace measured ones where the mutation catalog depends on them.**
  - **Zero-variance prices:** checked per row against the intrinsic's analytical error budget (§5.1), replacing "4 ULP".
  - **Black-family implied volatility:** checked per root against a derived bound with the better-conditioned of β and β̄ and the intrinsic's error near the money (§6). This replaces "in the rounding cell, or 4× attainable", which accepted roots 8e14 ULP off near the maximum.
  - **log1p's reduced path:** checked against ulp/2 + 0.14·u·|y| using references that now carry their residual (§1).
- **log1p returns x for |x| < 2^-54** (fdlibm). The reduced path rounded log1p(2^-1074) to 0.
- **The mutation catalog** (`dune exec scripts/mutation/mutation.exe`, OCaml): 33 mechanisms, each removed and required to fail the test that guards it, in a temporary copy under a `mutation` dune profile. The quotient remainder now has a direct coordinate oracle. The intrinsic branch guard remains a provisional, explicitly runnable surviving probe (§5.1).
- **Double-double primitives are the published algorithms with proved error bounds** (docs/error-analysis.md §0): Joldes, Muller and Popescu (ACM TOMS 2017) for `mul_float` (Algorithm 9, 2u²), `mul` (Algorithm 12, 5u²), `add_float` (Algorithm 4, 2u²) and `div` (Algorithm 18, 9.8u²), and Lefèvre et al. (ACM TOMS 2023) for `sqrt` (25/8 u²). They replace Algorithms 8 and 10, QD's unproved three-quotient division, and an unproved Newton square root. `add` already was Algorithm 6. `div` now normalizes both operands; normalizing the divisor alone allowed intermediate underflow even for a normal quotient. Worst-case ULP is unchanged in every oracle region; the determinism digest is re-recorded.
- **Double-double exp and expm1 follow QD's `dd_real::exp`** (Hida, Li and Bailey): reduction by 512 and nine doublings instead of a long series. Worst-case ULP is unchanged in every oracle region; `test/dd_reference.ml` pins exp, expm1 and log against mpmath. The determinism digest changes, because low-order bits of intermediates differ.

### Changed (numerical)
- Every libm call now goes through `Internal.Elementary`. Served values move by at most their previous rounding; every worst-case region ULP is unchanged or better (docs/results-*.md).
- **Zero-variance price:** the log-moneyness remainder is now double-double, which fixes a cancellation case: 8 → 1 ULP.
- **Black theta** is now double-double near the money: 17 → 4 ULP (Bachelier: 13 → 3).
- **Expiry theta** `θ(qS − rK)/365` is now formed from exact products: up to 413 → ≤ 7 ULP where S ≈ K.
- **Zero-variance intrinsic** is taken as A − C from the double-double legs when x's parts (|ln S/K| + |(r−q)T|) exceed 1. A forward placed at the strike through carry goes from 13 → 1 ULP.
- **Implied volatility:**
  - m and β come from the double-double legs;
  - a positive quote that underflows on rescaling is no longer inverted to σ = 0;
  - the log-space correction for β < 2^-900 is restored. Removing it was an error, because no oracle row exercised it.
- **Exact homogeneity.** The internal scale exponent uses floor division, so price(2^j S, 2^j K) = 2^j price(S, K) bit for bit.

### Changed (claims)
- **IV accuracy is now stated per contract.** It composes normalization and kernel envelopes, including the maximum-gap error and minimum-vega error transport. The random property composes forward and inverse uncertainty; its former 4× rule is removed. The previous "≤ 2 ULP of the exact root" held on the historical reference grid but not in general; the worst found over random contracts is 4 ULP from a 2-ULP cell.

## [0.1.0] - 2026-10-02

The first slice: the exact European family.

### Added
- **Models:** BSM, Black-76, displaced Black (Black-76 on exact sums F + d, K + d) and Bachelier. Each has prices, implied volatility (explicit outcome classes as `Iv.t`) and ten analytic Greeks with typed units.
- **Normal distribution:** Cody erfcx, `norm_cdf`/`pdf`/`log_cdf`, and AS241 `norm_inv`. A double-double normal distribution for cancelling Greeks.
- **Model contracts** (docs/model-contracts.md).
- **Oracles and evidence:** see docs/results-*.md.

### Numerical evidence (worst ULP per region, against the oracles in docs/results-slice.md)
- Prices: 1–16 ULP per region; Bachelier ≤ 3.
- Implied volatility: Black-family roots ≤ 2 ULP from the exact root; every outcome class matches.
- Greeks: ≤ 6 ULP for every Greek in both families.
