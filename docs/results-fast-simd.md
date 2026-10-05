# Optional European Fast-batch SIMD experiment

**Decision: retain the prototype; defer production adoption and SLEEF.** On the
measured ARM64 host, a reused, fully eligible 4,096-price Bachelier batch improves
from **113.0 to 14.8 ns/price** with operation-preserving SIMD. Only **1.40×** of
that comparison is SIMD versus the equivalent native scalar kernel. Compilation
cost increases, one-shot execution regresses, and the mixed-model book gains
little. SLEEF changes output bits and is slower than the existing operation graph
for eligible batches of 32 or more. This completes the optional experiment in
[#8](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/8); deployment acceptance
and representative business workloads remain open.

No public library code, API, dependency, numerical budget, certificate or default
backend changes. The experiment is not a newly qualified production backend.
The [prospective protocol](../experiments/fast_simd/PROTOCOL.md),
[commands](../experiments/fast_simd/README.md) and
[complete retained evidence](evidence/fast-simd/README.md) accompany this report.

## Scope and arithmetic

The selected branch is **Bachelier OTM**, with positive maturity/normal volatility,
absolute forward–strike distance, discount and standard-deviation high word in
[2^-100, 2^100], and corrected standardized distance in [0.46875, 4]. These fixed
limits select the existing middle `Y_prime` rational approximation and ordinary
exponents. Every unselected request, including other models, ATM/ITM, expiry,
remote tails, extremes and invalid inputs, uses public `Batch.Fast` fallback.
The gate was fixed before scoring, not fitted to results.

Five paths separate preparation, native compilation and vector math:

1. Public `Batch.Fast.compile` / `execute` / `run`.
2. Prepared OCaml scalar: additionally hoist immutable DD distance, square root,
   volatility scaling, discount and quotient into a private plan.
3. Native scalar: evaluate the same prepared arithmetic in C.
4. Native SIMD: two binary64 AArch64 AdvSIMD lanes, preserving operation grouping.
5. SLEEF SIMD: replace only the reduced-argument elementary exponential with
   `Sleef_expd2_u10advsimd`; retain the rational and split exponent calculation.

Native scalar and SIMD are instantiated from the same operation template.
Multiplications remain separate and only the original explicit FMAs fuse.
Implicit contraction, fast-math and auto-vectorization are disabled; the latter
keeps the native scalar control scalar. The assembly record shows scalar `fmul`
and two-lane vector arithmetic. Vector exponent restoration uses multiplication
by an exactly constructed normal power of two instead of scalar `ldexp`.
Under the bounded gate, the rational numerator/denominator remain positive,
all restored values are normal and the relevant exponent integers are small.
There is no subnormal rescaling path in the selected kernel. For the elementary
exponential's |x| < 2^-54 shortcut, the port's Horner accumulator rounds to 1,
so it evaluates the same `1+x`; the other elementary branches are unreachable
on the reduced interval. These are restricted-domain arguments, not full-domain
conformance or a proof of the compiler's implementation.

The native boundary takes a private SoA float array (q, residual, s, discount),
uses unaligned-capable NEON loads/stores, and returns into a fresh float array.
Odd selected counts receive a neutral padding lane. Fallback and selected
results are restored to original request order. The C function checks shape
and mode, retains no pointers, allocates no OCaml values, and does not release
the runtime lock. Typed OCaml code owns input validity and finite/nonnegative
result conversion. There is no shared scratch or cached price. The experiment
requires OCaml's flat float arrays; the recorded compiler enables them.

[SLEEF 3.6.1](https://github.com/shibatch/sleef/tree/3.6.1), commit
`6ee14bcae5fe92c2ff8b000d5a01102dab08d774`, is an external static build under its
Boost Software License 1.0. Its header, archive and build configuration hashes
are retained; no SLEEF implementation payload is committed. Its upstream test
suite was not run. The advertised elementary-function ULP specification does
not certify the composite price. Inherited project coefficient notices remain
in [NOTICE.txt](../experiments/fast_simd/NOTICE.txt).

## Numerical evidence and changed bits

The final corpus contains **110,632 rows**: 99,088 existing European/displaced
fixture rows, 208 branch/scale boundary cases, 66 exponent-reduction neighbors,
2,048 fixed-seed random original-input cases, 9,216 Bachelier timing requests and
six deliberate invalid/limit cases. Repeated inputs are retained. All Bachelier
requests actually timed are included, not only a nearby random population.
New numerical references refine the original binary64 inputs using the Gaussian
expectation formula at 100 and 200 decimal digits with mpmath 1.3.0; none was
unresolved. Agreement of refinements is empirical reference evidence.

- **8,220 selected rows:** prepared OCaml, native scalar and native SIMD match
  public Fast bit for bit. All five paths have worst rounded-reference distance
  **7 ULP** and worst normwise error **0.548 epsilon × scale**, inside the existing
  8-ULP / 4.3-epsilon requirements. The selected original oracle region is OTM;
  its observed maximum does not regress.
- **102,412 fallback rows:** every outcome matches, including five explicit
  failure outcomes. The sixth deliberate challenge returns an accepted value;
  the experiment does not reclassify it.
- **580 changed SLEEF rows (442 distinct inputs):** independent original-input
  refinement finds 263 improved and 317 worsened absolute errors. Changes are
  at most two binary64 words. Every row, both outputs, rounded reference, refined
  reference and signed error is retained. No changed row was discarded.

These results cover the exercised corpus only. They do not establish a uniform
error bound, new runtime certification, monotonicity over the entire domain,
x86-64 conformance or downstream Greek/IV compatibility. SLEEF's changed bits
would need the ordinary stability and backend review before adoption.

Native controls pass for empty, odd and mixed sizes, frozen input ownership,
nonaliased outputs, concurrent executions of all four prepared modes, and
invalid native shape/mode rejection. Eleven Python control groups exercise
scorer coverage, nonfinite/malformed data, changed-operation decisions, fallback
mismatches, failed startup/processes, real timeout/reap behavior, partial evidence
retention and source-change rejection. These controls run in ordinary CI without
SLEEF; the native experiment remains opt-in.

Both development and release ordinary suites pass, with the unchanged public
determinism digest `5ee6731f4b8a5674b949840d89e87346e18c300d99d9e863cad32185bedd8199`.
The first release command reported a Dune formatting difference; formatting was
corrected and the final aggregate command passes. Historical logs are retained.
Focused scalar preparation/fallback mutation results accompany the evidence;
these are not mutation qualification of every new native operation. Default CI
continues to run the existing seven core mutants.

## Performance evidence

Measured 2026-10-05 UTC at source
`b78eef6cd0f1027fefc9a8e4d68f208d6f46102d`, clean at collection start/end. The
library tree remains `0da7e7fda5ef50b4bd7696580829fd9a3adea598`, identical to the
qualified Fast allocation implementation. The native executable SHA-256 is
`7eecd8fd7878e0d76a13ad762db9221ed74d78876173458409e5544e26764d04`.

Host: Apple M1 Pro, 10 cores, 16 GiB; macOS 27.0 (26A428); upstream OCaml 5.3.0
Flambda; Dune 3.24.2; Apple Clang 21.0.0. The driver uses Dune release defaults;
the library and C kernels use their recorded `-O3` settings. One-minute load
ranged **9.45–10.98**.
This shared workstation was not isolated or idle. Task-owned builds, tests and
profilers were stopped during the timing campaign.

Four fresh processes run backend order forward/reverse/reverse/forward. Each
phase has three warmups and five samples, totaling **3,600 retained samples**.
Each sample averages max(2,8192/n) calls. Reported centers are medians of the four
process medians. Tables use **ns per output**; n>1 is amortized batch cost, not
individual request latency. The n=1 rows are repeated-call means, not cold-start
or tail latency. Compilation includes admission, layout conversion and packing;
execution includes native dispatch, fallback, output allocation and extraction.
One-shot starts from constructed typed requests and includes compile + execution.
Phases are timed independently and their medians need not add because of heap
state, collection and cache effects.

### Fully eligible Bachelier book: reused execution

| Batch size | Public Fast | Prepared OCaml | Native scalar | Native SIMD | SLEEF SIMD |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 111.2 | 177.1 | 69.3 | 62.6 | 56.9 |
| 32 | 100.0 | 78.7 | 18.2 | 12.0 | 13.5 |
| 256 | 99.1 | 79.6 | 16.7 | 11.0 | 12.6 |
| 4,096 | 113.0 | 90.1 | 20.7 | 14.8 | 16.2 |

At n=4,096, public execution takes **462.8 µs/batch** versus **60.5 µs** for
native SIMD, or 7.65× faster. Its four process medians span 14.53–15.01 ns/price;
public Fast spans 109.99–113.65. Native scalar already accounts for most of the
gain; SIMD adds 1.40×. OCaml allocated bytes/price fall **480.0 → 48.0** for reused
native execution (90%); prepared OCaml uses 320.0. These counters are allocation
volume, not retained heap, peak RSS or total native memory. Scalar/native results
also reflect compiler inlining and boxing differences; they are not a language-wide
performance comparison.

### Costs that prevent default adoption

The comparison below uses operation-preserving native SIMD at n=4,096. The
fallback-heavy book selects 25% of its Bachelier requests; the mixed book selects
25% Bachelier and falls back for BSM, Black-76 and displaced Black.

| Book and phase | Public Fast ns/price | Native SIMD ns/price | Change |
| --- | ---: | ---: | ---: |
| Eligible compile | 126.4 | 247.9 | +96.1% |
| Eligible reused execute | 113.0 | 14.8 | −86.9% |
| Eligible one-shot | 185.2 | 266.0 | +43.6% |
| Fallback-heavy compile | 126.5 | 304.9 | +141.1% |
| Fallback-heavy reused execute | 129.9 | 107.4 | −17.4% |
| Fallback-heavy one-shot | 213.8 | 450.9 | +110.9% |
| Mixed compile | 815.1 | 873.6 | +7.2% |
| Mixed reused execute | 794.7 | 788.5 | −0.8% |
| Mixed one-shot | 1,477.8 | 1,670.3 | +13.0% |

For n=1 eligible one-shot pricing, public Fast is **180.1 ns** and native SIMD
**264.1 ns**, a 46.6% regression. A single unselected request also pays routing
cost: reused execution 129.3 → 155.5 ns, one-shot 200.8 → 418.3 ns. There is no
uniform single-request improvement. At n=1 the “mixed” book contains only its
first, Bachelier request; it must not be interpreted as a mixed workload.

Eligible one-shot allocation increases **989.7 → 1,122.4 bytes/price**, because
extra preparation outweighs the execution allocation saving. SLEEF improves the
single selected reused case but costs **9.5% more** than native SIMD at n=4,096,
with the same output allocation. It does not justify a new dependency and changed
bits for this experiment. Full per-process medians, compile/execute/one-shot
allocations and CPU elapsed measurements remain in the evidence.

Separate CPU samples of the recorded binary show the eligible public path spending
substantial leaf samples in `Y_prime` and elementary exponential evaluation;
the mixed public path is dominated by DD exponential work. SLEEF's scalar
binary64 exponential cannot replace those DD operations under the same contract.
Profiles are attribution aids, not latency measurements; OCaml stack unwinding
has limitations, so leaf histograms are retained without claiming exact cost
percentages or hardware-counter evidence. Native allocation and result handling
become more visible as arithmetic shrinks. No scheduler or worker throughput
claim follows from these single-domain measurements.

## Follow-up disposition

Keep production on the current backend. If a real workload repeatedly executes
large, eligible Bachelier plans, the operation-preserving native kernel is a
candidate for a separate design: reduce preparation/routing overhead, specify
backend selection and packaging, qualify every supported architecture and add
native-operation mutation witnesses. Mixed-model DD work needs its own profile
and operation-level proposal; a broad elementary-function substitution is not
supported by this result. Representative business inputs, target hardware,
sink/transport costs and owner-set latency/memory requirements remain with #8
and #16. American tridiagonal work remains with #109/#119; it is not blocked by
this optional experiment. No release, tag or qualification transfer is implied.
