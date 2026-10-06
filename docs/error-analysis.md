# Error analysis

For each numerical path this document gives:
- where its error comes from;
- the bound the method gives;
- how the bound is measured;
- where the known limits are.

ε is 2^-53, the binary64 unit roundoff, and "DD" is double-double, about 2^-104 relative. The measured worst cases are in docs/results-*.md, and the budgets that enforce them are in the oracle scorers.

There are three different kinds of evidence here: published primitive theorems, analytical majorants for compositions, and measured regression envelopes. A composition that uses a measured envelope is **conditional on that envelope**; testing the composition does not prove its premise for every input. The exact-rational checks in `oracle/verify_bounds.py` check the inequalities below, not the OCaml implementation. They generate the constants consumed by the tests.

## 0. Double-double primitives (`Internal.Dd`)

Every bound below is composed from these. Each primitive is a published algorithm with a proved relative error bound, u = 2^-53:

| Operation | Algorithm | Proved bound |
| --- | --- | --- |
| DW + DW (`add`, `sub`) | AccurateDWPlusDW, JMP Algorithm 6 | 3u² + 13u³ |
| DW + FP (`add_float`) | DWPlusFP, JMP Algorithm 4 | 2u² |
| DW × FP (`mul_float`) | DWTimesFP3, JMP Algorithm 9 | 2u² |
| DW × DW (`mul`) | DWTimesDW3, JMP Algorithm 12 | 5u² |
| DW ÷ DW (`div`) | DWDivDW3, JMP Algorithm 18 | 9.8u² |
| √DW (`sqrt`) | SQRTDWtoDW, LLMPR Algorithm 8 | 25/8 u² |
| FP × FP (`two_prod`) | Fast2Mult (fma) | exact |

JMP is Joldes, Muller and Popescu, "Tight and rigorous error bounds for basic building blocks of double-word arithmetic", ACM TOMS 44(2), 2017. LLMPR is Lefèvre, Louvet, Muller, Picot and Rideau, "Accurate calculation of Euclidean norms using double-word arithmetic", ACM TOMS 49(1), 2023.

**Domain.** The primitive theorems assume no underflow or overflow. Scaling only the divisor does not establish this: `minsub/(3*minsub)` previously returned 0.5 instead of 1/3. Division now normalizes the divisor and extreme dividend before the reciprocal/product and restores their exponent difference. A dividend already in [2^-400,2^400] needs no normalization: multiplying by the normalized reciprocal leaves ample exponent room. Square root likewise normalizes by an even exponent. Independently scaling two result components costs at most one subnormal quantum, 2^-1074, in addition to the relative bound. A normal result alone never establishes the theorem's assumptions about intermediate values. `two_prod` is exact only when its residual is representable.

