# Focused American inverse optimization (#119)

Safeguarded interpolation reduces full candidate-price evaluations while retaining
the [estimated inverse contract](american-implied-volatility.md). On the unchanged
cost corpus, analytical call / American put / cash terminal call use **6 / 6 / 4**
prices, down from nine each. Price kernels and shared arithmetic are unchanged.
No operator, factorization or candidate value surface is reused across sigmas.

## Scope and derivation

The [frozen protocol](evidence/american-iv-optimization/protocol.md) fixes the
quotes, sigma range [0.05, 0.6], full width 0.005, 64-call allowance, 128/128
resolution, three domain expansions and original whole-request work budgets.
Both PDE inverse workloads must improve median allocation and latency by at
least 25%; analytical inverses and standalone prices allow at most 5% allocation
and 10% latency regression. These are engineering adoption criteria, not an SLA.

Baseline Memprof sampling attributes 50.3% of put allocation to stencil preparation
and 36.0% to constant-slab work. Cash interpolation accounts for 54.8% of the cash
call's samples, with stencil preparation 19.7% and slab work 13.8%. CPU sampling
also identifies the slab solver as the put's dominant leaf. These sampled shares
are diagnostic, not exact budgets. The operators depend on candidate sigma;
cash interpolation operates on a candidate-specific value vector. Reducing full
price calls avoids this work without caching invalid results.

The [proposal derivation](evidence/american-iv-optimization/proposal-design.md)
was written before runtime edits. Scaled point-price interpolation chooses only
a probe location. Endpoint spacing avoids oversolving one endpoint; every third
main proposal is a midpoint. Invalid or unrepresentable proposals use the existing
midpoint. At the first overlapping probe, at most two nearby prices may improve
the bracket; quarter probes remain the fallback. Every sign still uses the full
price uncertainty band, and acceptance still uses outward full-width arithmetic.
All attempted prices consume the original evaluation and partitioned work budgets.
No residual-only acceptance, assumed vega bound or certification claim is added.

## Matched measurements

Baseline `ba429ce2cdfe5545479d5fe75b55ed9822f06d1f` is PR #141's integration merge;
its tree equals the original PR head `8b3a25f9fdabfbc29da6861f4d9f6599ac365878`.
Candidate `738e23f78443fa58ab8670daf6de629567019be9` contains the runtime and
controls measured here. The final evidence/documentation commit does not change
that runtime. Both clean worktrees build the unchanged benchmark in release mode,
OCaml 5.3.0 Flambda, library/benchmark `-O3`, on Apple M1 Pro.
[Source mapping](evidence/american-iv-optimization/raw/source-map.json) also records
the earlier profile-only source and rejected first candidate.

Five alternating fresh-process pairs; one warmup per path and three timed blocks
per process. Each analytical block has 20 sequential calls; PDE blocks have one.
Medians below use the 15 block averages per path/build. Full raw ranges, exact
source/tree/binary/driver identities, compiler and OS are in
[timing.json](evidence/american-iv-optimization/raw/timing.json). All task-owned
builds, tests and profilers finished before timing. Shared-host one-minute load
was 3.24–7.02; these are warm local measurements, not isolated-host,
cold-start, tail-latency or deployment acceptance evidence.

| Path | Median milliseconds/request, before → after | Cumulative MB/request, before → after |
| --- | ---: | ---: |
| `american-put/end-to-end` | 1139.6560 → 756.1580 | 121.295904 → 80.923200 |
| `american-put/price` | 124.1940 → 123.9700 | 13.475224 → 13.475224 |
| `american-put/solve` | 1136.5000 → 756.3740 | 121.295432 → 80.922728 |
| `call-100-0.05-american/end-to-end` | 0.8352 → 0.5567 | 1.065158 → 0.710182 |
| `call-100-0.05-american/price` | 0.0900 → 0.0895 | 0.116662 → 0.116662 |
| `call-100-0.05-american/solve` | 0.8358 → 0.5600 | 1.064686 → 0.709710 |
| `cash-terminal-american/end-to-end` | 1693.8720 → 753.2660 | 320.392192 → 142.453272 |
| `cash-terminal-american/price` | 188.9670 → 189.8090 | 35.601424 → 35.601424 |
| `cash-terminal-american/solve` | 1699.9880 → 754.7810 | 320.391264 → 142.452344 |

