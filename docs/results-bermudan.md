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

Final source-bound measurements and validation records accompany this report.
