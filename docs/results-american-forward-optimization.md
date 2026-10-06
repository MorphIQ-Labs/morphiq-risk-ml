# Terminal cash-call acceleration and general-solver evaluation (#119)

Scalar terminal-cash calls now use an exact European payoff reduction, retaining
original-input arithmetic and event-side semantics. Earlier exercise, earlier
cash, puts and independently qualified Greek evaluations retain their existing
routes. This is an estimated-only price improvement, not a new certificate.

## Derivation and numerical compatibility

The [protocol](evidence/american-forward-optimization/protocol.md) precedes runtime
edits. For nonnegative strike K and joint payment D,
`(max(X-D,0)-K)+ = (X-(K+D))+`. If pre-cash exercise is permitted at that same
terminal instant, its payoff dominates. Positive expiry, terminal-only exercise
and all cash at expiry are enforced after complete admission/schedule processing.
Constant coefficients use the retained two-word strike centre and an outward
`exp(-rT)`-Lipschitz allowance for its remaining uncertainty. Piecewise
coefficients retain the entire strike enclosure through the integrated formula.
Existing boundary reductions have precedence. Arithmetic failures and the
original tolerance/64 allowance remain authoritative.

The [original generator](../scripts/generate_terminal_cash.py) computes 40
exact-binary-input cases at 256 and 512 Arb bits, using erfc independently of the
runtime CDF. Every case exercises both American and Bermudan admission: 80
prices. The strict tolerance is `2^-30 * max(S,K,individual cash amounts)`.
Cases include signed rates/yields, both event sides, simultaneous amounts,
piecewise coefficients, low strike words, extreme scales and zero effective
strike. All 80 candidate intervals contain their complete independent reference
intervals; all 80 old requests refused at identical settings. References were
committed before the runtime change. The ordinary offline checker binds exact
TSV inputs/intervals to the generator and precision records; five negative
controls challenge that checker.

Of the original 572 price outcomes, only the two terminal cash-call contracts
change across four configurations. Six previously unavailable requests now pass;
the two already served loose/refined prices improve their independent worst
errors from approximately 0.00365/0.00189 to below 7e-16. The other 564 complete
payloads and independent classifications are identical. All 920 Greek rows and
full base-price/diagnostic payloads remain identical. Greek base/perturbed prices
retain the qualified PDE route: the scalar identity alone does not qualify
spatial extraction or fixed-event theta, so their estimates may differ visibly
from separate scalar price requests.

Only the two cash-terminal inverse contracts change: initial-domain availability
improves from 24/30 to 26/30, while refined and tight campaigns remain 30/30.
All accepted brackets contain their complete independent reference intervals at
the original full widths (0.05 and 0.005); the other 28 full outcomes remain
identical at each setting. The [per-case record](evidence/american-forward-optimization/raw/iv-compatibility.json)
preserves old/new endpoints, call counts and exact rational reference gaps.
No cash-put inverse, piecewise inverse or certification claim is added.

## Matched performance and qualification

Baseline is integration `07916c6d706eb3c2193deba3dc475c8f3ab218bb`; measured
candidate is `a0c89b7905fd946215e05fd25b56c6c7bd32d830`, containing runtime
`c222191f5974e48d865701bcfc355347af675f3d` plus documentation. Both clean
worktrees use OCaml 5.3.0 Flambda, release mode and `-O3` library/benchmark flags
on Apple M1 Pro. The [unchanged fixed benchmark](../bench/american_iv.ml) uses
identical quotes, 128/128 grids, three domain expansions, full inverse width
0.005 and original budgets. Five alternating fresh-process pairs each contain
one warmup and three timed blocks per path. The table reports medians of 15
block averages; analytical blocks average 20 sequential requests, others one.
No task-owned build, test or profiler overlapped timing. A further installed
inverse native/bytecode check ran afterward against the same installed runtime.

| Path | Median milliseconds/request, before → after | Cumulative MB/request, before → after |
| --- | ---: | ---: |
| `american-put/end-to-end` | 655.9420 → 660.8580 | 80.923200 → 80.923200 |
| `american-put/price` | 107.4730 → 107.1820 | 13.475224 → 13.475224 |
| `american-put/solve` | 655.1650 → 657.2520 | 80.922728 → 80.922728 |
| `call-100-0.05-american/end-to-end` | 0.4821 → 0.4828 | 0.710182 → 0.710182 |
| `call-100-0.05-american/price` | 0.0811 → 0.0816 | 0.116662 → 0.116662 |
| `call-100-0.05-american/solve` | 0.4816 → 0.4867 | 0.709710 → 0.709710 |
| `cash-terminal-american/end-to-end` | 654.0640 → 0.3490 | 142.453272 → 0.527464 |
| `cash-terminal-american/price` | 164.1790 → 0.0710 | 35.601424 → 0.120672 |
| `cash-terminal-american/solve` | 656.3770 → 0.3420 | 142.452344 → 0.526536 |

All frozen adoption criteria pass: terminal cash price/solve/end-to-end latency
and allocation each fall by at least 90%; unchanged analytical and American put
controls stay within 10% latency/5% allocation allowances. The separate piecewise
terminal-call price improves **605.463 → 0.126 ms**, with cumulative allocation
**70.425 → 0.189 MB**, over another five alternating process pairs. Its price
changes from the grid estimate to the independently checked terminal formula;
its original one-currency-unit target is unchanged.

