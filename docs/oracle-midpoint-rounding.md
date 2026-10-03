# Positive time value at an intrinsic midpoint

A price oracle cannot infer rounding solely from agreement at two precisions.
For a BSM call with S=nextafter(1,+infinity), K=2^-53, T=1, r=q=0 and sigma=1e-4,
the exact intrinsic is 1+2^-53. Finite-precision evaluation loses its positive
time value and converts that midpoint to the even lower float 1. The exact
price is strictly above the midpoint and rounds to the next float. This is a
reference-generation defect, not grounds for widening a numerical budget.

The independent campaign also found 16 existing price rows where symmetric
Arb intervals straddle an intrinsic midpoint even at 4096 bits. In those rows
the recorded reference is the upper neighbour and is correct. They require a
one-sided argument rather than an assertion that symmetric refinement passed.

## Exact-input one-sided certificate

Restrict this finite-work shortcut to zero discount/carry (r=0 and, for BSM,
q=0), positive maturity/volatility, and valid positive lognormal coordinates.
Use exact rational binary64 inputs, including displaced sums. Let I be the
exact nonnegative intrinsic. For either side, price=I+TV with TV strictly
positive: a nondegenerate normal/lognormal law has positive probability of an
out-of-the-money payoff. Establish a rational strict upper bound B on TV.

For Black, let a=max(S,K), b=min(S,K) and s=sigma sqrt(T). The elementary
positive atanh series gives log(a/b) >= 2(a-b)/(a+b). Construct a power-of-two
upper bound s_u on s from T's binary exponent. If

    2(a-b)/(a+b) >= 40 s_u + s_u²/2,

then the smaller-magnitude out-of-the-money normal argument is at least 40.
The Gaussian tail inequality follows directly by bounding the integral of
phi(u) by the integral of (u/z)phi(u) for u>z. Dropping the subtracted positive
leg and using Phi(-z)<phi(z)/z gives
TV < b exp(-800) < b 2^-1100. For Bachelier, if |F-K|>=40 s_u,
its out-of-the-money price is s[phi(z)-z Phi(-z)], so
TV < s_u exp(-800) < s_u 2^-1100.

These are conservative work guards, not measured tolerances. The exponential
inequality has an exact rational check: with z=1/3, the first two terms of
2 atanh(z), plus the positive geometric tail bound
`2 z^5/[5(1-z²)]`, bound ln(2) above by less than 7/10. Thus
1100 ln(2)<770<800. The density factor 1/sqrt(2 pi) is less than one.

Form the exact rational adjacent-float cell endpoints for the nearest float to
I. If I is its upper endpoint, advance to the next float: strict TV>0 resolves
the direction even when the original midpoint would round down to even.
Accept a candidate only if I is at or above its lower endpoint and I+B is at
or below its upper endpoint. Both true price inequalities are strict, so the
candidate's parity is immaterial here. Overflow or unresolved premises decline
the shortcut. No finite working precision has to represent the tiny increment.

The standard-library-only helper is shared by the sibling price generators.
The independent Arb audit uses a separately implemented interval tail argument
and exact-cell comparisons. Known midpoint, opposite-side, guard-failure and
nonzero-carry controls must retain their classification. A correct reference
gate is not a claim that the fast price implementation is correctly rounded.

## Corpus and compatibility

The repaired rule is used by the European and displaced price generators and
by IV quote construction. The sibling generators fail on an unresolved row
rather than silently dropping it. Regeneration retains all historical rows
unchanged and adds 24 European prices, eight exact-shift displaced prices and
16 IV cases. [The row comparison](evidence/midpoint-reference-compatibility.json)
retains every addition and the fixture hashes. No production library arithmetic,
served value, replay digest or acceptance budget changes.

The independent [full interval campaign](evidence/arb-full-reference-campaign.json)
certifies all 57,320 European and 41,768 displaced price references. Thirty-two
cases require its separately implemented positive-time-value argument. It also
certifies all 59,200 smooth Greek references. The 7,200 expiry Greek rows are
explicitly excluded from analytic price-series differentiation: 6,780 finite
boundary results and 420 kink classifications. They are not counted as passes;
ordinary boundary tests and the separately scoped zero-volatility study remain
separate evidence. There are no discrepancies or unresolved rows in the audited
sets. Working precision is 256–4096 bits, with exact midpoint/subnormal and
opposite-reference rejection controls.

The [refreshed IV audit](evidence/arb-midpoint-iv-reference.json) independently
certifies all 5,579 positive reference root cells at 256 bits, with no unresolved
cases. Mathematical classification rows retain the ordinary solver/contract
checks; they are not counted as positive-root certificates.

Reproduce the optional campaigns with python-flint 0.9.0 / FLINT 3.6.0:

```sh
python scripts/arb_reference_campaign.py --output /tmp/arb-prices-greeks.json
python scripts/arb_iv_audit.py oracle/fixtures/iv.txt.gz --output /tmp/arb-iv.json
```

These audits strengthen finite-reference evidence and found a concrete oracle
failure mechanism. They are not an independent human review, formal proof of
the whole implementation, or institutional acceptance.

The complete ordinary suite, installation build and pinned formatter pass with
regenerated transitive provenance. All nine affected/core mutations are detected
([log](evidence/midpoint-core-mutations.txt)). A separate isolated Python
[mutation control](evidence/midpoint-oracle-mutation.json) compiles successfully
and is rejected by the numerical regression when the midpoint correction is
disabled. The ordinary numerical replay digest remains
`f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b`.
