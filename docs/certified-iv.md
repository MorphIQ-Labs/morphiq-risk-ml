# Exact-model IV acceptance

This design closes a different obligation from the approximate evaluator's
bounded iteration: every accepted positive inverse must be the nearest-even
binary64 rounding of the real inverse of the exact quote. This is a chosen
contract, fixed before scoring; it is not a tolerance fitted to a corpus.
Existing fast inverses supply proposals only. The independent
[model enclosure](model-enclosures.md) supplies every acceptance decision.

## Classifications

Expiry is independent of volatility. At positive maturity, enclose the
intrinsic I and, for lognormal models, the limiting maximum M from original
inputs. `Q>=M`, proved by an enclosure or exact equality, has no finite root.
An unresolved comparison is computational failure. Never reuse a DD point
estimate as if it were a proved sign.

Compare I-Q. Exact equality gives zero. If I>Q, preserve the existing
rounding-boundary convention only when I is proved to round to Q: compare
I with the exact midpoint of Q and its successor, resolving an exact tie by
the low bit of Q. Above that midpoint gives below-intrinsic. An unresolved
midpoint comparison fails. If I<Q, monotonicity gives a unique positive
real root below M (or with no finite upper price limit for Bachelier).

A mathematical root below the least positive binary64 is reported separately
when the intrinsic is below Q and the least positive volatility's enclosed
price is strictly above Q. A root above the largest finite volatility likewise
requires a proved price comparison at that volatility. Intermediate overflow
or an unresolvable endpoint cannot establish either classification.

## Positive-root acceptance and finite work

First test the proposal's exact rounding-cell midpoints. A strict negative
residual at the lower midpoint and strict positive residual at the upper
midpoint place the unique real root inside that cell, proving the returned
proposal is its correctly rounded binary64. Midpoints are unevaluated exact
sums where representable by the enclosure representation, not rounded floats.
If their enclosure cannot resolve the decision, there is no successful result.

Otherwise establish a strict residual-sign bracket around the proposal by
expanding its offset in the ordered nonnegative binary64 encoding. The
finite encoding has fewer than 2^63 positive values, so at most 64 expansions
reach a representation endpoint. At every expansion, nonfinite arithmetic
or an unresolved sign is visible; no discarded or failed row is a root.

Bisect a proved bracket by the integer encoding. Each step reduces its number
of representable intervals by at least half. At most 63 steps reach adjacent
floats. Then enclose the model at their exact real midpoint. A negative price
residual selects the upper float; a positive residual selects the lower;
proved exact equality selects the even endpoint. An unresolved midpoint fails.
When an interior candidate's price sign is unresolved, its rounding cell may
still be proved; otherwise fail rather than making an unproved bracket update.

All accepted results therefore come from a proved exact root, a proved
rounding cell, or a proved adjacent-float bracket with its midpoint decided.
There is no small-step, rounded-price-equality, last-iterate, measured-error or
iteration-cap success path. Bounds include the final volatility coordinate:
the independent evaluator receives sigma itself, rather than certifying total
volatility and assuming division by sqrt(T) preserves the result.

The enclosure representation cannot resolve every admitted finite input.
Its guards and arithmetic uncertainties define computational capability;
they are not additional mathematical invalidity. Explicit failure is part of
this contract. Production suitability still requires an intended-use domain,
coverage/failure-rate requirements, performance evidence and independent review.

## Working precision and residual scale

The runtime first tries two-word expansions, then
[four-word expansions with explicit error radii](runtime-enclosures.md) if the
first certificate cannot decide. [Both attempts](adaptive-certification.md) use
the same acceptance criterion. Word count is a working-precision choice, never
an assumed error bound. Each
decision depends on propagated arithmetic and analytical remainder bounds.
In particular, the normal tails use bracketing continued-fraction convergents;
no measured normal-function ULP ceiling is part of this certificate.

For Q>0, the evaluator encloses `V/Q-1` directly, using the
[quote-scaled formulas](model-enclosures.md#quote-scaled-inverse-residual).
This positive scaling preserves every residual sign and can retain a tail
whose unweighted probability would underflow. Residual preparation happens
after intrinsic/maximum classification, so a failure in an unnecessary
normalization cannot replace a proved boundary result.

All 5,575 positive reference roots in the public fixture must succeed and
equal their nearest-even reference. Independent controls cover cap exhaustion,
unresolved signs, ties, below-smallest and above-largest comparisons, the
full positive encoding and sparse displaced input words. The additional
stride-67 campaign supplies distant proposals; its unresolved rows are
reported separately and never counted as accuracy passes.

An additional independent interval audit evaluates both exact rounding-cell
midpoints with FLINT/Arb's erfc-based model formulas. It proves strict opposite
residual signs for all 5,575 fixture roots at 256-bit working precision; none
is unresolved. [Versions and fixture/script hashes](evidence/arb-iv-reference.json)
are retained. This independently checks the reference rounding decision beyond
two mpmath precisions agreeing. It does not verify all OCaml executions or
replace human review. See Johansson's [Arb paper](https://arxiv.org/pdf/1611.02831v1).

Reproduce outside ordinary CI with `python-flint==0.9.0`:

```sh
python scripts/arb_iv_audit.py oracle/fixtures/iv.txt.gz --output /tmp/arb-iv.json
```

A concrete supported failure is displaced F=K=2^64, displacement=2^-1074,
T=1, r=0, Q=2^64. The exact maximum exceeds Q and a finite inverse exists,
but the representation cannot resolve the sparse gap. `Numerical_failure`
preserves that distinction from `Above_maximum`. Likewise, an overflowing
normal distance is a computational failure even when the true inverse is
finite. These are availability limits, not exceptions to the Root guarantee.

The [replay audit](evidence/certified-iv-replay.json) records 6,272 changed IV
values across 30,240 model records, with no price, Greek or outcome-category
changes. Replay is compatibility evidence, not an independent accuracy proof.
