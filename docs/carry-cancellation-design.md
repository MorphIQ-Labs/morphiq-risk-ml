# Severe carry cancellation: bounded price refinement (#76)

For the exact binary64 inputs S=1+2^-52, K=T=1, q=0,
r=-2^-52+2^-105, the zero-variance call is S-exp(-r). Its positive
leading term is of cubic order in 2^-52. Forming a double-double logarithm
before adding carry discards terms that dominate this final difference; more
accurate evaluation of `expm1` on that already rounded coordinate cannot recover
them. Switching to a subtraction of two double-double discounted legs has the
same precision limitation.

The refinement reuses the existing bounded original-input real-model
enclosure. Dispatch asks whether actual cancellation occurred (`|x| <= terms/2`)
and the resulting coordinate lies within a conservative estimate of its DD
arithmetic uncertainty. The existing normal-intermediate coordinate analysis
uses 32u² for the logarithm, 9u² for assembly, 15u³ for the quotient correction
and 5u² for displaced low parts. Round upward for dispatch to
`64u² terms + 16u³ + (8u² if shifted low words are present)`, u=2^-53.
The term magnitude must be positive and finite. Requiring cancellation avoids
misclassifying tiny uncancelled carry because of the absolute quotient allowance.
This dispatch estimate is not a runtime error certificate or a universal
accuracy guarantee on unselected fast paths; only the refinement's actual
interval and rounding-cell check justify its returned value. No accuracy
allowance changes.
Zero-volatility and positive-volatility pricing must share the dispatch: an
incorrect intrinsic must not be reintroduced by a tiny positive volatility.

Construct the model from the stored original spot/strike words (including exact
displaced low parts), maturity and rates. Accept only a finite binary64 candidate
whose exact nearest-even rounding cell contains the full returned enclosure.
Test candidate and immediate neighbors; if no cell is resolved, return NaN through
the existing float-returning fast-price failure convention. No approximate DD
fallback is allowed after an inconclusive refinement. The existing enclosure
configuration has bounded series/expansion work and explicit domain failures.
This may reduce fast-price availability for severe cancellation at positive
volatility: a broad finite enclosure is not a rounding certificate.

The existing rounding-cell check for boundary veta is the shared operation owner;
shares the implementation with this price path; its default zero exponent retains the existing arithmetic and acceptance. Retain exact-input Arb
references, rate/time/scale/call-put neighbors, observed successful/refused counts,
ordinary-fixture deltas, affected mutation witnesses and before/after timing.
New values/refusals are a major numerical/outcome change (minor at version 0.y.z),
not a patch merely because the mathematical model stays unchanged.

## Zero-variance identity and scaling

Write c=(r-q)T and Dq=exp(-qT). Then

    S exp(-qT) - K exp(-rT) = Dq [(S-K) - K expm1(-c)].

The new zero-variance refinement evaluates the right side with four-word runtime
enclosures. Keeping `expm1(-c)` separate from 1 retains the small terms before
subtraction. The expansion owner bounds every discarded word and series tail;
nominal word count alone is not an error claim. A proved negative/nonpositive
signed difference gives exact zero payoff. Indeterminate sign returns failure.
Discount is evaluated as the fourth power of exp(-qT/4), within the existing
exponential domain; an out-of-domain intermediate remains a failure.

Currency homogeneity permits a power-of-two normalization, but only after every
scaled high/low word passes exact round-trip reconstruction of its original.
Otherwise the computation uses original, unscaled words. The final rounding
check compares neighboring binary64 cell endpoints in that normalized scale.
This preserves half-subnormal cell boundaries when scaling them is exact;
any residual scaling uncertainty remains in the enclosure. The returned value
is never obtained by blindly rounding an already rounded intermediate.

For positive volatility the existing original-input `Model_enclosure.price`
evaluator supplies the bounded refinement. It can be inconclusive for tiny
volatility and near-zero forward moneyness. The implementation deliberately
returns NaN then, including some values whose old approximation happened to be
within budget. There is no claim of universal availability. IV retains its own
existing exact-model certification; this change does not make the DD proposal
an inverse certificate or certify every fast Greek field.
