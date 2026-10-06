# American solver and assurance design

**Design for [#109](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/109),
under Epic #107. No runtime American pricer or certificate is delivered here.**
The [financial contract](american-model-contract.md) at #108 defines the target.
This document selects the first implementation architecture, freezes engineering
acceptance rules before pricing comparisons, and gives #116 a certification gate.
Existing European APIs, numerical values and certificates are unchanged.
The subsequent [#111 implementation and executed limits](american-pricing.md)
are documented separately. The [#113 Bermudan implementation](bermudan-pricing.md)
uses the continuation-only/discrete-projection rule below; numerical refinements
preserve the financial exercise instants. Its independent references and executed
limits are separate from this design evidence.

Select a nonuniform **stock-space grid including zero**, a monotone spatial
operator, backward Euler time stepping and policy iteration for the American
obstacle. Start with a compact OCaml tridiagonal kernel with checked matrix
conditions. Keep damped Crank–Nicolson and a pivoted LAPACK backend as explicit
comparison candidates; neither is required for #111. #110 must supply independent
pricing references before #111 changes runtime numerics. A small exact-rational
experiment below checks discrete algebra only.

## 1. Stopping problem to obstacle problem

Write calendar time t increasing towards expiry T, and define the discounted
continuation generator between events as

    L f = a(s) f_ss + b(s) f_s - r f,
    a(s) = sigma² s² / 2,    b(s) = (r-q)s.

The dynamic programming alternatives are immediate exercise g(s), when allowed,
and discounted continuation over a short time. Expanding the latter gives the
variational inequality, in the viscosity sense when derivatives fail to exist:

    min(V-g, -V_t-LV) = 0                 within an American window;
    V_t+LV = 0                           when exercise is not allowed;
    V(T,s) = g(s)                        at the terminal event side.

Thus V >= g and V_t+LV <= 0 in the exercise window, with equality of at least
one alternative. There is no assumption of a single exercise boundary. A delayed
opening uses the obstacle only inside its remaining window, including opening.
Outside it, imposing max(g,V) would change the financial contract.

Bermudan rights are discrete max operations separated by continuation solves,
not an American obstacle on intervening steps. At a cash event, work backward:
post-event exercise, the map V_after(max(s-D,0)), then pre-event exercise. An
expiry before the event terminates before that map. Original instants determine
this order; all events with equal physical time are processed without a time
step, and a joint dividend is applied once. Coincident coefficient knots select
the coefficients of the time interval being traversed, never an average.

At zero stock, the process is absorbing: calls are zero; puts are
K max_(u in remaining E) exp(-integral_t^u r). For piecewise r, test allowed
endpoints, curve knots within an American window and the allowed discrete
instants. A zero of r over a segment produces a plateau, not an extra numerical
root. This exact-real boundary includes negative-rate discount growth. A
finite-precision boundary evaluation has its own rounding/overflow failures.

At infinity, require at most linear growth. Safe global envelopes derived in
§7 are available for either sign of r or q. Do not impose V_put=0 or
V_call=s-K as an exact finite-domain boundary, or impose a strike/spot cap for
negative rates/yields. These are not universally valid boundary conditions.

The all-zero-volatility path uses deterministic stopping, including the interior
stationary points q*S(t)=r*K from #108, rather than approximating diffusion with
a tiny positive sigma. A partly zero-volatility schedule still needs transport
on its deterministic segments. Underflow of sigma² is not exact zero variance.
Exact expiry, zero strike and zero spot dispatch only after complete admission.
Boundary reductions do not automatically qualify Greeks or certification.

## 2. Spatial grid, positivity and domain treatment

Use 0=s_0<...<s_N=U, with spot and strike as anchors when distinct and interior;
spot is an evaluation node. This avoids an extra price interpolation in the
first no-cash engine and includes the absorbing state without a log-grid floor.
Freeze U and the nodes for one solve. Refinement preserves anchors and bisects
cells, with adjacent cell-size ratios at most 2 after balancing. If distinct
anchors cannot be represented, or balancing exceeds the work budget, report
that failure. Never epsilon-merge distinct financial inputs. A refining family
must have maximum cell width tending to zero on each fixed compact interval;
nonuniform spacing alone is not a convergence argument.

At interior node s, let h-=s-s_left and h+=s_right-s. The quadratic-interpolant
central approximation has neighbor coefficients

    l- = (2a - b h+) / (h- (h-+h+)),
    l+ = (2a + b h-) / (h+ (h-+h+)),
    (L_h v)_i = l- v_(i-1) - (l-+l++r) v_i + l+ v_(i+1).

Use it only if both neighbor coefficients are nonnegative. Otherwise use the
same second derivative with a one-sided first derivative:

    l- = 2a/(h- (h-+h+)) + max(-b,0)/h-,
    l+ = 2a/(h+ (h-+h+)) + max( b,0)/h+.

The direction follows the **backward pricing generator**: positive b uses the
forward difference. This preserves nonnegative neighbor rates even when
volatility is very small. Record switched rows. Central differences on an
arbitrary graded mesh do not promise second-order spatial convergence; upwind
rows are first order. No fixed Richardson order is assumed. Overflow, unresolved
coefficient signs, collapsed spacing or cancellation destroying the required
row margin causes refinement/rescaling or explicit numerical failure. The
runtime must verify the assembled binary64 matrix as well as the real formula.

For finite U, solve two versions with the same interior operator. At the upper
boundary use a lower value g(U) when exercise is allowed, otherwise 0, and an
upper envelope from §7. At terminal time both use the exact terminal payoff.
The lower boundary s=0 is shared. Each boundary encloses the unknown true value
at U in real arithmetic. For the corresponding *continuous* stopped-domain
problems, comparison brackets the unrestricted value; for the monotone discrete
problems it brackets the effect of the chosen boundary data on that grid.
These are different statements: the computed pair is **not** a continuum
price enclosure. Its midpoint is the point estimate; its half-spread is a
boundary-sensitivity diagnostic, before accounting for solve errors.

Start an engineering domain at U=4 max(S,K) for positive scale, with spot strictly
interior; this is a starting mesh choice, not a probabilistic tail bound. Expand
to 2U while retaining the original interior nodes and resolution. A small change
with fixed N would confound truncation and mesh error, so it is not acceptable.
Require the boundary spread and expansion differences in §6; keep expanding
within declared caps or return `Accuracy_not_demonstrated`. Products, extensions
and memory sizes must be representable. No universal U or number of standard
deviations is claimed sufficient. Later cash mapping can use the exact zero
boundary when s<=D; it must not clamp to a positive mesh floor.

## 3. Time integration and obstacle solution

For a step of positive length h from later time to earlier time within a single
coefficient interval, theta stepping forms

    A = I - theta h L_h,
    B = I + (1-theta) h L_h,
    f = B v_later + boundary contributions,
    min(A x-f, x-g) = 0.

The boundary contributions include both time levels for theta<1. Interior
American rows solve this LCP; continuation-only intervals solve A x=f. At a
change of exercise availability, split time exactly and apply the endpoint
right once. Do not solve continuation and then clip the vector to payoff as a
substitute for the implicit LCP: the neighboring equations change together.
The exact witness in §9 gives a counterexample.

With l±>=0, A has nonpositive off-diagonals. Its full-stencil row margin is
1+theta*h*r; removing prescribed boundary unknowns only increases this margin.
Enforce **theta*h*max(-r,0) <= 1/2**. This deliberately leaves a positive margin
of at least 1/2 in exact arithmetic. Identity exercise rows preserve strict row
diagonal dominance. These matrices are nonsingular M-matrices: to see inverse
positivity, a negative minimum component of a solution to A x>=0 contradicts
the positive row margin and off-diagonal signs. The same argument proves the
comparison property used by the obstacle solve.

Backward Euler (theta=1) is selected first: B=I, no explicit-side positivity
restriction and damping at every step. Negative rates still require the margin
guard. For Crank–Nicolson (theta=1/2), additionally require, at every row,

    1 - (1-theta) h (l-+l++r) >= 0.

Otherwise the update need not preserve order/positivity even though A is an
M-matrix. Subdivide or choose a recorded backward-Euler step; never call an
unrestricted Crank–Nicolson update monotone. Its evaluation candidate replaces
the first two nominal steps after terminal payoff and each kink-producing event
with four backward-Euler half-steps, splitting again at intervening events.
Every substep honors the actual exercise rights. This damping is an engineering
candidate, not a proof of second-order convergence for a moving free boundary.

In the sup norm, a comparison estimate for the full theta update is
(1-(1-theta)hr)/(1+theta*hr), under the stated positivity conditions. Negative
r can amplify values. For theta in [1/2,1] and the margin guard, a conservative
bound across steps is Gamma=exp(2 integral max(-r,0) dt); it is 1 for r>=0.
This is a discrete stability allowance, not a continuum error certificate.
Boundary errors and nonlinear obstacle residuals must also be propagated.

Build time slabs from original coefficient knots, exercise endpoints, Bermudan
instants and cash times; subdivide each slab by integer counts. Keep exact
original endpoints in the schedule. Do not accumulate repeatedly rounded h to
find an event. Interior-time representation, h evaluation and coefficient
assembly introduce arithmetic error, not a license to perturb event ordering.
A midpoint collapsing to an endpoint stops refinement with an explicit outcome.
There is no diffusion/discounting between two sides of one cash event.

### Policy iteration and termination

For current x, evaluate p=A x-f and e=x-g. Select continuation when p_i<=e_i
(including exact ties), otherwise exercise. Replace exercise rows by identity
rows with right side g_i; solve the resulting tridiagonal system and check the
*original* complementarity residual. Warm starts affect work, not acceptance.

[Reisinger and Witte, arXiv:1012.4976v4, §2](https://arxiv.org/html/1012.4976v4#S2)
prove finite termination for the discrete M-matrix problem in exact arithmetic;
the continuation tie rule gives an N+1 bound for N unknowns. That theorem does
not cover floating-point residual decisions or bound PDE discretization error.
We use it for algorithm selection, not as a runtime success test.

Measure R=max_i |min(p_i,e_i)| in currency units, alongside separate negative
parts of p and e. A product p*e can overflow and has the wrong units for the
price budget. Row rescaling must be recorded and undone for this residual.
Finite rounded residuals are diagnostics, not outward bounds. Recompute from
unfactored coefficients with an independently evaluated accumulation; reject
nonfinite results. Ties near arithmetic resolution remain unresolved exercise
diagnostics. An unchanged policy is not sufficient for success.

Set a policy-solve cap, detect repeated policies with a nonpassing residual,
and retain the worst row, residual and counts on failure. Reaching a cap,
cycling or stagnating returns `Nonconvergence`, never the last iterate as a
usable price. The N+1 theorem is not an automatic binary64 cap guarantee.
#111 must supply floating-point failure witnesses and arithmetic analysis.

## 4. Linear-solver boundary and storage

The linear solver receives one assembled policy matrix and right-hand side. It
owns a tridiagonal solve, not the stopping decision or the continuum model.
Return either a finite vector with residual diagnostics or a typed failure.
Never repair a small pivot by adding an unrequested diagonal perturbation.

| Candidate | Conditions and tradeoff | Selection |
| --- | --- | --- |
| Compact OCaml elimination/back substitution | O(N) work/storage; positive-diagonal, nonpositive off-diagonal, strictly row-dominant tridiagonal input. Positive exact elimination pivots follow from the M-matrix structure. Binary64 pivots and residuals still need checking. | Initial #111 implementation; no native dependency or call boundary. |
| LAPACK `DGTSV` | General tridiagonal solve with partial pivoting, destructive coefficient/RHS buffers, and an INFO status. It can handle systems excluded by the specialized kernel but does not repair a nonmonotone pricing scheme. | Optional #119 comparison; not built, timed or adopted in #109. |

The [pinned LAPACK source](https://github.com/Reference-LAPACK/lapack/blob/6ec7f2bc4ecf4c4a93496aa2fa519575bc0e39ca/SRC/dgtsv.f)
uses row interchanges when needed, with a second upper diagonal. INFO<0 is an
argument error; INFO>0 identifies a zero pivot. INFO=0 is not an accuracy test.
The wrapper must retain the original bands for an independent residual check.
Do not reuse DGTSV's overwritten arrays as a reusable factorization interface;
a later reuse experiment would evaluate a separate factor/solve pair.

For a policy matrix with row margin m>0, the real inequality
||x_hat-x_exact||_infinity <= ||A*x_hat-f||_infinity/m follows from inverse
positivity and A*1>=m*1. For the nonlinear LCP use min(1,m) in the corresponding
comparison/shift bound for its min residual. This bounds the **fixed discrete
problem** when the residual is rigorous. Ordinary binary64 evaluation omits
coefficient and residual-rounding uncertainty and cannot certify this bound.
Check the original LCP after every accepted policy solve, not just the selected
linear equations. Conditioning, rounding, overflow and underflow can require a
failure even though the exact matrix has positive pivots.

Factor reuse requires identical matrix entries, grid, h, theta, coefficients,
boundary elimination and policy mask. A new RHS alone permits reuse; a changed
exercise mask generally does not. Do not key factors solely by expiry or mesh
size. Identity rows retain tridiagonal structure without assuming contiguous
exercise regions. Preserve the unfactored bands and recompute factors into
separate work buffers. #119 measures the cost of copying/factorization together
with policy updates and residual checks, across realistic N and iteration counts.
A native microbenchmark alone cannot select the public backend.

Use contiguous unboxed float bands and vectors: lower/diagonal/upper coefficients,
original RHS, factor scratch, current/previous values, payoff, residual scratch,
and compact policy flags. Reuse them across steps within one call. Allocate
O(N) storage for each live solve; do not allocate per row or per policy update.
Upper/lower boundary solves and refinement runs may execute serially to cap
memory. Count all live grids, time/event metadata and requested diagnostics in a
checked byte budget before allocation. No full N-by-N matrix is needed at runtime.
The dense matrices in the research probe are intentionally independent checks.

For the current constant-input implementation, one price request owns a
single-entry spatial preparation cache. The fixed model, side and configuration
plus `(spatial level, domain expansion)` determine the grid, payoff and spatial
bands. Equal keys permit reuse across boundary, time and cash-mapping refinements;
a changed key releases the previous entry before building the new grid.
Matrices, factors, values and policy flags remain solve-owned. Logical row visits,
cancellation sites and upwind counts are preserved. Preparation replaces the
current solve's three arrays; no historical grid or per-event cache is retained.
See the [request-local reuse derivation and qualification](results-american-spatial-reuse.md).

One worker exclusively owns each mutable workspace. Compiled model/grid data
may be immutable shared data; no global mutable factor cache. Pricing stays
single-threaded inside a solve; outer portfolio workers own parallelism. A native
backend, if justified, uses one native thread per call with no global thread-count
mutation during concurrent requests. Oversubscription must be measured explicitly.

Any future FFI uses stable C-layout float64 Bigarrays or copies to owned native
storage; it must not retain a pointer into a movable OCaml float array across
allocation or runtime-lock release. Root the Bigarrays for the whole call, check
lengths/strides and LP64 versus ILP64 integers, prohibit writable aliasing, and
return no borrowed scratch views. Include packing and residual costs in timing.
A blocking LAPACK call is cancellable only before/after that bounded call; if
that fails the latency budget, restrict N or keep the OCaml path.

The [arithmetic contract](numerical-backend-contract.md) still applies: nearest
even, gradual underflow, no implicit contraction/reassociation or fast math.
Inspect/restore the thread's floating-point environment on every native exit;
reject an unsupported environment. Existing explicit multiplication/FMA owners
remain authoritative. Native/bytecode execution, concurrent calls, malformed
buffers and environment restoration require executable witnesses before an
optional backend ships. A vendor library cannot silently weaken these rules.

## 5. Error ledger and event interpolation

Keep distinct entries; `Unknown` is not a zero estimate.

| Contribution | Engineering diagnostic | Obligation for a rigorous full-price enclosure |
| --- | --- | --- |
| Input transformation/coefficient assembly and rounding | Finite checks, stable/scaled assembly, roundoff-resolution indicator, precision comparisons | Enclose original exact input operations, coefficients, time lengths and all arithmetic; preserve signed/zero distinctions. |
| Linear and complementarity solve | Original-system residual, margin, policy count and failure reason | Outward residual plus a justified inverse/comparison bound, propagated through all steps. |
| Space discretization | Independently refine nodes with time/domain held fixed | A proved consistency/global error bound appropriate to nonsmooth obstacle solutions and switched stencils. |
| Time/continuous exercise discretization | Independently refine each event-aligned slab | A justified time/stopping approximation bound; no theorem of second-order accuracy is assumed. |
| Finite upper domain | Lower/upper boundary sensitivity and domain expansion with interior nodes retained | A full-domain comparison/tail bound coupled to certified interior evolution. |
| Dividend map/interpolation | Refine event-adjacent cells, retain pre/post values | Bound jump evaluation, interpolation and incoming node errors, including the zero kink. |
| Final extraction | Spot anchor; any later interpolation is recorded | Enclose extraction and final binary64 rounding. |

Use piecewise-linear interpolation for the cash map with nonnegative weights
summing to one in the real formula. This is order-preserving and sup-norm
nonexpansive on input nodal values, unlike an unconstrained cubic. Verify actual
floating-point weights and mapping brackets. Invalid weights are failures, not
license to clip them. At s<=D use the zero boundary exactly in the model; when
the sign of s-D is unresolved numerically, refine arithmetic or report failure.
Kink-crossing cells cannot use a smooth second-derivative estimate without proof.

For a C² function on a cell of width d, the linear-interpolation error is bounded
by d² sup|V_ss|/8. Without smoothness, a Lipschitz constant L gives L*d/2, from
the weighted distances to the two endpoints. Coupling two ordered stocks under
the same Brownian path and nonexpansive cash jumps gives a usable real-model
constant L(t)=exp(integral_t^T max(-q,0) du) for unit call/put payoffs: discounted
stock differences, multiplied by exp(-integral max(-q,0)), are nonnegative
supermartingales. Apply the same stopping rule, then take suprema. This is an
original bound derivation, not a measured interpolation error.

Consequently event errors can be bounded in principle by incoming nodal error
plus L*d/2 and L times uncertainty in the jump location/nominal sum, with the
proper discount amplification to valuation. This can be very loose. It does
not bound PDE discretization, and #112/#116 must implement outward arithmetic
and verify all premises before calling any such number certified.

## 6. Frozen acceptance policy, results and bounded work

The following **engineering policy version 1** precedes #110/#111 pricing
scores. It is a requested *refinement criterion*, not a price-error guarantee.
The caller supplies a finite positive currency tolerance epsilon and explicit
work/memory caps; no universal trading or deployment tolerance is invented.
A certificate request uses a separate capability and cannot fall back to this.

- Use at least three levels for each active space/time refinement direction.
  Hold the other dimensions at their finest selected settings. The last two
  successive differences in each direction must each be <= epsilon/8.
- Require the fine-grid upper/lower boundary half-spread <= epsilon/8 and the
  last two domain-expansion differences <= epsilon/8, preserving the interior
  grid. For dividend extensions, independently refine mapping cells and require
  the last two event-refinement differences <= epsilon/8 too. Zero cash events
  still execute their phase logic. Mark only truly absent effects `Not_applicable`.
- Report the sum of the *latest* active differences plus boundary half-spread;
  require it <= epsilon/2. This is an observed diagnostic sum, not an enclosure
  or extrapolated error estimate. Do not multiply by a guessed convergence order.
- Let W be the configured maximum number of accepted time substeps across all
  solves/refinements, and Gamma the conservative stability allowance in §3.
  Each solve must achieve currency min-residual <= epsilon/(64 W Gamma), with
  separate primal-feasibility and continuation-inequality diagnostics meeting
  the same limit. For continuation-only solves use the linear residual. Reserve
  the same local scale for boundary-evaluation uncertainty in the engineering
  ledger. Failure to resolve that scale is explicit, not a widened tolerance.
- A roundoff-resolution indicator is also required: for each three-term residual
  row use 32*u*(sum_j |A_ij*x_j|+|f_i|+|x_i|+|g_i|)+32*eta, with u=2^-53 and
  eta=2^-1074, evaluated without overflow. If it exceeds one quarter of the local
  residual allowance, refine arithmetic or fail. This conservative screening
  expression does not cover coefficient errors or prove a floating-point bound;
  #111 owns an operation-level analysis and boundary evaluation evidence.
- Return a nonnegative finite point estimate only after all required checks
  complete. A computed negative price, bound violation or nonfinite diagnostic
  is not repaired by clipping. Retain the final mesh/domain/time/policy counts,
  scheme switches, requested epsilon, achieved diagnostics and method identity.

A large W or extreme negative rate can make this policy impossible in binary64.
That is an accuracy/resource limitation, not a reason to weaken the criteria.
The design deliberately exposes it for #110/#111 feasibility measurements.
If measurements justify a different engineering policy, change its version,
rationale and acceptance corpus before rescoring; do not silently relax limits.

For the first normalized reference campaign, freeze epsilon=2^-16*max(S,K)
for positive-scale cases, plus explicit zero-value expectations for zero-scale
cases. This is a regression target, not a claimed universal precision or a
business requirement. Include multiple currency scales and epsilon/4 requests.
#110 records cases and budgets before producing the candidate's scores.
Independent reference intervals must have radius <= epsilon/8 and known status.
Require max(|estimate-L|,|estimate-U|)<=epsilon, rather than subtracting reference
uncertainty from the observed error. A rigorously enclosed reference permits that
stronger interpretation; a precision/refinement interval is explicitly empirical
and supports only empirical comparison. Unresolved/missing/nonfinite/comparator
failures are retained as unresolved rows, never scored as passes or dropped.

For identities, use the union of independently documented uncertainties; zero
or exact-boundary expectations get their own arithmetic checks. Exercise-region
output is a list of estimated grid intervals with unresolved cells, not one
universal boundary or a proof of exercise indifference. Missing optional
premium/region diagnostics do not fabricate zeros. Required diagnostics failing
make the requested output unavailable. A premium uses a matching European
terminal problem, with uncertainty from both solves, including the cash model.

Proposed additive result shape (not installed OCaml declarations):

    Estimated_only { value; refinement_diagnostics; method_identity }
    Invalid_accuracy | Unsupported_capability | Unrepresentable
    Resource_limit | Cancelled | Nonconvergence
    Accuracy_not_demonstrated | Arithmetic_unresolved

Admission errors remain owned by #108. A valid unsupported feature is not an
invalid contract. `Estimated_only` has no `error_bound` or private certificate
field; partial failed iterates are available only as labelled debug evidence.
There is no automatic conversion to `Production`, certified aggregation,
European `Iv.Root`, certified Greeks or deployment acceptance.

Bound nodes, slabs, substeps, policy solves, refinement rounds, events, bytes and
requested diagnostic rows before work begins; use checked integer arithmetic.
Every attempted solve consumes budget, including a failed retry. Check
cancellation before allocation, every step/policy solve and at bounded row blocks
(e.g. at most 256 rows) during assembly/elimination/event mapping. Recheck before
publishing success. Cancellation cleans up the worker workspace and emits no
partial accepted price. #111 tests cap exhaustion, stagnation, every arithmetic
failure and cancellation at each phase; #118 later owns batch terminal accounting.

## 7. Full-price enclosure feasibility and the #116 gate

### A real full-domain bound that is already defensible

For the nonnegative stock and finite deterministic horizon, set

    R-(t) = integral_t^T max(-r(u),0) du,
    Q-(t) = integral_t^T max(-q(u),0) du.
    0 <= V_put(t,s) <= K exp(R-(t)),
    0 <= V_call(t,s) <= s exp(Q-(t)).

The put payoff is <=K and every permitted discount is <=exp(R-). For the call,
payoff<=stock; exp(-integral_t^u r)*S(u)*exp(-integral_t^u max(-q,0)) is a
nonnegative supermartingale, including downward limited-liability jumps.
Optional sampling at bounded exercise times gives the bound. Deterministic
piecewise bounded coefficients supply the needed integrability; no arbitrary
stochastic-rate extension is implied. Immediate payoff is an additional lower
bound **only when exercise is currently available**. A matching terminal
European value is a lower bound because terminal exercise is always allowed,
but a no-cash European implementation is not a bound for the cash model.

These are independently derived **real-price** inequalities, unlike a numerical
LCP residual. They also justify the finite-domain boundary envelopes in §2.
However they are usually too loose: for S=K=100 and r=0, the elementary put
interval [0,100] has midpoint radius 50, versus the frozen engineering target
100/65536. The exact-rational probe records that gap; it is not an experiment
showing that all stronger certification is impossible. Outward exponentials,
original-input integration and rounding are still needed even for this coarse
runtime interval. This issue implements none of those American certificates.

### A stronger route, with its obligations exposed

A candidate upper-bound approach is a global supersolution w(t,s) with at most
linear growth, terminal dominance w(T,s)>=g(s), obstacle dominance at every
allowed exercise instant, and w_t+Lw<=0 between events. At a cash event it must
satisfy w_before(s)>=w_after(J_D(s)) and any pre-event payoff. For a smooth w,
Itô's formula makes the discounted process a supermartingale; optional sampling
gives V<=w. Lower bounds come from genuinely feasible exercise strategies whose
expected payoffs are independently enclosed. This is an original verification
argument; it does not assume a lattice value is a rigorous lower bound.

If a globally verified positive residual defect is at most delta(t), a possible
correction is e(t)=integral_t^T discount(t,u)*delta(u) du: e'-r*e=-delta.
Then w+e has the required differential sign, **provided** payoff/terminal/event
and growth conditions are also verified (or separately corrected). Negative
rates magnify this correction. At nonsmooth spatial joins, an unverified local-
time term invalidates this argument; piecewise linear interpolation of grid
values alone does not satisfy its smoothness/sign premises. Discrete policy
residuals are not bounds on delta over continuous time and stock.

For #116, the promising first subset is constant coefficients, no cash,
positive S/K/sigma and one continuous window, with an explicit finite numerical
domain and evaluated original-input enclosures. First assess exact expiry/zero
reductions and the proved q=0, r>=0 no-cash call-to-European reduction separately;
any reuse requires a model-matching proof and existing certificate applicability.
Do not announce all Americans certified because a European reduction works.
The delivered [#116 disposition](american-certification.md) certifies guarded
exact reductions separately and retains the general stopping proof gaps below.

| Obligation | Evidence now | Gate before a runtime certificate |
| --- | --- | --- |
| Correct stopping model / event ordering | #108 contract and §1 | Executable admitted-input and event witnesses for the claimed subset. |
| Discrete solve and stability | Exact algebra probe; matrix derivation | Outward coefficient/residual checks and propagated solve uncertainty on original inputs. |
| Continuum discretization | Refinement design only | Proved full-price truncation/discretization bound **or** a verified global supersolution plus feasible-strategy lower bound. |
| Infinite stock domain | Coarse analytic envelopes | Verified exterior patch/tail estimate and junction conditions; numerical domain expansion alone fails this gate. |
| Cash events | Monotone interpolation and Lipschitz derivation | Outward joint sums/maps and interpolation accumulation; excluded unless completed. |
| Useful enclosure width | Coarse interval shown inadequate in one ATM case | Executed source-bound widths, containment/failure controls and budgets across the agreed subset. |
| Arithmetic and public acceptance | Separate type/failure contract | Outward full-price endpoints, final currency-radius check, incorrect-bound mutants, exhaustion and environment tests. |

**Disposition: implement #111 as estimated-only.** No useful general American
certificate has been established. #116 must either complete the obligations for
a named subset, with executed independent challenges, or retain an explicit
estimated-only disposition. It is not blocked merely because a theorem is hard;
it must document what was tried and the exact remaining gap. No American
`Production` success path is permitted by this design. Monte Carlo confidence
intervals, mesh agreement or exact solutions of a finite LCP cannot substitute
for these obligations. Price evidence never transfers automatically to Greeks
or to a nearest-even IV-root guarantee.

## 8. Alternatives, sources and implementation provenance

| Alternative | Disposition |
| --- | --- |
| Explicit time stepping | Useful independent experiment; positivity step restriction can make small cells costly. Not the initial general solver. |
| PSOR / penalty solve | Not selected: introduce relaxation/penalty choices and separate stopping tests. Retain as possible independent numerical comparisons, not certificates. |
| Damped Crank–Nicolson | Evaluate only under §3's matrix and RHS guards, including reset at events. #119 owns end-to-end evidence before promotion. |
| Lattice / boundary-integral reference | #110 owns independent formulations and convention reconciliation. A separate formulation is evidence, not automatic truth. |
| Specialized constant-parameter approximation | #119 may evaluate within proved assumptions. A single-boundary formula cannot define the general negative-rate/cash contract. |
| Dense BLAS / general distributed PDE toolkit | No demonstrated need for this one-factor tridiagonal workload. No dependency added. |

[The source inventory](evidence/american-solver/sources.json) pins the inspected
publication, source files, licenses, SHA-256 hashes, acquisition route and scope:

- Reisinger–Witte **arXiv:1012.4976v4**, 17 September 2011, algorithm/theorem in
  §2. The publication has the arXiv non-exclusive distribution notice, not an
  open-source implementation license. Its original PDF is preserved privately;
  no article bytes or supplied source implementation enter this public change.
- QuantLib **79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c**: finite-difference engine
  and rollback/damping configuration inspected as comparator conventions.
  Those choices are not copied as this project's LCP implementation. #110 owns
  a built model-matched comparison; no QuantLib American run is claimed here.
- LAPACK **3.12.1**, commit **6ec7f2bc4ecf4c4a93496aa2fa519575bc0e39ca**:
  DGTSV and its BSD-style license inspected. Its copyright/notice/disclaimer
  obligations apply to any future redistribution; no library is linked here.
- The previously inspected Healy negative-rate and cash-policy references remain
  pinned in [#108's inventory](evidence/american-contract/sources.json).

The source inventory distinguishes mathematical algorithm attribution, original
project derivations and original probe code from source-code reuse. No QuantLib
or LAPACK implementation is vendored, translated or linked by this change.
Publication permission is separate from implementation licensing and from the
project's Apache-2.0 license. Acquired originals/notices follow the
[research policy](research/README.md); public builds and the probe work offline
without the private archive.

## 9. Reproducible design evidence and handoff

Run the original standard-library-only research probe from the repository root:

```sh
python3 scripts/check_american_solver_design.py
```

Its [retained output](evidence/american-solver/design-checks.json) contains the
script SHA-256. The probe exercises 1,296 three-unknown LCPs on uniform/nonuniform
stock grids, both theta values, three rates including negative, three yields,
zero/low/positive volatility and two time lengths. It compares policy iteration
using compact elimination against **enumeration of all eight exercise policies**
solved with independent dense row-pivoted elimination, all with exact rational
arithmetic. A separate case forces a policy change after the first solve.
Polynomial actions independently check constant/linear consistency and central
stencil quadratic consistency. This is finite discrete evidence, not a
floating-point or continuum proof.

Failure controls reject positive off-diagonals, an excessive negative-rate
step and a negative explicit-side diagonal. A perturbed solution is rejected by
its original LCP residual. A pivot-required matrix demonstrates a legitimate
input outside the specialized kernel's domain; this is a comparison with our
independent dense check, **not an executed LAPACK benchmark**.

For A=[[2,-1],[-1,2]], f=[0,0], g=[1,0], a continuation solve followed by payoff
clipping produces [1,0], with min-residual norm 1. The actual LCP solution is
[1,1/2]. This supplies a deterministic witness against replacing the American
solve with a post-step max. The probe also checks positive interpolation and
the coarse ATM bound-width limitation in §7. It deliberately does not emit option
price fixtures or score a proposed runtime implementation.

| Next owner | Required work |
| --- | --- |
| #110 | Pin/build canonical runner, independent references and uncertainty/failure controls, using §6's frozen scoring rules. |
| #111 | Implement constant/no-cash solver, deterministic and boundary cases, original-input arithmetic, work/cancellation/failure controls, installed native/bytecode API and independent comparisons. |
| #112–#114 | Extend executed model/reference evidence for cash, Bermudan and curves; preserve matrix/event guards and error ledger. |
| #115/#117 | Define and qualify risk/inverse availability with solver uncertainty; no inherited European certificate. |
| #116 | Execute §7's certification/disposition gate. |
| #118/#119/#120 | Compiled ownership, measured kernel/backend comparison and source-bound qualification. |

Local build/format, probe replay, source hashes and documentation integrity are
the validation scope for this design change. No runtime performance advantage,
American pricing accuracy, new backend qualification, full mutation campaign,
release approval or independent external review is claimed.