All frozen adoption criteria pass, including end-to-end inverse paths and all
standalone-price controls. Allocation is cumulative OCaml allocation (decimal
MB), not live workspace. Whole-process peak RSS is 13.27–13.60 MB
before and 13.19–13.91 MB after, collected from each
child's own `wait4` reap. Each process sequentially exercises all three cases;
these RSS values cannot be assigned to one request or summed as simultaneous
memory. OCaml exit GC totals include warmups, validation and timed blocks:
median minor collections 2650 → 1469, major
collections 787 → 440 per process. The eight-MiB
configured pricing workspace is a separate limit from allocation and process RSS.

## Numerical compatibility and qualification

Estimated endpoint locations, evaluation counts and availability under a small
call budget intentionally change. Neither old endpoint bits nor a unique root
are promised by this update. All 30 cases retain their original outcomes:
24 accepted / six explicit price-accuracy refusals at the initial domain,
30 accepted at the refined domain, and 30 accepted at full width 0.005.
All six failure payloads are identical. Every accepted interval contains the
**complete fixed independent reference interval**, meets its original full-width
target and has strict opposing price-indicator bands.

The [per-case compatibility table](evidence/american-iv-optimization/raw/compatibility.csv)
retains old/new endpoints, call counts and exact rational distances from both
independent reference endpoints for all three configurations. These are bracket
gaps, not point-estimate errors. A narrower bracket can have a larger gap on one
side; no claim that each individual endpoint is closer is made. References are
the unchanged 256/512-bit Arb exact-quote corpus and the retained independent
stopping/lattice/QuantLib comparisons described in the
[inverse methodology](american-implied-volatility.md#independent-qualification).
PDE indicators and empirical reference intervals remain non-certifying.

Qualification on the measured runtime:

- Full ordinary development and release suites, package build and format pass;
  existing price/Greek/European determinism checks remain unchanged.
- Installed public native and bytecode consumers match complete 30-row tight
  outcomes; the negative-yield supplement matches all four exercise-contract checks.
- Quote/range/cap, exercise/event identity, plateau/uncertainty, callback exception,
  cancellation and workspace/evaluation-budget controls pass. Added low-vega,
  endpoint-progress and perturbed-quote witnesses check bounded progress, exact
  rational full-width and full-band signs. They are progress controls, separate
  from independent reference accuracy.
- All 12 affected compiled `american-iv-*` mutants are killed after a clean baseline,
  including removal of periodic midpoints and endpoint spacing. The optional
  catalog has 150 entries; default CI remains five jobs and seven core mutants.
- Nine collector controls exercise malformed/truncated/nonfinite/duplicate output,
  startup/process/timeout failures, per-child resource reaping, invalid reference/
  width/work observations and impossible performance criteria.

The first interpolation candidate passed reference containment but used 22/6/14
prices on the tight cost cases. It was rejected on work-count preflight before
controlled timing, not reported as a measured speedup. Its patch and complete
corpus logs are retained. The first development run caught the stale mutation
catalog-count assertion (148 versus 150); the corrected selection check and
subsequent release suite pass. This harness failure is retained separately from
numerical evidence.

## Remaining work and reproduction

Adopt this focused search improvement. The remaining scalar inverse allocation
and PDE time are substantial; a smaller RSS is not an accepted allocation budget.
Broad #119 remains open for compiled workloads (#118), worker/cancellation latency,
tridiagonal/backend comparison and justified alternative-engine evaluation.
Piecewise and cash-put inversion remain unsupported. Final cross-platform source
artifact qualification and any deployment acceptance remain #120 and their owner
criteria; local results do not complete them.

[Evidence](evidence/american-iv-optimization/) includes protocol, derivation,
SHA-256 manifest, all raw profiles/paired samples, failed attempts and qualification
logs. Scripts under `raw/` preserve executed paths; copy them to a scratch folder
and update checkout/output paths for reproduction. Decompress `.gz` raw logs there
before rerunning compatibility/profile summaries. `profile.ml.txt` is the exact
scratch driver; copy it as `profile.ml` to compile against the recorded baseline.
Use `opam exec --switch=morphiq-risk-ml -- dune build --profile release
bench/american_iv.exe` in each recorded clean checkout before `measure.py`.
The collector retains `OCAMLRUNPARAM=v=0x400` in both builds, verifies reference
containment and per-build CHECK identity outside timing, and checks clean source
and binary identity before/after every process. Profiling is a separate campaign;
its times do not enter the performance comparison.
