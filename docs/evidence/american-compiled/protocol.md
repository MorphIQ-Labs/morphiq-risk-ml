# Compiled American requests and dated scenario plans (#118)

Freeze against American integration ff4517b8632d0d866022570e9c0000e16141884c
before implementation. This is an additive orchestration API. Scalar financial
models, numerical operation order, tolerances, certificates and work accounting
remain owned by Early_exercise.Bsm and its Piecewise/Certified/IV modules.

## Public contract

Batch.American compiles immutable admitted constant/piecewise models, sides and
explicit requested operations into reusable batches. A typed operation retains
its own estimated price, estimated Greek bundle, constant-sigma estimated IV or
certified price result. Piecewise IV/certification is unrepresentable. Failures
remain typed by their owning scalar API. Compilation copies caller arrays;
operations, private configurations and admitted models are immutable. Returned
arrays are fresh. Structural count/resource errors are distinct from row results.

Planner.American adds a separate typed scenario surface, reusing Scenario and
the existing bounded ordered fork/join executor. Each position declares its
constant or dated piecewise coefficients, cash/exercise dates, operation list,
side, multiplier, currency and stable IDs. Market factors supply spot; named
lognormal-volatility shocks map the original constant level or each original
curve level independently. Only spot/lognormal-volatility shocks are supported.
Rates/yields, quotes and dates are fixed. No implicit aggregation, cashflow,
settlement, economic P&L, approximate-to-certified conversion or quote synthesis.

Dates are bounded integral civil-day ordinals; remaining time is the exact
integer difference divided once by 365 or 360, defining the scalar binary64
input. All scenarios start from the frozen snapshot. Past cash events are
removed; cash exactly at valuation retains an explicit before/after convention.
The supplied spot represents that chosen valuation side and is not adjusted for
past payments. American opening rolls to the later of its original instant and
valuation; Bermudan rolls remove past rights and never add new ones. Expiry
before the selected valuation instant gives a per-row Post_expiry result.
Curve levels are right-continuous at valuation, retain future knots and use
the final left level at expiry. Schedule errors are rejected before filtering,
so a roll cannot hide malformed events or invalid duplicate exercise/curve records.
Scalar-permitted coincident cash records retain their original order and amounts.

## Identity, reuse and bounds

Versioned canonical identity includes all exact input words, complete original
schedules/sides, output order, all accuracy/work settings, quotes, date convention,
scenario encoding and plan resource policy. Configurations gain read-only private
record introspection so identity never depends on opaque Marshal layouts.

Plans share only immutable inputs, bindings and frozen schedules. A row admits
its rolled model once and reuses that admission among requested operations.
Fixed batches reuse supplied admissions across executions. Existing request-owned
grid/coefficient/event reuse remains inside the qualified scalar owners and uses
their full dependency keys. No inter-row factor/value-surface cache is added:
S/K/grid, coefficient levels, event order, sigma and resource policy can differ.
Cross-request operator caching/crossover work remains #119; successful compilation
does not assert a faster solve. Solver workspaces remain per-call/worker-owned.

Checked sums/products bound instruments, scenarios, calculations, tile rows,
workers and buffered output slots. A separate maximum admitted solver workspace
policy rejects operations whose configured scalar allowance exceeds it. It is
not an RSS/allocation cap; admitted schedules/plan storage and result diagnostics
are disclosed separately. Cancellation is an atomic token checked within scalar
work and between outputs/rows. Worker cancellation cannot emit a successful row
for interrupted work. Only the coordinator invokes the sink, in scenario-major
original-position order; committed counters advance only after sink acceptance.
All workers join before return, including cancellation and exceptions. Empty
plans, sink errors, worker failures and incomplete prefixes remain explicit.

## Qualification before adoption

Test scalar/compiled complete-outcome equality for constant, cash, Bermudan and
piecewise price/Greeks; supported certified and IV outputs; and exact refusals.
Independently test date conversion, right-continuous rolls, before/after cash,
terminal payoffs, sparse rights, past events and post-expiry outcomes. Keep
unresolved scalar references explicit. Exercise changed strikes/coefficients/
schedules/quotes/settings in identity tests and protect all input/output arrays.

Test repeated and concurrent batch/plan use, 1/2/3-worker replay, tile ownership,
resource arithmetic, cancellation inside a PDE request, cancellation between
outputs/rows, sink rejection/exception, and stable committed-prefix accounting.
Add type-rejection tests for unsupported models and assurance conversion, plus
compiled fault witnesses for event filtering, output identity, bounds and
cancellation/commit semantics. Run native/bytecode and installed consumers,
ordinary development/release suites, format/install and affected mutants.
Preserve existing European API/determinism and five-job/seven-mutant CI scope.

After owned validation/profile jobs finish, record five fresh-process rounds
of compilation and reused execution separately: fixed batch versus explicit
scalar calls, and dated plans with 1/2 workers, for analytical and general PDE
prices plus representative Greek/IV/certificate outputs. Retain exact driver,
binary/source/configuration, warmups, all samples, process allocation/GC/RSS,
host load and first-output/cancellation observations. Report amortized throughput
as such. No deployment SLA, universal parallel speedup or new numerical accuracy
threshold is inferred; broad workload/crossover acceptance remains #119/#120.

## Fixed measurement matrix (before measurement)

Use native release/O3 OCaml 5.3.0 Flambda. Each workload has four identical
positions (distinct IDs) and two paired scenarios: base spot 100 and spot 101,
both at day zero. K=100, r=.05, q=0, sigma=.2, expiry day365, opening day0,
ACT/365F, no cash. Workloads: call price, general put price, put delta+gamma
bundle, call estimated IV, call certified reduction. Price configuration:
64 space cells, 64 time steps, two domain expansions, tolerance1; work limits
8192 nodes, 131072 steps, 1048576 policy solves, 100000000 row visits, 8MiB
workspace, 64 policy iterations. Greek tolerances are10, default bumps.
IV search [.05,.6], width .01, 32 evaluations and independent fixed quote
`0x1.4e6b2e3d54dc2p+3` (the existing call-100-0.05-american reference).
Certificate absolute limit1e-9. Quotes stay fixed under the spot shock.

Compare explicit scalar calls on eight pre-admitted inputs with the matching
compiled fixed batch. Separately measure dated-plan execution with one and two
workers, tile_rows=1, no-op streaming sink with first-row clock observation.
Use two warm-up executions and five measured executions per mode per process;
five fresh processes alternate forward/reverse mode order. Compilation alone
uses 100 repetitions after two warmups, separately for fixed and dated plans.
Compare complete scalar/batch/plan outcomes outside timing. Per-mode cumulative
allocation is coordinator-domain only; separate per-child RSS includes workers.
Process-wide GC counters are reported as diagnostics, never mislabeled as
whole-process allocation. No missing/refused Greek quantity counts as a success.

A separate cancellation probe requests cancellation after a controller delay
of5ms during a general put solve. Record actual issuance and elapsed return,
controller scheduling delay, committed prefix and stop reason. This observation
has no latency threshold. Compilation bounds include market factors and schedule
events; the date adapter supports the qualified 64-bit runtimes only.
