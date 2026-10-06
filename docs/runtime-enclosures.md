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

Magnitude-ordered FastTwoSum preserves the exact sum when the sum does not
overflow; the residual finiteness check enforces every intermediate's finiteness
as derived below. Gradual underflow does not round a subnormal
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

### Fixed words and private packing storage

The two supported configurations retain two or four words. An immutable record
of five floats stores `hi`, `lo`, `third`, `fourth` and `error`; absent trailing
words use zero. This avoids mixing floats and list pointers in the record and
allows the supported native compiler to use its packed float representation.
The first two logical slots always exist, including zero; the third/fourth slots
exist only when nonzero. Grow eliminates zero residuals and carry, so occupied
slots are contiguous. Negation may change padding zero signs; both signs still
mean an absent trailing slot and do not enter the arithmetic. `words` reconstructs
the original logical list for research/test consumers; production arithmetic
works directly from the fixed slots. `Internal.Enclosure.S.t` changes layout and
removes the list-valued `tail` field; stable public APIs are unchanged.

Each packing operation uses a checked float array containing its input terms.
That same array becomes the growing expansion. Before inserting term `i`, the
expansion length is at most `i`. The term at `i` is read before the grow step;
its writes end at or before `i`, so future terms remain intact. Inside grow,
at most `j` residuals have been emitted when reading slot `j`, so its write
cannot overwrite an unread expansion word either. Both loops preserve the
previous increasing-magnitude expansion and insertion order. All accesses stay
checked. Arrays never escape into an enclosure or cross public operation calls,
workers or domains. Scalar division reuses a private array across its own
sequential suboperations, as derived below.

Bounds follow directly from the supported representation: additions insert at
most eight terms; multiplication inserts at most 32 terms (two words per pair
of at most four retained words on each side); scaling uses at most four;
`of_words` uses two; denominator lower parts use at most three. No global pool,
thread-local cache, user-visible borrowed lifetime or shared mutable scratch is introduced.

### Scalar fusion and quotient-local scratch

Subtraction inserts the same logical words as `add a (neg b)`, negating the
right words while filling the packing input instead of allocating a temporary
record. Zero shortcuts still return `neg b` or `a` in the original order.
Scalar additions/differences insert the same two words as an exact scalar:
`b, +0` or `-b, -0`. On the zero-left shortcut, negated scalar results retain
negative padding zeros in every negated slot. Scalar validation still precedes
shortcuts, including zero operands and nonfinite scalar inputs.

`mul_float` visits the same `na × 2` pairs as `mul a (exact b)`, including the
zero low word, separately rounded products, explicit FMA residuals and finite
checks. It stores pairs in the same reverse-pair order and accumulates quantum
allowances in the same forward order. An exact scalar has radius zero and
magnitude `abs b`: the original magnitude fold starts at zero, adds `abs b`,
then zero slots, all exact identities under the existing outward-zero rules.
Thus its propagated input radius remains
`(centre_magnitude a *^ 0) +^ (abs b *^ a.error)`. Precision, product allowances,
radius rounding and failure conditions are unchanged. The generic multiplication
remains an independent implementation for full-field compatibility comparisons.

Scalar division now owns one eight-word packing array. Each quotient proposal
is an exact scalar with two logical words, so multiplying it by the denominator
uses eight terms. Adding that proposal to the quotient needs at most six;
subtracting the product from the remainder needs at most eight, for either
supported precision. A checked private allocator enforces this derived bound.
Each operation overwrites its entire used prefix before packing; packing receives
the used length, not capacity, so stale tail slots cannot participate. Retained
fields are copied into immutable results before the next operation reuses the
array. No recursive call, callback or user-visible borrowed buffer shares it.
Exceptions abandon only that call's scratch, and separate calls/domains own
separate arrays. All array accesses remain checked.

