# Bermudan campaign policy v1 (#113)

Freeze before reference execution and runtime changes. Baseline integration is
9635803a0586875d23f4dfebea3f779834f2e29d (#133). Original binary64 words, explicit
finite exercise instants and joint liquidator cash jumps define the quantity.
The 32-case corpus includes terminal reduction, sparse/irregular/dense and nested
rights, zero volatility, signed rates/yields, low volatility, absorbing stock,
zero strike, valuation/expiry event sides, zero/coincident/large cash amounts.

Admission must freeze a nonempty strictly ordered array of exercise instants,
reject duplicate instants, and require first time=opens_at and last time=T.
With cash, the first/last sides must match opening/expiry; all instants use
Regular exactly off cash dates, Before/After exactly on cash dates. Both sides
at one physical time are distinct. No silent sorting, deduplication, inserted
expiry or extension to continuous exercise. The admitted schedule getter returns
a copy and retains Bermudan identity even for a terminal-only reduction.

Backward evaluation uses linear continuation between exercise instants. At a
joint cash event, project permitted After rights, map max(S-D,0), then project
permitted Before rights. Regular rights project at their exact times. The
absorbing put boundary discounts to the next permitted right for positive rates,
or the last for negative rates. No exercise between listed dates. Deterministic
paths maximize over those dates only; American stationary points are irrelevant.

Reference strategy, fixed before observations: original positive three-point
Gaussian quadrature, separate from the runtime PDE/policy solver, with N=256,
512,1024 steps per union-event slab and 16N logarithmic stock nodes. Projection
occurs only at listed dates. Compare zero/global-cap exterior envelopes.
Empirical radius = 4*max(last two refinement changes) + final boundary half-spread
+ 256*u*N*scale. This is an engineering uncertainty estimate, not a certificate.
Use independent 80/160-digit original-input analytical/deterministic calculations
where available. Check a fixed quadrature problem at both precisions separately.

Execute pinned QuantLib 79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c at grids 128,
256,512. Retain unmodified Bermudan engine results and original finite-rights
liquidator adapter results separately. QuantLib sorts its input dates; our public
admission must reject unsorted inputs. Cash floor/coincident/side differences
must not be called matching conventions. Date conversion, deterministic/zero
boundaries and endpoint cash exclusions remain explicit; no missing row is a pass.
No third-party runtime code is imported or translated.

Primary epsilon=2^-16*max(S,K), separately loose epsilon=max(S,K)/100. Reference
radius must be <=epsilon/8; use the existing independent scorer and keep every
unavailable/unresolved row. No accuracy target is widened after scoring. Reuse
#112 initial (32/32) and refined (128/128) configurations and limits, retaining
independent space/time/domain/cash-mapping changes. Exercise dates stay fixed
across numerical refinements. Results remain estimated-only.

Validate singleton European reduction, nested-rights ordering and American
domination with matched models and explicit refinement/reference uncertainty.
Test admission ownership/order/sides, before/after dividend competition, valuation
rights, zero-time expiry, cancellation/resource/failure controls, native/bytecode,
concurrent independent calls, wrong references and malformed/truncated runners.
Add affected optional numerical mutants; default CI stays five jobs/seven core.
Preserve existing American and European capability with full ordinary suites and
284 American complete-outcome comparisons. Measure representative Bermudan costs
and matched American regression only after task-owned compute finishes, with
repeated processes, source/binary hashes, allocation/GC and host load. Broader
performance remains #119; strict/source-artifact qualification remains #120.
