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

## Reference resolution correction, version 2

The v1 comparison retained 39 failed containment comparisons caused by
insufficient oracle resolution and 28 unresolved reference rows. These are not
silently scored as runtime defects or passes. In particular, 100 decimal
printed digits can obscure a deficit smaller than 1e-300 from an exactly
representable currency value, and a 256-bit relative stopping goal cannot
adjudicate a certificate dominated by tiny time value above exact intrinsic.
The original generator, references, runtime outputs and scores remain intact.

Version 2 targets a fixed absolute interval radius `a*2^-1200` for positive
receive value, at the same bounded precision ladder and resource caps. This
resolves below the 1074-bit normalized binary64 subnormal scale with a 126-bit
margin; it is a reference resolution choice, not a runtime allowance. Retain
1400 decimal digits (more than 4096 binary bits) including outward printed
radius; scoring reparses and checks the complete retained intervals. Exact
boundary identities remain exact.

For very deep OTM cases, completing the square gives
`C <= E[X 1(Z>z0)] = a Phi(d1)`. If the independently enclosed d1 satisfies
`d1<=-42`, then `0<=C<=a*exp(-882)/(42*sqrt(2*pi))` by Mills' inequality.
This bounds the positive payoff without evaluating a vanishing relative tail.
It supplies the second route, alongside the independent closed form. Since
this is a finite absolute bound, it must still fit inside the served runtime
certificate; neither passing the reference goal nor route overlap implies
acceptance. Remaining coarse intervals, errors or unresolved results stay
explicit. Case membership, original limits and runtime source are unchanged.

## Bounded quadrature work correction, version 3

The stronger 1200-bit reference goal exposed an integration resource issue:
at 4096-bit arithmetic, requesting a 2048-bit quadrature stopping goal exhausted
the fixed evaluation budget on an ordinary case and returned a broad interval,
although 2048-bit arithmetic had already reached roughly 1024-bit accuracy.
The obsolete v2 campaign was stopped; its completed-status log and generator
snapshot are retained as an aborted diagnostic run, not a completed campaign.

Keep the 1200-bit reference goal and all original resource caps. Request
quadrature tolerance `2^-min(p/2,1280)`, giving 80 guard bits beyond the required
normalized reference resolution without demanding unused 2048-bit quadrature
accuracy. Final interval width and certificate containment still decide
acceptance; the requested quadrature tolerance is not presumed achieved.
All 649 rows are rerun under one generator version, preserving full outcome
accounting. No runtime code, limit, certificate or accuracy allowance changes.