**Peak process RSS increases despite lower allocation:** the mixed benchmark
process reaches 13.19–13.93 MB before and 19.04–20.05 MB after. Each child's own
`wait4` reap measures the whole sequential benchmark process, not a single
request or concurrent deployment. The median OCaml heap high-water count also
increases (717,110 → 1,323,843 words); this campaign does not isolate its cause.
Median minor/major collections fall from 1470/440 to 651/218 per process.
Eight MiB of configured pricing workspace remains distinct from cumulative
allocation, OCaml heap capacity and RSS. No RSS improvement is claimed.

Shared-host one-minute load was 5.34–7.12. These are warm local engineering
measurements, not cold-start, tail-latency, concurrency or deployment acceptance.
The [raw measurements](evidence/american-forward-optimization/raw/timing.json)
retain ranges, exact inputs, GC, compiler/OS/source/tree/binary/driver identities
and all 10 process observations. Nine collector controls cover malformed,
truncated, duplicated, nonfinite, failed/timeout and impossible-target evidence.
The complete [raw archive](evidence/american-forward-optimization/raw.tar.gz)
includes price/Greek snapshots, independent scores, profiles, qualification,
per-process logs and original reproduction drivers. The
[manifest](evidence/american-forward-optimization/SHA256.json) hashes every
published evidence artifact.

Development and release ordinary suites, package/format checks, 19 affected
compiled mutants, installed native/bytecode terminal consumers (80 cases) and
installed tight inverse consumers (30 cases) pass with complete cross-mode
output identity. Full
572-price, 920-Greek and three 30-case inverse campaigns retain unchanged targets
and explicit failures/unresolved references. The seven new terminal mutants
cover exercise/cash dates, call/put separation, event phase, exact low word,
payment inclusion and the separate Greek route. The optional catalog is 157;
default CI remains five jobs and seven core mutants. Final immutable
source-artifact qualification and independent review remain #120.

## Canonical comparison and specialized-method disposition

The supplementary comparator is clean QuantLib revision
`79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c` (1.44.0), built externally. The
[original adapter](../scripts/american_acceleration_reference.cpp) is research
infrastructure, not a runtime dependency or translated third-party implementation.
QuantLib's license and source/library/compiler identities are retained as hashes.
No research PDF or third-party source is redistributed by this change.

For 31 matching constant terminal contracts, QuantLib BlackCalculator differs
from the independent exact-input references by at most 1.98e-14 currency units.
Nine cases are explicitly excluded for piecewise coefficients, unrepresentable
exact effective strikes or zero effective strike. Its binary64 forward/discount
construction is a distinct rounded evaluation and does not define truth.

For general American pricing, evaluate QdFpAmericanEngine's fast, accurate and
high-precision schemes on all 16 eligible original corpus cases: positive
spot/strike/volatility, nonnegative rate/yield, one-year full exercise window,
constant coefficients and no cash. All 30 scheme/case comparisons with resolved
independent references meet the original case epsilon. The remaining 18 have
unresolved independent references and remain unresolved; scheme agreement does
not convert them into accuracy passes. Every other original case has a recorded
scope exclusion. QuantLib reconstructs rates from discounts, so this also
contains input-conversion effects.

A separate five-process recalculation measurement of the matching ATM put gives
median **15.1 µs fast, 139.6 µs accurate and 5.073 ms high precision**. Each block
forces `option.recalculate()`; it does not time a cached NPV. Object construction
is outside the timed block. These are research engine evaluations with different
accuracy/work contracts, not drop-in public API speedups or certified prices.
Complete original-corpus scores, exclusions and samples remain in the archive.

**Disposition: pursue a separately qualified specialized method; defer production
adoption in this change.** The primary
[Healy 2021 treatment, sections 5.1–5.4](https://arxiv.org/html/2109.15157v1)
explains the exercise-boundary integral approach and the extra difficulties
under negative rates. The local canonical implementation was inspected at the
recorded revision; the ALO paper's
[primary abstract](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2547027)
was available, but its full text was not acquired. Before adoption, derive an
original-input arithmetic/error contract, convergence/failure handling, bounded
work/cancellation and price/Greek/IV interoperability; obtain/read the full
original algorithm and audit any implementation reuse terms. Cash jumps,
delayed/Bermudan rights, piecewise coefficients and multiple-boundary regimes
need separate derivations, not relaxed dispatch guards. The small eligible
research corpus cannot qualify that wider domain.

## Remaining general-solver cost

Fresh standalone-put CPU sampling still identifies `slab_constant` as the
largest leaf. Of 519 Memprof samples, approximately 48.7% arise in stencil
preparation, 37.4% in time-slab work, 3.9% in grids and 10.0% elsewhere. These
sampled shares are attribution evidence, not exact allocation budgets.

The terminal reduction removes an unnecessary grid solve; it does not accelerate
ordinary American put time stepping. A next focused native-loop experiment should
compare policy selection and tridiagonal elimination/back substitution using
actual policy matrices and complete requests. Preserve original operation order,
explicit FMA versus rounded multiplication, pivot/failure order, logical work and
bounded cancellation checkpoints. Factor reuse is valid only for an unchanged
operator **and complete policy system**; changing IV sigma invalidates the
operator. No factor cache, new tridiagonal backend or general native solver is
adopted here. Broad #119 retains those comparisons, compiled portfolio/worker
campaigns and independently qualified derivative alternatives. Deployment targets
and final source-artifact qualification remain separate.
