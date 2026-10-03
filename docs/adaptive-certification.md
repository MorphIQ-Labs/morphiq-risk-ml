# Adaptive work with unchanged IV acceptance

The first certified implementation's measured cost and profile are in
[performance.md](performance.md). Expansion accumulation dominates the sampled
execution, and each inverse allocates millions of words. This design reduces
work before changing arithmetic semantics or accuracy requirements.

## Two enclosed attempts

Run a cheaper enclosed evaluation first. Accept only the same exact-model
rounding-cell or mathematical-boundary certificate used by the full evaluator.
If preparation, a sign, a rounding decision or bounded search cannot be resolved,
repeat with the existing full evaluator. No low-precision point estimate is
accepted, and the first attempt cannot weaken a previously successful full
attempt. Both attempts have fixed finite work bounds.

The arithmetic/model implementations are instantiated from the same algorithms
with immutable work configurations. Types keep their enclosure values separate.
There is no mutable global precision, shared lazy cache, learned threshold or
input-region rule fitted to reference successes.

| Work parameter | First attempt | Full attempt |
| --- | ---: | ---: |
| Retained expansion words | 2 | 4 |
| Scalar-division corrections | 2 | 4 |
| Reciprocal polynomial degree | 1 | 3 |
| Reduced exp/expm1 Taylor terms | 16 | 48 |
| Atanh logarithm terms | 32 | 96 |
| Machin atan terms | 32 | 64 |
| Central normal integral terms | 48 | 96 |
| Mills convergents | 64 and 65 | 128 and 129 |

These are work budgets. Their nominal bit counts are never accuracy premises.
Each concrete calculation propagates its actual radius and analytical tails.
The choice can affect first-attempt availability and cost, but not the meaning
of a successful result. The full configuration retains the prior implementation.

## Bounds parameterized by work

The [runtime arithmetic identities](runtime-enclosures.md) hold for any retained
word count: discarded words contribute their outward absolute sum. After any
positive number of scalar quotient corrections, the final enclosed residual
divided by the exact denominator bounds the remaining error.

For a denominator `b=b_high*(1+rho)`, `|rho|<=r<1/2`, an N-term reciprocal
polynomial has remainder at most `r^N/(1-r)`. N=2 gives `1-rho`; N=4 gives
the existing cubic. Arithmetic errors are propagated in either evaluation.

With N reduced exponential terms, the first omitted term is t(N+1); every
subsequent ratio is at most `|argument|/(N+2)`. The bound is therefore
`|t(N+1)|/(1-|argument|/(N+2))`. The ten reconstruction steps are unchanged.
For N logarithm terms the remainder is
`2 |z^(2N+1)| / ((2N+1)(1-|z|²))`.

An N-term alternating atan sum has error at most the magnitude of its first
omitted term, `x^(2N+1)/(2N+1)`. The central normal series after N terms has
first omitted term `x^(2N+1)/(2N+1)!!`; its later term ratio is bounded by
`x²/(2N+3)`. At the existing central guard |x|<=4 this denominator is positive
for both configurations. Every argument uncertainty remains in the enclosure.

Adjacent even/odd Mills convergents bracket the real value for positive input
at every finite depth, as derived in [model-enclosures.md](model-enclosures.md).
Taking the hull of both enclosed convergents bounds both truncation and floating
arithmetic. A shallower pair can be much wider; the solver must fail that
attempt if the interval cannot establish its decision.

The first pair's depth is informed by an exact-rational calculation at the
tail guard x=4. The gaps for depths 16/17, 32/33 and 64/65 are respectively
less than 9e-12, 4e-17 and 5e-25. The positive denominator polynomials make
these gaps decrease as x increases. Thus 32 terms can leave an error of the
same order as a binary64 decision even before price conditioning; 64 provides
a substantially narrower first enclosure. This is a work-allocation choice,
not an acceptance tolerance. The actual propagated interval still decides.

## Required verification

Run the independent exact-rational primitive/expansion and extra-bit reference
checks for both configurations. Exercise forced failure and tie/boundary
controls for both solvers. All existing public reference successes, exact-root
rounding and classification expectations remain required, with no changed
fixture or budget. Check replay compatibility explicitly. Run the affected
mutations and the default core. Benchmark the same fixed workloads against
the full-only certificate, whose accuracy contract is now identical.

The fallback is not evidence that the first attempt's bounds are correct:
independent arithmetic tests and the written enclosure derivation remain
necessary, because an unsound first attempt could accept before fallback.

## Operation-preserving scalar shortcuts

The profile also motivates inlining TwoSum and its finite checks, allowing
Flambda to eliminate temporary tuple/float boxes. Every arithmetic operation
and every finite check remains; the multiplication boundary is unchanged.

For product residuals, if both magnitudes are at least `2^-485`, their frexp
exponents are each at least -484. Their sum is therefore at least -968, which
is exactly the existing sufficient condition for a representable residual
quantum. Two magnitude comparisons can return the same zero allowance without
allocating the two frexp results. All other operands use the original exponent
test. This shortcut preserves the radius decision for every finite input; it
does not infer exactness merely from a zero fused residual.

## Exercised assurance

Both configurations pass the same 1,126 deterministic exact-rational primitive
cases, 2,000 generated arithmetic compositions, 26,998 supported elementary
and normal references, and 1,670 original-input model references. Cases outside
an elementary guard are reported separately; they are not accepted comparisons.
The generic solver tests exercise incorrect proposals, ties, computational
failures and bounded work for both configurations.

The complete ordinary suite passes. All 5,575 positive public IV reference roots
retain nearest-even rounding, with no numerical failures on that corpus. The
replay digest remains
`029a559e0d6360c69c4039b32d1f9123f0c0ae8e2c5811bc2dd4e57fd17b0651`.
These are exercised availability and compatibility results, not universal
finite-input availability or independent human review.

All 17 affected mutations, including the seven default core mechanisms, fail
their designated numerical guards after a clean baseline and successful builds.
[The retained log](evidence/adaptive-iv-mutations.txt) includes three new optional
witnesses: the product shortcut's exponent condition, mandatory refinement when
the first attempt is unresolved, and the reduced exponential's truncation tail.
The full catalog has 40 mechanisms; the default core remains seven.
