# BSM rho at subnormal rounding cells (#77)

For positive maturity/volatility and side theta=+1/-1,

    rho = theta T K exp(-rT) Phi(theta d2),
    d2 = [log(S/K)+(r-q)T]/(sigma sqrt(T)) - sigma sqrt(T)/2.

At S=K=1, r=q=0, T=2^-1074 and sigma=1/4, d2 is strictly negative.
Thus call rho lies strictly between zero and 2^-1075 and rounds to zero;
put rho is strictly below -2^-1075 and rounds to -2^-1074. Approximating
Phi by one half before multiplying loses which side of the midpoint applies.
The one-ULP baseline error is within the existing 16-ULP rho allowance, but
violates the independently proved rounded-zero check. That check is unchanged.

## Enclosed final rounding

When a finite BSM rho proposal is subnormal, zero, or the smallest normal,
recompute the quantity from original words. This threshold is the binary64
normal/subnormal boundary, not a fitted numerical budget. The proposal is
only a dispatch signal; it is not used as a model input or acceptance proof.

Write T=tm*2^te and K=km*2^ke using exact binary64 frexp. Enclose
`theta tm km exp(-rT) Phi(theta d2)` and keep te+ke separate until the shared
nearest-even cell test. Original T still forms carry, discount and d2.
The existing model CDF series retains the correction to one half as expansion
words and bounds its tail; no rounded binary64 probability is substituted.
Equal original spot/strike words establish exact zero log ratio. Other ratios
use enclosed logs, with any remaining uncertainty preserved.

Zero-volatility ITM rho uses the same normalized product without a CDF;
the original-input log-forward sign decides ITM/OTM. Unresolved sign is
Numerical_failure, never a payoff kink. Existing exact ATM kink and expiry
owners run first. A finite computed zero is not by itself a classification.

For a CDF argument -z with z>=1, the Mills integral gives
`Phi(-z) < exp(-z²/2)`: bound the integral by inserting u/z>=1 and integrate
u exp(-u²/2), retaining the factor 1/(z sqrt(2pi))<1. Thus
`log|rho| < log T + log K - rT - z²/2`. A strict enclosed comparison against
`-1075 log 2` proves a zero result before the generic CDF's conservative tail
floor can destroy that information. This preserves ordinary underflowed-tail
availability without weakening the final-cell requirement.

For negative CDF arguments at or beyond -4 whose zero cell is not proved,
evaluate the entire rho tail in units of 2^-1074:
`exp(log T + log K - rT - z²/2 + 1074 log 2) R(z)/sqrt(2pi)`.
Here R is the existing outward Mills-ratio owner, bounded by successive
continued-fraction convergents. This avoids rounding a tiny CDF before its
coefficient restores scale. The same final cell test uses exponent -1074.
The central CDF path remains separate: replacing its exact dyadic coefficient
by logarithms would lose the very small midpoint direction in the original
witness. Signed zero follows the side for positive-volatility rho.

If an outward magnitude bound proves the final value strictly below half the
minimum subnormal, return zero directly. Otherwise accept only a full
enclosing rounding cell. Arithmetic domain or cell uncertainty becomes a
field-specific Numerical_failure. There is no fallback to the old proposal.
This changes the offered numerical capability, not the real model. Other
Greeks, tied forward-model rho, Production and certified IV keep their owners.
The method does not certify unselected normal-range fast rho values.
