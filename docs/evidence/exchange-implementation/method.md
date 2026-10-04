# Exchange runtime method and preconditions

This derivation precedes implementation scoring. Original-word covariance is
nonnegative. Its zero identity is evaluated from original typed inputs: both
volatilities zero, or equal volatilities with correlation exactly one. No
rounded covariance value determines degeneracy.

For positive maturity and nonzero covariance, let e be the maximum volatility's
frexp exponent. Enclose ui = sigma_i * 2^-e, including any sparse/subnormal
scaling error. Compute

    w = (u1-u2)^2 + 2*u1*u2*(1-rho).

All operations use the existing outward expansion owner. Let k be the even
integer at or below the maturity's frexp exponent. Compute an enclosure of
`sqrt(w * (T * 2^-k)) * 2^(e+k/2)`. This avoids forming the unscaled covariance
products. Square-root input and final total standard deviation must both have
proved positive intervals. Failure to establish either is numerical failure,
including a positive variance too small to resolve. Subnormal restoration
uses Enclosure.scale's explicit quantum allowance; overflow fails explicitly.

Use a common currency exponent h from max(S1,S2), and enclose
`ai = (Si * 2^-h) * exp(-qi*T)`. Discount exponents use original words and
Enclosure.mul. The existing exp owner requires argument magnitude <=256;
this is an explicit initial capability restriction, not an admission rule.
It also guards intermediate overflow and finite radii. Extreme discount
cancellation outside this owner is unresolved rather than approximated.

For positive legs, enclose the log ratio as
`log(S1) - log(S2) + (q2-q1)*T`, without rounded forwards or a rounded spot
ratio. Compute d1 and d2 with the enclosed standard deviation, then
`a1*Phi(d1)-a2*Phi(d2)` with Model_enclosure.cdf, whose series/Mills/tail
preconditions and remainder bounds remain owned by that module. An uncertain
CDF branch fails rather than choosing from a rounded sign. The complete
interval is restored by 2^h before computing the final currency radius.

Expiry uses the exact original-word spot difference and positive-part identity.
Zero receive gives exact zero; zero deliver uses its discounted receive leg.
For zero variance, equal yields factor the original spot difference before
multiplication. Equal spots and yields give exact zero without discount
arithmetic. Other zero-variance cases use the discounted-leg difference;
uncertain sign is enclosed conservatively by the positive-part hull. This
retains uncertainty instead of falsely claiming a deterministic zero.

One full bounded enclosure evaluation is used initially. No empirical error
allowance, rounded effective-volatility adapter, unchecked fallback, new
transcendental implementation or change to existing model outputs is needed.
The served centre is max(0, enclosure.hi); its radius is the existing outward
error_of_float of the restored interval about that centre. Acceptance requires
finite centre and finite nonnegative radius <= the original requested absolute
limit. Zero limit succeeds only with a zero radius. Failure to produce a finite
enclosure differs from a finite enclosure that misses the requested limit.

The inherited enclosure proofs and their finite checked domains do not prove
all admitted exchange inputs. Focused independent containment tests, optional
mechanism mutants and later #61 qualification establish their stated finite
scope; independent human review remains outstanding.
