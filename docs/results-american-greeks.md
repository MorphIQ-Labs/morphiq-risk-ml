# American Greek qualification (#115)

The scalar API delivers delta, gamma, parallel vega/rho and fixed-event theta
on the American integration branch, with separate per-Greek acceptance. It adds
estimates and explicit refusals; it does not add a certificate.
The [capability](american-greeks.md) defines coordinates, outcomes and exclusions.

## Frozen evidence

Baseline is `a980d1bfdc42a664a2f1bc11cd28263745cb2b98`. The
[protocol](evidence/american-greeks/protocol.md) freezes 46 original-word contracts,
five quantities, primary/loose absolute targets and initial/refined numerical
configurations. All 40 #114 cases remain, including cash and exercise events,
signed coefficients, zero-volatility segments and deterministic boundaries.
The additions cover expiry kinks, deep exercise, near-exercise stocks, the
no-early-exercise call reduction and valuation Bermudan rights.

Independent references use mpmath 1.3.0 at 80/160 digits and original Gaussian
quadrature at 256/512/1024 with derivative stencils, parallel parameter families
and fixed-future-event valuation rolls. Of 230 quantity rows, 61 references
resolve at the primary target and 105 at the loose target. These empirical
resolution classifications do not establish a universal error bound.

The [separate canonical campaign](evidence/american-greeks/canonical-addendum.md)
uses QuantLib `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c`, log-grid spline
spatial derivatives and price perturbations at 128/256/512. It resolves 32
primary and 124 loose rows. Canonical agreement never replaces an unresolved
independent reference. The initial finite theta sentinel and irrelevant calendar
round-trip exclusion were corrected; earlier raw attempts remain archived.

The [reference manifest](evidence/american-greeks/reference-provenance.json)
links original inputs, protocols, assembled references, raw output and exact
adapter/generator snapshots. Public reproduction needs the optional pinned
QuantLib build and mpmath environment; public builds/CI read committed evidence
and need no private research access.

## Runtime qualification

Measured runtime/test candidate: `09cde8d056ad8ee2dd5ef8ca70ef2158e68b7319`.
Runtime code is unchanged since `24680cc`; subsequent commits strengthen
boundary tests, collectors, provenance and routine bytecode test cost. The
[qualification manifest](evidence/american-greeks/qualification.json) links
all four runtime campaigns, independent and supplementary scores, complete
price replay, test logs and raw performance samples in the
[qualification archive](evidence/american-greeks/qualification-raw.tar.gz).

Each campaign contains all 230 requested quantities. “Declined” combines base
price failure, explicit unavailable and failed Greek refinement; it is never an
accuracy pass. “Unresolved reference” means the runtime returned an estimate
but the independent reference did not resolve at the requested target.

| Grid / target | Independent passes | Unresolved reference | Declined | Scored failures |
| --- | ---: | ---: | ---: | ---: |
| Initial / primary | 34 | 2 | 194 | 0 |
| Initial / loose | 44 | 2 | 184 | 0 |
| Refined / primary | 29 | 2 | 199 | 0 |
| Refined / loose | 80 | 73 | 77 | 0 |

Refined loose returns 153 estimates, 52 explicit unavailable outcomes and 25
Greek refinement refusals, with no base-price failures. By contrast, 150 primary
refined quantity rows fail at the base price. Finer settings do not guarantee
more availability: fixed work limits and independent acceptance remain active.
The supplementary QuantLib comparisons pass 11/32/6/110 rows in table order,
with 25/14/25/43 unresolved references and the same declined counts. They do not
replace the independent counts above. Numerical gamma, vega and theta references often
remain wide; these rows are retained individually, not advertised as validated
accuracy. This is a bounded capability over an explicit corpus, not universal
Greek coverage.

| Refined loose quantity | Independent passes | Unresolved reference | Declined |
| --- | ---: | ---: | ---: |
| Delta | 25 | 1 | 20 |
| Gamma | 8 | 24 | 14 |
| Vega | 12 | 19 | 15 |
| Rho | 28 | 6 | 12 |
| Theta | 7 | 23 | 16 |

The runtime uses the maximum stencil/arithmetic indicator over every observed
refinement level, a stricter screen than checking only the final stencil. For
example, refined loose constant-ATM delta is declined despite small final mesh
changes. No target was widened to change that outcome. Vega/rho additionally
compare one-sided slopes, so a stable central average at a stopping kink is not
published as a derivative. Underlying price indicators amplified into Greek
units remain visible and may exceed the derivative target; this API reports
empirical convergence, not certified cancellation of pricing error.

## Compatibility and local checks

All **572 complete existing price outcomes and independent scores** agree
exactly with baseline `a980d1b`: 412 constant American/Bermudan plus 160 piecewise,
covering both grids and target sets. Values, diagnostics, work, failures and
unresolved classifications are compared, not just accepted prices. Existing
European replay is unchanged.

Development and release ordinary suites, public package build, formatting and
negative type witnesses pass. Tests cover all five analytical reductions,
stochastic piecewise derivatives, exercise-interior values, expiry/zero-volatility
and cash/event exclusions, exact perturbation representability, stopping kinks,
request validation, ownership, cancellation, callback exceptions and resource
limits. Installed native/bytecode clients return identical ten Greek words
through the constant and piecewise public APIs. The staged bytecode loader needs
`CAML_LD_LIBRARY_PATH` set to the installed stubs directory.

