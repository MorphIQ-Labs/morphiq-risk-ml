# Scalar shadow results

The [pre-run specification](shadow-campaign.md) and [compressed raw report](evidence/shadow-campaign.json.gz)
retain the 258 captured rows, all outcomes, canonical comparisons, independent
intervals, signed and gross aggregates, timings and source hashes. Reproduce:

```sh
opam exec --switch=morphiq-risk-ml -- dune build bench/shadow.exe
# An isolated optional environment, not the production package:
python -m pip install python-flint==0.9.0 QuantLib==1.43
python scripts/shadow_campaign.py --output /tmp/shadow-campaign.json.gz
```

## Numerical outcome

All 216 interior rows serve 11 certified quantities and a certified positive
IV. Independent Arb evaluations validate all 2,492 served price/Greek bounds:
242 prices and 2,250 smooth Greeks, including the separately labeled stress and
boundary rows. The IV audit certifies 223 positive root cells, ten zero roots,
eight expiry classifications and one price-at-maximum classification. Eight
extreme-carry rows return numerical failures, and eight invalid-maturity rows
are refused. Unsupported boundary Greeks are retained. No failed audit or
unresolved independent comparison is counted as a pass.

All nine process/workload repetitions produce identical outcome words. The
independent checker rejects a deliberately corrupted served price; the exact
aggregation control refuses to expose an incomplete group as a usable total.
These are finite-corpus engineering results, not general availability claims.

## Comparator findings

Every material discrepancy is independently decomposed into original-to-mapped
input conversion and mapped-model comparator error. The report retains all
219 affected quantity rows; none is hidden by netting.

| Finding | Rows | Independent disposition |
| --- | ---: | --- |
| QuantLib Black/Bachelier calculator volga | 182 | Tagged source computes vega times d1*d2/stddev (or d²/stddev). Annual-volatility volga requires division by sigma, hence a missing sqrt(T). Formal price differentiation validates the production output; the report also evaluates the actual source expression and retains its small residual. |
| QuantLib Bachelier calculator vanna | 36 | Tagged source returns -d*phi(d)*sqrt(T)/stddev without D. The discounted-price derivative contains D. Formal differentiation validates the production value and independently checks the undiscounted source expression. |
| Displaced intrinsic after binary64 shift conversion | 1 | F=2, K=1, displacement=2^64, zero volatility: exact original intrinsic is 1; both rounded shifted coordinates equal 2^64, giving QuantLib 0. The synthetic -10,000 position creates a USD -10,000 signed difference and USD 10,000 gross difference. |

The corresponding sources are linked in the specification. Comparator formula
attribution uses the source identity and an independently evaluated residual
below the predeclared 1e-10 diagnostic threshold; it is not a universal rounding
bound for QuantLib. Raw comparator outputs are not patched. A volga adapter
would need explicit volatility-coordinate conversion; a discounted normal
vanna adapter would need its discount factor. Neither belongs in this library's
pricing formulas. No external upstream issue or reviewer engagement is claimed.

QuantLib prices use its formula functions, Greeks its calculators. Forward rho
is explicitly adapted to fixed forward, and theta is per calendar day. Missing
calculator counterparts (charm, veta, color) retain independent Arb comparisons.
IV records include both engines' outcomes and original/mapped price residuals;
QuantLib's approximate inverse is not scored as a correctly rounded solver.

## Operational outcome

On an Apple M1 Pro, macOS 27, OCaml 5.3.0 Flambda -O3, the three fresh processes
each execute three repetitions (774 row evaluations). Batch elapsed time is
6.072–6.097 seconds; process-to-ready startup is 5.8–6.3 ms. Per-row p50 is
9.49–9.53 ms, p95 11.19–11.60 ms and p99 24.91–25.32 ms. A row includes admission,
11 separate production certificates, IV, extraction and encoding. It is not a
single price/Greek kernel call. The first and subsequent batch timings and every
raw row latency are retained; no cold/warm sample is silently removed.

Allocated words are 10,833,181,838 per process workload: about 112 MB cumulative
allocation per row on this 64-bit host, despite only about 12.3 MB peak child
RSS. Collection counts, CPU time and load (roughly 1.8–2.7) are retained. The
separate clock/loop probe costs about 24–25 ns per call and is not subtracted.
GC pause time is not isolated. This shared workstation run is neither a quiet
host service-level test nor a memory-residency estimate from allocation counts.

The cost is material. Separate full-precision certificates recompute substantial
model work; this scalar integration is not evidence of a million-instrument
scenario throughput target. The earlier [profile and kernel benchmarks](performance.md)
identify expansion arithmetic and allocation as priorities. Shared preparation,
rigorously bounded adaptive certificates and a batch interface are engineering
options, each requiring its own contract and evidence. No measured acceptance
limit is relaxed to make the workload faster.

The diagnostic engineering criteria pass. Deployment acceptance remains pending
actual business workload coverage, economic thresholds, operational requirements,
independent human review and designated owner approval under #13/#15/#16/#17.
