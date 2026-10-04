# Inverse normal replacement: construction and qualification contract

Baseline: `42eb6d1245509927152d204598d1e553fb4b127c` (PR #68).
The AS241 replacement is a separate, dependent change under #64. Existing
inverse-normal gates remain 4 ULP central (|p-1/2|<=0.425) and 8 ULP in the
tails; financial, outcome and certificate requirements are unchanged.
This construction is fixed before scoring. No AS241 coefficient, regional
constant or operation graph is reused, and no clean-room claim is made.

## Definition and sources

For 0<p<1, solve Phi(x)=p using odd symmetry about p=1/2. Endpoints remain
negative/positive infinity, invalid probabilities and NaN remain NaN, and
p=1/2 returns positive zero. A binary64 p denotes its exact real value.

The identities follow from the defining Gaussian integral; consulted primary
mathematics are NIST DLMF [7.17](https://dlmf.nist.gov/7.17) (inverse definitions)
and [7.8](https://dlmf.nist.gov/7.8) (Mills inequalities), version 1.2.8,
accessed 2026-10-03 local time. No source implementation/table is imported.
The existing project-generated error functions supply forward evaluations;
the qualified double-word logarithm supplies a tail target with a low word.

## Central equation and bracket

For |p-1/2|<=1/4, t=2|p-1/2| is exact by Sterbenz and power-of-two scaling.
Solve erf(y)=t and restore x=sign(p-1/2) y/sqrt(1/2). The nonzero root lies
in [t/2,t], wholly within the generated small-erf interval [0,1/2].
Indeed erf(y)<2y and erf(t)>=2c t(1-t²/3)>t for t<=1/2, where c=1/sqrt(pi).
The initial y=t uses no fitted seed.

The derivative is 2c exp(-y²), at least 2c exp(-1/4), and the absolute second
derivative is at most 2c on this interval. Newton error therefore contracts
as |e_next| <= exp(1/4) e²/2 in exact arithmetic. Initial error is <=t/2<=1/4;
six steps make the ideal iteration error negligible relative to binary64.
The forward 26u bound, scalar exponential error, final division and each
Newton operation contribute separately; the ideal recurrence is not a claim
of correct rounding for the implemented function.

A bracket endpoint is updated only when the computed residual is outside
32u times the computed erf value. This exceeds the qualified 26u/(1-26u)
forward error with rounding margin. Newton proposals are projected into the maintained
bracket. Projection cannot increase distance to a root inside that bracket. No cancellation through Phi(y)-1/2 is introduced.

## Tail equation and bracket

For a=min(p,1-p)<1/4, 1-p is exact on the upper half by Sterbenz and 2a is
exact, including the smallest positive subnormal input. Form
T=-log(2a) as a double word. Solve

    G(y)=y²-log(erfcx(y))=T,    x=sign(p-1/2) y/sqrt(1/2).

For every positive binary64 a, the root lies in [0,28], since
T<=1073 log(2)<28² and erfcx(y)<=1. The initial y=sqrt(T_hi) is near an upper
bound. Jensen's inequality on the positive Gaussian integral gives
log(erfcx(y))>=-2cy, hence 0<=sqrt(T)-y<c.

Mills' bounds give G'=2c/erfcx(y)>=2c and 0<G''<2. Newton from above therefore
has e_next<=e²/(2c), and e0<c implies e_n<2c*2^(-2^n).
Six exact steps put this remainder below 2^-63. Floating target, evaluation,
proposal and conversion errors are distinct from this ideal truncation.
The square-minus-target is formed with one explicit FMA before subtracting
the target low word and log(erfcx), avoiding a separately rounded large square.

Endpoint updates use an outward residual allowance of 128u(1+|log(erfcx)|),
which covers 40u erfcx input error, the reduced-log 0.14u remainder plus final
rounding, small-exponent ln(2) recombination (|e|<=6), FMA/subtractions and
32u²|T| target error. On y in [0,28], erfcx(y)>1/64; the ordinary logarithm
therefore never sees an extreme exponent or subnormal. This allowance is for
bracket validity, not the tighter empirical 4/8-ULP output gate. A full finite-
arithmetic refinement and rational inequality checks accompany qualification.

## Required evidence

Retain and expand probability neighbors around 0, 1/2, 1, the new 1/4 and
3/4 switches and forward-function interval transitions. Cross-check inverse
references independently with high-precision erfinv as well as log-tail root
solving. Check sampled monotonicity, endpoint/domain behavior, every changed
output, fixed-quote IV classifications/certificates and both build profiles.
Record any new replay bits with compatibility evidence before accepting a
new digest. Benchmark standalone inversion, LBR consumers and full workflows
on the shared host only after task-owned computation stops. No error budget
will be widened to accommodate the candidate.

## Finite arithmetic and final refinement

`oracle/inverse_normal_bounds.py` checks conservative rational inequalities
for the scalar iteration. With u=2^-53 and normalized central error r=|e|/t,
the recurrences r_next <= r²/3+128u and
|e_next| <= 0.9e²+4096u yield r<129u and |e|<4100u after six steps.
The central operation allowance uses derivative >=3c/2, 32u forward error
and 16u derivative perturbation; the tail allowance uses G'<=58, |e|<0.6,
|G-T|<35 and a 64u derivative-ratio perturbation. Projection is nonexpansive.
These deliberately coarse enclosures depend on the existing component bounds;
they do not prove the empirical 4/8-ULP gates or global monotonicity.

The expanded adjacent-input corpus exposed two one-ULP monotonicity reversals
in the initial scalar candidate, near p=0.24 and p=0.25. Before rescoring,
add one double-word Newton correction throughout the already qualified
Normal_dd domain |x|<=6 (not only at the failing probabilities). Evaluate the
negative root and its original lower-tail probability to avoid subtraction
from one. The correction is x-(Phi(x)-a)/phi(x), formed in double words and
rounded once. Its ideal error is O(|x| e²), while the existing Normal_dd
forward-error bounds and DD operation errors govern finite arithmetic.
The |x|<=6 boundary is the existing forward component's supported domain.
Outside it, retain the safeguarded log-tail method. This is an accuracy
refinement, not a runtime certificate of correctly rounded inversion.

For a conservative final-correction enclosure, the scalar bounds and
sqrt(2) conversion give |e0|<10^-12 throughout the correction domain.
On the segment to the true root, |x|<6+10^-12, phi(x)>2^-29 and the local
Newton quadratic factor is <4. The density lower bound follows from
27 log(2)>18.00000000001 and 1/sqrt(2 pi)>0.39. Combining the existing
512u² absolute CDF bound with 64u² additional DD-operation allowance gives

    |e1| <= 4e0² + 576u² / 2^-29 + u |unrounded corrected x|.

The last term is the final binary64 rounding. This deliberately conservative
absolute bound is useful for coverage, especially at the correction boundary;
near zero it is much looser than the empirical ULP gate. It does not establish
correct rounding or monotonicity for all binary64 probabilities. Those claims
are restricted to the explicitly tested/refined corpus.

For that 64u² allowance, the residual subtraction contributes at most 3u²
in absolute terms, division contributes less than 10u² (the correction is
less than 10^-11), and the final DD subtraction at magnitude below 7 contributes
at most 21u². The 200u² relative density perturbation acts on a correction
below 10^-11 and contributes less than u². The remaining margin covers their
composition and the tiny inflation of the component CDF error. These operations
stay normal in this correction domain; no exponent-extension theorem is used.
