# Exchange qualification protocol, version 1 (#61)

Freeze membership and these bounds before scoring the new campaign. Preserve
all 66 implementation controls, then add correlated/reversed, unequal/equal
carry, zero/equal/unequal volatilities, two maturities, dyadic currency scales,
extreme volatilities and discount-domain neighbors. Original binary64 words,
case IDs, limits and mandatory success flags are in cases-v1.json. No new
runtime behavior or allowance change is part of qualification.

Use the implementation's two independent original-word routes, precision
ladder 256/512/1024/2048/4096, quadrature degree 128, 20,000 evaluations,
depth 30, one 60-second worker per row and at most 10,000 frozen rows. Every
worker failure, unresolved row, invalid input, explicit runtime failure and
served certificate remains accounted for. Acceptance requires both complete
independent intervals inside the served currency certificate and its radius
within the original requested limit. Unresolved is never an accuracy pass.

## Extreme volatility: independent payoff-deficit bound

Let X=a exp(-s^2/2+sZ), with Z standard normal. Then
`a-C=E[min(X,b)]`. Split at Z=c. The first part is at most
`E[X 1(Z<=c)] = a Phi(c-s)` by completing the square in the expectation;
the second is at most `b P(Z>c) = b Phi(-c)`. For s>=80 choose c=40.
Both tails are at most Phi(-40), so

    0 <= a-C <= (a+b) exp(-800)/(40 sqrt(2*pi)).

This is a bound directly on the positive payoff expectation, independent of
closed-form CDF subtraction. Its implementation uses rational v>=6400 as the
exact precondition and Arb for all discount/tail arithmetic. The symmetric
interval a +/- deficit is deliberately conservative. Precision refinement
and the same 256-relative-bit reference goal still apply. A too-wide deficit
bound stays unresolved, rather than being forced to overlap a certificate.
The previous `volatility-49` unresolved result is retained in #60 history.

## Other qualification lanes

- Retain #86's three-platform CI and unchanged prior replay, then execute the
  manual candidate workflow on its immutable merge commit: source-artifact
  installation, native/bytecode consumers, ordinary tests, canonical portfolio
  replay and full optional mutation catalog. Default CI remains seven mutants.
- Run a source-bound scalar stream scorer and check reversal/parity and dyadic
  currency scaling only with compatible quantities and outward error arithmetic.
- Measure admission and certified evaluation/end-to-end separately. Alternate
  equivalent repeated workload runs, retain host load and allocation, and do
  not infer idle-machine costs or optimization speedups. There is no exchange
  portfolio adapter to benchmark; prior portfolio compatibility remains tested.
- Publish scope, finite outcome counts, unresolved/failure dispositions,
  qualification source/artifact/platform identities and a claims-map update.
  Experimental qualification is not a release or institutional approval.