The cited algorithms are also summarized, with later formalized bounds, in [Boldo, Jeannerod, Melquiond and Muller, Floating-point arithmetic, §5](https://doi.org/10.1017/S0962492922000101). We retain the conservative 5u² multiplication bound; that review gives the tighter 4u² for DWTimesDW3. Original-source links, inspected versions, checksums and acquisition provenance are indexed in the [research bibliography](research/README.md).

## 1. Elementary functions (`Internal.Elementary`)

| Function | Construction | Error sources | Measured |
| --- | --- | --- | --- |
| exp | k = round(x/ln 2), r = x − k·ln2_hi − k·ln2_lo by fma; e^r − 1 by a degree-14 Taylor/Horner series; 1 + (e^r − 1); ldexp | `k·ln2_hi` is exact for \|k\| < 2^20. Reduction also includes the ln(2) split residual and the final fma rounding; the latter cannot be omitted. §8 includes these terms in the 4u exponential bound. | ≤ 1 ULP over 31k arguments |
| expm1 | \|x\| ≤ 1: the series to degree 21, with absolute tail ≤ 1/[22!(1−1/23)] < 2^-69. Otherwise 2^k(1 + em1) − 1. | Horner rounding is relative, because no cancellation happens at the leading term. | ≤ 1 ULP |
| log, log1p | m ∈ [√½, √2), f = m − 1 (exact, Sterbenz); 2·atanh(u) with u = f/(2 + f) and its fma remainder | Series truncation is < 2^-60 relative. Carrying u's remainder removes the quotient's rounding from the leading 2u. log recombines with both ln(2) parts, including the final rounding. | ≤ 1 ULP over 49k arguments |

### 1.1 Reduced binary64 log1p

For |f| < 2^-54, returning f is correctly rounded: the omitted term f²/2 is less than a quarter spacing. The cutoff agrees with [fdlibm's s_log1p.c](https://netlib.org/fdlibm/s_log1p.c), `ax < 0x3c900000`.

Otherwise let w = f/(2+f), y = 2 atanh(w), q = RN(f/RN(2+f)), and v = q². On the reduced interval v < V = 0.0295, including the rounding at its endpoints. TwoSum and the quotient residual restore the leading 2w to O(u²); the tail is evaluated at q. There are **two** roundings in q, from the denominator and the division. Bounding only one was a defect in the former 0.085 calculation.

Use the positive-coefficient series for atanh and bound each weighted Horner error by a geometric series. In units of u|y| the contributions are:

| Source | Upper expression |
| --- | --- |
| Tail argument, two roundings in q | 2V/(1−V) |
| Coefficients, explicit-fma Horner, squared argument and products | (3 + 2/(1−V)) V/[3(1−V)] |
| Omitted terms after degree 21 | V^11/[23(1−V)u] |
| Adding the tail to the quotient correction | V/[3(1−V)] |
| Computed quotient correction and second-order arithmetic | 32u, plus the inflation below |

Their sum, with higher-order inflation, is **0.128144454533 < 0.14**. Thus the test requires |z−y| ≤ ulp(z)/2 + 0.14u|y|, using the oracle's residual to measure fractional ULPs. This replaces 0.085, whose rounded-down table and missing denominator contribution did not establish its claim. The measured worst remains about 0.5205 ULP. Removing the quotient correction fails this bound.

### 1.2 Double-word exp and expm1

The exponential now uses a project-derived degree-22 Taylor polynomial,
`expm1(r) = r + r² (1/2! + r (1/3! + … + r/22!))`, directly on |r| < R = 0.347.
There is no extra division by 512, stopping rule or doubling recurrence.
`oracle/dd_exp_coefficients.py` splits each exact rational 1/n! into two
nearest-even binary64 words. Its check reconstructs the stored values and
bounds each coefficient error by u²/n!. The same generator verifies the ln(2)
split using rational lower/upper bounds on `2 atanh(1/3)`. No coefficient table
or implementation text is imported. Historical QD attribution is retained in
the [source provenance record](source-provenance.md).

Write A = 3u²+13u³, M = 5u² and H = 1/(1−100000u). For the coefficient of r^k,
at most k multiplications and k additions contribute rounding. The separately
rounded square and the final tail product respect that count. The coefficient
1/2 is exact and its DD-plus-float addition costs at most 2u², below A; the
leading coefficient 1 is represented by the original input r. The sum of
their absolute weights after dividing by |r| is at most
`sum k R^(k−1)/k! = exp(R)`. Coefficient splitting contributes at most another
`u² exp(R)`. This bounds both signs without assuming all evaluated terms have
the same sign. Since `|expm1(r)|/|r| >= 1−R`, a relative majorant in u² units is

    H [ ((A+M)/u² + 1) exp(R)/(1−R)
        + R^22/[23! (1−R/24) (1−R) u²] ]
      = 19.875907520… < 80.

The second term bounds the entire omitted Taylor tail by a geometric series.
H bounds the higher-order products and reciprocal perturbations of fewer
than 1000 error factors; all denominators in this construction are bounded
away from zero. `oracle/verify_bounds.py` proves these inequalities with exact
rationals and a rational exponential enclosure, without sampled errors.
The published **ε_expm1 = 80u²** budget is unchanged. Inlining the Fast2Sum
and product-residual helpers and selected Horner calls exposes temporary
records to the compiler without changing primitive arithmetic or the explicit
multiplication/FMA boundaries. The [optimization qualification](results-dd-exponential-optimization.md)
checks both development and release profiles.

For |r.hi| < 2^-104 the helper returns r. The omitted relative Taylor term is
below 2u². This branch applies to both exp and expm1, keeping the leading
Horner products away from subnormal underflow. Without it, a rounded product
residual can overlap the high word; the exact primitive replay detects that
precondition failure. Tiny input low words and finite-exponent residual noise
still receive the separate absolute allowance described below.

For exp, write x = m ln(2) + r, choosing integer m by rounding x.hi/ln2.hi.
The rational check establishes |r| < .347 over the implementation's bounded
reduction domain, including low words and selection roundoff. Adding 1 weights
the expm1 error by |expm1(r)|/exp(r) < .416. The generated ln(2) split has
relative error < u²/4. The constant product and subtraction contribute at most
(2+3|x|)u²: 2.25|m ln 2|u² from the product and A|r| from subtraction.
Thus **ε_exp(x) = (40+3|x|)u²** remains valid with the conservative unchanged
ceiling: `H(0.416×80+3+2) < 40`.

Outside the direct expm1 interval, subtracting 1 gives

    ε_expm1(x) = ε_exp(x) exp(x)/|expm1(x)| + 4u².

These are relative bounds before final exponent scaling, for finite outputs
and normalized input pairs in the implementation's range. Add an absolute
quantum for final component underflow; this is not a pure relative guarantee
for subnormal outputs or a contract for NaN/infinite inputs. The replacement
retains the existing outer range guards. See the
[qualification report](results-dd-exponential.md) for finite-boundary coverage
and compatibility evidence.

### 1.3 Double-word log

For m ∈ [√½,√2], w=(m−1)/(m+1), v=w² < V=0.0296. The numerator is exact by Sterbenz and the denominator is an exact DD sum. The atanh series has positive coefficients, allowing geometrically weighted error propagation even for m close to 1. In u² units a reduced bound is

    H [9.8/(1−V) + 3/(1−V) + 5V/(1−V)
       + 9.8V/[3(1−V)] + 5V/[3(1−V)²] + 5
       + V^23/[47(1−V)u²]] < 20.

The terms cover the quotient parameter, Horner additions/products, generated reciprocals, squared parameter, final product and truncation. In recombination, |ln m|/|ln a| ≤ 1 and |e ln 2|/|ln a| ≤ 2. The constant product costs (2+1/4)u², and the final DD addition costs A. Therefore **ε_log = 32u²**, above H(20+2×2.25+3) = 27.500000001…. `log_float` accepts one binary64 argument; exp/expm1 tests exercise both input words.

QD's Newton log has absolute error near zero. Its relative error is unbounded as ln m tends to zero; this library needs relative accuracy for near-unit spot/strike ratios. That is why the atanh construction remains.

### 1.4 Independent checking

`dd.txt.gz` contains 86,145 three-word reference expansions, including 47,719 nonzero input low words, reduction boundaries, subnormals and exponent extremes. Generation at 110 and 220 digits agrees on all reference words; tiny arguments receive additional precision. A separate exponent keeps oracle errors representable. The scorer uses an independent error-free expansion sum, so high-word disagreement cannot erase the low-word discrepancy; it does not use the library's DD subtraction. It accounts for oracle expansion error, its own roundoff and final component underflow, and rejects NaN/infinity. These tests check the analysis against examples; agreement of two mpmath precisions is not an interval proof.

## 2. The normal distribution

- **Φ(x) outside the small-erf interval** is `½·erfcx(|x|/√2)·exp(−x²/2)`. erfcx uses project-generated local and asymptotic polynomials; §8 certifies their stored coefficients and evaluation. The half-square is split exactly (`x² = hi + lo` by fma), so the exponential's argument carries no rounding.
- **Why that matters in the tail.** The naive form's relative error grows like ε·x², which is 5.7e-14 at x = −38. Here the remaining error is the rounding of erfcx, exp and two products: ≤ 5 ULP measured on the expanded corpus, with the existing 6-ULP gate unchanged.
- **Φ⁻¹ inverts the Gaussian integral.** Six safeguarded steps use the small-erf or log-erfcx equation, followed by a double-word CDF correction on its supported domain. The [derivation](inverse-normal-replacement.md) separates conservative analytical iteration bounds from the unchanged empirical 4/8-ULP gates; [qualification](results-inverse-normal.md) records regional errors and sampled monotonicity. Neither is a universal correctly-rounded inverse certificate.
- **ln Φ composed from Φ.** The enforced CDF envelope is 6 ULP to a rounded reference, hence 6.5 spacings to the real value. The scorer evaluates the actual inner CDF and uses the largest spacing in its neighbourhood, including binade crossings. With this error E, the mean-value denominator is `1−Q−E` or `Φ−E`, not the central value. The outer evaluator and oracle rounding contribute `2 ulp(got)+ulp(reference)/2`. This is conditional on the measured CDF and elementary envelopes. A nonpositive denominator is unresolved and fails; it is never accepted as an infinite bound.
- **The double-double Φ and φ** (`Normal_dd`, |d.hi| ≤ 6 with a normalized low word) now have analytical bounds: **200u² relative for φ and 512u² absolute for Φ**. The absolute CDF bound survives cancellation at negative d; it does not assert uniform relative accuracy in the tail. Section 8.3 derives the series, stopping and arithmetic contributions. Both the original pinned cases and the generated two-word corpus enforce these constants.

## 3. Log-moneyness x = ln(A/C) = ln(S/K) + (r − q)T

x is computed in DD:
- ln q for q = fl(S/K), by the atanh series (32u² relative);
- the quotient remainder ρ = (S − qK)/(qK), with S − qK exact by fma and ρ itself in DD, plus −ρ²/2;
- (r − q)T as two exact products (two_prod);
- for displaced Black, F + d and K + d as exact sums, with their low parts added as Sl/S − Kl/K.

The absolute error depends on the component bounds and |ln(S/K)|+|(r−q)T|. The explicit bound and finite-exponent qualifications are in §5.1.

**Consequence.** A price depends on x through ∂ln V/∂x. That derivative is about |h|/s in the out-of-the-money tail (h = x/s) and 1/|x| for the zero-variance price. So the tail error stays about ε until |h|·(|ln S/K| + |(r−q)T|)/s approaches 2^51, and the zero-variance price is limited where x itself cancels.

**Known limit.** A forward placed at the strike through carry has x ≈ 1e-16 of its terms. Its zero-variance price is then taken as A − C from the DD legs instead (§5), because C·expm1(x) would inherit x’s absolute coordinate error.

## 4. The normalised Black function b(x, s), out of the money (x ≤ 0)

The kernel uses Jäckel's three regions (η = −13, τ = 2ε^(1/16)):
- **Regions I and II.** b = vega·(b/vega). The scaled function comes from Jäckel's asymptotic or small-t expansion. Section 8.4 bounds each truncation remainder and the actual rounded polynomial evaluation separately. The vega, `exp(−(h² + t²)/2)/√(2π)`, is evaluated with h = x/s in DD (including x's and s's low parts) and the exponent assembled from split products and DD corrections. §8 includes their remaining arithmetic error. Applying the exponential last with its prefactor folded in avoids premature underflow before final exponent restoration. A direct mpmath probe of Region I measures about 1 ULP.
- **Region III** is `½·exp(−(h² + t²)/2)·(erfcx(q1) − erfcx(q2))` with the generated erfcx, or the erfc forms.

**Cancellation.** Region III subtracts positive terms. Its observed cancellation and ULP maxima are regression evidence, not premises of the certificate. The new evaluator propagates absolute errors through this subtraction; it assumes no fixed upper cancellation factor.

**Attainable accuracy (Jäckel).** b is a function of its inputs. With them exact, its relative condition in s is |s·b′/b|, so a rounded s alone costs (1 + |s·b′/b|)·ε. The library carries s = σ√T in DD, so its input formation contributes DD error rather than binary64 rounding; that contribution is small, not identically zero.

## 5. Price assembly

- **Black family.** V = 2^e·(max(θ(A−C),0) + √A·√C·b(−|x|, s)), with (S, K) scaled by 2^-e, initially e = ⌊(e_S + e_K)/2⌋. For |x| < 2^-500 and small x terms, the exponent is lowered by 512 to retain tiny intrinsic products; this depends only on dimensionless quantities.
  - Floor division makes the scaling equivariant, so V(2^j S, 2^j K) = 2^j V(S, K) exactly when the input scaling is exact and output scaling crosses no overflow/underflow boundary. A property test checks this on its stated domain.
  - The out-of-the-money part applies 2^e inside the exponential (Cody–Waite 2^-n·e^-r), avoiding an intermediate underflow before the final exponent restoration.
- **Intrinsic θ(A − C)** comes from DD legs, `S·exp_DD(−qT)` and `K·exp_DD(−rT)`:
  - as C·expm1(x) when |x| ≤ 0.35 and x's terms are ≤ 1;
  - otherwise as A − C. The bounds are the component-dependent expressions in §5.1; neither branch has a uniform 2^-104 coefficient.

  It is then rounded once, including into the subnormals (`Dd.to_float_scaled`). Equal-coordinate zero-variance contracts with max(|r|,|q|)T < 2^-500 instead form S(r−q)T from mantissas and accumulated exponents. The omitted relative term is < 2^-499. This covers carry below the binary64 range while the currency price is normal. For example S=K=2^1000, T=2^-1074, r=1, q=0 changed from 0 to 2^-74. This special price path does not establish exact inverse classification at these exponent extremes; inverse classification still uses the DD legs.
- **Bachelier.** V = D·(max(θΔ,0) + s·φ(d)·Y′(−|d|)), with Y′ = 1 + h·Φ(h)/φ(h) from Jäckel's Remez rationals. This avoids subtracting φ(d) − |d|Φ(−|d|). d = Δ/s is carried in DD, and D·θΔ is DD.

**Measured.** Worst errors per region are 1–22 ULP on this project's 57k-contract oracle, and 1–19 ULP on the 41,760-contract displaced oracle.

### 5.1 The intrinsic's analytical error budget, and the zero-variance price

The intrinsic I=A−C is formed in DD. With the component majorants above, L=|ln(S/K)| and C_y=|(r−q)T|, the normal-intermediate analysis is:

- E_x ≤ ε_log |ln RN(S/K)| + 15u³ + 9u²(L+C_y) + E_low, with E_low ≤ 5u² for displaced inputs. For a quotient outside the normal range, use |ln S|+|ln K| in the log term.
- C·expm1(x): E ≤ A E_x + |I|[ε_expm1(x)+ε_exp(rT)+10u²].
- A−C: E ≤ A[ε_exp(qT)+5u²] + C[ε_exp(rT)+5u²] + 3u²|I|.

The code uses expm1 for |x|≤0.35 and L+C_y≤1. This is a conservative validity rule, **not an optimizer of the two bounds**; the crossing depends on the component constants and contract. The scorer checks |V−RN(I)| against E and both final half-ULP roundings. It considers both branches within the rounding uncertainty of a threshold. These formulas are not a universal finite-exponent certificate: intermediate underflow and unresolved cancellation require separate treatment.

**Mutation evidence.** Rounding the quotient remainder to one word now fails the independent coordinate corpus (`quotient-remainder`). Near S/K=1 the log term is small enough to distinguish it. The old assertion that no test could distinguish this was false. Removing the intrinsic terms guard still survives the current price corpus under the revised bounds. Run `dune exec scripts/mutation/mutation.exe -- --probe intrinsic-terms` to reproduce that specific result. The exclusion is provisional; a survivor is not a proof of equivalence or impossibility.

### 5.1.1 Severe carry cancellation refinement (#76)

When the DD coordinate lies within a conservative estimate of its formation
uncertainty after cancellation, the fast price now refines from original words.
Zero variance uses `exp(-qT) [(S-K) - K expm1(-(r-q)T)]` with runtime enclosures;
positive variance uses the existing original-model enclosure. A finite result
requires the complete interval to prove its binary64 rounding cell. Inconclusive
refinement returns NaN, never an unchecked DD fallback. Exact currency scaling
and cell comparisons at the normalized exponent preserve subnormal boundaries.
The [method](carry-cancellation-design.md) defines dispatch, domains and limits;
the [results](results-carry-cancellation.md) distinguish corrections, explicit
availability losses and unaffected ordinary corpora. This branch does not turn
the rest of the fast API into a universal certificate.

### 5.2 Independent price certificates and quality gates

All **99,056 price rows** (57,296 European and 41,760 displaced) now require the per-input analytical certificate in §8, including expiry and zero variance. Unsupported domains, nonfinite radii and disagreement between the arithmetic replay and the served value fail the ordinary scorer. There is no measured-envelope fallback.

The existing 8–32 ULP budgets remain additional quality gates. They are measured targets, not premises of the new price certificate. Both the ULP and normwise gates remain enforced without the old 4-ULP bypass. Bachelier's norm includes D σ√T/√(2π), because its time value is unbounded relative to the discounted forward/strike.

## 6. Implied volatility

The public inverse now accepts a positive root only when independent runtime
model enclosures prove its nearest-even binary64 rounding. Intrinsic/maximum
comparisons use original input words, including sparse displaced low parts;
uncertainty is an explicit computational failure. The enclosures include
finite-exponent allowances, analytic remainders and the final volatility
coordinate. See [the arithmetic derivation](runtime-enclosures.md),
[model expressions](model-enclosures.md) and [root acceptance](certified-iv.md).
All 5,575 positive oracle rows must match their correctly rounded reference;
no failed or merely approximately correct root counts as a pass.

The following fast calculations now produce **proposals only**:

1. **Proposal classification.** DD intrinsic and maximum estimates select a candidate path; they cannot decide a public mathematical classification.
2. **Normalisation.**
   - β = (quote − intrinsic⁺)/√(AC) and β̄ = (maximum − quote)/√(AC) are formed from the DD legs, then rounded once.
   - ln β is taken from the unscaled quote, because a subnormal quote loses bits when rescaled.
3. **Inversion.** Jäckel's Let's Be Rational: a four-branch rational-cubic initial guess, then two Householder steps whose objectives are chosen per branch for conditioning.
4. **Correction.** One Newton step with the extended-precision kernel:
   - on b̄ when β > b_max/2;
   - on ln b when β < 2^-900;
   - on b otherwise.

### 6.1 Bounded proposal generation

`Iv_iteration` works with the implemented binary64 evaluator. Its successful
exit is an evaluated equality, or an opposite-sign bracket whose endpoints
are adjacent nonnegative binary64 numbers. A small Newton step alone is not
success. Rounded evaluator values can locally be nonmonotone: only the
endpoint signs, not monotonicity of intermediate computed values, are required
for this discrete guarantee. The real pricing function remains increasing.

Positive finite binary64 encodings preserve order and lie below 2^63. Every
fourth iteration bisects their integer encodings. Each such step at least
halves the number of representable intervals; 63 bisections therefore leave
adjacent endpoints. The default budget is 256 iterations, allowing the
safeguarded Newton proposals and the final check. A stagnating proposal may
evaluate the adjacent float toward the target: it succeeds only if the
actual residual completes the bracket, otherwise iteration continues. This is a finite arithmetic
termination argument provided the endpoint signs hold and evaluations are
finite. Other failed proposals use an arithmetic midpoint when it is
strictly interior, so an underflowed tail need not jump to the middle of the
exponent range at every fallback. The mandatory fourth-step encoding split
still supplies the finite bound. Smaller test-supplied budgets return `Non_convergence`. Nonfinite
values or failed brackets return `Numerical_failure`. An invalid Newton
proposal uses bisection, while an invalid price evaluation fails explicitly.

Bachelier uses zero as its evaluated lower endpoint. The upper construction
rounds `((quote/D) + |distance|) sqrt(2 pi)` outward (including the displacement
low word), then verifies its computed price. Black treats LBR and the Newton
correction as proposals, validates the result and its adjacent floats, and
falls back to the same bounded solver on a checked local bracket. Failure to
bracket is explicit; the accuracy reported in Jäckel's paper is not a premise
of successful termination. A nonfinite or nonpositive final volatility
conversion is `Numerical_failure`, never `Above_maximum` or
`Below_smallest_volatility` without an independent mathematical decision.

These evaluator checks are not the public acceptance criterion. A separate
four-word enclosure evaluator certifies the annual-volatility rounding cell.
It brackets by expansion in ordered float encodings (at most 64 steps), then
bisects (at most 63 steps). Its default 128-step cap cannot itself report
success. Unresolved signs fail. See [the audit](iv-termination-audit.md).

### 6.2 Executed exact-model certificates

For each positive root in the committed oracle, `Iv_bounds.certified_root_bound`
executes the §8 price and vega certificates, including exact-rational primitive
postconditions. Let the candidate price ball be `[p-E,p+E]`, quote be `Q`, and
`v_min>0` be a downward-rounded lower bound for vega throughout the interval
between candidate and the oracle root's rounding interval. Normal-model vega
increases with volatility. Black vega has one maximum, so its minimum on an
interval is at an endpoint. Endpoint certificate lower bounds therefore give

    |candidate - exact_root| <= (|p-Q| + E) / v_min.

The scorer rounds each bound operation outward and includes the oracle root's
final rounding uncertainty. Nonpositive vega bounds, unsupported certificates
and nonfinite bounds fail. Subnormal uncertainty is carried by the price ball;
it is not replaced by relative precision. Final volatility conversion is
already included because the certificate evaluates the final served candidate.
There is no assumed small-step or Newton quadratic remainder in this bound.

Random recovery applies the same mean-value argument to two certified price
balls, at the generating volatility and the returned candidate. Their
outward difference encloses the exact price difference. It does not assume
that the generating volatility is the inverse of its rounded served quote.

These are a posteriori certificates, not independent quality thresholds: a
poor candidate can have a valid but large certified error bound. Consequently
the historical quality gates below remain mandatory and unchanged. Their
measured premises are not used by the analytical certificate. The independent runtime acceptance proof is separate from these test certificates; corpus success does not establish universal availability.

### 6.3 Historical Black quality budget

The error requirement composes normalization error with a kernel envelope. It does not claim that two Householder steps plus Newton converge for every representable contract. In particular, the former assertion that the Newton quadratic remainder is below u² did not follow from a citation to Jäckel. The scorer now transports error using the minimum vega over the candidate/reference interval. Black vega has one maximum as volatility varies, so that minimum is at an endpoint; the mean-value theorem then handles nonlinear transport without discarding a quadratic term.

At the reference root the regression budget is `3u + (δβ+κ)c`, with a first-order conversion allowance 3u and c=b/(s b′) or b̄/(s b′). The endpoint-vega ratio inflates this before comparison with the exact-root oracle. These IV budget calculations still use ordinary binary64 transcendental evaluations rather than outward enclosures, and the first-order conversion allowance has not been promoted to a complete rounding bound. They are conditioned regression requirements, not executed certificates like §8. Nonfinite error or allowance fails.

- **Ordinary branch:** δβ=u below the money; above it add `(E_I+3u² quote)/(quote−I)`. κ=65u remains conditional on the measured 32-ULP kernel envelope (including the reference half-ULP); it is not a published theorem for this implementation.
- **Complement:** use the maximum-leg error, not the intrinsic error. If M is the DD maximum, set E_M=|M|[ε_exp(rate·T)+5u²] and g_lower=(M−quote)−E_M−2u|M−quote|. The normalization error includes `u+E_M/g_lower`, the two discount exp bounds and 32u² for DD assembly. If g_lower≤0 the bound is unresolved and rejected. Five independently generated near-maximum ATM roots expose the old omission: one was about 360 times outside the old allowance.
- **Logarithmic branch:** β<2^-900 uses the absolute log-normalization error and the kernel envelope, transported by b/(s b′).

**Complement kernel derivation.** At s²=2|x| the normalized price is below b_max/2; monotonicity then implies t+h>0 whenever β>b_max/2. Thus both erfcx arguments are nonnegative, and their sum has no cancellation. The integral representation of erfcx gives

    |d log(erfcx(z))/dz| ≤ min(2/√π, 1/z), z≥0.

For each z=(t±h)/√2, rounded division/addition and the √½ constant give an absolute perturbation at most δz=4u(t+|h|)/√2. Use 1.129 near zero, otherwise min(1.129,1/(z−δz)), to cover the whole argument interval. This replaces the unsupported constant 3u argument estimate. The implemented budget is

    κ = 21u + δz·max(argument sensitivities)
        + u²(16E+8E²), E=(h²+t²)/2.

The 21u allows 9u for a 4-ULP-to-rounded-reference erfcx envelope, u for the positive sum, 3u for a 1-ULP exponential envelope, and 8u for the scaled product/reduction assembly. The final term allows DD exponent error and the exponential perturbation's second order. This IV scorer remains **conditional**: it still uses the historical 4-ULP erfcx and 1-ULP exponential envelopes. The broader analytical component bounds in §8 do not retroactively prove those tighter historical premises, and this scorer has not yet been migrated to the per-input certificate. It replaces the unexplained 17u claim; it is not a completed universal certification of that path.

**Branch uncertainty.** An error δ in β changes ln β by at most −log(1−δ). The scorer adds rounding in reconstructing x and the threshold, and evaluates every overlapping branch. The previous arbitrary 1e-6 guard is gone.

### 6.4 Historical Bachelier and round-trip quality budgets

Bachelier no longer accepts “in the rounding cell or within 4 ULP.” It propagates an absolute price uncertainty through the minimum vega between candidate and exact reference. With J the positive intrinsic, O the time value, u=2^-53,

    E_price = J[ε_exp(rT)+8u²] + 19u O + 2^-1074.
    E_sigma = [E_price + 8u σ_hi vega_hi]/vega_lo + ulp(reference)/2.

The 19u is conditional on the measured 8-ULP price envelope (17u to the real value), plus two normalization roundings. The 8u displacement allowance for stopping and final conversion is provisional: a small rounded step alone does not prove a small true residual, and this constant has not been established from the implemented termination conditions. Bachelier vega is increasing in σ, so endpoint vegas enclose the full interval. The absolute quantum is essential for subnormal quotes: their relative precision can be much less than 53 bits. This derives error transport, not a universal proof of the price kernel or the 200-iteration convergence limit.

The random round-trip test likewise composes the forward 32-ULP price budget with the inverse budget, using minimum endpoint vega. It no longer has a 4× attainable rule or a repricing escape. It only attempts recovery of the generating σ when the forward uncertainty interval excludes both price boundaries. Boundary classification and exact-quote roots are tested separately; a rounded quote at the intrinsic need not identify the generating σ.

## 7. Greeks

Each Greek is an ordinary part plus P·exp(−(h² + t²)/2)·2^k, with every algebraic factor folded into the prefactor P and the exponential applied last. Φ enters through the Mills ratio, so in the tails all terms share one exponential and nothing underflows early.

Brackets that cancel near the money are evaluated in DD, using `Normal_dd` for Φ and φ and the DD legs:
- theta: θ(qAΦ(θd1) − rCΦ(θd2)) − Aφ(d1)σ/(2√T);
- charm: θqΦ(θd1) − φ(d1)·∂d1/∂T;
- veta and color: q + d1·∂d1/∂T ∓ 1/(2T), with veta's form scaled by √T so it stays finite where 1/T is not.

Terms in 1/T are rewritten so that √T and σ cancel analytically.

**Forward-model rho** (Black-76, displaced Black, Bachelier) is −T·V. The scorer requires rho=RN(−T·served_price), bit for bit, then composes **absolute** error:

    |rho−reference| ≤ |T| E_price + ulp(rho)/2 + ulp(reference)/2.

E_price includes the price reference's rounding and the largest spacing in the possible price interval. A fixed “price budget + 1 ULP” is invalid because multiplication can change the binade: 32 price ULPs at 1 become 61 rho ULPs after multiplication by 1.9. A regression pins that counterexample.

**Independent certificates.** All **65,980 finite Greek rows**, including 13,625 below-binary64 results, now require operation-by-operation analytical error propagation. The remaining 420 rows are payoff-kink refusals. An additional **2,506 three-word Greek references** include 51 contracts at and adjacent to zeros of cancelling Greeks. Those rows compare the served result with the extra reference bits using the analytical radius, without a ULP-budget or rounding-cell escape. Existing ULP budgets remain separate quality gates. Forward-model rho additionally retains its served-price identity check.

## 8. Rounded kernels and complete price/Greek expressions

### 8.1 Approximation and floating evaluation are separate errors

The error functions use project-generated coefficients from Gaussian integral
identities. [The construction](error-function-replacement.md) derives 48 local
degree-16 erfcx polynomials, a degree-12 asymptotic tail, and the small-erf
series. `oracle/erf_coefficients.py` encloses each coefficient with exact
rationals, including the second word of each local leading coefficient.
Both enclosure endpoints must round to the stored word.

`oracle/erf_certificates.py` bounds Taylor remainders, coefficient error,
argument rounding and coefficient-weighted explicit-FMA evaluation. It uses
Machin's identity and integer square roots to enclose 1/√π. The resulting
relative majorants in units of u are:

| Path | Approximation including stored constants | Complete normal-intermediate bound |
| --- | ---: | ---: |
| local erfcx, [0,12) | 0.075294 | 3.037720 |
| asymptotic polynomial, [12,2^27) | 0.123177 | 3.144418 |
| leading asymptote, [2^27,infinity) | — | 1.372415 |
| small erf, |x|<=1/2 | — | 3.366957 |

The existing certificate ceilings remain **40u for erfcx** and **26u for small
erf**. These are analytical majorants, separate from scalar ULP regression
gates. Absolute allowances cover subnormal operations; the relative bounds
do not extend through overflow. Positive erfc now uses an exact split square
and the qualified scaled exponential. Its cutoff at 28 is below half a
subnormal quantum; the replay requires its uncertain argument to remain at
least 27.5 and proves that stronger cutoff condition separately.

Jäckel's Y′ rationals retain their upstream coefficient provenance and notice
in `lib/normalised_black.ml`. `oracle/kernel_certificates.py` still bounds
these coefficients' differential residuals with exact Bernstein enclosures
on 128 subintervals. Rational denominators have nonnegative coefficients and
are bounded below by their left endpoint.

For G(a)=Y′(−a), a≥0, the defining equation is aG′−(1+a²)G+1=0. Its positive integral solution similarly bounds relative approximation error by the differential residual. For tail G=wC/B, C=B+wA, the residual numerator is

    B²−(1+3w)CB−2w²(C′B−CB′).

The middle interval uses a(P′Q−PQ′)−(1+a²)PQ+Q², including the boundary mismatch at a=4. Approximation bounds are below 21.605u and 60.012u respectively. The only negative middle numerator coefficient has absolute coefficient condition below 1.001. Its evaluation allowance is 1.001[(1+u)^15/(1−u)^14−1]. The small branch G=1−a Mills(a) has amplification a Mills(a)/G < 1.5 on [0,15/32]. Including all factors gives less than 89.041u; the certificate uses **96u relative**.

These relative bounds require normal intermediates and the stated argument signs. The replay checks its finite domain (including |h|≤2^400 where squaring is needed), and adds absolute underflow allowances separately. It does not extrapolate relative guarantees through an overflow or a flushed tail. The error-function replay transports its split-square uncertainty through the scaled exponential instead of flushing a normal tail.

### 8.2 Exponent scaling and split inputs

The binary64 exponential's degree-14 coefficients are read directly from `lib/elementary.ml`. On |r|≤0.347, exact rational sums bound coefficient error, weighted Horner error, the degree-15 remainder, reduction by the two ln(2) words and final addition. The relative majorant is 3.088251u < **4u**, before the absolute quantum for subnormal scaling.

`Split.scaled_exp_neg` computes m exp(−hi−lo) 2^k. For 0≤hi≤4096, |lo|≤0.001 and |k|≤2048, reduction has |n|<6000 and error at most 1.4u+6000(error_ln2+u²). Combining the 4u exponential bound with three rounding factors and

    |exp(−lo)−(1−lo)| / exp(−lo) ≤ lo²/[2(1−|lo|)]

gives **12u+lo² relative**, plus final underflow. The checker verifies the affine majorant at lo²=0 and 10^-6. Input exponent uncertainty ρ<1 is transported by ρ/(1−ρ). Prefactor error is scaled before restoring the power of two, preserving rescued subnormal tails. For hi≥4096, a separate inequality proves underflow when exponent uncertainty is at most 1%, |m| plus its error is below 2^1025 and k≤2048.

This analysis exposed an actual numerical defect: the previous cutoff ignored m. The implementation now normalizes extreme prefactors and includes their exponent in the cutoff. For example, m=2^1000 and hi=800 must give a positive result. The Bachelier price with F=40·2^995, K=0, T=1, r=0 and σ=2^995 likewise has a positive put value that was previously lost.

`Split.sqrt` now scales by an even exponent before forming its FMA residual, with the 25u²/8 primitive bound plus scaling underflow. `Split.quotient_dd` normalizes extreme operands, computes the quotient residual, and **renormalizes the pair with Fast2Sum**. Without that last step the correction can exceed half an ULP, violating the nonoverlap premise of later DD algorithms. For normalized inputs, write N=n(1+α), D=d(1+β) and q=(n/d)(1+δ), with |α|, |β|, |δ|≤u. The exact FMA residual n−qd and the two input-low corrections have total magnitude at most (3u+u²)|n|. Rounding q·dl, the two additions and division contributes less than 9H u²|n/d|. Replacing the correction denominator d by d+dl contributes less than 4H u²|n/d|. Conversion to relative error and higher-order products remain below **16u²**. Fast2Sum preserves q+r exactly in the normal-intermediate case. A separate absolute quantum allowance covers exponent restoration. No pure relative bound is asserted for a subnormal result.

### 8.3 DD normal series, including cancellation

The implementation prepares only the divisor-dependent intermediates of the
unchanged DD divider for the fixed odd denominators. Dividend scaling and all
rounded operations retain the original order and values. Paired CDF/density
evaluation reuses the identical DD square and exponential. These substitutions
do not change the following allowances; see the
[operation-preserving qualification](results-inverse-optimization.md).

For normalized |d.hi|≤6, d²<37. Marsaglia's series has same-sign terms q_n=d^(2n+1)/(2n+1)!!. Its recurrence uses a DD square, multiplication and division, giving 19.8u² per accumulated term index. The positive-series identity bounds Σn|q_n|/Σ|q_n| by d²/2. At index 128, |q_128/q_0|≤37^128/257!!<2^-120, so the implementation's 400-step cap cannot be reached.

There are at most 129 DD additions. The resulting series allowance is

    [19.8·37/2 + 3·129 + 1] H u²,
    H = 1/(1−100000u).

The last unit covers the stopping remainder and tiny-term underflow. If the next-term ratio were at least 1/2, its index would be at most 37 and accumulated_sum/current_term≤2^37, inconsistent with the implemented 2^-110 stopping criterion. Once the test can trigger, the remaining geometric tail is no larger than the current term. Underflow contributions, even amplified by the series and operation count, are far below u².

For φ, square error, exponent sensitivity, the §1.2 DD exponential and the checked two-word constant give [40+3·37/2+5·37/2+6]H u² < **200u² relative**. Multiplying the series by φ produces magnitude at most 1/2. Including that product and the final addition gives less than **512u² absolute for Φ**. The use of absolute error is essential for 1/2 minus a nearly equal term. No measured cancellation factor enters this result.

### 8.4 Black expansion remainders and Region III

Write a=−h≥0 and t=s/2. Region I expands exp(−v²/2) in the positive integral with weight exp(−(a−t)v)−exp(−(a+t)v). Taylor's alternating remainder is bounded by the next integrated term. With r=a²−t²>0, q=a²/r² and e=t²/a², after index N its magnitude is bounded by

    (t/r) q^(N+1) · 2(2N+1)!!
      · Σ_{j=0}^{N+1} binom(2N+3,2j+1) e^j.

The evaluator computes this positive expression outwards at a's lower and t's upper endpoint. It does not rely on a quoted relative accuracy for the asymptotic expansion.

Region II expands sinh(tv) in the same positive Gaussian integral. If I_j(a)=∫_0^∞ v^j exp(−av−v²/2)dv, the omitted terms after t^13 obey

    remainder ≤ 2 t^15 I_15(a) / [15! (1−t²/17)],
    I_15(a) ≤ min(128·7!, 15!/a^16).

Integration by parts gives I_17/I_15≤16 for a≥0, and successive term ratios are bounded by t²/17. The moment recurrence

    I_(2n+1) = (4n−1+a²) I_(2n−1)
               − (2n−1)(2n−2) I_(2n−3)

connects these moments to the implementation's polynomials. `oracle/lift_polynomials.py` checks their coefficients using exact fractions, including rounded large literals, and generates the test evaluator from the actual operation grouping. It also checks Region I coefficients against the integrated alternating terms. Polynomial arithmetic is propagated separately from the remainder.

Region III replays the actual erfc/erfcx branches, both positive legs, exponentials and subtraction. Adding absolute errors handles arbitrarily strong cancellation within the checked domain. ATM and deep-tail branches have separate omitted-term or underflow bounds. The split Gaussian exponent includes the omitted low-word squares, cross products and formation uncertainty; the conservative arithmetic allowance is 64u²(h²+t²), plus input perturbations and an absolute underflow allowance.

### 8.5 From components to prices and every Greek

`test/certified.ml` carries a computed center v and a nonnegative absolute radius e. Every radius operation rounds outwards with `Float.next_after`. For two input balls a and b:

    E_add = E_a + E_b + round(result)
    E_mul = |a| E_b + (|b|+E_b) E_a + round(result)
    E_div = [E_a + (|RN(a/b)|+round(result)) E_b]
            / (|b|−E_b) + round(result).

The denominator is rounded down and must be strictly positive. `round` includes a subnormal quantum. DD nodes use the published relative majorants, input perturbations and a fixed 32-quantum allowance for gradual underflow. Each executed primitive in the generated DD replay checks that allowance with exact rational arithmetic, including inside exp/expm1/log and the normal series. Finite outputs and nonoverlap are enforced. These are per-input witnesses; the 32-quantum allowance is not asserted as a published or universal finite-exponent theorem. Coordinate logarithms, quotient remainders, displaced low parts, carry, root time, discount factors and DD cancellation are all propagated before model assembly. Thus a Greek close to zero receives an absolute bound from its actual terms, not a fixed relative or ULP allowance.

Ordinary tests require the replay's center to match the library's served bits. This checks that the written arithmetic model follows the selected implementation path; it is not accuracy evidence by itself. **Mutation builds disable those replay-identity assertions.** A numerical mutant must still fail the independent reference comparison, a mathematical precondition or its designated regression test. Changing a result's last bit alone is not counted as a kill. The mutation catalog applies this rule; the separate intrinsic-guard probe remains provisional.

The certificates cover every price and finite Greek in the committed model fixtures, plus the direct component and extra-bit Greek corpora. Unsupported arguments fail rather than returning an infinite radius or falling back to the historical measured budget. This is executable analytical error propagation, not formal verification of Python, OCaml, the compiler or every finite input admitted by the public API.

## Certification status and remaining proof obligations

| Layer | What is established | What is still missing |
| --- | --- | --- |
| DD primitives | published normal-intermediate theorems; two-operand/even-exponent normalization; exact rational primitive witnesses on the replayed inputs | a formal finite-exponent proof covering arbitrary low words and every call site |
| DD exp/expm1/log | written analytical majorants, exact-rational checks, dense two-word corpus | independent/formal verification of the complete implementation |
| Reduced log1p | corrected 0.14 majorant with positive margin; fractional-ULP oracle | whole-domain elementary guarantees beyond the reduced path |
| Black/Bachelier prices | exact-rational rounded-kernel bounds, integral remainders and per-input propagation on all 99,088 rows; strict quality gates retained | independent/formal verification and extension beyond the checked finite domains |
| Black-family IV | original-input boundary enclosures, bounded work and runtime proof of correctly rounded positive roots | independent/formal review, broader availability and operational acceptance |
| Normal_dd and all Greeks | DD series majorants and per-operation absolute bounds; 65,980 finite rows and 2,506 extra-bit references | independent/formal verification and coverage of all finite admitted inputs |
| Bachelier IV | original-input boundary enclosures, quote-scaled residual and runtime proof of correctly rounded positive roots | independent/formal review, broader availability and operational acceptance |
| Production price/smooth Greeks | original-input runtime enclosures, typed per-request absolute limits, finite private certificates; 4,176 extra-bit public checks and independent Arb Greek differentiation | owner-approved use/materiality, independent human/formal review, broader availability and portfolio acceptance; expiry/zero-volatility Greeks explicitly unsupported |
| American/Bermudan exact reductions | [guarded no-cash expiry, terminal-only and nonnegative-rate zero-yield call proofs](american-certification.md); original-input runtime enclosures and explicit currency limits | general stopping, cash/piecewise certificates, Greeks/IV guarantees, independent review and final artifact qualification |
| Zero-volatility ATM veta | coordinate-specific differentiation; runtime rounding certificate; 532 nested-derivative references independently enclosed by Arb | broader capability and independent review; arithmetic/rounding uncertainty is an explicit numerical failure |
| Random IV recovery | certified exact-quote inverse plus analytical transport between generating and returned price balls | supported production use and operational acceptance |
| Committed price/smooth-Greek references | independent Arb certificates for all 99,088 price and 59,200 smooth-Greek rounding cells; one-sided tail proof resolves intrinsic midpoints | future/unexercised inputs and independent human review; 7,200 expiry-Greek rows excluded explicitly from analytic series scope |
| Intrinsic branch rule | valid conservative rule; explicit surviving probe | a discriminating corpus/bound or proof of equivalence; no impossibility claim |

Consequently the complete library is **not certified for all finite admitted inputs**. The price/Greek certificates no longer depend on measured ULP envelopes in their checked domains. Historical measured quality gates are still useful and remain enforced. IV and random recovery now additionally execute analytical per-input transport certificates. The historical measured budgets remain quality gates. Public IV success additionally requires a runtime exact-model rounding certificate; unresolved classifications and roots fail explicitly. This does not promise successful resolution of every admitted finite input or qualify the separate fast price/Greek APIs for every such input. The [production adapter](production-boundary-design.md) separately enforces absolute numerical limits on each accepted price or smooth Greek request and returns explicit capability/accuracy failures. It does not turn the fast API into a universal certificate or establish institutional approval. The intrinsic branch probe's survival remains a corpus/bound limitation, not an impossibility result.


### Finite-exponent noise in the checked DD compositions

The exact primitive witnesses establish, for each executed operation, its fixed relative allowance plus at most 32 subnormal quanta. These additive errors must also be transported through the DD elementary and normal functions; checking each primitive alone is insufficient. A deliberately coarse absolute transport estimate suffices because the analytical ceilings have explicit spare margin.

Before exp’s final power-of-two restoration, all Horner factors have magnitude below .347; their total absolute perturbation transport is bounded by the geometric sum 1/(1−.347) < 2. The final multiplication by r² contracts, and the leading addition has unit absolute sensitivity. The tiny branch bypasses the polynomial. The log reduction denominator exceeds one, its series parameter is below 0.172 and its accumulator below 1.04. Its Horner factors contract; the final small products and sums fit within an additional factor 16. Integer-times-ln(2) products are separately checked primitive nodes, not repeated multiplications.

For the normal series, |d|<7 and d²<37. The amplification of any term-recurrence perturbation is bounded by the product of max(1,37/(2k+1)), which is below exp(19)<2^28. The absolute series is below 7 exp(19)<2^31. Its sensitivity to d² is below 401·7 exp(19)<2^40: for d²≥1 use the degree bound, and for d²≤1 bound each power by one. This bound even permits the 400-iteration cap. The density path combines a contracting negative exponential with the reduced-exp calculation; final normal assembly multiplies it by the bounded series. Thus 16(2^40+2^31)(2+1)<2^60 bounds absolute transport from any primitive perturbation. Fewer than 2^14 primitive calls, including nested division calls and coefficient initialization, each contribute at most 32 quanta. Their total is below **2^80·2^-1074**. `verify_bounds.py` checks these numerical inequalities with rationals.

This allowance fits inside the unused gap between each derived majorant and its published-in-this-repository ceiling: all five gaps exceed one u² unit. The smallest nonzero scale needing this argument is the direct expm1 branch, whose |x|≥2^-104 implies |expm1(x)|>2^-106. Nonzero log of a binary64 input, reduced exp plus one, and density on |d|≤6 have larger minima. The tiny expm1 branch returns its input and has its separate Taylor bound. Thus 2^80·2^-1074 < u²·2^-106 fits within the explicit spare margin; it does not reuse the higher-order inflation H. Exp’s final exponent restoration transports both the value and this error together, with the final component-rounding quantum accounted for separately.

This argument relies on the exact primitive witnesses for the executed inputs. It does not turn the fixed 32-quantum allowance into a theorem for arbitrary inputs.

## PR #12 source and assumption audit

The source comparison uses the original algorithm boxes and later corrections, not a secondary implementation's measured accuracy. The downloaded research artifacts below are identified by SHA-256 so the comparison is reproducible.

| Primary source | Version and SHA-256 | Audit result |
| --- | --- | --- |
| [Joldes–Muller–Popescu](https://hal.science/hal-01351529v3/document) | HAL v3; `2a820178d2ef079559de9940d7af38258fac24558d406be64779ea901486cbc0` | DD operations match Algorithms 4, 6, 9, 12 and 18. Finite-exponent assumptions remain explicit. |
| [Muller–Rideau formalization](https://hal.science/hal-02972245v2/document) | HAL v2; `099e710ab98c82227fe7a16610b7e283ff6d69f22e8d2887e06bc1dd8edabf8b` | Confirms the primitive bounds, with corrected proofs. Retaining 5u² for multiplication is conservative. |
| [Lefèvre et al., Euclidean norms](https://hal.science/hal-03482567v2/document) | HAL v2; `a60eb7edbf7e6ca4454d97f0c2a1eee89806093a6f487cb429c087678858ac93` | DD sqrt follows Algorithm 8. Split.sqrt now applies Algorithm 8’s Fast2Sum too; the unnormalized Algorithm 7 pair can violate the DD consumer precondition. |
| [Jäckel, Let's Be Rational source archive](http://www.jaeckel.org/LetsBeRational.7z) | downloaded 2026-10-02; `da2f6870b213e04ef35b4d309269ee5ce12be5830d9733e5f29542bf7b652470` | Kernel region formulas and thresholds were compared with the author's C++. Our scaling changes and solver modifications need their own analysis. |
| [Jäckel, Let's Be Rational paper](http://www.jaeckel.org/LetsBeRational.pdf) | downloaded 2026-10-02; `351a9e2cc603f8817be74a9719e5269bd61784fc7a3d36e2d7131fa25b1a104d` | The paper's reported accuracy does not prove convergence of every modified finite-exponent path here. |
| [QD 2.3.24](https://github.com/BL-highprecision/QD/blob/v2.3.24/src/dd_real.cpp) | release tag v2.3.24 | Historical reference for the removed exponential adaptation; see the source-provenance record and replacement report. |
| [Cody CALERF](https://netlib.org/specfun/erf) | canonical Netlib source | Historical implementation reference, replaced by the generated error functions; see the replacement derivation and provenance record. |

The non-ATM live-price and kernel replays now require the moneyness sign to be resolved by its interval; the ATM branch uses the full call/put derivative bound |∂b/∂x|≤exp(|x|/2)<2 on |x|<0.01, covering either sign of a true moneyness hidden by the rounded zero. This enforces the nonnegative tail-coordinate premise of the moment remainder rather than assuming it from the rounded center.

The audit corrected the negative-argument expm1 tail normalization (the majorant remains below 80u²), bound `Split.scaled_exp_neg` using its own stored ln(2) split, and extended the erfcx derivative inequality through the full allowed −0.01 endpoint. A zero-leading-term Greek branch now divides its uncertainty by a downward-rounded **lower** denominator bound.

`oracle/instrument_dd.py` copies the production bindings and inserts exact rational postconditions; it does not rewrite their arithmetic. Zarith is a test-only dependency. For a computed pair z, each primitive checks its exact discrepancy against ε(|z_hi|+|z_lo|)/(1−ε)+32·2^-1074; the product residual uses one quantum. Square root checks the squares of the two rational interval endpoints. These checks cannot establish correctness for unexecuted inputs, and do not by themselves prove a transcendental approximation or its composed underflow allowance. The analytical derivations and independent high-precision oracle remain necessary. Mutation runs retain these mathematical checks while disabling bit-replay checks.

The direct DD generator previously sampled low words symmetrically using ulp(hi), which can violate nonoverlap on the smaller-spacing side of a power of two. It now forms the exact rational sum and renormalizes both input words before evaluating the independent reference. The checker enforces the precondition instead of relying on that sampling assumption. It then exposed a production scaling defect: rounding a low word to the subnormal grid can create a halfway overlap with an odd high significand. DD scaling and the final split-quotient scaling now renormalize in this case; the extra Fast2Sum/TwoSum preserves the scaled pair’s sum exactly. Dedicated mutations remove the DD scaling repair and the split-root normalization. The latter was also exposed by enforcing nonoverlap on every component result; Split.sqrt now uses Algorithm 8’s final Fast2Sum.

Fixture provenance now pins transitive local generator imports. A partial rebuild preserves unselected records and refuses to rewrite the manifest if any unselected fixture is stale. Missing and duplicate records fail; deleting an imported dependency from a record also fails. The extra-bit Greek fixture was regenerated to record its `gen_greeks.py` dependency.

## Fast Greek result finiteness and retained maturity scaling

The [#62 derivation and qualification](finite-greek-results.md) distinguishes
finite-output validation from numerical accuracy. All ten model Greek fields
reject nonfinite payloads after unit conversion. A nonfinite intrinsic cannot
establish a zero payoff. BSM rho retains the maturity exponent until final
currency scaling, with the existing multiplication/exponential allowances and
matching certificate replay; no budget is widened. Independent exact-input
references also check finite results, including the corrected subnormal rho.

The [#77 refinement](rho-subnormal-design.md) additionally preserves the
probability correction at half-subnormal rounding boundaries. Selected BSM
rho results now require an original-input enclosure inside one nearest-even
cell, with explicit failure otherwise. Analytical zero proofs and scaled
Mills tails avoid losing the final product's scale. This does not certify
unselected normal-range fast rho. See the [qualification and availability
accounting](results-rho-midpoint.md).

## Fast Greek cancellation capability (#80)

The exhausted-coordinate selector from §5.1.1 also bounds the offered fast
Greek capability: selected requests refuse all fields before using those
coordinates. A computed zero without original-input ATM identity likewise
cannot establish a kink. Zero-volatility theta instead assembles
`q(A-C)+(q-r)C` in DD before currency scaling. Smooth theta has a separate
component-cancellation refusal where its DD leg subtraction loses precision;
only that field fails. These selectors are explicit capability restrictions,
not runtime error certificates for unselected results. See the
[derivation](greek-cancellation-design.md) and
[original-input qualification](results-greek-cancellation.md).