`test/enclosure_scalar.ml` checks full fields (including padding-zero signs),
refusal classifications and exact-rational containment over boundary and seeded
inputs in both precisions. It also checks that retained results survive later
divisions/failures and concurrent independent calls. The optional scalar-radius
and scratch-length mutants require numerical containment failures, not changed
replay fingerprints. The complete model/certificate/reference suites remain
separate obligations.

### Exponential-owned scratch

Each nonzero `exp`/`expm1` call additionally owns one private array, reused by
the original sequential series and reconstruction operations. With `w` retained
words, general products need at most `2*w*w` terms, sums `2*w`, scalar products
`4*w`, and scalar quotient suboperations eight. Capacity `max 8 (2*w*w)` is
therefore eight floats in Fast and 32 in Full. Each checked allocator verifies
the requested prefix against this bound; packing receives the actual used
length and must not read stale tail slots.

Generic addition/multiplication and scalar quotient bodies accept a private
allocator internally. Ordinary public operations still allocate their own
scratch. Exponential-local operations share only storage: term insertion,
product/FMA and radius order, scalar validation, quotient iterations, series
degrees, tail bounds and reconstruction counts remain unchanged. Every nested
argument finishes by copying retained fields into an immutable record before
the next operation overwrites scratch. The array never escapes, survives a
failed call for reuse, or crosses independent calls/domains. Zero/domain checks
precede the new exponential allocation.

`test/enclosure_exponential.ml` checks retained results, intervening failures,
independent domains and native/bytecode full-field replay in both precisions.
Its independent rational check uses degree-96 Taylor bounds on `|x| <= 1`,
with remainder `3*|x|^97/97!` from `exp(|x|) < 3`. Monotonicity checks both
endpoints of uncertain inputs, for exp and expm1. Existing range-reduced
elementary/model reference checks cover additional inputs. The optional
stale-prefix mutant must fail a numerical containment/availability witness;
changed replay alone is insufficient.

### Interpolation-owned scratch

`linear_interpolate` is an internal, model-independent composition of enclosed
endpoint comparisons, `(point-lower)/(upper-lower)`, strict convex-weight
checks and `(1-weight)*left + weight*right`. Exact endpoints return the original
scalar directly, including its zero sign. An unresolved weight is a distinct
result; the cash owner retains its original failure message, diagnostics and
local arithmetic limit. Binary grid search, event sides, mapping refinements,
work accounting and cancellation checkpoints stay in that owner.

The primitive owns one array of `max 8 (2*w*w)` floats. The exponential bounds
above also cover this composition and general division: its denominator lower
part needs `w-1` terms, quotient suboperations eight, and geometric correction
products at most `2*w*w`. Each operation overwrites its used prefix and copies
retained fields. General division's ordinary entry point still allocates fresh
storage and retains its original scalar-quotient ownership; only this composition
supplies the interpolation array. The geometric tail and validation are unchanged.

Scalar subtraction/multiplication insert the same logical exact-scalar words
and zero signs as their generic counterparts. The first endpoint comparison
already constructs `point-lower`; this immutable enclosure is reused as the
numerator after the upper endpoint check. Both inputs and all five stored fields
are unchanged, so reevaluating that pure subtraction cannot supply new evidence
or a different failure. This is within-call common-expression reuse, with no
cross-point/cache dependency. Width is still enclosed from the original nodes;
the expression is not rewritten into slope form or reassociated. Explicit
inlining removes argument boxing without changing arithmetic.

`test/enclosure_interpolation.ml` checks both precisions against the original
composition and an independent exact-rational linear formula. For uncertain
points inside ordered finite nodes, the affine image is bounded by the two
rational endpoint values (including decreasing interpolants). The numerical-only
mutation guard checks containment and availability; ordinary compatibility also
covers unresolved weights, arithmetic failures, signed endpoints, extreme nodes,
retained results and independent domains. No result or callback borrows scratch.

### Shared packing invariants

