# Results: implied volatility

Historical cross-check measured on 2026-10-02 with OCaml 5.3.0 + flambda (`-O3`). The historical tables record the acceptance rules used for those runs. Current exact-root tests require the correctly rounded reference root and execute analytical per-input price/vega certificates, retaining the historical conditional budgets as additional quality gates. The quote's price-rounding interval is diagnostic; the inverse's volatility-rounding cell is the runtime acceptance criterion. See [error-analysis.md §6](error-analysis.md#6-implied-volatility).

## Current exact-model acceptance

The current runtime acceptance path uses original-input arithmetic/model
enclosures and decides the exact inverse's binary64 rounding cell. All 5,575
positive roots in the current committed fixture match the correctly rounded
reference: BSM 1,754, Black-76 1,802, displaced 1,162 and Bachelier 857. Every
such row must succeed; numerical failure is not an accuracy pass. The generic
solver also exercises forced exhaustion, unresolved values, tie parity and the
full positive encoding. Existing historical quality and analytical transport
checks remain additional gates. See [the contract](certified-iv.md).

The comparison and mechanism counts below are retained historical evidence;
new runtime certification can make an old proposal mutation redundant. Current
curated mutation claims belong to the executable catalog and its latest run.

## Accuracy

Scored against the external `public_iv_reference.json` dataset identified by the [converter](../oracle/convert_public_iv.py): 3,522 European rows from mpmath 1.4.1 at two precisions. For each root the reference gives the rounding cell, i.e. every σ whose exact price rounds to the binary64 quote. Every row with an expectation passes.

| Reference class | Rows | Outcome required | Result |
| --- | ---: | --- | --- |
| root, Black family | 959 | in the cell, or ≤ 2 ULP from the exact root | all pass; worst 2 ULP; 855 inside the cell |
| root, Bachelier | 572 | in the cell, or ≤ 4 ULP | all pass; 434 inside the cell |
| zero_volatility_limit | 778 | `Root 0` | all pass |
| rounded_zero_volatility_bound | 267 | `Root 0` | all pass |
| no_finite_inverse | 6 | `Above_maximum` | all pass |
| expiry_not_identifiable | 378 | `Not_identifiable_at_expiry` | all pass |
| invalid_input | 60 | refusal naming the parameter | all pass. Black-76, displaced Black and Bachelier have no dividend input, so those 15 rows are unrepresentable rather than refused. |
| unresolved_* | 502 | none: the reference decides nothing | recorded |

## Method

| Step | Technique | Evidence |
| --- | --- | --- |
| Classification | The quote is compared, to about 106 bits, with the discounted intrinsic and the maximum. Both use the double-double `exp`/`expm1`, and the log-moneyness is double-double. A quote equal to the correctly rounded intrinsic is σ = 0. | Binary64 legs: 143 rows fail. No rounded-bound rule: 175 rows fail (Bachelier: 92). |
| Inversion | Jäckel's Let's Be Rational, ported from his 2024 reference: four-branch rational-cubic initial guess, then two Householder(3/4) steps. | A round-trip test holds it within 8× the attainable accuracy (1 + \|b/(s·b′)\|)·ε; measured worst 1.08×. |
| Near the maximum | `β̄ = (maximum − quote)/m` comes from the exact distance. It drives the highest branch, its initial guess and the at-the-money inverse, because β itself rounds up to b_max there. | `β̄ = b_max − β`: 67 rows fail. |
| Subnormal β | `ln β` is taken from the unscaled quote, since rescaling a subnormal quote drops bits. | 3 rows fail. |
| Final correction | One Newton step against the extended-precision kernel, on the complement `b̄` when β > b_max/2. | Without it the worst error is 4 ULP and fewer roots land in the cell; the 2-ULP budget fails. |
| Bachelier | A bracketed Newton on ln(OTM price), between `β√(2π)` and `(β+\|Δ\|)√(2π)`. | Rounded-bound mutant: 92 rows fail. |

One design note on dead weight: a second log-space correction for subnormal β was redundant with the `ln β` path. Each survived mutation alone, and removing both brings the failure back, so only the root fix was kept.

## Types

`Iv.t` is one closed variant: `Root`, `Below_intrinsic`, `Above_maximum`, `Not_identifiable_at_expiry` `Below_smallest_volatility`, `Non_convergence` or `Numerical_failure`. The scorer's exhaustive match over it compiles only because every class is handled.

The volatility is typed by coordinate. `Black.*.implied` returns `Vol.lognormal Iv.t` and `Bachelier.implied` returns `Vol.normal Iv.t`, so a Bachelier inverse cannot be fed back into a Black price.
