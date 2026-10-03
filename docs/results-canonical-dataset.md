# Canonical generated portfolio results

The [720-row specification](canonical-dataset.md) and input dataset were
committed as `b3b3ccd542b48c916bcfdc2a9d9c702e0c4d74fb` before the first scored
run. The owner [authorized generated canonical datasets](acceptance/owner-review-2026-10-03.md).
This is a broader scalar qualification grid, not observed institutional holdings
or a calendar-roll scenario engine. The existing boundary/stress campaign is
retained separately; no old rows were removed.

## Numerical result and retained findings

- All **7,920** price/Greek requests were served and independently certified
  against Arb original-input prices and formal price derivatives.
- All **720** positive IV results had their exact original-model nearest-even
  rounding cells independently certified. The input quote is QuantLib's raw
  price, so recovery of the generator's volatility is not the inverse contract.
- All **nine** repetitions produced identical result words. No request,
  reference or admission failure occurred. The largest returned absolute
  certificate radius was `9.061632667078734e-11`, below the unchanged `1e-10`
  requested limit.
- All **264** model/scenario/quantity aggregates were complete. QuantLib
  supplied every constituent for 186 aggregates; 78 lacked a complete
  canonical counterpart (including the quantities its calculator omits).
- **523** raw canonical quotes differ in binary64 bits from the certified
  original-input price. Agreement with a canonical library is therefore not
  being treated as the definition of accuracy.

The initial comparison gate failed closed with five unexplained rho findings.
Its [raw report](evidence/canonical-shadow.json.gz), including that failure,
remains unchanged. The [separate adjudication](evidence/canonical-adjudication.json)
resolves those five by reproducing the actual canonical arithmetic and checking
the production certificates independently. Together these reports pass the
fixed generated-workload criteria; neither a threshold nor an output changed.

| Material findings | Count | Disposition |
| --- | ---: | --- |
| Volga | 570 | Existing canonical formula's missing maturity factor, checked against the independent mapped-model derivative. |
| Normal vanna | 94 | Existing canonical formula's missing discount factor, checked against the independent mapped-model derivative. |
| Rho, conversion dominates | 2 | Original-to-binary64 mapped input effect retained separately from comparator arithmetic. |
| Rho, additional arithmetic investigation | 5 | Source/binary operation replay and independent error decomposition below. |

These 671 findings remain in the raw records. All price comparisons remain
below the pre-existing one-cent weighted materiality trigger. Comparator
findings do not relax production acceptance and are not silent repairs to
QuantLib's returned values.

For BSM calls `canonical-0118`, `canonical-0148` and `canonical-0178`,
QuantLib's `BlackCalculator::rho` subtracts the option value from a term near
the discounted forward. The mathematically equivalent simple call rho is
`T K D N(d2)`, but the implemented expression loses accuracy through cancellation.
The [pinned source](https://github.com/lballabio/QuantLib/blob/6b57206e04598f092efee66e3b367efc84771995/ql/pricingengines/blackcalculator.cpp)
and [actual ARM64 wheel disassembly](evidence/quantlib-rho-arm64-disassembly.txt)
identify its operations, including fused multiply-add. An explicit FMA replay
reproduces all three captured values bit for bit. Exact rational arithmetic
separates operation rounding from the CDF/density/input effects; Arb encloses
the difference from the real mapped and original model. The largest observed
rho difference is about `1.02e-9`, exceeding the fixed diagnostic trigger.
This is a comparator accuracy limitation on these cases, not a formula change
or a general accuracy theorem for QuantLib.

For forward calls `canonical-0358` and `canonical-0538`, the comparator adapter
correctly uses `-T * canonical_price`. Exact rational replay isolates the final
binary64 multiplication from the canonical price error, amplified by maturity.
Both results replay exactly. The production rho certificates pass independently.
The adjudicator's negative control changes one comparator result by one ULP
and requires a completed replay rejection. The binary-specific replay refuses
a different QuantLib wheel, rather than assuming every build contracts alike.

## Operational result

On the recorded Apple M1 Pro / macOS ARM64 host with OCaml 5.3.0 Flambda,
each fresh process executed 2,160 rows (three complete repetitions). A row
includes admission, eleven separately certified outputs, IV and result encoding.

| Measure across three fresh processes | Result |
| --- | --- |
| Batch elapsed | 23.73–24.00 s |
| Row median | 10.46–10.60 ms |
| Row p95 | 18.90–19.10 ms |
| Row p99 | 20.11–20.33 ms |
| Largest observed row | 32.57 ms |
| Process startup to READY | 8.94–9.68 ms |
| Cumulative allocated words per process | 41,860,563,167 |
| Minor / major collections per process | 159,721 / 68 |
| Peak child RSS | 19,562,496 bytes |

Cumulative allocation is about 155 MB per row, not resident memory. Host load
was recorded and no other benchmark/test campaign ran concurrently; the shared
workstation was not an isolated production host. These results support offline
scalar evaluation with explicit failure handling. They do not establish a
latency SLA or million-instrument portfolio throughput. The separate earlier
GC trace remains profiling evidence for its own workload, not this campaign's
pause measurement. No runtime optimization or numerical code changed here.

## Artifacts and reproduction

[Input dataset](evidence/canonical-portfolio.json.gz): 720 rows, exact original
and mapped words, raw QuantLib quotes, certified original-input prices, design
coordinates, source hashes, versions and wheel identity. Canonical source is
QuantLib commit `6b57206e04598f092efee66e3b367efc84771995` (1.43).
The row-content SHA-256 is
`f87f22d47fb3af166b0a239c2828312baa528c3d28151de48ec609da077d377c`.
The [generator](../scripts/generate_canonical_dataset.py) imports no production
outputs. Ordinary CI checks the captured grid and rejects malformed, nonfinite,
duplicate, tampered or truncated rows using only Python's standard library.

Run the generation/campaign commands in the frozen specification. The initial
campaign returns exit 1 for the five findings; then reproduce their disposition:

```sh
/path/to/pinned-oracle-python scripts/adjudicate_canonical.py \
  --campaign docs/evidence/canonical-shadow.json.gz \
  --output /tmp/canonical-adjudication.json
```

The final adjudication requires all original numerical checks to pass and
every remaining material finding to follow the verified rho path. Any other
failure or unexplained quantity remains blocking. These optional campaigns
add no QuantLib/Arb dependency to ordinary CI and do not change mutation selection.
