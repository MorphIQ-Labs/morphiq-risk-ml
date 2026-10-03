# Canonical generated portfolio, specification 1

The owner authorized generated datasets from canonical references on
2026-10-03. This specification is fixed before the first scored campaign.
The dataset qualifies a reproducible scalar model workload; it is not a sample
of an institution's positions, market history, or trading activity.

## Coverage and construction

The complete primary grid has 720 rows: four models (BSM, Black-76, displaced
Black and Bachelier), six maturities (1/365, 1/12, 0.5, 1, 5, 10 years), five
standardized forward moneyness levels (-4, -1, 0, 1, 4), three total deviation
levels (0.1, 0.5, 1), and both calls and puts. Both sides share the same model
inputs. These are remaining-maturity sweeps, not calendar rolls or P&L scenarios.

For each model, number the 90 maturity/moneyness/deviation combinations j in
the order above. Cycle price scales (0.01, 100, 10000) by j modulo 3, rates
(-0.05, 0, 0.025, 0.1) by floor(j/3) modulo 4, and BSM yields
(-0.02, 0, 0.03) by floor(j/12) modulo 3. These nuisance coordinates are
sampled deterministically, not fully crossed; scale and deviation are coupled.
The manifest and per-row design coordinates preserve that limitation.

For lognormal models, K*=scale, F*=K* exp(m total), sigma=total/sqrt(T).
BSM uses S=F* exp(-(r-q)T); Black-76 uses F=F*; displaced Black uses
shift=1.25 scale, F=F*-shift, K=K*-shift. For Bachelier,
K cycles (-scale, 0, scale) by floor(j/3) modulo 3, total_normal=scale total,
F=K+m total_normal and sigma_normal=total_normal/sqrt(T).
These input-construction operations round to binary64. The resulting original
input words, not the design coordinates, define the exact model under test.

Use QuantLib 1.43's `blackFormula` or `bachelierBlackFormula` to generate
the quote from the mapped binary64 forward, strike, discount and standard
deviation. Retain those mapped words and the raw quote. Independently generate
an original-input correctly rounded price using python-flint 0.9.0 / FLINT
3.6.0 Arb with precision refinement and a rounding-cell check. Keep both
prices even when they disagree. IV is the inverse of the supplied canonical
quote, not an assertion that inversion must recover the design volatility.

No row is removed because a comparison or certification fails. Nonfinite or
unresolved generated references abort generation rather than producing a
partial dataset. The existing 258-row shadow corpus supplies the separate
expiry, zero-variance, invalid-input, extreme-carry and midpoint regressions.

## Fixed acceptance and operational scope

Preserve the shadow campaign's pre-existing absolute request limit of 1e-10
in each quantity's units, USD 0.01 weighted-price discrepancy trigger and
1e-10 raw-Greek discrepancy trigger. Do not widen these after observing results.
Every primary row must serve all eleven requested price/Greek certificates and
a positive IV; Arb must independently certify every served bound and positive
IV rounding cell. Every unexplained material discrepancy blocks qualification.
Canonical defects and input conversion must have explicit retained dispositions.

Quantities cycle (-10000, 25000, -50000, 100000) by row index. The worst allowed
per-trade numerical error is 100000 times 1e-10 = USD 0.00001 for price,
below the diagnostic one-cent trigger. Aggregate errors use exact rational
weighted sums of actual certificate radii plus outward center rounding;
neither netting nor missing results may hide an error. Diagnostic triggers
are not a blanket business materiality approval for arbitrary portfolios.

Run three repetitions in each of three fresh native processes, checking all
numerical outputs for exact replay. Retain all row latencies, startup, elapsed
and CPU time, cumulative allocation, collection counts and host/compiler
metadata. No heavy tests run concurrently with timing. This qualifies offline
scalar calculations with explicit failure handling; no latency SLA or
million-instrument planner throughput is inferred from it.

## Reproduction

```sh
opam exec --switch=morphiq-risk-ml -- dune build bench/shadow.exe
/path/to/pinned-oracle-python scripts/generate_canonical_dataset.py \
  --output docs/evidence/canonical-portfolio.json.gz
/path/to/pinned-oracle-python scripts/shadow_campaign.py \
  --input docs/evidence/canonical-portfolio.json.gz \
  --output docs/evidence/canonical-shadow.json.gz
```

Generation is optional, separate from ordinary CI and all mutation selection.
The committed dataset supports replay without regenerating canonical quotes.
Source hashes and environment versions distinguish captured evidence from
regeneration on a different libm, platform or binary distribution.
