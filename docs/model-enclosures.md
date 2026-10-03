# Runtime model enclosure derivation

This layer encloses the real European model from the original binary64 inputs.
Displaced coordinates enter as exact two-word sums before any currency scaling.
It consumes the residual-based arithmetic in [runtime enclosures](runtime-enclosures.md),
not the approximate production kernel or an empirical ULP allowance. An unresolved
operation is a computational failure; a finite radius is not itself acceptance.

## Normal distribution

We derive the normalization constant rather than trusting a decimal literal.
Machin's identity is `pi = 16 atan(1/5) - 4 atan(1/239)`: the tangent addition
formula gives `tan(4 atan(1/5) - atan(1/239)) = 1`, and the angle lies in
`(0,pi/2)`. For each arctangent, sum 64 alternating terms and bound the remainder
by the magnitude of term 65, using the alternating-series theorem for `0<x<1`.
All arithmetic, including the rational arguments, carries its enclosure. Then
`phi(x) = exp(-x*x/2)/sqrt(2*pi)`.

For `|x|<=4`, the positive integral series gives

    Phi(x) = 1/2 + phi(x) sum[n>=0] x^(2n+1)/(1*3*...*(2n+1)).

This follows by differentiating `exp(-x*x/2)` times the series: the derivative
is `exp(-x*x/2)` and the series vanishes at zero. Evaluate 96 terms. The first
omitted term is bounded by a geometric tail with subsequent ratio at most
`|x|²/195`. The same magnitude argument covers negative x and intervals crossing
zero. Subtracting from one can lose relative precision; that loss appears in
the absolute enclosure rather than an asserted relative guarantee.

For positive `x>4`, use the Laplace continued fraction for the Mills ratio:

    Phi(-x)/phi(x) = 1/(x + 1/(x + 2/(x + 3/(x + ...)))).

This is an equivalent form of [NIST DLMF 7.9.1](https://dlmf.nist.gov/7.9.E1)
after `z=x/sqrt(2)` and elementary equivalence transformations. Successive finite
convergents bracket the infinite positive fraction: replacing the positive
remaining tail by zero and infinity supplies its two extremes, and each
reciprocal reverses their order. Use the hull of the 128th and 129th
convergents, including arithmetic uncertainty in each. No measured convergence
rate or assumption that the final terms are negligible is used. Symmetry gives
the other tail. Input intervals must establish the positive-tail branch;
otherwise the bounded series branch or an explicit unresolved result applies.

To cover Gaussian arguments beyond the elementary exp guard, this layer may
evaluate `exp(a/4)` and square twice, propagating the enclosure at each step.
It requires `|a|<=1024`. Overflow or a nonfinite radius remains failure;
underflow contributes an absolute radius and may prevent a useful decision.

## Model expressions and boundaries

For lognormal coordinates, let `S,K` be the exact (possibly displaced) values,
`A=S exp(-qT)`, `C=K exp(-rT)`, `x=log(S/K)+(r-q)T`, `s=sigma sqrt(T)`,
`d1=x/s+s/2`, `d2=x/s-s/2`. The value is

    theta [A Phi(theta d1) - C Phi(theta d2)].

The intrinsic is `max(theta(A-C),0)` and the finite-volatility supremum is A
for a call or C for a put. Equal discount rates allow `(S-K) exp(-rT)`;
otherwise the difference is enclosed directly. Equality of exact operands is
preserved where it proves an exact cancellation. Each expression propagates
input and arithmetic uncertainty; cancellation does not permit discarding it.

For Bachelier, `D=exp(-rT)`, `delta=F-K`, `s=sigma sqrt(T)`, `d=delta/s`:

    V = D [theta delta Phi(theta d) + s phi(d)].

The intrinsic is `D max(theta delta,0)` and there is no finite supremum.
At expiry or zero volatility, use the intrinsic directly. Taking `max(x,0)`
requires either a proved sign, exact zero, or a conservative interval hull.
The derivative of price with respect to positive volatility is strictly
positive for positive maturity and valid positive lognormal coordinates (or
finite normal coordinates), so strict signs of enclosed endpoint prices prove
an exact-model root bracket. Inability to resolve a sign is not a root.

## Scope and acceptance

These formulas supply bounded model evaluations, not an automatic accuracy
budget or production-domain policy. A consumer must specify how small an error
or root bracket it accepts and reject unresolved decisions. They do not certify
the existing fast kernel by resemblance, and do not assume the same expression
is numerically optimal. Independent reference tests must retain original input
values and separately report any evaluation failures.

The ordinary suite checks all 7,940 existing three-word normal PDF/CDF rows
and 1,670 new original-input model rows (1,280 ordinary, 288 zero-variance or
expiry, 72 tails and 30 sparse/tiny cases). Every one must return an enclosure
consistent with the precision-refined reference; no row in this fixture may
be silently refused. Three separate controls require explicit failure for
overflowed normal distance, an unsupported discount and a nonpositive
lognormal coordinate. The references use erfc-based mpmath formulas at
110/220 digits, increased to 400/800 for sparse and tiny inputs. Agreement
does not constitute a formal interval proof of the reference. The scorer
includes the normalized three-word expansion's absolute uncertainty.
