# Runtime enclosure derivation

Runtime decisions use finite expansions and explicit radii; no measured kernel
ULP budget or test-only rational arithmetic is a premise. The IEEE environment
in [the backend contract](numerical-backend-contract.md) is required.

The counts below describe the full four-word configuration. The
[adaptive configuration](adaptive-certification.md) instantiates the same
identities with two retained words and shorter series, propagates the actual
remainder, and retries the full configuration when its certificate cannot decide.

## Representation and exact sums

An enclosure means `|x-sum(words)| <= error`, retaining at most four binary64
words. Every field is finite and the radius is nonnegative. Radius operations
round outward with successor/predecessor; nonfinite intermediates fail.
Overflow is never a usable infinite certificate. Four words provide additional
working precision; the radius, not a nominal bit count, determines each decision.

Knuth's TwoSum preserves the exact sum when its intermediates do not overflow;
every intermediate is checked. Gradual underflow does not round a subnormal
addition/difference: both operands are integer multiples of the least subnormal,
and so is their exact sum. Repeated TwoSum implements Shewchuk's Grow-Expansion,
Theorem 10, with zero elimination. See the [author report](https://people.eecs.berkeley.edu/~jrs/papers/robustr.pdf).
It preserves the exact sum while keeping components in magnitude order.
Truncating to four words adds the outward sum of every discarded magnitude to
the radius. The representation does not silently discard a small fifth word.

The loop was checked against the author's unchanged `grow_expansion_zeroelim`
in [predicates.c](https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c).
The executed baseline performs 32,009 exact-rational postcondition checks;
[source hash, compiler and flags](evidence/canonical-expansion.json) are retained.
`scripts/canonical_expansion.py SOURCE --output REPORT` reproduces that campaign.
The OCaml primitive campaign separately uses exact rationals.

### Allocation-preserving arithmetic order

Each `pack` owns a fresh checked float array with capacity equal to its number
of input terms. It folds those terms in their original order. A grow step
reads the increasing-magnitude expansion from index zero, performs the same
`TwoSum(carry, term)`, writes each nonzero residual, then appends the final
nonzero carry. Induction on the terms gives the same ordered residuals and
carry as the previous list traversal. Signed-zero elimination and every
intermediate finite check remain unchanged.

At iteration `j`, at most `j` residuals have been emitted. The next write is
therefore at or behind the term just read, never ahead into unread storage.
One insertion grows the expansion by at most one word, so after `k` input
terms its length is at most `k`; the input count bounds every write. Only
initialized indices below the current length are read. No scratch escapes
`pack` or is shared across calls, threads or domains. Indexing remains checked;
there is no unsafe access, new foreign code or public mutable representation.

The retained-word pass visits the array from its last initialized index down
to zero, exactly the previous reversed-list order. It retains the same words
and adds discarded magnitudes to the radius in the same order. Products,
explicit FMA, underflow allowances, series counts and acceptance limits are
unchanged. This changes storage and allocation, not the floating operation
graph or error derivation. Independent exact-rational checks remain required.

## Products and division

For binary64 operands a,b, let `p=RN(a*b)` and `r=fma(a,b,-p)`. The exact product
residual has at most 53 significant bits (the standard error-free TwoProduct
argument underlying the published DD primitives). The remaining finite-exponent
obligation is representability of its least bit. If `frexp(a)` and `frexp(b)`
have exponents ea,eb, their product is an integer multiple of
`2^(ea+eb-106)`. Thus `ea+eb>=-968` ensures that quantum is at least `2^-1074`,
and the fused residual is exact. Otherwise retain an absolute quantum allowance
for possible residual underflow. Zero and multiplication by ±1 are exact cases.
A zero fused residual alone is never evidence of an exact product.

Multiply every retained word pair, retaining both p and r, then exactly sum the
terms and bound truncation as above. Input radii contribute

    |a_center| E_b + (|b_center|+E_b) E_a.

Division by an exact scalar uses four residual corrections. Starting with
remainder a, choose `q=RN(remainder_high/b)`, add q to the quotient expansion,
and update the enclosed remainder by subtracting the enclosed exact product
q*b. After four corrections, enlarge the quotient radius by
`magnitude(remainder)/|b|`, outward rounded. This is an a posteriori identity:
the proposal's rounding is accounted for by its residual, with no assumed
relative accuracy for the four corrections and no assertion that it converged.

For general division write `b=b_high*(1+rho)`, including every lower word and
the input radius in rho. Require its enclosed magnitude r to be below 1/2.
Evaluate `1-rho+rho²-rho³` and enlarge by `r^4/(1-r)`, multiplied by the
magnitude of `a/b_high`. This is the explicit geometric remainder. An unresolved
denominator or nonfinite correction fails.

Power-of-two scaling is exact for each normal resulting word; each word entering
the subnormal range receives one absolute quantum allowance. Scale the radius
outward and renormalize through exact sums, accounting for discarded words.

## Elementary enclosures

For exp/expm1 require the whole input interval inside `[-256,256]` and reduce
by `2^10`. Evaluate 48 Taylor terms at `|r|<=1/4`; the first omitted term t49
has remaining tail bounded by

    |t49| / (1-|r|/50).

Ten squarings reconstruct exp; ten `y <- 2y+y²` updates reconstruct expm1.
Every operation propagates its enclosure. The fixed work count and explicit
remainder replace an assumption that small terms are negligible.

For log normalize by a power of two, `x=2^k m`, set `z=(m-1)/(m+1)` and require
its enclosed magnitude below 1/2. After 96 terms of `2 sum z^(2n+1)/(2n+1)`,
the tail is bounded by

    2 |z^193| / (193 (1-|z|²)).

Enclose ln(2) by this same series at the exact rational argument 1/3.

For sqrt normalize by an even exponent and choose the hardware sqrt of the
leading word as an initial proposal q. For any exact positive proposal q,

    |sqrt(x)-q-(x-q²)/(2q)|
      = (sqrt(x)-q)²/(2q) <= |x-q²|²/(2q³).

Evaluate that correction and explicit remainder with enclosures. Repeat three
times, choosing the retained expansion's center as the next exact proposal and
recomputing the residual against the original normalized input. Taking a center
here does not claim it is the exact root: the next residual accounts for its
entire error. A proved lower bound on q supplies the remainder denominator.
Finally rescale with its underflow allowance. This identity remains the guarantee
whether or not the expected quadratic improvement occurs.

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
three-word fixtures: 19,058 elementary rows and 7,940 normal-function rows lie
in this implementation's function/domain scope; 5,988 exponential rows exceed
its explicit guard and 15,217 rows exercise other functions. Those rows are
reported separately, never counted as passes.
The original DD reference test continues to exercise all 48,203 rows.

The optional `enclosure-fma-underflow` mutant removes the residual's rounding
allowance. Squaring `0x1.0000000000001p-537` distinguishes it: the exact product
is slightly above the least subnormal, while its fused residual rounds to zero.
That zero residual is not evidence of an exact product. This witness checks
the exact-rational postcondition, independently of the implementation's formula.
