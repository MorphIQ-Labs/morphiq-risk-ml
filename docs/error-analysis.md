# Error analysis

For each numerical path this document gives:
- where its error comes from;
- the bound the method gives;
- how the bound is measured;
- where the known limits are.

ε is 2^-53, the binary64 unit roundoff, and "DD" is double-double, about 2^-104 relative. The measured worst cases are in docs/results-*.md, and the budgets that enforce them are in the oracle scorers.

These are analyses with measured envelopes, not machine-checked proofs. Where a bound is only measured over the oracles' grids and random samples, this says so.

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

**Domain.** The bounds assume no underflow or overflow. `div` computes `1/b.hi`, which overflows for a subnormal divisor, so it first scales b exactly into [1, 2) by a power of two and scales the quotient back. That keeps the computation inside the theorem's domain whenever the quotient itself is normal. Results that fall into the subnormal range carry absolute rather than relative error, and are rounded once by `to_float_scaled`.

## 1. Elementary functions (`Internal.Elementary`)

| Function | Construction | Error sources | Measured |
| --- | --- | --- | --- |
| exp | k = round(x/ln 2), r = x − k·ln2_hi − k·ln2_lo by fma; e^r − 1 by a degree-14 Taylor/Horner series; 1 + (e^r − 1); ldexp | `ln2_hi` has 32 significant bits, so `k·ln2_hi` is exact for \|k\| < 2^20, and the reduction's error is \|k\|·ulp(ln2_lo)/2 ≤ 2^-80 absolute. Truncation is < 2^-60 relative on \|r\| ≤ ln 2/2. Horner rounding is O(ε·\|r\|) relative, and one rounding comes in 1 + em1. | ≤ 1 ULP over 31k arguments |
| expm1 | \|x\| ≤ 1: the series to degree 21, with truncation 1/22! < 2^-70. Otherwise 2^k(1 + em1) − 1. | Horner rounding is relative, because no cancellation happens at the leading term. | ≤ 1 ULP |
| log, log1p | m ∈ [√½, √2), f = m − 1 (exact, Sterbenz); 2·atanh(u) with u = f/(2 + f) and its fma remainder | Series truncation is < 2^-60 relative. Carrying u's remainder removes the quotient's rounding from the leading 2u. log adds e·ln2_hi exactly. | ≤ 1 ULP over 49k arguments |

**log1p's derived bound.** For |f| < 2^-54, log1p returns f, which is correctly rounded because f²/2 < ulp(f)/4 (fdlibm `s_log1p.c`); below that, the reduced path's u = f/2 would underflow. On the reduced path, f ∈ [√½ − 1, √2 − 1] and |f| ≥ 2^-54, the result is z = RN(2u + T) with y = 2·atanh(w), w = f/(2 + f). Apart from that final rounding, the error is at most 0.085·u·|y| (u = 2^-53):

| Source | Bound, × u·\|y\| |
| --- | ---: |
| The tail evaluated at u rather than w | 0.030 |
| The tail's evaluation: coefficients, Horner, v = u², the products | 0.036 |
| Series truncation (< 2^-60 relative) | 0.0078 |
| Rounding of T | 0.0098 |
| ul's computed error | ≈ 4u, negligible |

So |z − y| ≤ ulp(z)/2 + 0.085·u·|y|. The scorer checks this against a reference that carries its residual (exact − reference). Measured worst: 0.5205 ULP from exact. Without the quotient remainder ul, the leading 2u carries up to another u·|y|, and the bound fails.

**Determinism.** These use only IEEE basic operations and fma, which every conforming platform rounds the same way (docs/determinism.md).

**Double-double exp and expm1** (`Internal.Dd`) follow the QD library (Hida, Li and Bailey, qd-2.3.24 `dd_real::exp`): m = round(x/ln 2), r = (x − m·ln 2)/512, the Taylor series of e^r − 1 until a term falls below 2^-104/512, then nine doublings s ← 2s + s². The reduction's error, about |x|·2^-105 absolute in r, is relative error in e^x. A pinned mpmath test (`test/dd_reference.ml`) measures exp within 2^-100 + |x|·2^-105. Unlike QD, exp continues into the subnormal range, where the low part underflows.

**Double-double log** stays the atanh series on m ∈ [√½, √2]. QD's log, a Newton step x + m·e^(−x) − 1, has absolute error near 2^-104, which is unbounded relative error as ln m → 0. ln(S/K) for S ≈ K needs relative accuracy there: the QD form put a zero-variance price 21 ULP off.

