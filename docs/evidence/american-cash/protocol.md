# Cash-dividend campaign policy v1

Freeze this corpus/protocol before canonical/reference execution or runtime
changes. Original words, the liquidator joint cash event and explicit
Regular/Before/After sides define the model. Distinct times are never merged.

Retain every row and exception. Primary epsilon=2^-16 max(S,K), plus a separately
labelled loose epsilon=max(S,K)/100; reference radius must be <=epsilon/8.
Use the existing independent scorer. Unresolved references cannot pass.

Independent reference: original discounted three-point Gaussian transition
quadrature with positive weights (1/6,2/3,1/6), piecewise-linear stock-value
interpolation, explicit zero state and exact cash-event scheduling. This is
not a PDE/policy solve. Refine N=256,512,1024 steps per slab with 16N logarithmic
stock nodes between scale*2^-14 and 32*scale, plus zero/spot/strike. Compare
both admissible upper-boundary envelopes. Empirical radius is four times the
largest of the last two changes plus the final boundary half-spread and a
256*u*N*max(S,K) arithmetic screen. No extrapolation or containment theorem.
Exact rational zero-carry/zero-volatility witnesses and independent 80/160-digit
closed-form/event calculations supplement the stochastic quadrature. A small
80/160-digit quadrature replay checks arithmetic of a fixed discrete problem.

QuantLib is pinned at 79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c. Retain unmodified
Spot-dividend engine results, explicitly noting its positive mesh-floor mapping
and duplicate-time handling differences. Also execute the pinned canonical FDM
solver with an original liquidator event adapter for strictly interior events;
never present that adapter as an unmodified upstream dividend engine. Endpoint
side/date/zero-stock exclusions stay visible. Canonical grids 128,256,512.

Runtime configurations use three independent space/time/mapping levels and
three domains with original frozen #109 criteria. Base cells/steps: 32/32
(initial) and 128/128 (refined). Both have two domain doublings. Initial limits:
4096 nodes,32768 steps,262144 policy solves,200000000 row visits,4194304 bytes,
64 policies/step. Refined: 8192 nodes,131072 steps,1048576 policies,1000000000
row visits,8388608 bytes,64 policies/step. No criterion is widened after scoring.

Mapping is independently refined using a pre-jump sampling grid: evaluate the
incoming PDE interpolant at max(s-D,0), then project that sampled jump function
back onto the PDE grid. Vary mapping samples with PDE space/time fixed; vary
PDE space with mapping samples fixed at the finest level. Record both changes
and arithmetic/cell-width diagnostics. This is estimated-only, not certification.

Controls include schedule freezing/invalid sides/order, joint sums, zero-time
rights, pre-dividend exercise, zero cash, limits/cancellation, malformed/missing
runner data, wrong references and optional premium unavailability. Compare the
old no-cash corpus unchanged, then measure no-cash/zero-cash/positive-cash costs
separately with all task-owned compute finished and host load recorded.