Addition emits all logical words of its first operand, then its second, including
the same explicit zero slots as before. Multiplication visits operand pairs in
the original nested-loop order, computes the same separately rounded product,
explicit FMA residual and quantum allowance, and accumulates those allowances
in that order. The old fold prepended each `(product,residual)` pair: the new
buffer writes that pair backward by pair index, leaving product before residual
inside each pair. The packing input sequence is therefore identical, including
zero products. It does not reverse the allowance accumulation or silently skip
zero insertions.

The largest retained words are copied directly into the immutable record.
Discarded words are visited from highest remaining index to zero, preserving
the old outward radius-addition order. Magnitudes iterate over the same logical
slots from the same initial zero. Radius propagation, precision, series terms,
finite checks and requested limits remain unchanged. The grow and magnitude
helpers are explicitly inlined to avoid boxed float arguments/results; inlining
does not authorize reassociation or implicit multiply-add contraction.

### Allocation-free normal exponent extraction

The product-quantum guard needs only the exponent returned by `frexp`. For a
finite normal binary64 word with stored exponent field `E`, its value is
`sign * (1 + fraction/2^52) * 2^(E-1023)`. Moving the significand into `[1/2,1)`
gives exactly `frexp_exponent = E-1022`, for either sign. The implementation
extracts bits 52–62 with integer operations. Field zero retains the original
`Float.frexp` path for zero/subnormals, so their normalization is unchanged.
Product finiteness and the enclosure construction boundary exclude nonfinite
operands before this helper is used. The existing `ea+eb >= -968` criterion and
one-quantum underflow allowance are unchanged; no mantissa tuple is needed for
normal inputs. Independent rational product checks and a biased-exponent mutant
exercise this bound, including inputs adjacent to its cutoff.

The ordinary rational/component/model suites, native/bytecode sum guard and
complete public certificate replays remain required. New packed-word and normal
exponent mutations complement the existing discarded-word, residual, underflow,
series and final-acceptance witnesses.

### Magnitude-ordered exact sums

The grow loop now selects the larger-magnitude operand at each addition. It
computes `s = RN(a+b)` and then `b - RN(s-a)` if `|a| >= |b|`, otherwise
`a - RN(s-b)`. Each subtraction rounds separately. The magnitude comparison
establishes the exponent ordering required by FastTwoSum; it is not inferred
from the expansion's current storage order.

[Kornerup, Lefèvre, Louvet and Muller, *On the Computation of Correctly-Rounded
Sums*, Theorem 1 and Algorithms 1–3, pp. 2–3](https://perso.ens-lyon.fr/jean-michel.muller/TC-2010-04-0248.R1.pdf)
establish the exact residual in binary arithmetic with nearest rounding and
gradual underflow, provided the initial sum does not overflow. Their magnitude
ordering satisfies the theorem's exponent premise. Zero operands give the same
identity directly; the theorem's nonzero premise is therefore not an exclusion.

This is an algorithm substitution, not reassociation authorized by a real-number
identity. Both it and the previous Knuth TwoSum compute the same rounded sum
and exactly representable residual on their finite domain. Nonzero residuals
therefore have identical words. Any signed-zero residual difference disappears
at grow's existing zero-elimination branch. Carry, retained words, discarded-word
radius order, and all downstream numerical formulas remain unchanged.

The final residual check enforces finiteness of the whole selected graph:
a finite floating addition/subtraction requires finite operands. Walking backward
from `low = small - (s - large)` reaches the subtraction, both inputs and `s`.
Thus overflow or a nonfinite input cannot pass this check. The original six
checks followed all the arithmetic; their common exception message is retained.
No multiplication, FMA, finite-exponent allowance or array access is changed.

`test/enclosure_sum.ml` checks exact rational addition over both operand orders,
signs, cancellation, ties, subnormals, exponent extremes and seeded raw-word
inputs in both enclosure configurations and native/bytecode execution. It also
requires explicit overflow refusal. Two named mutations remove magnitude
ordering and finiteness respectively. The wider primitive, model, IV and public
certificate suites remain independent obligations; finite tests do not prove
the theorem or compiler semantics.

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
