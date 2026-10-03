# Replacement plan for unresolved numerical-source rights

Decision: 2026-10-03, maintainer selected replacements with clear provenance
instead of permission outreach. Owner: [#64](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/64),
under Epic #47. See the [source audit](source-provenance.md).

This records the staged plan, not a claim of legal clearance. Stage 1 now
has a [DD exponential implementation and qualification report](results-dd-exponential-optimization.md).
AS241 and CALERF remain unchanged pending their own acceptance criteria. Do not rename functions, rearrange an adapted operation graph, or
recite a paper citation and describe that as a new provenance chain. Since the
existing sources have been inspected, do not claim a clean-room process.

## Common requirements

- Start from mathematical definitions and explicitly documented derivations.
  Generate any new approximation coefficients from those definitions with
  versioned generators, pinned tool dependencies and precision-refinement checks.
  Do not reuse AS241/CALERF coefficient tables or QD's implementation structure.
- Record every consulted implementation and its exact license/version before
  copying any code. An independently written generator is preferred; using a
  permissively licensed library is an alternative requiring its own provenance
  review, not an automatic clearance based on the name of its license.
- Fix domains, error budgets, failure behavior and performance measurements
  before scoring. Preserve typed APIs, exact-model quantities, explicit FMA and
  separately rounded multiplication. No host-libm or fast-math substitution.
- Use precision-refined mpmath and independent analytical certificates as
  correctness references. The existing kernels provide a compatibility baseline,
  not ground truth. Never weaken a bound or omit a failing region to get green.
- Publish derivations, generators, fixtures and validation evidence with the
  project. Preserve acquired reference material and rights records privately.

## 1. Replace the QD-derived double-word exponential

Implement `Dd.exp` and `Dd.expm1` from a documented range-reduction and series
derivation. A concrete first candidate uses reduction to a bounded interval
around zero and direct double-word Taylor evaluation, with degree selected from
an analytical remainder bound. Generate split constants and factorial values
from a recorded high-precision calculation; account for their rounding errors.
This avoids adopting QD's reduction-by-512/nine-doubling implementation.

Handle tiny `expm1` arguments without losing subnormals; evaluate `expm1` directly
where subtracting one would cancel. Derive underflow/overflow and final scaling
rules over the existing domain, including nonzero low words. Keep the separate
paper-derived double-word primitives and logarithm unless their own audit finds
another issue. Audit earlier in-repo implementations before any reuse; being in
our Git history is not proof of independent provenance.

Acceptance: `test/dd_reference.ml`, elementary/pricing/IV/Greek oracles,
runtime enclosure and replay certificates, and complete ordinary tests. Refresh
operation-dependent bounds in `docs/error-analysis.md` and affected oracle
generators. Benchmark scalar and end-to-end costs; a longer series may be slower.
This lands first because the other replacement candidates can use `Dd`.

## 2. Replace CALERF's error functions

Start from the definitions of erf, erfc and scaled erfc. Explore an odd series
near zero, newly generated approximations on explicitly bounded positive
intervals, and an analytically bounded asymptotic expansion in the far tail.
Select intervals, degrees and transitions from the derived error and rounding
budgets, rather than copying Cody's table or machine constants.

Use the erfcx differential equation to certify the new stored approximations
and their residuals where applicable. Derive negative-argument reconstruction
and exponent limits, preserving subnormal behavior and explicit NaN/infinity
handling. Maintain helper interfaces needed by Black, Bachelier and LBR, or
migrate all consumers together. `Normal_dd.cdf` is only defined for |d| <= 6
and is not a drop-in full-domain replacement.

Acceptance: new approximation certificates replace the old coefficient replay
in `oracle/kernel_certificates.py`; `oracle/verify_bounds.py` and runtime
enclosures follow the actual new operations. Exercise representable neighbors
of every interval/cutoff, cancellation in option prices and Greeks, large
positive erfcx arguments and negative overflow. Match existing regional
accuracy requirements and record availability/served-value changes.

## 3. Replace AS241's inverse normal

After the forward normal functions are qualified, develop a safeguarded inverse
solver with mathematically derived initial estimates and a maintained bracket.
Use symmetry and log-tail residuals where ordinary probabilities or densities
underflow. Bound work and refine against the original binary64 probability.
Keep exact endpoint/NaN/domain behavior and assess the smallest positive
probability and the nearest representable value below one explicitly.

If an iterative implementation is too expensive for the IV workload, evaluate
newly generated inverse approximations with reproducible coefficients and
verified refinement. That is a measured decision after the solver establishes
an independent reference, not permission to reuse AS241's constants.

Acceptance: normal inverse oracle regions, monotonicity, tail behavior,
independent inverse checks, LBR seed consumers, and full IV classifications.
Round-trip agreement with the new CDF alone is insufficient. Measure both
normal inversion and the resulting option-IV iteration count and throughput.

## Integration and release gate

Each stage is a focused PR under #64, with no waiver of the
[numerical backend contract](numerical-backend-contract.md) or
[stability policy](stability.md). Run build/format, the complete ordinary suite,
and affected named mutations locally, then the existing three-platform CI.
Report before/after per-region errors, output/refusal changes, and controlled
performance measurements. Intentionally changed served bits require the
documented compatibility decision, changelog and reviewed determinism digest;
do not merely regenerate the digest to silence a failure.

Before closing #64, audit the current tree for remaining adapted tables/code,
including generators, test helpers and optional experiment snapshots. Confirm
source and installed artifacts carry the appropriate notices, qualify the
exact candidate through the existing acceptance lane, and retain historical
provenance. No release is declared fully cleared while any component's
distribution status remains unresolved.