Nine affected compiled fault mechanisms were killed with clean baselines and
successful mutant builds. The first campaign killed eight; the cash-kink mutant
survived because an earlier exclusion masked its guard. A reachable pre-cash
case was added and killed that mutant on rerun. Both logs remain. Initial Dune
lock and standalone bytecode loader failures are also retained as harness
failures, not numerical results. The full stochastic five-Greek bytecode test
passed before routine bytecode cost was reduced: routine bytecode keeps all
five analytical Greeks plus numerical delta/gamma/theta; native keeps the full
stochastic parallel comparison. The default five CI jobs and seven core mutants
are unchanged; the catalog now contains 126 mechanisms.

## Standalone pricing regression

The [cost protocol](evidence/american-greeks/cost-protocol.md) was fixed before
timing. Five alternating fresh-process pairs per workload use one warmup and
three measured calls, identical drivers and OCaml 5.3.0 Flambda release builds.
All owned tests, builds and reference runs completed before timing. Shared Apple
M1 Pro load was 8.29–10.77; these are local engineering observations, not an SLA.

| Price workload | Baseline median | Candidate median | Candidate allocation/request |
| --- | ---: | ---: | ---: |
| American, no cash | 130.2 ms | 130.5 ms | 12.91 MB |
| American, cash | 384.0 ms | 378.0 ms | 42.17 MB |
| Bermudan, no cash | 263.7 ms | 266.8 ms | 40.54 MB |
| Bermudan, cash | 389.3 ms | 391.5 ms | 64.00 MB |
| Piecewise, no cash | 677.1 ms | 681.3 ms | 127.03 MB |
| Piecewise, cash | 412.7 ms | 416.6 ms | 87.05 MB |

Every workload passes the frozen limits of at most 5% more cumulative allocation
and 10% more median latency. The added optional observer costs exactly eight
allocated bytes per standalone price in these workloads. Median timing changes
are between −1.6% and +1.2%, within shared-host variability. MB denotes decimal
cumulative allocation, not live workspace or process peak RSS.

## New Greek request cost

Five fresh-process rounds per model/request use one warmup and one measured
call, alternating request order. The same admitted ATM put and 128/128 grid are
used for price, spatial (delta/gamma/theta) and all-five requests. Whole-work
limits are scaled by the fixed partition count to preserve the underlying
solver allowance; no refinement target is widened. Measured work includes
encoding a complete outcome digest. Every process returns the same digest for
its workload, and the base price agrees across requested quantities.

| Model / request | Median latency (range) | Cumulative allocation | Estimated/requested Greeks |
| --- | ---: | ---: | ---: |
| Constant / price | 129.7 ms (129.0–133.4) | 12.91 MB | — |
| Constant / spatial | 131.4 ms (129.7–132.8) | 13.09 MB | 2/3 |
| Constant / all | 1.704 s (1.702–1.730) | 170.18 MB | 4/5 |
| Piecewise / price | 670.3 ms (668.5–678.0) | 127.03 MB | — |
| Piecewise / spatial | 678.3 ms (676.8–697.2) | 127.21 MB | 3/3 |
| Piecewise / all | 8.815 s (8.745–8.862) | 1,653.81 MB | 5/5 |
| Piecewise cash / price | 406.5 ms (405.9–413.6) | 87.05 MB | — |
| Piecewise cash / spatial | 407.3 ms (406.0–408.0) | 87.28 MB | 3/3 |
| Piecewise cash / all | 5.339 s (5.328–5.692) | 1,134.72 MB | 5/5 |

Constant delta fails the conservative stencil screen in both Greek requests;
it is retained as a refusal, not counted as a computed sensitivity. These
engineering targets are not recommended trading tolerances. Shared-host load
was 8.78–12.42; child peak RSS across all workloads was 7.63–8.68 MB. That small
RSS does not make the 1.13–1.65 GB cumulative allocation of the varying all-five
requests an acceptable optimized budget.

Spatial extraction adds about 0.18–0.23 MB and 0.7–8.0 ms here. Asking for both
vega and rho adds twelve complete price evaluations, roughly multiplying cost
by thirteen; no cross-perturbation preparation cache or differentiated solver
has been introduced. **#119 remains open** for a focused measured Greek
optimization: profile preparation versus solves, evaluate request-owned reuse
with full dependency keys, and assess differentiated/one-sided schemes only
with independent kink/event qualification. Preserve complete outcomes and
visible uncertainty. The broad batch/backend and deployment campaigns remain
separate; these measurements are neither a backend comparison nor an SLA.

## Reproduction

Use the pinned OCaml toolchain and commands in `AGENTS.md`. The archive contains
`capture.py`, `compare.py`, original build manifests, exact installed consumer,
test logs, all request files, raw stdout/stderr and score reports. Paths in the
historical manifests identify the measured worktrees and executables; rebuild
and capture new manifests for another checkout rather than reusing old hashes.

```sh
opam exec --switch=morphiq-risk-ml -- dune build --profile release @install @runtest @fmt bench/american_greeks.exe
python3 scripts/test_american_greeks.py
python3 scripts/test_benchmark_american_greeks.py
python3 scripts/check_american_greeks.py --executable _build/default/test/american_greeks.exe --mode loose --refined --output /tmp/greek-runtime
python3 scripts/benchmark_american_greeks.py --build /tmp/candidate-build.json --output /tmp/greek-cost
```

For independent regeneration, build the original adapters with the recorded
QuantLib revision and `-std=c++17 -O3 -ffp-contract=off`. Use
`generate_american_greeks.py` with its required QuantLib, derivative-quadrature,
price-quadrature and pinned mpmath interpreter paths; then assemble using
`collect_american_greeks.py`. The separate canonical family campaign uses
`generate_american_greeks_canonical.py` and
`collect_american_greeks_canonical.py`. Each supports `--help`. The reference
archive retains earlier adapter versions and their matching hashes, including
the corrected attempts. No private repository access is required.
