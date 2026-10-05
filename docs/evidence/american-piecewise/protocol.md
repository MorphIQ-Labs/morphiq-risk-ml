# Piecewise coefficient qualification protocol (#114)

Frozen before reference generation or runtime changes. Baseline American
integration is `e733c881434eb0ccc9faea045f90f5c13742a1dd` (#135). Scope is scalar
estimated BSM American/Bermudan pricing, optional liquidator cash dividends,
and independent piecewise-constant deterministic rates, yields and volatility.
No new certificate, Greek, IV, market bootstrap or batch API is implied.

## Admission and API

Expose a distinct `Bsm.Piecewise` admission surface, sharing the existing
configuration, failures and estimated result type. Keep existing constant
admission/getters intact; never report a varying curve as a constant input.
Use different abstract curve types for annual continuously compounded rate,
annual continuous dividend yield and annual lognormal volatility. Volatility
levels use `Vol.lognormal Vol.t`, never normal-volatility units.

Each immutable curve explicitly declares its horizon, initial level and ordered
change instants strictly inside (0,T). This is a complete partition: the initial
level begins at zero and the last interval explicitly ends at the declared
horizon. All three horizons must match the admitted option expiry exactly.
Reject nonfinite levels/times, duplicate/unsorted/outside knots and mismatched
coverage. T=0 still validates all initial levels and admits no knots. Levels
apply on [start,end), so a knot selects its right-hand level; expiry has the
last left limit. Getters preserve original schedules and copy exposed arrays.
Only numerically redundant adjacent equal levels may be coalesced after full
validation, retaining original getters. No sort, extrapolation or averaging.

A parallel rate/yield shift adds one annual continuous-rate displacement to
every level of that curve; a segment perturbation changes exactly one original
level. Volatility perturbations are in annual lognormal-volatility units and
must remain nonnegative. These define later Greek coordinates, not new Greeks.

## Numerical obligations

Merge coefficient knots with cash/exercise events. Every rollback slab has
constant coefficients; coefficient events add no Bermudan rights and no stock
jump. At coincident events use After exercise, liquidator mapping, Before
exercise in backward order, with the interval's own coefficients for rollback.
Reuse spatial preparation only when grid AND coefficient dependencies match.
Retain bounded request-owned preparation, original-word enclosures, cancellation
and work limits. New metadata and preparation must fit checked workspace.

For a zero-stock put, maximize K exp(-integral_t^u r) over remaining permitted
exercise instants: allowed window endpoints and rate knots for American, listed
instants only for Bermudan. A rate's local sign cannot select a globally optimal
exercise date when future signs change. A zero-strike no-cash call similarly
uses yield integrals. Safe exterior/stability envelopes use integrals of the
negative parts of rates/yields, not a single terminal average.

All-zero volatility uses a deterministic stock path. Inspect allowed endpoints,
coefficient and cash sides, and American interior stationary points q*S=r*K
within each constant segment. Bermudan checks only listed instants. A partly
zero-volatility schedule retains its stochastic continuation and deterministic
transport segments. For no-cash terminal reduction, enclose R=integral r,
Q=integral q and A=integral sigma^2 from original words before evaluating the
European formula. Unresolved arithmetic stays unavailable.

Constant schedules reduce to the existing constant API and retain its complete
outcomes. Removing redundant identical-level knots must preserve the quantity
and the numerical execution; different profiles with the same terminal R/Q/A
must remain distinguishable when early exercise matters.

## Independent references and acceptance

Freeze original-word cases before generating results: American/Bermudan,
constant/split-equivalent profiles, independently staggered knots, signed rate
changes, interior zero-stock discount optima, signed yields, volatility swaps,
all/mixed zero volatility, deterministic interior maxima, terminal reductions,
cash/coefficient/right coincidences and endpoint cases.

Use original positive three-point Gaussian quadrature with N=256/512/1024 per
union-event slab and 16N logarithmic stock nodes. American projects at numerical
steps inside its window; Bermudan projects only at listed rights. Compare zero
and global-cap exterior values. Empirical radius is four times the maximum of
the last two resolution changes, plus final boundary half-spread and
256*u*N*scale. This is an engineering reference uncertainty, not certification.
Use independent mpmath 1.3.0 calculations at 80/160 digits for analytical and
fully deterministic cases; separately replay a fixed discrete N=8 quadrature
problem at both precisions. Retain unresolved rows.

Execute QuantLib `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c` at N=128/256/512,
using original curve/cash/exercise adapters. Keep unmodified engines separate
from the liquidator/event adapter. Record unsupported date conversions,
analytical boundaries and cash-side differences per row. No upstream runtime
code is imported. Read and record the actual coefficient/rollback interfaces.

Primary epsilon=2^-16 max(S,K); separately loose epsilon=max(S,K)/100.
A reference radius must fit epsilon/8 to count as resolved. Use initial 32/32
and refined 128/128 configurations with existing resource limits. Do not change
targets or drop failures after scoring. Preserve 412 complete existing constant
American/Bermudan outcomes and their independent classifications.

Run development/release ordinary suites, install/format, native/bytecode and
public type/ownership/cancellation/resource witnesses; execute affected named
mutations with numerical/precondition kills after successful builds. Add faults
for averaging a varying profile, selecting the wrong side of a coefficient knot
and an incorrect future discount optimum. Default CI remains five jobs/seven
core mutants. Full catalog and release/source-artifact acceptance remain #120.

Measure matched constant-path regression and representative varying no-cash/cash
prices after task-owned compute finishes: five alternating fresh-process rounds,
one warmup and three reused-admission prices; preserve raw output, allocation,
GC, per-child RSS, source/binary/compiler identity and host load. Investigate a
constant-path median latency increase above 10% or allocation above 5% before
adoption. New varying workloads are characterization, not invented SLAs.
