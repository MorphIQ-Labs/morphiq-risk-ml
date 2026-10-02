# Results: numerics layer

Measured on 2026-10-02 with OCaml 5.3.0 + flambda (`-O3`), Apple silicon.

## Accuracy

Scored against `oracle/gen_normal.py`: mpmath 1.3.0 at 80 digits, correctly rounded to binary64. Every row is within budget.

| Quantity | Rows | Worst | Budget | FerroRisk measured worst |
| --- | --- | --- | --- | --- |
| `norm_cdf`, body | 13,270 | 4 ULP | 6 ULP | 1 ULP |
| `norm_cdf`, x ≤ −8 | 5,829 | 4 ULP (4.9e-16 rel) | 6 ULP (FerroRisk: 6e-14 rel) | — |
| `erfcx` | 15,398 | 4 ULP | 4 ULP | 1 ULP |
| `log_norm_cdf` | 19,099 | 4 ULP | 4 ULP | 1 ULP |
| `norm_pdf` | 19,099 | 3 ULP | 4 ULP | 2 ULP |
| `norm_inv`, central | 5,163 | 4 ULP | 4 ULP | 4 ULP |
| `norm_inv`, tails | 4,142 | 4 ULP | 8 ULP | 6 ULP |

Every row where the truth rounds to an endpoint (0 or 1 for the CDF, −0.0 for `log_norm_cdf`) returns that endpoint exactly.

These choices were derived rather than ported:

- **Exact square split.** The tail factor exp(−x²/2) splits x² exactly with an FMA. Without the split, the tail error measures 5.7e-14, which is FerroRisk's 6e-14 budget. With it the tail holds the body's budget, so the tail budget is now 6 ULP. A mutant that removes the split fails 1,379 tail rows.
- **No CALERF `XMAX` flush.** Cody's 1990 `XMAX` cutoff sends `erfcx` to zero while the true value is still a representable subnormal. Past it, `sqrt(1/pi)/y` is a single correctly rounded division.
- **Subnormal range.** Results that fall into the subnormals are formed as `exp(−h/2)²`, so they round once.

Open item: `erfcx` and `log_norm_cdf` sit at their 4-ULP budget, and the body CDF sits at 4 of its 6 ULP. FerroRisk measures 1 ULP for all three. Closing the gap probably needs a compensated reflection in `erfcx` (`2·exp(x²) − erfcx(−x)`) and in `log1p(−Q)`.

## Iteration speed

| Step | Wall time |
| --- | --- |
| Clean build, library and tests | 0.46–0.48 s |
| Incremental rebuild after editing `normal.ml` | 0.12 s |
| One mutant: rebuild plus the full oracle (82k rows) and property suite | 0.44–0.45 s |

Some mutants are equivalent and need to be excluded. A last-digit change to a 17-significant-digit literal can parse to the same binary64. `2.98635138197400131e02` and `…132e02` are the same double, so that mutant survives without telling you anything.
