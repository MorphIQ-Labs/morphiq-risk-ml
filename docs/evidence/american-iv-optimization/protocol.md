# Focused American inverse optimization protocol (#119)

Frozen before profiling, candidate implementation or performance scoring.
Baseline is PR #141 head `8b3a25f9fdabfbc29da6861f4d9f6599ac365878`.
If its integration merge occurs during this work, verify tree equality and
record the squash merge before rebasing this focused branch. Broad #119 stays
open; this pass does not deliver compiled workloads or alternative engines.

Use the unchanged `bench/american_iv.ml` corpus/configuration: exact fixed quotes
from #117, sigma range [0.05,0.6], full width 0.005, 64 permitted evaluations,
128 space/time cells, three domain expansions, pricing target 1 and the existing
whole-request budgets. Measure no-early call, American put and terminal cash
call: standalone price, admitted inverse and admission/quote-validation plus
inverse. Do not change quotes, resolutions, work allowances or accuracy targets
to earn a performance pass. Scalar price performance is a control, not an inverse.

Engineering adoption criteria, fixed before edits: both PDE inverse workloads
must reduce median cumulative allocation and median latency by at least 25%.
The analytical inverse and all standalone-price controls must not regress by
more than 5% allocation or 10% median latency. These are matched optimization
criteria, not deployment budgets or an SLA. Preserve every failed candidate and
sample; unmet criteria require diagnosis or deferral, not relaxed targets.

Profile allocation with OCaml Memprof and collect CPU stacks separately from
acceptance timing. Attribute cost to owning operations. Consider bounded,
request-owned preparation reuse only with complete dependency keys, workspace
accounting and uncached fallback. Never reuse an operator/factor/value surface
when its dependencies change. Alternatively, a safeguarded proposal rule may
reduce full price calls, but it needs a written argument before implementation:
proposals cannot establish signs, exact roots, uniqueness or price accuracy.
The original strict uncertainty-aware signs and full-width test remain the
only successful inverse acceptance criteria. Flat, invalid or unrepresentable
proposals require bounded safe fallback. No vega lower bound may be assumed.

An intentional probe-order change may change the returned estimated endpoints,
work count and availability under a small evaluation budget. Document that
compatibility change. Every accepted interval must contain the complete fixed
independent reference and meet the unchanged width/price-indicator checks.
Retain all original 30-row outcomes at initial/refined domains and width 0.005,
plus the negative-yield supplement, plateau/low-vega, quote perturbation,
cap/range, event/finite-rights, callback, workspace and forced-budget controls.
Do not replace a failed price with a sign or hide newly unavailable rows.
Unchanged price/Greek/European implementations must retain their ordinary
numerical/determinism checks; any shared arithmetic change expands qualification
to that owner's full affected campaigns before adoption.

Run applicable native/bytecode, development/release ordinary, type, installed
consumer and affected compiled mutation checks. Add independent witnesses for
new progress/uncertainty guards. Default CI remains five jobs/seven core mutants;
full source-artifact/cross-platform qualification remains #120.

After task-owned builds, tests, profilers and reference jobs finish, run five
alternating baseline/candidate fresh-process pairs with identical drivers and
configurations. Retain all raw samples, full outcome identities per build,
source/tree/binary/driver hashes, compiler, hardware and host load. Measure
cumulative allocation separately from GC and per-child peak RSS. Do not treat
shared-host medians as tail latency, an isolated-host result or deployment
acceptance. Publish absolute remaining costs and the numerical compatibility
assessment, even when the frozen improvement criteria are met.
