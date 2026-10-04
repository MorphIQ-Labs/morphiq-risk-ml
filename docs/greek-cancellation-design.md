# Fast Greek capability under unresolved carry cancellation

The inputs and derivative conventions remain those in model-contracts.md.
For positive maturity and volatility, write x=log(S/K)+(r-q)T,
s=sigma sqrt(T), h=x/s and d1,2=h +/- s/2. If formation of x loses delta-x,
the d coordinates lose delta-x/s. The density logarithm changes by
-d1 delta-d1-(delta-d1)^2/2; derivatives also contain factors in d1, d2,
1/sigma and 1/T. Finite output checks and an independently refined price do
not control these errors. All ten sensitivities use these coordinates or
their payoff classification. The retained #80 original-input Arb witness
shows inaccurate finite outputs in all ten fields.

## Supported computation

Share the existing price refinement dispatch, with its unchanged component
majorants and finite-exponent qualifications in carry-cancellation-design.md.
When that dispatch identifies exhausted DD coordinate precision, the fast
Greek evaluator returns Numerical_failure in every field before evaluating
its formulas. This is a declared capability restriction, not a proof that
all those real derivatives are inaccurate or undefined. It sacrifices some
accurate baseline results. No budget is widened and no failed field counts
as an accuracy success. The unrestricted fast paths retain their existing
finite-corpus assurance; this dispatch does not prove universal accuracy.

Also refuse a computed zero coordinate unless the original exact inputs
establish ATM: S=K (including displaced low words) and r=q. A zero produced
by carry underflow or cancellation cannot establish a payoff kink, nor be
used as exact zero in smooth positive-volatility derivatives. Original-word
identity is sufficient to preserve the existing genuine ATM boundary paths.
Other computed-zero coordinates remain a numerical capability failure; the
restriction does not assert that the requested derivative is undefined.

Expiry remains owned by Greeks.expiry. Exact ATM at zero volatility retains
its coordinate-specific kinks, right derivatives and certified veta. Tied
Black-76/displaced models have zero carry; their ordinary paths and exact
shifted-sum identity remain unchanged. Prices, Production and certified IV
retain their own owners and acceptance contracts.

This is a major outcome change (minor while 0.y.z). Qualification must retain
original-word rate/time/currency/call-put/volatility neighbors, tied and
shifted controls, independent reference uncertainty, per-field transitions,
a regression for all ten discovered outputs, a refusal-bypass mutant and
separate admission/price/Greek measurements. There is no universal Greek
accuracy or availability claim. Future original-input sensitivity refinement
may restore values only with its own numerical justification.

## Zero-variance theta sibling

Common-discount neighbors also expose cancellation of qA-rC after the two
legs were rounded separately to binary64. This is outside the exhausted-x
restriction: x can retain its sign while theta loses its discount-leg
residual. Evaluate the exact identity q(A-C)+(q-r)C in DD, using the existing
DD intrinsic and cash-leg owner and an exact-input DD rate difference.
Restore the currency exponent once after assembling the annual derivative;
then apply the existing daily unit conversion. OTM derivatives remain zero.
This removes the avoidable binary64 leg subtraction; it does not establish
a universal relative bound near every zero of theta. Existing theta budgets
and independent neighbor references remain unchanged.

## Smooth theta component cancellation

Low-word displaced controls expose a second route: d1 can be accurate while
q A Phi(d1) and r C Phi(d2) cancel beyond DD precision. Correct coordinates
alone cannot repair this. In the DD-CDF branch, refuse only theta when the
annual result is inside the component noise scale
`[2048 + 16 (|qT|+|rT|)] u² (|qA|+|rC|)`, u=2^-53, with positive component
magnitude. The 512u² absolute CDF allowance, `(40+3|rate*T|)u²` leg allowance
and DD assembly allowances motivate this upward-rounded selector before
scoring; it is not a runtime interval bound. In particular, finite-exponent
qualifications and errors outside this selected region remain unchanged.
The mathematical derivative stays smooth: only this field reports
Numerical_failure through the existing finite-result owner. Other fields
retain their independently scored outputs. No accuracy budget is widened.
