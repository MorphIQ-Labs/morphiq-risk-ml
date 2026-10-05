# Estimated scalar American pricing

`Early_exercise.Bsm` implements constant-coefficient American call/put pricing,
including #112's [scheduled cash-dividend extension](american-cash-dividends.md). It supports continuous yield, finite signed rates/yields,
expiry, zero stock/strike, deterministic stopping and delayed exercise opening.
Inputs denote their original exact binary64 values. Read the
[financial contract](american-model-contract.md) and
[frozen solver policy](american-solver-design.md#6-frozen-acceptance-policy-results-and-bounded-work).

Every successful result is **Estimated_only**. A requested tolerance governs
observed refinement and arithmetic screens; it is not an absolute price error
bound. This API cannot produce a `Production.certified` value.
Bermudan schedules, piecewise coefficients, Greeks, IV and batch/planner support
remain #113–#118. There is no implicit date adapter or settlement convention.

## Use and outcomes

Run the [complete public example](../examples/american_price.ml):

```sh
opam exec --switch=morphiq-risk-ml -- dune exec examples/american_price.exe
```

First construct a typed `Vol.lognormal`, then `Bsm.admit` the immutable financial
inputs. `opens_at` and `time_to_expiry` are year offsets with
0 <= opens_at <= time_to_expiry. `inputs` returns an immutable snapshot. Full
validation precedes even expiry or zero-stock dispatch.

`configure` separately validates a positive finite currency tolerance, base
space/time counts, domain doublings and explicit resource caps. Counts n, 2n,
4n form the three independent refinements. The example's tolerance of 1 currency
unit at a scale of 100 is an illustrative loose engineering request, **not a
recommended trading tolerance**. Tighter requests frequently fail in this first
implementation; the measurements below retain those failures.

`price` returns a private estimate with method identity, requested tolerance,
refinement differences (or `None` for analytical reductions), maximum original
system residual, roundoff/boundary arithmetic indicators and work counts.
`Accuracy_not_demonstrated` retains the unsuccessful refinement diagnostics;
`Nonconvergence` retains the step, worst row and residual. Resource exhaustion,
cancellation, unrepresentable work and unresolved arithmetic are distinct errors.
No failure contains a usable partial price. A valid financial input can exceed
the implementation's numerical capability.

Optional exercise regions are sampled grid-cell classifications. Adjacent cells
may have multiple exercise intervals, continuation or unresolved classification;
a transition cell is unresolved. Zero-payoff equality is not labelled definite
exercise. These are estimated regions, not continuum free-boundary certificates.
Regions are unavailable before a delayed window opens and on analytical routes.

The optional premium subtracts a separately enclosed, model-matched European
terminal price. Its European error and subtraction indicator are reported
separately; the American component remains estimated and has no rigorous error
bound. A small negative estimated premium is not clipped to zero. Optional
comparison failure is `Unavailable`, not a fabricated zero. Cash-dividend
requests currently report the matching European comparison as unavailable;
they never substitute the no-cash European value.

## Implementation and arithmetic

The implementation is original OCaml code derived from the #108/#109 equations;
no QuantLib or LAPACK implementation is copied, translated or linked. The
reference corpus independently uses the stock tree and pinned QuantLib runner
from [#110](american-references.md). The existing source/paper provenance applies.

- Start at U=4 max(S,K), insert exact spot/strike anchors and balance adjacent
  cells to a ratio at most 2. Each domain doubling retains the previously
  balanced nodes and resolution; each spatial refinement bisects cells.
  Unrepresentable distinct anchors/midpoints fail rather than being merged.
- Assemble central neighbor coefficients only when expansion enclosures resolve
  both signs as nonnegative. Otherwise use the selected upwind generator.
  Original rate differences, grid differences, products and quotients use the
  existing bounded `Enclosure.Fast` arithmetic. Positive coefficients that cannot
  be represented are refused. Converted coefficients are still approximate;
  their uncertainty is not a PDE error certificate.
- Use backward Euler on separately subdivided [opens,T] and [0,opens] slabs,
  additionally splitting at each cash date for cash requests.
  Original endpoints are exact; interior coordinates are independently formed
  from an enclosed slab length divided by the integer count. The rounded step
  is a coefficient approximation, not a change of financial time. Collapsed
  coordinates and negative-rate margin failures are explicit.
- Solve the original obstacle system by policy iteration and checked compact
  tridiagonal elimination. Exercise rows become identity rows. No continuation
  solve followed by clipping substitutes for the LCP. Recompute the original
  complementarity residual with explicit FMA, separately from elimination.
  The assembled full-stencil row margin must stay at least 1/4 after rounding;
  the exact-model step guard leaves at least 1/2. Nonfinite/negative pivots fail.
- Enforce the frozen local residual allowance epsilon/(64 W Gamma) and its
  32u three-term roundoff indicator, with u=2^-53 and gradual underflow. Gamma
  uses an outward expansion evaluation for negative-rate amplification.
  Enclosed boundary evaluations must also meet the local allowance. A failed
  screen never increases a tolerance. A large configured W can make a request
  unavailable even before it exhausts that budget.
- Policy stagnation, a repeated mask fingerprint with a nonpassing residual,
  or the iteration cap produces `Nonconvergence`. Fingerprints can conservatively
  reject on a collision; they can never accept an inaccurate solve. Exact
  finite-termination theorems are not binary64 convergence guarantees.
- Lower/upper finite-domain boundary data use permitted payoff/zero and the
  signed-rate/yield global envelopes. The pair's midpoint and half-spread are
  diagnostic. Three domains and independent three-level space/time refinements
  must satisfy the original frozen policy. No extrapolation order is assumed.
- Check intrinsic/global price inequalities without clipping. The matching
  no-cash European lower comparison additionally uses the recorded refinement sum as
  an engineering discrepancy screen, not a rigorous American uncertainty bound.

The analytical paths use expansion arithmetic for expiry, absorbing stock,
zero strike and original-input deterministic stopping. Deterministic candidates
include both window endpoints and interior q*S(t)=r*K; the 250/9 interior maximum
has a direct regression. Equal/nonzero volatility is never inferred from a
rounded sigma-squared. European reduction applies to a degenerate exercise
window or a no-yield call with nonnegative rate on the no-cash route. Cash
requests use event-aware deterministic stopping; see the extension for its
additional diagnostics, restrictions and costs. Analytical results retain the
same estimated-only public type, even where their internal arithmetic is enclosed.

## Work, memory and cancellation

Each call owns its scratch and runs on one thread. There is no shared mutable
cache, native solver, retained borrowed view or worker to join. Separate calls
can execute concurrently; tests compare independent-domain and sequential results.

Caps cover live nodes, all time substeps and policy solves across refinements,
row visits (including grid balancing), per-step policy iterations and workspace.
The conservative workspace reservation is 512*max_nodes + 32*policy_iterations
+ 65536 bytes, covering simultaneous grids/bands, captured values, policy history,
optional regions and bounded arithmetic temporaries. Analytical routes reserve
65536 bytes. This is a live numerical workspace envelope, not total allocation,
OCaml heap capacity, process RSS or a guarantee that the host has enough RAM.

Cancellation is checked before work/allocation, every step/policy solve, every
256 numerical row visits and before publication. Individual bounded OCaml array
allocations and expansion operations finish before the next checkpoint; no
wall-clock cancellation SLA is claimed. User callback exceptions propagate.
Unwinding releases request-owned references without publishing a partial result.

## Measured numerical capability

This section retains the #111 **no-cash** campaign. The separate
[cash campaign](american-cash-dividends.md#evidence-and-limits) does not extend
these results to other dividend conventions.

The [campaign protocol](evidence/american-implementation/protocol.md) was frozen
as commit `ecadc0e` before scoring the runtime. Both initial and refined budgets
are explicit; the original #110 corpus/uncertainty and #109 thresholds are intact.
All 41 cases remain in every run. Zero-scale cases require exactly zero output.

| Requested criterion | Configuration | Reference pass | Unresolved reference | Runtime unavailable | Reference fail |
| --- | --- | ---: | ---: | ---: | ---: |
| Primary epsilon=2^-16 max(S,K) | initial | 18 | 1 | 22 | 0 |
| Primary | refined | 17 | 1 | 23 | 0 |
| Primary / 4 | initial | 17 | 1 | 23 | 0 |
| Primary / 4 | refined | 17 | 1 | 23 | 0 |
| Separate loose epsilon=max(S,K)/100 | initial | 19 | 4 | 18 | 0 |
| Separate loose | refined | 32 | 6 | 3 | 0 |

A finer mesh is not automatically more available: matrix roundoff indicators
and configured W grow. The refined primary request still fails on ordinary ATM
puts (space refinement) and calls (roundoff). The three refined loose failures
are the long/high-volatility call and put and the zero-rate/yield put, all with
explicit policy nonconvergence. These limits preclude broad accuracy or
production-readiness claims.

For the **same refined loose outputs**, scoring at the original primary goal
yields 18 passes, 14 failures, six unresolved references and three unavailable
requests. The loose results do not satisfy the primary campaign by relabelling.
Of the original eight unresolved references, six receive loose estimates and two
are unavailable; no new accuracy claim is made for any of them. Reference
extension and broader numerical qualification remain obligations for #119/#120.

Raw requests, outputs and per-row scoring are retained under
[evidence/american-implementation](evidence/american-implementation/).
Reproduce a campaign in a new output directory:

```sh
opam exec --switch=morphiq-risk-ml -- dune build test/american_pricing.exe
python3 scripts/check_american_runtime.py \
  --executable _build/default/test/american_pricing.exe \
  --mode primary --output /tmp/new-american-campaign
# Add --refined, or choose --mode quarter / --mode loose explicitly.
```

Default CI runs the initial primary corpus, native/bytecode public controls,
negative type tests and scorer failure controls. The larger campaigns and scalar
measurements are explicit local evidence. The original two American mutations and three cash-event mutations are
in the optional catalog; the seven-mutant default lane is unchanged.
No existing European helper, served value or replay digest is changed.

## Initial scalar performance

These are historical #111 measurements. See the
[matched allocation optimization](results-american-allocation.md) for the
current native scalar result and unchanged numerical/availability evidence.

The [complete samples](evidence/american-implementation/performance.json) cover
one admitted ATM put, S=K=100, r=.05, q=.02, sigma=.2, T=1, with the refined
**loose tolerance=1** configuration. Each price includes all boundary/refinement
solves (11,776 accepted substeps), not a single unvalidated grid solve.

On this shared Apple M1 Pro, 16 GiB, macOS 27, OCaml 5.3.0 Flambda, installed
release library and external `-O3` consumer:

| Operation | Median per request | Range of process means | Allocated bytes/request |
| --- | ---: | ---: | ---: |
| Financial admission alone | 22.3 ns | 21.7–22.9 ns | 440 |
| Estimated price, admitted inputs/configuration reused | 565 ms | 544–593 ms | 1,181,699,416 |
| Price plus optional region/premium diagnostics | 555 ms | 528–603 ms | 1,182,270,936 |

Five fresh processes per mode alternate order, with one warmup and a full major
collection before each measurement. Each price process averages three requests;
admission averages 100,000. Ranges are variation of those means, not single-call
tail percentiles. Inner elapsed time uses the wall clock; the enclosing process
also has monotonic elapsed observations. Load averages were 13.6–14.1 during the
campaign. All task-owned builds/tests had finished, but the host was not isolated.
The overlapping timings do not establish a diagnostics speed advantage.

**About 1.18 GB is cumulative OCaml allocation per general pricing request**, not
RSS or the live workspace cap. This is a substantial initial implementation cost,
not an optimized path or acceptable portfolio throughput claim. The subsequent
#119 profile and boxing optimization are recorded in the linked matched report.
No previous American runtime exists for a before/after speedup comparison.
The preliminary admission measurements were invalidated by constant folding;
[their raw observations](evidence/american-implementation/performance-preliminary.json)
are retained and explicitly excluded. The final driver makes the input opaque
before admission/pricing.

[The numerical source record](evidence/american-implementation/numerical-source.json)
pins the six-campaign implementation and executable. The later benchmark-only
change did not alter the runtime library. The installed native/bytecode example
produced identical output; its [commands and results](evidence/american-implementation/installed-consumer.json)
retain package-path verification. Source-artifact qualification across all
platforms, broader performance work and independent institutional acceptance
remain separate #120/#119/#27 obligations.
