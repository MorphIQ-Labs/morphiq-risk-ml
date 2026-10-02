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

The cited algorithms are also summarized, with later formalized bounds, in [Muller, Floating-point arithmetic, §5](https://doi.org/10.1017/S0962492922000101). We retain the conservative 5u² multiplication bound; that review gives the tighter 4u² for DWTimesDW3.

## 1. Elementary functions (`Internal.Elementary`)

| Function | Construction | Error sources | Measured |
| --- | --- | --- | --- |
| exp | k = round(x/ln 2), r = x − k·ln2_hi − k·ln2_lo by fma; e^r − 1 by a degree-14 Taylor/Horner series; 1 + (e^r − 1); ldexp | `ln2_hi` has 32 significant bits, so `k·ln2_hi` is exact for \|k\| < 2^20, and the reduction's error is \|k\|·ulp(ln2_lo)/2 ≤ 2^-80 absolute. Truncation is < 2^-60 relative on \|r\| ≤ ln 2/2. Horner rounding is O(ε·\|r\|) relative, and one rounding comes in 1 + em1. | ≤ 1 ULP over 31k arguments |
| expm1 | \|x\| ≤ 1: the series to degree 21, with truncation 1/22! < 2^-70. Otherwise 2^k(1 + em1) − 1. | Horner rounding is relative, because no cancellation happens at the leading term. | ≤ 1 ULP |
| log, log1p | m ∈ [√½, √2), f = m − 1 (exact, Sterbenz); 2·atanh(u) with u = f/(2 + f) and its fma remainder | Series truncation is < 2^-60 relative. Carrying u's remainder removes the quotient's rounding from the leading 2u. log adds e·ln2_hi exactly. | ≤ 1 ULP over 49k arguments |

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

The construction follows [QD 2.3.24, dd_real.cpp](https://github.com/BL-highprecision/QD/blob/v2.3.24/src/dd_real.cpp): reduction by 512, Taylor accumulation and nine doublings. Our factorial coefficients are generated by DD division, unlike QD's literals, so their error must be included. QD is an algorithm reference, not a proof of the following bounds.

Write A = 3u²+13u³, M = 5u², D = 9.8u². A product of n error factors is bounded using `(1+e)^n−1`, not by dropping higher-order terms. For the estimates below we additionally multiply by H = 1/(1−100000u). This exceeds the products of fewer than 1000 roundoff factors and the reciprocal perturbations of the denominators (all at least 0.97, except the explicitly treated cancellation). It is an analytical rounding allowance, not an observed maximum.

After reduction |r| < R = 0.0007. The relative Taylor arithmetic bound, in u² units, is

    S = ((1+A)^7−1)/u² + 5R/2
        + (40 + ((1+D)^8−1)/u²) R²/[6(1−R)].

Seven additions cover the quadratic term and terms through degree 8. Each generated factorial needs at most eight divisions; eight power/product errors give the 40 term. For negative r, partial-sum magnitudes can exceed the final magnitude: multiply S by 1.001 (> 1/(1−R)). The relative omitted tail is bounded by the larger of

    R^8/[9!(1−R/10)]
    2^-113/[5(1−R/6)].

The second expression treats early stopping: the tested small term is included before the loop exits. For doubling `s <- 2s+s²`, each addition contributes A; each multiplication is weighted by |s|/(2−|s|). The sum of these weights over nine doublings is below 0.24. Relative error transport through the whole doubling sequence is below 1.21, since |512r| ≤ 0.347 and |z exp(z)/expm1(z)| < 1.21. Consequently

    H × 1.21 × [1.001 S + max(tails)/u² + 9A/u² + 1.2]
      = 75.155662471… < 80.

This gives **ε_expm1 = 80u²** on |x| ≤ ln(2)/2. The tiny branch |x| < 2^-104 returns x; its omitted relative term is < 2u² and avoids losing x in division by 512.

For exp, adding 1 weights the expm1 error by |expm1(z)|/exp(z) < 0.416. The two-word ln(2) constant has relative error < u²/4; `verify_bounds.py` establishes this with a rational atanh(1/3) enclosure. Reduction contributes at most (2+3|x|)u²: the DD constant product contributes 2.25|m ln 2|u², and the DD subtraction contributes A|x−m ln 2|. Thus the majorant is **ε_exp(x) = (40+3|x|)u²**: H(0.416×80+3+2) < 40.

Outside the direct expm1 interval, subtraction of 1 gives

    ε_expm1(x) = ε_exp(x) exp(x)/|expm1(x)| + 4u².

These are relative bounds before final exponent scaling, for finite outputs and normalized input pairs in the exp implementation's range. Add an absolute quantum for component underflow. They do not assert a pure relative guarantee in the subnormal range. The 80u² bound is larger than the old measured 64u² envelope: the degree-8 truncation and generated coefficient errors cannot be omitted merely because the observed errors are small.

### 1.3 Double-word log

For m ∈ [√½,√2], w=(m−1)/(m+1), v=w² < V=0.0296. The numerator is exact by Sterbenz and the denominator is an exact DD sum. The atanh series has positive coefficients, allowing geometrically weighted error propagation even for m close to 1. In u² units a reduced bound is

    H [9.8/(1−V) + 3/(1−V) + 5V/(1−V)
       + 9.8V/[3(1−V)] + 5V/[3(1−V)²] + 5
       + V^23/[47(1−V)u²]] < 20.

The terms cover the quotient parameter, Horner additions/products, generated reciprocals, squared parameter, final product and truncation. In recombination, |ln m|/|ln a| ≤ 1 and |e ln 2|/|ln a| ≤ 2. The constant product costs (2+1/4)u², and the final DD addition costs A. Therefore **ε_log = 32u²**, above H(20+2×2.25+3) = 27.500000001…. `log_float` accepts one binary64 argument; exp/expm1 tests exercise both input words.

QD's Newton log has absolute error near zero. Its relative error is unbounded as ln m tends to zero; this library needs relative accuracy for near-unit spot/strike ratios. That is why the atanh construction remains.

### 1.4 Independent checking

`dd.txt.gz` contains 24,451 three-word reference expansions, including 13,041 nonzero input low words, reduction boundaries, subnormals and exponent extremes. Generation at 110 and 220 digits agrees on all reference words; tiny arguments receive additional precision. A separate exponent keeps oracle errors representable. The scorer uses an independent error-free expansion sum, so high-word disagreement cannot erase the low-word discrepancy; it does not use the library's DD subtraction. It accounts for oracle expansion error, its own roundoff and final component underflow, and rejects NaN/infinity. These tests check the analysis against examples; agreement of two mpmath precisions is not an interval proof.

## 2. The normal distribution

- **Φ(x) outside Cody's first interval** is `½·erfcx(|x|/√2)·exp(−x²/2)`. erfcx uses Cody's rationals, whose stated relative error is below 10^-18 before rounding. The half-square is split exactly (`x² = hi + lo` by fma), so the exponential's argument carries no rounding.
- **Why that matters in the tail.** The naive form's relative error grows like ε·x², which is 5.7e-14 at x = −38, the FerroRisk budget. Here the remaining error is the rounding of erfcx, exp and two products: ≤ 4 ULP measured over the whole range, tails included.
- **Φ⁻¹ is AS241.** The central branch evaluates only polynomials, so it is reproducible. The tails add one `log`: ≤ 4 ULP measured.
- **ln Φ composed from Φ.** The enforced CDF envelope is 6 ULP to a rounded reference, hence 6.5 spacings to the real value. The scorer evaluates the actual inner CDF and uses the largest spacing in its neighbourhood, including binade crossings. With this error E, the mean-value denominator is `1−Q−E` or `Φ−E`, not the central value. The outer evaluator and oracle rounding contribute `2 ulp(got)+ulp(reference)/2`. This is conditional on the measured CDF and elementary envelopes. A nonpositive denominator is unresolved and fails; it is never accepted as an infinite bound.
- **The double-double Φ and φ** (`Normal_dd`, |d| ≤ 6) use Marsaglia's series, whose terms all share a sign. For d < 0 the final ½ − … loses log₂(1/(2Φ(d))) bits, about 30 at −6, motivating a cancellation-scaled **measured** envelope 2^-100·max(1,1/(2Φ(d))). The 13-point pinned test checks that envelope; it is not a derived bound for the series. This remains a proof gap for the cancelling Greeks.

## 3. Log-moneyness x = ln(A/C) = ln(S/K) + (r − q)T

x is computed in DD:
- ln q for q = fl(S/K), by the atanh series (2^-104 relative);
- the quotient remainder ρ = (S − qK)/(qK), with S − qK exact by fma and ρ itself in DD, plus −ρ²/2;
- (r − q)T as two exact products (two_prod);
- for displaced Black, F + d and K + d as exact sums, with their low parts added as Sl/S − Kl/K.

The absolute error is about 2^-104·(|ln(S/K)| + |(r − q)T|).

**Consequence.** A price depends on x through ∂ln V/∂x. That derivative is about |h|/s in the out-of-the-money tail (h = x/s) and 1/|x| for the zero-variance price. So the tail error stays about ε until |h|·(|ln S/K| + |(r−q)T|)/s approaches 2^51, and the zero-variance price is limited where x itself cancels.

**Known limit.** A forward placed at the strike through carry has x ≈ 1e-16 of its terms. Its zero-variance price is then taken as A − C from the DD legs instead (§5), because C·expm1(x) would inherit x's 2^-104·|terms| error.

## 4. The normalised Black function b(x, s), out of the money (x ≤ 0)

The kernel uses Jäckel's three regions (η = −13, τ = 2ε^(1/16)):
- **Regions I and II.** b = vega·(b/vega). The scaled function comes from Jäckel's asymptotic or small-t expansion, accurate to about ε/2 by his analysis. The vega, `exp(−(h² + t²)/2)/√(2π)`, is evaluated with h = x/s in DD (including x's and s's low parts) and the exponent split exactly. The exponential is applied last with any prefactor folded in, so a value rounds once even in the subnormals. A direct mpmath probe of Region I measures about 1 ULP.
- **Region III** is `½·exp(−(h² + t²)/2)·(erfcx(q1) − erfcx(q2))` with Cody's erfcx, or the erfc forms.

**Known limit.** Where q1 and q2 are both above Cody's threshold, the erfcx difference cancels by up to about 6×. The worst case is 10–23 ULP, around h ≈ −4.6, s ≈ 1 at strikes of 1e-150. FerroRisk's reference for that case checks out to 4.7e-17 against mpmath at 200 digits, so the error is the method's own. Jäckel's reference has the same limit.

**Attainable accuracy (Jäckel).** b is a function of its inputs. With them exact, its relative condition in s is |s·b′/b|, so a rounded s alone costs (1 + |s·b′/b|)·ε. The library carries s = σ√T in DD, so its input formation contributes DD error rather than binary64 rounding; that contribution is small, not identically zero.

## 5. Price assembly

- **Black family.** V = 2^e·(θ·intrinsic⁺ + √A·√C·b(−|x|, s)), with (S, K) scaled by 2^-e, initially e = ⌊(e_S + e_K)/2⌋. For |x| < 2^-500 and small x terms, the exponent is lowered by 512 to retain tiny intrinsic products; this depends only on dimensionless quantities.
  - Floor division makes the scaling equivariant, so V(2^j S, 2^j K) = 2^j V(S, K) exactly. A property test checks this.
  - The out-of-the-money part applies 2^e inside the exponential (Cody–Waite 2^-n·e^-r), so it rounds once.
- **Intrinsic θ(A − C)** comes from DD legs, `S·exp_DD(−qT)` and `K·exp_DD(−rT)`:
  - as C·expm1(x) when |x| ≤ 0.35 and x's terms are ≤ 1, with error 2^-104·C·(|ln S/K| + |(r−q)T|);
  - otherwise as A − C, with error 2^-104·A.

  It is then rounded once, including into the subnormals (`Dd.to_float_scaled`). Equal-coordinate zero-variance contracts with max(|r|,|q|)T < 2^-500 instead form S(r−q)T from mantissas and accumulated exponents. The omitted relative term is < 2^-499. This covers carry below the binary64 range while the currency price is normal. For example S=K=2^1000, T=2^-1074, r=1, q=0 changed from 0 to 2^-74. This special price path does not establish exact inverse classification at these exponent extremes; inverse classification still uses the DD legs.
- **Bachelier.** V = D·(θΔ⁺ + s·φ(d)·Y′(−|d|)), with Y′ = 1 + h·Φ(h)/φ(h) from Jäckel's Remez rationals. This avoids subtracting φ(d) − |d|Φ(−|d|). d = Δ/s is carried in DD, and D·θΔ is DD.

**Measured.** Worst errors per region are 1–23 ULP on this project's 57k-contract oracle, and 1–15 ULP on the 41,760-contract displaced oracle.

### 5.1 The intrinsic's analytical error budget, and the zero-variance price

The intrinsic I=A−C is formed in DD. With the component majorants above, L=|ln(S/K)| and C_y=|(r−q)T|, the normal-intermediate analysis is:

- E_x ≤ ε_log |ln RN(S/K)| + 15u³ + 9u²(L+C_y) + E_low, with E_low ≤ 5u² for displaced inputs. For a quotient outside the normal range, use |ln S|+|ln K| in the log term.
- C·expm1(x): E ≤ A E_x + |I|[ε_expm1(x)+ε_exp(rT)+10u²].
- A−C: E ≤ A[ε_exp(qT)+5u²] + C[ε_exp(rT)+5u²] + 3u²|I|.

The code uses expm1 for |x|≤0.35 and L+C_y≤1. This is a conservative validity rule, **not an optimizer of the two bounds**; the crossing depends on the component constants and contract. The scorer checks |V−RN(I)| against E and both final half-ULP roundings. It considers both branches within the rounding uncertainty of a threshold. These formulas are not a universal finite-exponent certificate: intermediate underflow and unresolved cancellation require separate treatment.

**Mutation evidence.** Rounding the quotient remainder to one word now fails the independent coordinate corpus (`quotient-remainder`). Near S/K=1 the log term is small enough to distinguish it. The old assertion that no test could distinguish this was false. Removing the intrinsic terms guard still survives the current price corpus under the revised bounds. Run `dune exec scripts/mutation/mutation.exe -- --probe intrinsic-terms` to reproduce that specific result. The exclusion is provisional; a survivor is not a proof of equivalence or impossibility.

### 5.2 Measured price regression envelopes

The remaining 8–32 ULP budgets are measured envelopes, not consequences of the DD theorems. Both the ULP gate and the normwise gate are enforced; there is no longer an “any row within 4 ULP passes” bypass. For Bachelier the scale now includes D σ√T/√(2π), since its time value is unbounded relative to the discounted forward/strike. This changes the norm to match the model instead of bypassing the test when that scale was too small.

## 6. Implied volatility

1. **Classification.** The quote is compared, to about 2^-104, with the DD intrinsic and the DD maximum.
2. **Normalisation.**
   - β = (quote − intrinsic⁺)/√(AC) and β̄ = (maximum − quote)/√(AC) are formed from the DD legs, then rounded once.
   - ln β is taken from the unscaled quote, because a subnormal quote loses bits when rescaled.
3. **Inversion.** Jäckel's Let's Be Rational: a four-branch rational-cubic initial guess, then two Householder steps whose objectives are chosen per branch for conditioning.
4. **Correction.** One Newton step with the extended-precision kernel:
   - on b̄ when β > b_max/2;
   - on ln b when β < 2^-900;
   - on b otherwise.

### 6.1 Conditional Black root budget

The error requirement composes normalization error with a kernel envelope. It does not claim that two Householder steps plus Newton converge for every representable contract. In particular, the former assertion that the Newton quadratic remainder is below u² did not follow from a citation to Jäckel. The scorer now transports error using the minimum vega over the candidate/reference interval. Black vega has one maximum as volatility varies, so that minimum is at an endpoint; the mean-value theorem then handles nonlinear transport without discarding a quadratic term.

At the reference root the relative budget is `3u + (δβ+κ)c`, with the conversion allowance 3u and c=b/(s b′) or b̄/(s b′). The endpoint-vega ratio inflates this before comparison with the exact-root oracle. Nonfinite error or allowance fails.

- **Ordinary branch:** δβ=u below the money; above it add `(E_I+3u² quote)/(quote−I)`. κ=65u remains conditional on the measured 32-ULP kernel envelope (including the reference half-ULP); it is not a published theorem for this implementation.
- **Complement:** use the maximum-leg error, not the intrinsic error. If M is the DD maximum, set E_M=|M|[ε_exp(rate·T)+5u²] and g_lower=(M−quote)−E_M−2u|M−quote|. The normalization error includes `u+E_M/g_lower`, the two discount exp bounds and 32u² for DD assembly. If g_lower≤0 the bound is unresolved and rejected. Five independently generated near-maximum ATM roots expose the old omission: one was about 360 times outside the old allowance.
- **Logarithmic branch:** β<2^-900 uses the absolute log-normalization error and the kernel envelope, transported by b/(s b′).

**Complement kernel derivation.** At s²=2|x| the normalized price is below b_max/2; monotonicity then implies t+h>0 whenever β>b_max/2. Thus both erfcx arguments are nonnegative, and their sum has no cancellation. The integral representation of erfcx gives

    |d log(erfcx(z))/dz| ≤ min(2/√π, 1/z), z≥0.

For each z=(t±h)/√2, rounded division/addition and the √½ constant give an absolute perturbation at most δz=4u(t+|h|)/√2. Use 1.129 near zero, otherwise min(1.129,1/(z−δz)), to cover the whole argument interval. This replaces the unsupported constant 3u argument estimate. The implemented budget is

    κ = 21u + δz·max(argument sensitivities)
        + u²(16E+8E²), E=(h²+t²)/2.

The 21u allows 9u for a 4-ULP-to-rounded-reference erfcx envelope, u for the positive sum, 3u for a 1-ULP exponential envelope, and 8u for the scaled product/reduction assembly. The final term allows DD exponent error and the exponential perturbation's second order. This composition remains **conditional**: the binary64 erfcx/scaled-exponential component envelopes and the assembly bound have not been proved uniformly. It replaces the unexplained 17u claim; it is not a completed universal certification of that path.

**Branch uncertainty.** An error δ in β changes ln β by at most −log(1−δ). The scorer adds rounding in reconstructing x and the threshold, and evaluates every overlapping branch. The previous arbitrary 1e-6 guard is gone.

### 6.2 Bachelier and round trips

Bachelier no longer accepts “in the rounding cell or within 4 ULP.” It propagates an absolute price uncertainty through the minimum vega between candidate and exact reference. With J the positive intrinsic, O the time value, u=2^-53,

    E_price = J[ε_exp(rT)+8u²] + 19u O + 2^-1074.
    E_sigma = [E_price + 8u σ_hi vega_hi]/vega_lo + ulp(reference)/2.

The 19u is conditional on the measured 8-ULP price envelope (17u to the real value), plus two normalization roundings. The stopping test and final conversion contribute the 8u displacement allowance. Bachelier vega is increasing in σ, so endpoint vegas enclose the full interval. The absolute quantum is essential for subnormal quotes: their relative precision can be much less than 53 bits. This derives error transport, not a universal proof of the price kernel or the 200-iteration convergence limit.

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

**Measured.** Every Greek's worst case is ≤ 6 ULP against an oracle that requires a closed-form route and mpmath differentiation of the price to agree. Away from the deep tails, finite differences of the served price agree to 1e-7 over random contracts.

## Certification status and remaining proof obligations

| Layer | What is established | What is still missing |
| --- | --- | --- |
| DD primitives | published normal-intermediate theorems; two-operand/even-exponent normalization; subnormal regressions | a formal finite-exponent proof covering arbitrary low words and every call site |
| DD exp/expm1/log | written analytical majorants, exact-rational checks, dense two-word corpus | independent/formal verification of the complete implementation |
| Reduced log1p | corrected 0.14 majorant with positive margin; fractional-ULP oracle | whole-domain elementary guarantees beyond the reduced path |
| Ordinary Black kernel and price regions | strict measured 8–32 ULP regression gates, no 4-ULP bypass | a uniform rounded Cody/Jäckel kernel analysis, including Region III cancellation |
| Complement/IV | maximum-gap error included; argument sensitivity, threshold and nonlinear transport explicit | component envelopes and convergence are still conditional |
| Normal_dd and non-rho Greeks | independent price differentiation, finite-difference checks, named cancellation mutants | DD normal-series proof, then per-Greek operation/conditioning bounds; current power-of-two ULP budgets remain measured |
| Bachelier IV | conditional price-to-root bound, with subnormal quantum; no rounding-cell acceptance | uniform price-kernel and finite-iteration proof |
| Random IV recovery | forward and inverse errors composed on identifiable inputs | inherits the component envelope premises |
| Intrinsic branch rule | valid conservative rule; explicit surviving probe | a discriminating corpus/bound or proof of equivalence; no impossibility claim |

Consequently the complete library is **not certified for all finite admitted inputs**. In particular, “all remaining measured budgets have been derived” would be false. Closing those rows requires analysis of the rounded rational kernels and cancelling Greek expressions, followed by extra-bit references, scorer changes, and mechanism-specific mutations. Existing measured gates remain enforced while these obligations are open.
