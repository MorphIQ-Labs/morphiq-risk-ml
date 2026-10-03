# Changelog


Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Numerical changes carry evidence per [docs/stability.md](docs/stability.md).

## [Unreleased]

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

- **This project's own oracles for every layer** (docs/oracles.md): elementary functions, the normal distribution, European and displaced prices, implied volatility with exact roots and rounding cells, and Greeks by two independent routes. They are committed as fixtures with a SHA-256 manifest (`scripts/manifest.py check`), so the tests no longer depend on FerroRisk's data. `scripts/ferro_crosscheck.sh` keeps FerroRisk as a second opinion.
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
- **IV accuracy is now stated per contract.** It composes normalization and kernel envelopes, including the maximum-gap error and minimum-vega error transport. The random property composes forward and inverse uncertainty; its former 4× rule is removed. The previous "≤ 2 ULP of the exact root" held on FerroRisk's grid but not in general; the worst found over random contracts is 4 ULP from a 2-ULP cell.

## [0.1.0] - 2026-10-02

The first slice: the exact European family.

### Added
- **Models:** BSM, Black-76, displaced Black (Black-76 on exact sums F + d, K + d) and Bachelier. Each has prices, implied volatility (the #448 outcome classes as `Iv.t`) and ten analytic Greeks with typed units.
- **Normal distribution:** Cody erfcx, `norm_cdf`/`pdf`/`log_cdf`, and AS241 `norm_inv`. A double-double normal distribution for cancelling Greeks.
- **Model contracts** (docs/model-contracts.md).
- **Oracles and evidence:** see docs/results-*.md.

### Numerical evidence (worst ULP per region, against the oracles in docs/results-slice.md)
- Prices: 1–16 ULP per region; Bachelier ≤ 3.
- Implied volatility: Black-family roots ≤ 2 ULP from the exact root; every outcome class matches.
- Greeks: ≤ 6 ULP for every Greek in both families.
