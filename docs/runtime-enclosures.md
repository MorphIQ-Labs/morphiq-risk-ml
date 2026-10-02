# Runtime enclosure derivation

This is the derivation for an independent, bounded arithmetic enclosure used
to distinguish resolved model decisions from numerical uncertainty. It does
not import the test suite's exact-rational witnesses or a measured ULP budget
as a runtime premise. The ordinary IEEE environment in
[the backend contract](numerical-backend-contract.md) is required.

## Representation and primitive bounds

An enclosure `(h,l,e)` means `|x-(h+l)| <= e`, with all three words finite and
`e >= 0`. The sum `h+l` is a real unevaluated sum, not a rounded addition.
The radius uses upward-rounded nonnegative operations: a binary64 operation
followed by its successor. Lower denominators use downward rounding. Overflow,
an unresolved denominator or a nonfinite radius is failure, never a usable
infinite certificate.

`TwoSum(a,b)` gives the exact sum as two words when its operations do not
overflow. All intermediates are checked. Gradual underflow does not introduce
an inexact addition here: binary64 operands and their sums/differences are
integer multiples of the least subnormal, and a result in the subnormal range
is representable exactly. This is Knuth's error-free addition, also the
published primitive underlying the existing double-word algorithms.

For a product, compute `p=RN(a*b)` and `r=RN(fma(a,b,-p))`. Without requiring
the fused residual to be exact, the exact product lies within `p+r ± R(r)`,
where `R(v)` is an upper bound for half the largest adjacent spacing, with
one least subnormal used when that half-spacing is unrepresentable. This
follows directly from correctly rounded FMA, including underflow. Zero and
multiplication by ±1 have exact special cases. A scalar product retained as
one word instead has error at most `|r|+R(r)`.

Addition sums the high words with TwoSum, then the low words and high-word
residual. Each discarded low-addition residual is obtained with TwoSum and
added to the radius. Renormalization is another exact TwoSum. Multiplication
uses the high product/residual and all three cross products, including
`a_low*b_low`; it accounts for every product and low-addition rounding. Input
uncertainty contributes

    |a_center| E_b + (|b_center| + E_b) E_a.

For division by an exact scalar `b`, choose `q=RN(a_high/b)`, form the fused
residual of `a_high-q*b`, add `a_low`, and divide that correction by `b`.
The first quotient's rounding is corrected by the residual; only the residual,
low addition and correction division errors, plus `E_a/|b|`, remain.

General division writes `b=b_high(1+rho)`, including `b_low` and its error in
the enclosure for rho. For `|rho| < 1/2`, evaluate `1-rho+rho²` and add the
explicit geometric remainder `|rho|³/(1-|rho|)`, multiplied by the magnitude
of `a/b_high`. No assumption that the denominator's low word is negligible
replaces that remainder. A denominator whose sign cannot be resolved fails.

Scaling by a power of two is exact whenever the scaled word is normal; each
word that enters the subnormal range receives an absolute quantum bound.
The radius itself is scaled upward. These rules remain conservative for
sparse low words and underflow rather than extending an unbounded-exponent
relative theorem by assertion.

## Elementary enclosures

For `exp` and `expm1`, require the entire argument interval to lie in
`[-256,256]`, and reduce exactly by `2^10`. For `|r|<=1/4`, evaluate 24 Taylor
terms. If `t_25` is the first omitted term, the tail is bounded by

    |t_25| / (1 - |r|/26).

Every subsequent term ratio is no larger than `|r|/26`. The term enclosure
includes argument and arithmetic uncertainty. Ten squarings reconstruct exp;
ten updates `y <- 2y+y²` reconstruct expm1 without subtracting one. Every
update propagates its actual primitive enclosure. The fixed iteration counts
bound execution; the remainder is evaluated, not assumed negligible.

For a positive logarithm, power-of-two normalization gives `x=2^k m` with the
high word of m in `[1,2)`. Set `z=(m-1)/(m+1)` and require its enclosed
magnitude to be below one half. After 64 terms of
`2 sum z^(2n+1)/(2n+1)`, bound the remaining tail by

    2 |z^129| / (129 (1-|z|²)).

The constant ln(2) is enclosed by the same series at the exact rational
argument 1/3. No host logarithm or unverified decimal constant supplies it.

For square root, normalize by an even exponent before taking the hardware
square root q of the high word. Compute an enclosure for `d=x-q²`, and use
`q+d/(2q)`. For every positive x in the input interval,

    |sqrt(x) - q - (x-q²)/(2q)|
      = (sqrt(x)-q)²/(2q)
      <= |x-q²|²/(2q³).

Add that explicit remainder and rescale. Positivity and every division are
checked. The scalar square-root result is a proposal whose finite error is
accounted for by this identity, not an assumed double-word theorem.

## Scope

These are enclosures of real arithmetic expressions under the stated IEEE
semantics, not a formal verification of the compiler. Test-only exact
rationals and precision-refined references independently check the primitive
postconditions and elementary results, including sparse low words and
subnormals. Unsupported or unresolved cases must propagate as explicit
failures. Financial domain, boundary classification, root enclosure and
output acceptance must be layered on these primitives with their own
documented derivations; a primitive enclosure alone does not qualify a model.

The deterministic and seeded generated primitive campaign checks all endpoint
combinations with exact rationals, including uncertainty propagated from a
prior operation. The elementary campaign uses the existing precision-refined
three-word fixtures: 19,058 rows lie in this implementation's function/domain
scope; 5,988 exponential rows exceed its explicit guard and 23,157 rows exercise
other functions. Those rows are reported separately, never counted as passes.
The original DD reference test continues to exercise all 48,203 rows.

The optional `enclosure-fma-underflow` mutant removes the residual's rounding
allowance. Squaring `0x1.0000000000001p-537` distinguishes it: the exact product
is slightly above the least subnormal, while its fused residual rounds to zero.
That zero residual is not evidence of an exact product. This witness checks
the exact-rational postcondition, independently of the implementation's formula.