## 2. The normal distribution

- **Φ(x) outside Cody's first interval** is `½·erfcx(|x|/√2)·exp(−x²/2)`. erfcx uses Cody's rationals, whose stated relative error is below 10^-18 before rounding. The half-square is split exactly (`x² = hi + lo` by fma), so the exponential's argument carries no rounding.
- **Why that matters in the tail.** The naive form's relative error grows like ε·x², which is 5.7e-14 at x = −38, the FerroRisk budget. Here the remaining error is the rounding of erfcx, exp and two products: ≤ 4 ULP measured over the whole range, tails included.
- **Φ⁻¹ is AS241.** The central branch evaluates only polynomials, so it is reproducible. The tails add one `log`: ≤ 4 ULP measured.
- **The double-double Φ and φ** (`Normal_dd`, |d| ≤ 6) use Marsaglia's series, whose terms all share a sign. For d < 0 the final ½ − … loses log₂(1/(2Φ(d))) bits, about 30 at −6, giving a relative error ≤ 2^-100/(2Φ(d)). A pinned mpmath test checks that.

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

**Attainable accuracy (Jäckel).** b is a function of its inputs. With them exact, its relative condition in s is |s·b′/b|, so a rounded s alone costs (1 + |s·b′/b|)·ε. The library carries s = σ√T in DD, so s contributes no error of its own.

## 5. Price assembly

- **Black family.** V = 2^e·(θ·intrinsic⁺ + √A·√C·b(−|x|, s)), with (S, K) scaled exactly by 2^-e, e = ⌊(e_S + e_K)/2⌋.
  - Floor division makes the scaling equivariant, so V(2^j S, 2^j K) = 2^j V(S, K) exactly. A property test checks this.
  - The out-of-the-money part applies 2^e inside the exponential (Cody–Waite 2^-n·e^-r), so it rounds once.
- **Intrinsic θ(A − C)** comes from DD legs, `S·exp_DD(−qT)` and `K·exp_DD(−rT)`:
  - as C·expm1(x) when |x| ≤ 0.35 and x's terms are ≤ 1, with error 2^-104·C·(|ln S/K| + |(r−q)T|);
  - otherwise as A − C, with error 2^-104·A.

  It is then rounded once, including into the subnormals (`Dd.to_float_scaled`). The zero-variance price is that value, and the inverse classifies quotes against the same DD value.
- **Bachelier.** V = D·(θΔ⁺ + s·φ(d)·Y′(−|d|)), with Y′ = 1 + h·Φ(h)/φ(h) from Jäckel's Remez rationals. This avoids subtracting φ(d) − |d|Φ(−|d|). d = Δ/s is carried in DD, and D·θΔ is DD.

**Measured.** Worst errors per region are 1–23 ULP on this project's 57k-contract oracle, and 1–15 ULP on the 41,760-contract displaced oracle.

### 5.1 The intrinsic's certified error, and the zero-variance price

The intrinsic I = A − C is formed in double-word. Its error E composes the proved primitive bounds (§0) with the component bounds that `test/dd_reference.ml` enforces: ε_exp(z) = 2^-100 + |z|·2^-105 for exp and expm1, and ε_log = 2^-100 for log. Those two are measured envelopes, not proofs. With L = |ln S/K| and C_y = |(r − q)T|:

