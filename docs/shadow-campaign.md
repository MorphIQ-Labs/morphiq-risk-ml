# Controlled scalar shadow campaign

This is the engineering campaign for #8/#16 under Epic #27, not an owner-approved
representative institutional book. Its specification is fixed before its first
scored run. The workload is synthetic, contains no customer information, and
exercises scalar calls on one domain. It does not implement Epic #23's planner.

## Inputs and diagnostic criteria

Use BSM, Black-76, displaced Black and Bachelier, both sides, maturities
1/12, 1 and 5 years, three moneyness levels and three explicit spot/forward,
volatility and remaining-maturity parameter scenarios. Remaining maturity is
an independent input sweep, not a valuation-date roll, settlement or economic
P&L simulation. Deterministic integer quantities include positive and negative
positions. All synthetic price units are labeled USD; each model has its own
synthetic risk factor. Boundary/stress cases are identified separately and
include expiry, zero variance, exact displaced sums lost by binary64 addition,
invalid admission, extreme carry and the intrinsic midpoint oracle regression.

Every price and smooth Greek request specifies an absolute limit of 1e-10 in
that quantity's declared units. This is a diagnostic request, not a production
default or an approved materiality policy. Every successful output must meet
its own returned bound against independent Arb price/series derivatives. Every
positive IV must have its exact original-model rounding cell certified by Arb;
there is no looser IV acceptance tolerance. Mathematical classes and computational
failures are retained. No unresolved audit counts as a pass. The expected
interior engineering criterion is zero failed or unresolved requests. Stress
availability is reported separately; no stress failure-rate allowance is inferred.

Flag price discrepancies above USD 0.01 per weighted trade or aggregate. Also
flag comparator differences above 1e-10 per raw Greek unit for independent
adjudication. These thresholds select diagnostic findings; they do not replace
runtime error certificates or constitute owner-approved economic acceptance.
Inspect gross per-trade differences and signed totals, so netting cannot conceal
errors. Aggregation uses exact rational weighted sums and adds each absolute
certificate radius plus the outward rounding of the aggregate center. Group
Greeks by scenario, model, synthetic factor, coordinate and quantity. An incomplete
group has no usable complete total. IVs are not additive.

## Comparator and independence

Pin QuantLib 1.43, python-flint 0.9.0 / FLINT 3.6.0. QuantLib is an optional
comparison dependency only. Read its tagged [Black formula source](https://github.com/lballabio/QuantLib/blob/v1.43/ql/pricingengines/blackformula.cpp),
[Black calculator](https://github.com/lballabio/QuantLib/blob/v1.43/ql/pricingengines/blackcalculator.cpp)
and [Bachelier calculator](https://github.com/lballabio/QuantLib/blob/v1.43/ql/pricingengines/bacheliercalculator.cpp).
The formula price and calculator Greek paths are distinguished in raw records.
QuantLib agreement is not the definition of correctness.

Map BSM to binary64 F=S exp((r-q)T), D=exp(-rT), and total standard deviation
sigma sqrt(T). Forward models keep F fixed; displaced coordinates are summed in
binary64 for QuantLib. Independently evaluate both the original exact-input
model and that mapped real model in Arb. Split each discrepancy into input
conversion and comparator arithmetic/formula effects. For mapped BSM Greeks,
use effective r=-ln(D)/T, q=r-ln(F/S)/T and sigma=stddev/sqrt(T); forward models
use effective r and sigma with fixed mapped coordinates. This makes the varied
coordinate explicit. Forward rho is adapted as -T times the formula price;
QuantLib's calculator rho includes forward dependence and is not that quantity.
Theta is per day; charm, veta and color have no calculator counterpart and
are compared only with independent formal price differentiation.

Do not silently repair canonical outputs. In particular, inspect the tagged
volga implementation's volatility coordinate and the normal vanna discount
factor when adjudicating discrepancies. Preserve raw values and give any
conversion or defect its own explicit disposition. IV comparators have their
own convergence contracts (Black accuracy 1e-12 total standard deviation,
1000 iterations; Bachelier's published approximation); record them without
claiming correctly rounded roots or classification equivalence.

## Operational measurement

The native worker retains all outcomes. Capture process-to-ready startup,
end-to-end subprocess time, per-row monotonic latency, batch elapsed/CPU time,
allocated words from `Gc.counters` and GC collection counts. A separate
10,001-call clock probe reports clock/loop overhead without subtraction. Rows include admission, 11 separate
certified evaluations and IV, plus typed result extraction and word encoding;
they are not kernel timings. Parsing and final I/O are included only in the
subprocess measurement. Repeat the captured workload within each of three
fresh processes; the first batch is cold and following batches are warm.
Compare numerical result words across every repetition. Record peak child RSS,
host/compiler/build/source hashes, load and raw timings. GC counts do not
measure GC pause time; no unmeasured GC-time claim or service-level guarantee
is made. Clock/allocation instrumentation is explicitly part of this diagnostic.
No concurrent benchmark or full mutation campaign runs during these measurements.

Actual production portfolio coverage, economic thresholds, permitted failures,
latency/throughput requirements and deployment recommendation remain designated
owner decisions. This campaign supplies reproducible evidence for that decision.
