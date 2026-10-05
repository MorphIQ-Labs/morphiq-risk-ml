# Initial American pricing references

[#110](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/110) supplies the
initial reference corpus before runtime American pricing. It follows the
[financial contract](american-model-contract.md) and
[solver/assurance design](american-solver-design.md). **No runtime American API
is implemented or qualified by this campaign.** Subsequent runtime results
are in the [#111 implementation evidence](american-pricing.md).

The [frozen protocol](evidence/american-references/protocol.md) and
[41-case corpus](evidence/american-references/cases-v1.json) were committed as
`4369884` before either engine was executed or prices were scored. Both sides,
ITM/ATM/OTM, short/long expiry, low/high/zero volatility, signed rates and yields,
delayed opening, absorbing/expiry boundaries and currency scaling are covered.
The primary engineering tolerance is epsilon=2^-16 max(S,K), with a required
reference radius no larger than epsilon/8. Zero-scale cases require exact zero.
The additional epsilon/4 challenge requested by #109 uses the same scorer; it
never widens the primary tolerance.

## What was executed

| Route | Role and limits |
| --- | --- |
| Pinned QuantLib finite differences | Canonical comparator at paired space/time grids 128, 256, 512 and 1024, Crank–Nicolson and two damping steps. Its results do not define truth. |
| Original standalone stock tree | Independent two-point stock-mean matching and backward stopping recursion; no QuantLib lattice or runtime solver imports. Paired N/N+1 sizes at 512/1024/2048/4096, with empirical extrapolation and width diagnostics. |
| mpmath 1.3.0 at 80/160 digits | Replay 64 or 128 steps of the same discrete stock-tree target with direct node exponentials, independently of the C++ stock recurrence. An arithmetic screen, not a continuum error bound. |
| python-flint 0.9.0 / Arb at 256/512 bits | Original-input analytical European, expiry, absorbing stock, zero strike and deterministic stopping calculations. Finite outward endpoints are verified against the Arb intervals. |
| Exact rational event replay | Eight zero-carry/zero-volatility cash and Bermudan examples; an additional absorbing-stock piecewise-rate example uses Arb. These are initial extension specifications, not general stochastic extension references. |

The [build record](evidence/american-references/build.json) identifies the exact
compiler/options, library/configuration hashes and both runner binaries.
QuantLib revision `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c` was clean. Its
previously built library, CMake cache and configuration matched the
[existing source-bound build](evidence/exchange-implementation/quantlib-build.json);
`cmake --build` reported no work. Both new original adapters were compiled with
C++17, `-O3`, contraction disabled and project warnings treated as errors. This
was reuse of a verified library build, not a newly rebuilt full QuantLib tree.

Canonical inputs use evaluation date 2025-01-01, Actual/360, continuously
compounded flat r/q, annual lognormal volatility and immediate-settlement
AmericanExercise. The adapter requires every mapped time word to equal its
original input. QuantLib's same-date Instrument NPV=0 is recorded as incompatible
with this project's expiry payoff. Zero-stock engine exceptions remain explicit.
This comparator has no cash schedule and must not be reused as a cash oracle.

## Independent derivation and assurance

For each tree step dt, choose u=exp(sigma sqrt(dt)) and d=1/u. Matching the
conditional stock mean gives p=(exp((r-q)dt)-d)/(u-d). Nonnegative probabilities
are a precondition; an out-of-range probability is refused without clipping.
Backward induction discounts the two child values and competes with immediate
payoff only at eligible nodes. This construction differs from the planned PDE
operator and policy solve. It approximates the diffusion and continuous stopping;
no finite tree price is asserted to be a continuum bound.

At each base N divisible by four, the runner also computes terminal European
and quarterly Bermudan values on the **same tree**, intersecting rights with the
American opening window. This checks nested exercise-set monotonicity without
asserting continuum accuracy. The delayed opening index is the exact-rational
ceil of opens*N/T; its gap to opening is part of the stopping discretization.
The adjacent odd-N run supplies only the European/American pair, not a silently
rounded Bermudan schedule.

For N/N+1 mean A(N), 2*A(2N)-A(N) is an empirical extrapolation candidate. Its
radius is four times the largest of the last two candidate changes plus the
frozen arithmetic screen. That multiplier/order assumption has no theorem of
containment: these references are labelled **empirical**, even when narrow and
in agreement with QuantLib. Width or precision-screen failures remain unresolved.
Analytical lower/upper bounds and scaling cross-check the candidate where their
premises hold. No result is passed through the library's existing certificate
constructors.

Analytical routes treat binary64 words as exact rationals before Arb operations.
A deterministic window checks endpoints and admissible stationary times
q*S(t)=r*K; it includes the exact 250/9 interior-maximum example. Zero-strike calls
retain the stopping problem: their value is S times the largest exp(-q*t) over
the window. Zero-stock puts similarly maximize K exp(-r*t), including negative
rates. The no-early-exercise call reduction is used only for no cash, q=0 and
r>=0. These model reductions are distinct from empirical general-American values.

Very small European probabilities can have impractically large exact rational
denominators. Export uses finite binary64 endpoints widened outward and then
**checks containment with Arb**, including underflow to endpoints around zero.
It does not set a tiny positive reference to an exact zero or disable integer-size
limits. This affects reference serialization, not any runtime pricing path.

## Results and retained uncertainty

[All references and comparisons](evidence/american-references/references-v1.json)
retain original words, analytical intervals, precision replays, every lattice
level, uncertainty estimates and per-level canonical classifications.

- 33/41 independent references are usable under the primary policy: **13
  analytical intervals and 20 empirical lattice estimates**.
- Eight references remain unresolved. They are present in the fixture and cannot
  produce a successful accuracy comparison.
- At the finest canonical grid, **27 comparisons pass**, eight are unscoreable
  because the reference is unresolved, and six are convention/engine exclusions.
- Across all four grids, retain 85 passes, **23 failures**, 32 unresolved-reference
  comparisons and 24 exclusions. The failures occur on coarser grids; none is
  relabelled as a pass because a finer run succeeded.
- All 124 available discrete exercise-inclusion checks pass their floating-point
  screen. Forty boundary/probability cases lack that tree route and remain
  unavailable. The two powers-of-two scaling comparisons have overlapping
  independently computed intervals. All nine extension witnesses pass.

| Canonical space/time grid | Pass | Fail | Unresolved reference | Excluded |
| --- | ---: | ---: | ---: | ---: |
| 128 | 12 | 15 | 8 | 6 |
| 256 | 21 | 6 | 8 | 6 |
| 512 | 25 | 2 | 8 | 6 |
| 1024 | 27 | 0 | 8 | 6 |

These are finite-corpus results, not a recommendation that grid 1024 is sufficient
for all inputs. The separately retained epsilon/4 comparisons can lose reference
eligibility or fail at a grid that meets the primary epsilon. No acceptance
threshold was tuned to the observations.

| Unresolved case | Empirical radius | Allowed primary radius | Disposition |
| --- | ---: | ---: | --- |
| `call-80` | 0.000234480 | 0.000190735 | Width exceeds fixed goal |
| `call-120` | 0.00170078 | 0.000228882 | Width exceeds fixed goal |
| `call-long-high-vol` | 0.00229022 | 0.000190735 | Width exceeds fixed goal |
| `put-80` | 0.000508239 | 0.000190735 | Width exceeds fixed goal |
| `put-120` | 0.00168673 | 0.000228882 | Width exceeds fixed goal |
| `put-long-high-vol` | 0.00172761 | 0.000190735 | Width exceeds fixed goal |
| `put-low-vol` | 0.00110876 | 0.000190735 | Width exceeds fixed goal |
| `probability-stress` | Unavailable | 0.000190735 | Probability outside [0,1] at a frozen tree level |

#111 must extend/adjudicate independent evidence before claiming accuracy in
these eight cases; their existence does not make those financial inputs invalid.
The initial-reference task explicitly allows unresolved cases. #112/#113/#114
must extend the reference specification and execute model-matched stochastic
cash/Bermudan/curve evidence before those capabilities ship. #116 still owns
useful rigorous full-price certification or an explicit estimated-only disposition.

## Reproduction and default CI

Both runners are original project code:
[stock tree](../scripts/american_lattice.cpp),
[QuantLib adapter](../scripts/american_quantlib.cpp), and
[shared strict input protocol](../scripts/american_runner_io.hpp).
The optional [generator](../scripts/generate_american_references.py) requires
mpmath 1.3.0 and python-flint 0.9.0, plus the two locally built executables.
Use the compiler flags and pinned source/build identity above; local paths in
the recorded build commands are replaceable paths, not build dependencies.

```sh
python3 scripts/freeze_american_cases.py          # print the frozen corpus
python3 scripts/check_american_references.py     # verify committed evidence offline
python3 scripts/test_american_references.py      # lightweight failure controls
# In an environment with the pinned optional packages and compiled runners:
python3 scripts/generate_american_references.py \
  --lattice /path/to/lattice --quantlib /path/to/quantlib \
  --output /new/campaign-directory
```

Generation refuses an existing output directory. Failed processes retain raw
output and cannot publish a complete reference fixture. `--reuse-raw` can replay
analytical export/scoring from a prior campaign only after exact input, runner
source/binary and raw-stream checks. Both completed raw streams remained byte
identical across the endpoint-export correction and the final tighter-tolerance
scoring replay. Preliminary failures and build reuse are identified in the build
record; no failed attempt counts as a pricing comparison.

[The transitive manifest](evidence/american-references/manifest.json) pins the
corpus/protocol, generator/data owners, C++ sources, exact input streams, raw
outputs, build record and reference fixture. Changing numerics requires
regeneration and review, not hand-editing a fixture or its expected values.

Default Dune CI runs only the standard-library schema/provenance and failure
controls. They reject corrupt sources/fixtures, missing/duplicate rows, truncated
or nonfinite output, changed tolerances, incorrect prices/expectations, failed
startup, nonzero process exit and timeout. They recheck all cash expectations
and primary/tighter scoring semantics. They do not compile QuantLib or generate
large trees, and add no optional Python/runtime dependencies or broad mutation
campaign to normal CI.

The source and publication provenance from
[#109](evidence/american-solver/sources.json) remains applicable. No new paper
was downloaded for this campaign, no third-party implementation was translated,
and no public build accesses the private research archive. Source-bound reference
completion is distinct from runtime implementation, performance qualification,
independent external review and deployment acceptance.