- **x** = ln q + (ρ − ρ²/2) + (r − q)T, plus displaced Black's low parts:
  E_x ≤ ε_log·L + 15u²·|ρ| + 9u²·(L + C_y) + E_low, with |ρ| ≤ u, and E_low ≤ 5u² for displaced Black (its sums' low parts enter to first order).
- **C·expm1(x):** E ≤ A·E_x + |I|·(ε_exp(x) + ε_exp(rT) + 10u²), since C·e^x = A.
- **A − C:** E ≤ A·(ε_exp(qT) + 5u²) + C·(ε_exp(rT) + 5u²) + 3u²·|I|.

The code takes C·expm1(x) when |x| ≤ 0.35 and L + C_y ≤ 1: there its bound is the smaller of the two. The zero-variance price is I rounded once, so against the correctly rounded reference R, |V − R| ≤ ulp(V)/2 + ulp(R)/2 + E. The price scorer checks this per row (`test/bounds.ml`). On both fixtures no row uses any of E: every served value is within the two half-ULP roundings.

**Two mechanisms a test cannot decide.** Carrying ρ in double-word removes a u² term from E_x, which is below ln q's own certified error. The branch rule chooses the smaller certified bound, and the other branch's realized error stays inside it. Both are justified by this analysis, but no input can make their removal violate a bound, so the mutation catalog (`scripts/mutation/`) does not include them.

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

**Bound (Black family).** The quote is exact. The inverse rounds β (or β̄ near the maximum) once, and takes one Newton step against the kernel. LBR's two Householder steps leave the start accurate to working precision (Jäckel 2015, 2024), so the step's quadratic term is below u². With s the exact normalised root and b′ = ∂b/∂s, the relative error in σ is at most

3u + (δβ + κ)·c

- **3u** covers σ = s/√T, with √T's low part.
- **δβ** is the error in β. Below the money δβ = u. In the money, β = (quote − I)/m carries the intrinsic's error E (§5.1), so δβ = u + (E + 3u²·quote)/(quote − I). That term dominates for quotes just above the intrinsic.
- **c and κ, by branch:**
  - β ≤ b_max/2: c = b/(s·b′), and κ = 64u, the kernel's component bound (the price oracle's enforced 32 ULP for out-of-the-money values; a measured envelope).
  - β > b_max/2: c = b̄/(s·b′), and κ = 17u. Here b̄ = ½·e^(−(h²+t²)/2)·(erfcx(q₁) + erfcx(q₂)) with q₁, q₂ ≥ 0, because s² > 2|x|. The 17u is 8u from erfcx's 4-ULP component bound, 3u from the arguments, u for the sum and 5u for the scaled exponential.
  - β < 2^-900, Newton on ln b: c = b/(s·b′) times the absolute error in ln β − ln b. That error comes from `Elementary.log` (1 ULP each) and the kernel (64u).

The IV scorer checks |σ − σ*| ≤ bound·σ* + ulp(σ*)/2 per root (`test/oracle_iv.ml`). It no longer accepts a root merely because it lies in the quote's rounding cell. Near the maximum that cell is unbounded above, and a mutant that dropped the final correction returned roots 8e14 ULP off while staying in the cell.

**Bachelier** keeps "in the rounding cell or within 4 ULP" until its bound is derived. Its inverse loses precision for subnormal quotes, where the price evaluation's rounding is absolute: two roots are 1e6 ULP from the exact root, inside a cell the 8-bit quote makes wide.

**Measured.**
- Over 3,000 random contracts (`test/properties.ml`), the worst root error among roots that don't reprice exactly is 2.10× Jäckel's attainable accuracy (1 + |b/(s·b′)|)·ε.
- Every outcome class matches on the grid oracles.

## 7. Greeks

Each Greek is an ordinary part plus P·exp(−(h² + t²)/2)·2^k, with every algebraic factor folded into the prefactor P and the exponential applied last. Φ enters through the Mills ratio, so in the tails all terms share one exponential and nothing underflows early.

Brackets that cancel near the money are evaluated in DD, using `Normal_dd` for Φ and φ and the DD legs:
- theta: θ(qAΦ(θd1) − rCΦ(θd2)) − Aφ(d1)σ/(2√T);
- charm: θqΦ(θd1) − φ(d1)·∂d1/∂T;
- veta and color: q + d1·∂d1/∂T ∓ 1/(2T), with veta's form scaled by √T so it stays finite where 1/T is not.

Terms in 1/T are rewritten so that √T and σ cancel analytically.

**Measured.** Every Greek's worst case is ≤ 6 ULP against an oracle that requires a closed-form route and mpmath differentiation of the price to agree. Away from the deep tails, finite differences of the served price agree to 1e-7 over random contracts.

## Known limits, collected

| Where | Limit | Status |
| --- | --- | --- |
| Region III's erfcx difference | 10–23 ULP worst, the method's own | within budget (32); a DD erfcx difference would remove it |
| Component bounds for the double-word exp, expm1 and log, and for the kernel | measured envelopes (2^-100; 32 ULP), not proofs | the derived price and IV bounds compose them; deriving them is open |
| Bachelier implied volatility | no derived bound; subnormal quotes lose precision | "in cell or 4 ULP" until derived |
| x's terms cancelling below about 1e-16 of themselves | x carries 2^-104·(terms) absolutely; the zero-variance price switches to A − C | measured 1 ULP; a deeper cancellation needs triple-double |
| Implied volatility | (1 + \|b/(s·b′)\|)·ε relative in σ, which can exceed a narrow rounding cell | measured 2.10× the bound |
| Bounds generally | Measured over grids and fixed-seed random samples, not proved for all inputs | stated as envelopes in the stability policy |
