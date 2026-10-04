# First model extension: certified European exchange prices (#59)

## Decision and gate

Select the two-asset constant-parameter lognormal European exchange model
(Margrabe), with **certified scalar prices only**, as the first experiment.
The payoff is the positive part of receiving one unit of asset 1 in exchange
for one unit of asset 2 at a fixed maturity. Both assets are valued in the same
currency. This is a numerical/architecture learning choice, not a claim of
customer demand or institutional suitability.

The prerequisite experimental baseline (#47) and adversarial campaign (#53)
are closed. PR #84 merged as `b10490a09ffa0c0c1f33227b1dc98d8197c3d21e`;
its [adjudication](adversarial-assurance-closeout.md) retains uncertainty and
availability limits. This document is the bounded selection/contract gate for
#58/#59. #60 may implement this scope after this design lands; #61 must qualify
it before the extension is described as delivered. This selection record itself claims no runtime change or completed canonical
execution. The subsequent [implementation record](exchange-prices.md) owns its
new API and evidence; #61 qualification and independent human review remain open.

| Candidate | Learning and architecture fit | Mathematical/reference cost | Decision |
| --- | --- | --- | --- |
| Two-asset lognormal exchange | Adds correlation, two separately typed asset inputs, degenerate covariance and propagation of input uncertainty into an existing numerical family | Exact closed form; original numeraire derivation, independent payoff integration and a canonical QuantLib engine are available | Select bounded scalar price scope |
| Merton jump diffusion | Adds a stochastic mechanism and infinite-mixture error accounting; scalar payoff fits existing family | Requires proved Poisson-weighted payoff-tail bounds, extreme intensity/jump controls and independent evaluation of the infinite expectation; a last-small-term stop is not a bound | Defer until this extension's assurance transfer is qualified |
| Heston stochastic volatility | Substantial new characteristic-function, complex-arithmetic and conditioning work | Fourier truncation/quadrature, logarithm branches, parameter degeneracies and independent true-expectation references require a larger proof surface | Defer; no numerical contract or implementation is selected |

Candidate comparison is based on original publication identities and inspected
canonical source; only the selected model's original mathematical section was
reviewed for this decision. The unselected models have not been independently
qualified. A defer decision does not deliver them.

## Sources and deviations

The inspected original is William Margrabe, **Working Paper No. 13-76**,
Rodney L. White Center, University of Pennsylvania: [institutional scan](https://rodneywhitecenter.wharton.upenn.edu/wp-content/uploads/2014/03/7613.pdf).
Printed pp. 2–4 state the no-dividend correlated diffusion and equation (7).
The subsequent [1978 publication](https://doi.org/10.1111/j.1540-6261.1978.tb03397.x)
is Journal of Finance 33(1), 177–186; it is not the acquired version.
The working-paper numeraire paragraph on printed p. 4 has a denominator `x1`
in one homogeneity display; the following display uses `x2`. The derivation
below explicitly divides by asset 2 and does not reproduce that inconsistency.
The paper's early-exercise discussion is outside this European-only scope.

We include constant continuous dividend yields as an explicitly derived
extension to the paper's no-dividend assumptions. The derivation below, rather
than an unexamined formula substitution, owns that extension.

Canonical comparator: [QuantLib](https://github.com/lballabio/QuantLib/tree/79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c)
commit `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c` (local description
`v1.43-357-g79f08f66b`), particularly
`ql/pricingengines/exotic/analyticeuropeanmargrabeengine.cpp`,
`ql/instruments/margrabeoption.*` and `test-suite/margrabeoption.cpp`.
The comparator supports integer exchange quantities; qualification uses Q1=Q2=1.
Its direct variance subtraction and division by standard deviation are not
proofs at near-singular or zero variance. Comparator nonfinite values and
exceptions must be recorded, not copied as this library's boundary semantics.
No source code or coefficients are imported into the runtime.

The inspected jump-diffusion and Heston engines at the same commit establish
the additional series/integration work in the comparison above. Publication
identities are Merton (1976), [JFE 3, 125–144](https://doi.org/10.1016/0304-405X(76)90022-2),
and Heston (1993), [RFS 6, 327–343](https://doi.org/10.1093/rfs/6.2.327).
Their complete papers were not acquired or reviewed in this selection.

The [source inventory](evidence/model-selection/sources.json) pins inspected
files, the QuantLib license and the working-paper bytes. The original PDF is
preserved privately with unresolved redistribution rights. Public builds use
only public derivations, code and fixtures; they never require archive access.

## Real model and financial conventions

Inputs denote exact real values represented by their original binary64 words.
For i=1,2, under a common risk-neutral measure,

    dSi / Si = (r - qi) dt + sigma_i dWi,
    d<W1,W2> = correlation dt.

The yields, volatilities, correlation and common risk-free rate are constant.
The target is `C = exp(-rT) E[max(S1(T)-S2(T), 0)]`. There is no cash strike,
early exercise, FX conversion, discrete dividend, calibration or transaction
cost. A zero initial asset is the absorbing-zero boundary of this model.
Price and its absolute-error limit are in the common currency per unit
exchange. T is a year fraction supplied by the caller; no calendar/day-count
convention is silently chosen by the scalar model. Volatilities are
lognormal per square-root year and yields are continuously compounded per year.

Define, in real arithmetic,

    a = S1 exp(-q1 T), b = S2 exp(-q2 T),
    v = T [(sigma1-sigma2)^2 + 2 sigma1 sigma2 (1-correlation)],
    s = sqrt(v).

For positive a,b,s,

    d1 = log(a/b)/s + s/2, d2 = d1-s,
    C = a Phi(d1) - b Phi(d2).

This is exact for the stated stochastic model: there is no model-series,
time-step or quadrature approximation in the proposed runtime formula.
Numerical elementary/CDF truncation and rounding errors still need bounds.

To justify the yield extension, write the discounted terminal assets as
`a exp(-sigma1² T/2 + sigma1 sqrt(T) Z1)` and the analogous b term.
Exponential tilting by asset 2's unit-mean lognormal factor changes the
log asset ratio's mean to `-v/2` and leaves its variance v. Consequently

    C = E[max(a exp(-v/2 + sqrt(v) Z) - b, 0)], Z ~ N(0,1).

Integrating the two Gaussian tails gives the closed form above. This also
shows why common r cancels: it is not an API input. The reverse exchange is
obtained by swapping the complete asset records, including yields and
volatilities; no existing one-asset `Side` convention is repurposed.
Exchange parity is `C(1,2)-C(2,1)=a-b`; `max(a-b,0)<=C<=a`.

## Admission, boundaries and outcomes

Mathematical admission requires finite nonnegative spots and T, finite yields,
two existing typed nonnegative lognormal volatilities, and finite correlation
in [-1,1]. Correlation's closed endpoints are valid. A new abstract correlation
constructor owns its range check; callers cannot create an invalid value.
Signed zero is mathematically zero. Validate inputs before choosing a boundary
path, so expiry does not silently excuse an invalid correlation or asset input.

| Case | Exact target / required handling |
| --- | --- |
| T=0 | `max(S1-S2,0)`, from original words; no discount evaluation |
| S1=0 | Zero, including both spots zero |
| S2=0 | `S1 exp(-q1T)` |
| v=0, T>0 | `max(a-b,0)`; preserve discount/carry cancellation |
| correlation=1, sigma1=sigma2 | v is exactly zero |
| both volatilities zero | v is exactly zero for every admitted correlation |
| correlation=-1 | v=`T(sigma1+sigma2)^2`; not generally zero |
| tiny positive v | Positive-variance branch or explicit numerical failure; a rounded zero is not proof of degeneracy |
| finite inputs but unrepresentable result or unresolved arithmetic | Numerical failure; not invalid financial input or an unchecked infinity/zero |

For T>0, v=0 iff both volatilities are zero, or correlation=1 and the
volatilities are equal. Establish this identity from original inputs before
using a computed variance. At v=0 and a=b the price is defined; there is no
price-level payoff-kink failure. Derivatives have their own future contracts.

The proposed public owner is a separate `Exchange` module with opaque admitted
inputs, labelled `receive`/`deliver` asset records, typed volatility/correlation,
and a private `certified_price` containing value and outward absolute error.
Only `price : admitted -> max_error:float -> (certified_price, error) result`
is offered. Its local input-error type identifies the leg/field; it does not
append exchange-specific variants to existing exhaustive model error types.
Admission failures are distinct from `Invalid_accuracy` (nonfinite/negative
limit), `Numerical_failure` (unresolved arithmetic/representation) and
`Accuracy_exceeded` (a valid finite enclosure cannot meet the requested limit).
An unsuccessful result contains no fallback price. Zero requested error can
succeed only when exactness is proved, not merely because two approximations
agree. A returned certificate must have finite value and finite nonnegative
radius no greater than the explicit requested limit.

No unqualified fast-price entry point, Greeks, implied volatility, or implied
correlation is selected. One price cannot identify two volatilities and a
correlation. Existing one-coordinate Greek types do not identify two asset
deltas or a correlation sensitivity. Batch/Scenario/Planner integration is
deferred: those request/market records cannot yet express the two-asset state
and its joint shocks without a separate financial contract. #60 must preserve
their existing behavior and explain the exclusion in its example; it must not
stuff one asset into a strike field or invent a generalized pricing IR.

## Finite-precision plan and proof obligations

1. Form v using the nonnegative squared-difference expression, with exact
   original inputs and outward arithmetic. Preserve exponents before products
   and square roots; floating-point underflow is not a zero-variance proof.
   Avoid the ill-conditioned subtraction `sigma1²+sigma2²-2 rho sigma1 sigma2`.
2. Form a and b, their log ratio and any zero-variance difference without
   prematurely rounding discounted legs. Reuse the established outward
   exponential/log/CDF and cancellation owners where their preconditions hold.
   A common exact power-of-two currency scale may protect intermediates, but
   restoration and underflow must be enclosed.
3. Propagate the complete enclosures of a,b,s into the price. **Do not** round
   s or an effective volatility to a float and call an existing BSM certificate
   as if that rounded number were the original model. A new model enclosure
   adapter must own that dependency; shared certificate helpers may be factored
   only with equivalent preconditions and compatibility evidence.
4. Bound inherited arithmetic and analytic tails at each operation, including
   sparse/subnormal error and final currency restoration. An outward interval
   may be intersected with independently established price bounds. Choose a
   finite representative and radius covering the entire resulting interval;
   test the caller's limit only after final rounding. No empirical ULP factor
   is a certificate or permitted fallback.
5. Use bounded existing enclosure configurations, at most the existing first
   and full attempts; unresolved work returns failure. Define exact reachable
   operation/domain guards in #60 before scoring. Capability need not cover
   every admitted extreme, but all failures must be counted.

Conditioning is explicit. As v approaches zero, the derivative of sqrt(v)
is unbounded; relative variance-error arguments alone do not control price.
For positive a,b and s>=0 (by continuity at zero), the price is Lipschitz in
each leg with constant 1, and its s derivative is `a phi(d1)<=a/sqrt(2pi)`.
Thus leg enclosure widths plus an outward upper bound on
`a/sqrt(2pi)` times s uncertainty provide a useful cross-check; the actual
runtime enclosure still propagates dependencies and rounding. Deep OTM prices
require absolute bounds even when relative conditioning is arbitrarily bad.

Unresolved implementation obligations are: a call-site proof for scaled
covariance/sqrt, original-leg discount cancellation, interval dependence at
near-degeneracy, certificate centering/restoration, bounded resource limits and
their joint preconditions. They must be resolved or explicitly limited in #60,
then independently challenged in #61. Existing enclosure tests and published
theorems do not automatically prove these new call sites.

## Independent reference and canonical execution plan

Before runtime implementation, build the pinned canonical source and retain
the compiler, configuration and runner hashes. Use explicit evaluation dates,
flat curves and one day counter for both processes. Start with Actual/360 and
whole-day maturities exactly representable as the intended binary64 T, Q1=Q2=1,
and record the actual day fraction. Test common-rate invariance separately.
Expiry handling through a dated instrument may differ from this scalar payoff
contract; record/exclude that comparator route explicitly, while still checking
our expiry target independently. QuantLib availability and agreement are not
the acceptance oracle.

Reference route A uses exact-rational covariance from original dyadics and
independent Arb log/exp/erfc evaluation of the closed form. Route B integrates
the positive-part Gaussian expectation above, not the library's CDF formula.
For a,b,s>0 its exercise threshold is `z0=(log(b/a)+v/2)/s`. Enclose z0,
split around its uncertain strip, rigorously integrate the smooth positive
branch on a finite interval and bound the strip by width times an outward
integrand supremum. Do not give a nonsmooth max expression to a quadrature
routine that assumes analyticity.

For truncation to [-L,L], the omitted payoff is nonnegative and bounded by
`a[Phi(s-L)+Phi(-L-s)]`. This follows by dropping the negative b term and
completing the square in the lognormal-weighted Gaussian density. With L>s+1,
bound these tails independently using
`Phi(-x) < exp(-x²/2)/(x sqrt(2pi))`. Include quadrature, uncertain-strip,
tail and arithmetic errors. A finite integration range or matching precision
alone never proves the expectation. Both routes require original-input interval
overlap; resolved rounding/containment decisions require adequate enclosure
precision. At expiry/zero spots/zero variance, use independent exact identities
or outward discount differences rather than divide by s.

Pin the currently documented optional reference stack (Python 3.14.8,
mpmath 1.3.0, python-flint 0.9.0, FLINT 3.6.0). Refinement is bounded at
256/512/1024/2048/4096 bits, at most 64 requests per subprocess with a
60-second deadline, at most 10,000 frozen requests per lane. Quadrature must
also declare a subdivision/evaluation budget before scoring. Resource caps are
operational limits, not convergence proofs. Every unresolved reference or tool
failure is retained; no row is dropped or counted as an accuracy success.

## Qualification protocol for #60/#61

Freeze generator version, exact words, case IDs and the following cross-product
selections before evaluating the new implementation. Keep mandatory sentinels
separate from broader availability observations; neither is a business SLA.

- Ordinary and swapped exchanges; common-rate invariance in the comparator;
  equal and unequal yields; exact dyadic currency rescaling and parity.
- Correlation -1/0/1 and adjacent binary64 neighbors; equal volatilities and
  their neighbors; one/both zero volatilities; minimum-subnormal volatilities
  and maturities; normal/subnormal exponent transitions and large finite scales.
- Expiry, zero spots, zero variance, exact and near forward equality, cancelling
  original log-ratio/carry, far tails, negative yields and discount overflow.
- NaN/infinity/negative spot, maturity and volatility; correlation just outside
  its closed interval; invalid requested accuracy; exact-only and demanding
  finite limits. Preserve mathematical admission separately from availability.
- Fixed mandatory successes with absolute limit 1e-9 currency: (S1,S2)=(100,95),
  T=1, q=(0.01,0.02), sigma=(0.2,0.3), rho=0.5, and its reverse exchange;
  (100,100), T=1, q=(0,0), sigma=(0.2,0.2), rho=0. Exact-zero/expiry controls
  additionally require available zero-radius certificates when their real price
  is exactly representable. Broader extreme cells may fail explicitly.

Acceptance requires each served radius to contain the independently bounded
true target and meet the original caller limit. Reference uncertainty stays
unresolved. Freeze accuracy requests before scoring; neither availability nor
accuracy thresholds may be widened after a finding. Mutants must challenge
correlation's cross term, premature variance rounding/zero classification,
discount-leg rounding, asset reversal and acceptance/radius enforcement, with
successful mutated builds and numerical witnesses. Add only affected optional
mutants; retain the same seven default CI sentinels.

Measure admission, certified evaluation and end-to-end cost/allocation
separately on ordinary, near-singular, tail and refused inputs, with repeated
samples and host-load records. Compare unchanged existing-model controls and
the canonical engine under explicitly reconciled semantics; do not equate a
faster unchecked comparator with a certified result. Run existing package,
format, complete ordinary suite, type rejection and replay gates. Existing
scalar/Batch/Scenario/Planner outputs and public digest must remain unchanged
unless a separately justified defect requires its own evidence and scope.

The additive module has a minor API effect; no existing exhaustive variants
should change. Versioning and release publication remain separate decisions.
#61 must retain all sources, uncertainties, discrepancies, scope limits,
measured costs and mutations before #58 can be described as complete.
