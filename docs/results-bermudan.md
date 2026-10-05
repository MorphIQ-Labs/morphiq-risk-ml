# Bermudan implementation evidence (#113)

The implementation adds explicit finite exercise schedules to the estimated
scalar BSM API. The [contract and limits](bermudan-pricing.md) and
[frozen protocol](evidence/bermudan/protocol.md) govern this campaign. The corpus
was frozen at `ed6d0ea`; executed references were committed at `affdfa6` before
runtime edits. Baseline is American integration `9635803`.

## Independent capability

All 32 rows are retained in each configuration. Primary tolerance is
`2^-16 max(S,K)`; loose tolerance is `max(S,K)/100`. A reference's empirical
radius must fit within one eighth of the requested tolerance to count as resolved.

| Configuration | Independent passes | Runtime unavailable | Reference too wide |
|---|---:|---:|---:|
| Initial, primary | 14 | 18 | 0 |
| Refined, primary | 16 | 16 | 0 |
| Initial, loose | 18 | 14 | 0 |
| Refined, loose | 26 | 1 | 5 |

The refined loose run returns 31 prices. Irregular/dense schedules, negative-rate
put/cash and low-volatility rows have references too wide for accuracy passes.
The short-maturity irregular schedule fails the runtime refinement criterion.
Tighter targets remain a material limitation; no tolerance was widened and no
failed or unresolved row was dropped. These are engineering comparisons, not
certificates or recommended trading limits.

The 15 analytical/deterministic references and fixed discrete arithmetic replay
use 80/160 digits. Positive Gaussian quadrature independently projects finite
rights at N=256/512/1024 per slab. Eighteen references resolve the primary target;
26 resolve the loose target, independently of runtime availability. QuantLib
uses its recorded pinned build and N=128/256/512. Per-case adapter and unmodified
engine discrepancies are in [canonical comparisons](evidence/bermudan/canonical-comparisons.json).
For example, the unmodified cash call with After-only exercise differs from
our model because its dividend/exercise ordering admits pre-payment exercise;
its value must not be treated as a matching reference.

## Contract and compatibility checks

Public tests cover copied arrays/getters, order/duplicate/endpoint/side rejection,
terminal European reduction, finite deterministic stopping, both cash-event
sides, unlisted cash dates, valuation and expiry, nested schedules, American
domination with explicit diagnostics, resource/cancellation failures and
concurrent request ownership. Normal and lognormal volatility types remain
separate; results remain private and estimated-only.

The absorbing-boundary witness uses the backward-Euler discrete constant-strike
cap `K (1+r*h)^(-n)` for positive rates, plus accumulated local residual/roundoff
screens and boundary spread. Its feasible first-date analytical payoff supplies
a separate lower check. Comparing against an exact exponential cap using only
observed refinement initially failed by about 2.6e-9: refinement differences are
not a total-error bound. The corrected test follows the discrete equation and
does not change runtime tolerances or behavior.

All 284 existing American outcomes (41 no-cash and 30 cash cases, two targets,
two configurations) match the baseline in complete serialized outcome identity
and independent classifications. This includes prices, failures, diagnostics
and work counts; it does not replace independent correctness comparisons.

The three new optional mutation witnesses remove a finite deterministic right,
omit the listed valuation projection, or use an immediate absorbing boundary
before the next right. Seven existing affected American mutants are also in
scope. The catalog has 112 entries; default CI remains five jobs and seven core
mutants. Full catalog execution is not claimed.

## Cost characterization

The [cost protocol](evidence/bermudan/performance-protocol.md) fixes five fresh
processes, one warmup and three measured prices, allocation/GC and per-child RSS.
Matched American regression uses the unchanged price driver and source-verified
#133 baseline. Bermudan no-cash/cash measurements use distinct finite-right
models; their ratio to American times is not a speedup. Broader optimization is
#119; strict-target and source-artifact qualification remain #120.

The source-bound candidate is `b7cbc6af29ed98268d121ba587b5a4753a989527`.
[Raw samples and build manifests](evidence/bermudan/performance/results.json)
record an Apple M1 Pro, OCaml 5.3.0 Flambda, macOS 27, load 18.63–30.21.
Task-owned compute finished before timing; this remained a shared machine.

| Workload | Median price latency | Cumulative allocation / price |
|---|---:|---:|
| American, no cash: baseline → candidate | 140.25 → 139.76 ms | 12.8972 → 12.8980 MB |
| American, cash: baseline → candidate | 407.80 → 407.28 ms | 42.1534 → 42.1540 MB |
| Bermudan, two dates, no cash | 383.28 ms | 178.89 MB |
| Bermudan, two dates and both cash sides | 557.42 ms | 259.14 MB |

The American changes are within this session's timing variation, with under
1 KB extra allocation per request. These different financial models do not
establish an American/Bermudan speed comparison. Process peak RSS across samples
was 7.73–8.19 MB, distinct from cumulative allocation. No deployment memory or
latency budget has been accepted.

**Bermudan allocation remains material and needs follow-up under #119 before
compiled workloads.** A subsequent [allocation profile](evidence/bermudan/allocation-profile.json)
attributes about 88% of no-cash and 81% of cash sampled allocation to enclosed
exponentials used in the absorbing boundary's next-exercise discount. Continuous
American exercise often has zero waiting time, so it avoids that computation.
A bounded request-owned cache of exact slab/time-level boundary evaluations is
a candidate for a separate correctness-preserving optimization pass; numerical
recurrences or rounded-time cache keys require their own derivation. No such
cache is implemented or measured here. Cash interpolation and all strict-target
limitations remain relevant.

Development/release suites, package/format checks, explicit bytecode contract
controls, the locally installed public native/bytecode example, and ten affected
mutation witnesses pass. [Validation records](evidence/bermudan/validation.json)
retain the initial surviving boundary probe and its corrected numerical witness.
The default seven-mutant CI lane is unchanged; full-catalog and cross-platform
source-artifact qualification remain #120. No release or main-branch merge is
implied.
