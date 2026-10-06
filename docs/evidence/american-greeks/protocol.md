# Estimated American Greeks qualification (#115)

Frozen before derivative reference generation and runtime edits. Baseline is
`a980d1bfdc42a664a2f1bc11cd28263745cb2b98` on American integration. This work
adds estimates, not certificates. Existing price outcomes and European APIs
remain compatibility obligations. Qualification may be delivered in focused
stages; #115 stays open until all five quantities and their evidence are present.

## Coordinates and public outcomes

Delta and gamma differentiate declared-side spot; strike, all cash amounts,
absolute events and coefficients remain fixed. Vega shifts every annual
lognormal volatility level additively. Rho shifts every annual continuous rate,
including drift and discounting, holding yield fixed. These are per unit shifts,
not per percentage point. Theta is the forward valuation-time derivative with
fixed absolute future events, divided by 365 (per day), holding spot fixed.
Bucketed risks and higher derivatives are deferred.

Use validated per-Greek requests with positive finite absolute refinement
targets; vega/rho additionally require positive finite initial bumps. Immutable
configuration rejects empty/duplicate requests. Report the accepted base price,
per-Greek estimated/unavailable/numerical-failure outcomes, numerical diagnostics
and all accepted perturbed prices. Cancellation/resource exhaustion terminates
the request. Work limits cover the whole request, including perturbations;
scratch is call-owned and bounded. No failed derivative becomes a zero Greek.

No ordinary vega is offered at a zero volatility level. Spot zero, deterministic
stopping ties, expiry payoff kinks, valuation cash jumps and unresolved exercise
transitions have explicit unavailable outcomes where the implemented derivative
route does not establish a smooth quantity. Future knots are not valuation
events and must remain fixed in theta. A Bermudan right at valuation can create
a jump as the right passes: report theta unavailable, even if price succeeds.
Expiry theta is unavailable. State any additional capability exclusions openly.

## Derivation and numerical acceptance

For numerical prices, extract delta/gamma from the same spot-anchored grid,
never from spot bumps that silently rebuild different meshes. With left/right
distances a,b and slopes L=(V0-Vminus)/a, R=(Vplus-V0)/b, use
delta=(b*L+a*R)/(a+b), gamma=2*(R-L)/(a+b). Compare adjacent and twice-wide
stencils; nonuniform gamma has an O(|b-a|) third-derivative term, so do not claim
universal second order. Evaluate both exterior-boundary solutions and every
existing space/time/domain/cash-mapping refinement. Reject mixed or unresolved
exercise/continuation neighborhoods. Grid equality is empirical, not proof of
the continuum exercise boundary.

In smooth continuation use theta=(r*V-(r-q)*S*delta-
sigma^2*S^2*gamma/2)/365 with current coefficients; exercise-interior theta is
zero only when the whole tested neighborhood supports that classification.
For analytic no-cash terminal reductions, use original-word enclosed R,Q,A
integrals and derivatives of the integrated European formula. A justified
no-early-exercise call reduction has the same spatial Greeks; perturbations
must independently satisfy its preconditions. Other analytic stopping regimes
must not be mislabelled European.

Vega/rho use central shifts h,h/2,h/4 on unchanged spatial grids and event
schedules. Require each original level plus/minus each shift to be exactly
representable; otherwise decline the perturbation rather than silently changing
the parallel real family. Nonnegative volatility remains mandatory. Compare
derivative estimates across both bump and all solver refinements. Cancellation
in subtracting prices receives a separate arithmetic indicator. Retain the
amplified underlying price refinement indicator; it is neither a rigorous bound
nor evidence that the derivative's mesh error cancels. All diagnostics remain
empirical. Do not extrapolate away failed refinements.

For each requested derivative, all successive refinement changes and final
boundary/stencil/arithmetic indicators must be <= target/8, and the sum of final
changes and indicators <= target/2. Bump changes participate in the same rule.
Nonfinite indicators fail. These are engineering acceptance screens, not derived
continuum bounds. Analytical arithmetic enclosures must also fit target/8.

## Independent evidence

Retain all 40 original-word #114 rows, adding expiry strike kinks, deep exercise,
valuation Bermudan rights, near-exercise stocks and no-early-exercise calls.
Keep unavailable and unresolved rows. Freeze input words before scoring.
Primary derivative targets: delta 0.001; gamma 0.0001 (currency inverse);
vega/rho 0.05 currency per unit; theta 0.0001 currency/day. Separate loose
targets: 0.02, 0.002, 1, 1, 0.005 respectively. Use price targets and 32/128
base resolutions already frozen for #114. Initial vega/rho bump is 2^-10.

Execute QuantLib 79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c at 128/256/512:
its log-grid spline delta/gamma and snapshot theta are a canonical comparison,
not truth. Preserve date/convention exclusions. Independently use the original
Gaussian quadrature at 256/512/1024 with derivative stencils and perturbations;
retain reference mesh, stencil and bump uncertainty. For analytic reductions
use mpmath 1.3.0 at 80/160 digits with independently differentiated formulas.
For numerical references the empirical radius is four times the maximum of
the last two refinement changes plus stencil/bump/boundary/arithmetic indicators.
Only reference radii <= target/8 count as resolved; accepted runtime estimates
must satisfy absolute discrepancy plus reference radius <= target. Neither
unresolved reference nor runtime refusal counts as an accuracy pass.

Record exact sources/binaries/commands, raw failures and source-drift guards.
Collectors reject missing, duplicated, malformed, nonfinite or truncated rows,
timeouts/startup failures and impossible criteria. Preserve 572 prior price
outcomes; ordinary European determinism digest remains unchanged. Run native/
bytecode, type/ownership, cancellation/resource, dev/release, install/format,
and affected compiled mutation witnesses. Keep default five CI jobs/seven core
mutants unchanged. Characterize price versus requested Greeks, allocation and
latency in repeated fresh processes only after task-owned validation exits.
Performance is characterization, not a newly invented deployment SLA.

## Primary source inspection

Read pinned QuantLib FdmBlackScholesSolver and FdBlackScholesVanillaEngine source:
delta transforms the log-grid derivative by 1/S; gamma transforms
(V_xx-V_x)/S^2; theta delegates to a rollback snapshot. The project's grid is
in stock coordinates and its theta uses the local model equation instead.
No upstream implementation is copied into the runtime.
