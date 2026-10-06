# Frozen American inverse protocol (#117)

Base: `d34c77b6ee89b294545e06bf20a4bfe28622545b`. Freeze this contract and
reference campaign before editing runtime numerics or scoring the inverse.

Invert one constant annual lognormal volatility with every other original input,
cash amount/event side and exercise right fixed. The volatility present in the
admitted contract is replaced, not used as an inferred curve. Piecewise inversion
is excluded by its distinct admission type; no one-quote curve fit is implied.

Support no-cash calls/puts and liquidator cash calls under a derived nondecreasing
volatility comparison. Refuse cash puts explicitly: the terminal-after-cash put
at S=D=100, K=10, r=q=0, T=1 has value K-C(S,D)+C(S,D+K), which is nonmonotone in
sigma. Independently evaluate that identity before implementation. A zero/empty
cash record may be conservatively excluded for puts; never drop event semantics.

Expose a separate estimated-only inverse API. Validate a finite nonnegative
quote and a finite increasing typed volatility search range, positive absolute
volatility-width target, and explicit maximum price-call count. Preserve the
original quote word. Results are private estimated intervals with their endpoint
price observations, empirical price-uncertainty indicators and evaluation count,
not point roots, rigorous volatility enclosures or nearest-even certificates.

Use bounded bisection with explicit overlap handling. A price is classified below
or above the quote only after its refinement, roundoff and boundary indicators
are included with outward comparison arithmetic. Do not turn an overlapping
price band or zero vega into a root. Quarter probes may tighten an overlapping
midpoint while preserving strict opposite endpoint signs. If uncertainty prevents
progress, report uncertainty-or-plateau. Success requires the entire remaining
volatility interval width to meet the requested target, not a price residual.
No claim of strict monotonicity or uniqueness follows from nondecreasing prices.

Separate invalid requests, unsupported capability, proved no-solution boundaries,
volatility-independent contracts, search-range exclusion, pricing failures,
uncertainty/possible plateaus, sampled monotonicity violations, unrepresentable
progress and bounded exhaustion. A finite search endpoint never proves global
nonexistence. Exact expiry/absorbing payoff witnesses must not fabricate a root.

Partition the existing pricing step/solve/row limits across the maximum price
calls, reserve bounded inverse metadata from the workspace limit, and retain
callback exceptions and cancellation at every pricing call and before return.
Do not allocate a price-call-sized history or multiply counters without checks.
The existing price/Greek/certified APIs remain unchanged.

Before scoring, independently generate original-word exact-quote inverse
references. Use Arb European formulas for no-early-call and terminal-only rights,
including cash at terminal After_cash (effective strike K+D in the reference's
exact arithmetic only). Include call/put, signed rates/yields, short maturity,
low-vega/deep-ITM, quote perturbations and boundary/plateau refusals. Establish
new fixed-quote lattice and pinned QuantLib comparisons for genuine American and
finite-rights puts; retain precision/grid disagreement and unresolved rows.
Never score only repricing by the runtime's own approximation or assume that a
rounded generated quote has exactly its generating volatility as root.

Initial campaign: sigma search [0.05,0.6], width target 0.05; separate tighter
challenge 0.005. General estimated pricing uses 128 space/time cells, two domain
expansions and refinement target 1 currency unit for S,K around 100. Also exercise
32-cell controls, strict price targets and bounded exhaustion. These are explicit
engineering targets, not calibration accuracy or deployment acceptance. Preserve
all failures; do not loosen criteria to obtain success. Every accepted interval
must contain the entire resolved independent reference interval; a too-wide or
unresolved reference is not a pass.

Run development/release suites, native/bytecode and installed consumers, private
API type rejection, callback/resource and incorrect-uncertainty/bracketing/guard
mutants. Default CI remains five jobs/seven core mutants. Retain complete existing
ordinary outcomes; no European certificate or historical review is transferred.
Measure admitted solve and end-to-end cost only after owned validation ends:
five fresh processes, warmup, raw samples, allocations, source/binary/toolchain
identity and host load. No speed target is assigned. General pricing availability,
full source-artifact qualification and institutional acceptance remain explicit.
