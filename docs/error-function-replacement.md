# Generated error functions: derivation and qualification contract

Candidate replacing CALERF under #64, based on main `d799144fa2783185f038b1f9730a23863173804b`.
This document fixes the construction and budgets before scoring the candidate.
The 40u erfcx and 26u small-erf analytical ceilings, existing normal ULP gates,
and downstream price/Greek/IV requirements remain unchanged.

## Mathematical source and coefficient provenance

Start from f(x)=exp(x²) erfc(x)=2/sqrt(pi) integral_0^infinity exp(-t²-2xt) dt.
The integral follows by translation in the defining complementary Gaussian
integral; see [NIST DLMF 7.7](https://dlmf.nist.gov/7.7). Differentiation gives
f'=2xf-2/sqrt(pi), and complete monotonicity on x>=0. No CALERF coefficients,
interval constants or implementation text are reused. Existing historical
source notices remain; this is independently derived work after inspecting
CALERF, not a clean-room claim.

`oracle/erf_coefficients.py` uses exact fractions only. It encloses 1/sqrt(pi)
with the existing Machin/integer-square-root construction. For centers below 2,
even/odd Taylor polynomials of exp(-2xt), integrated against exp(-t²), bracket
f. Their coefficients satisfy a0=1, a1=-2/sqrt(pi), n a_n=2 a_(n-2).
For centers >=2, positive moments I_n=integral t^n exp(-t²-2xt) dt give
R_n=I_n/I_(n-1)=(n/2)/(x+R_(n+1)) and f=c/(x+R_1). A positive final ratio lies
between zero and infinity; alternating Möbius maps give adjacent finite
continued-fraction bounds. This is the Gaussian continued fraction
([DLMF 7.9](https://dlmf.nist.gov/7.9)), generated from the integral recurrence.
There is no upstream coefficient table or runtime continued fraction.

Local coefficients satisfy a1=2c0 a0-2/sqrt(pi) and
n a_n=2c0 a_(n-1)+2 a_(n-2). Interval propagation accounts for cancellation.
Every stored binary64 coefficient requires both rational enclosure endpoints
to round to the same word. Thus coefficient identity has a rational witness,
not just agreement between two numerical precisions.

## Piecewise construction

On [0,12), use 48 intervals of width 1/4, with centers (2i+1)/8 and degree 16.
The largest offset is 1/8. Taylor's integral remainder is bounded by
|a17(0)| (1/8)^17 because the derivative magnitude decreases on the positive
axis; f(x)>1/25 here. Local coefficients are evaluated by explicit FMA Horner. The leading coefficient
retains a second generated word; the tail and this residual are combined before
adding its high word, so the initial coefficient rounding is not lost.
Only the first cell can have an inexact subtraction from its center; its
absolute argument error is at most u/8. The verifier includes that contribution,
coefficient enclosures and coefficient-weighted Horner rounding. Intermediate
polynomials remain bounded; subnormal offsets have a separate absolute quantum
allowance transported through a contracting Horner chain.

For x>=12, expand exp(-t²) under the positive Laplace integral. The degree-12
polynomial in w=1/x² has exact coefficients (-1)^k (2k-1)!! / 2^k.
Taylor's integral remainder is bounded by the first omitted term, including
its sign; no convergence of the infinite asymptotic series is assumed.
The relative remainder at 12 is below 0.000762u. For x>=2^27 the omitted
correction is <=1/(2x²)<=u/4, so use c/x directly, including subnormal results.
See [DLMF 7.12](https://dlmf.nist.gov/7.12) for the asymptotic identity.

Small erf uses x times the degree-13 polynomial in x² from integrating
exp(-t²), on |x|<=1/2. Its alternating remainder, rounded coefficients,
squared argument, weighted FMA errors and final multiplication are bounded
separately. This retains relative accuracy as x tends to zero, plus an
absolute quantum for underflow. Existing 26u certificates are preserved.

For positive erfc, split x² with an explicit FMA and apply the existing scaled
exponential to f(x). This preserves subnormal results instead of importing
CALERF's machine-dependent flush. A derived cutoff at 28 has erfc below half
a subnormal quantum. Negative erfc uses symmetry. Negative erfcx reconstructs
2 exp(x²)-f(-x) using the qualified DD exponential and the exact square split;
x<=-27 is safely beyond binary64 overflow. erf uses odd symmetry and 1-erfc.
NaN, infinities and signed zeros have explicit behavioral tests.

## Qualification required before acceptance

Generate independent reference values and representable neighbors of every
new boundary, including underflow and negative overflow; retain all old rows.
Run existing normal, DD, price, IV and Greek gates with fixed budgets, update
operation-dependent replay to the new graph, and refine every served-value
discrepancy. Record regional maxima and any changed classifications. Refresh
the replay digest only after the numerical compatibility audit.

Build and test both profiles on OCaml 5.3.0 Flambda, run affected named
mutations and required three-platform CI. Benchmark identical input corpora
sequentially with host load and allocation recorded. Final evidence and
compatibility disposition will be recorded with the implementation.

The first binary64-only local polynomial passed the scalar, DD and price gates,
but one pre-existing cancelling BSM theta row was 18 ULP from its independent
reference (budget 8). Retaining the generated leading coefficient residual
reduces that witness to 4 ULP. This correction applies to every local interval;
no input-specific exception or tolerance change is used. The
`erfcx-leading-residual` mutation preserves the original failure mechanism.
