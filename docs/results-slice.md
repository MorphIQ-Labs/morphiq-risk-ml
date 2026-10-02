# Slice 1: findings

Status as of 2026-10-02. The exact European family (BSM, Black-76, displaced Black and Bachelier) has prices, implied volatility and ten analytic Greeks. All are scored against FerroRisk's independent references, and every row with an expectation passes.

## Exit criteria (SLICE.md)

### 1. Accuracy

Measured against this project's own oracles (docs/oracles.md): mpmath, refined to agreement between precisions, committed and hash-checked. FerroRisk's references are an optional cross-check (`scripts/ferro_crosscheck.sh`), and every row of them also passes.

| Layer | Oracle | Rows | Worst error |
| --- | --- | ---: | --- |
| Elementary functions | `elementary` | 111,470 | ≤ 1 ULP (exp, expm1, log, log1p) |
| Normal distribution | `normal` | 82,000 | ≤ 4 ULP, tails included |
| Prices: BSM, Black-76, Bachelier | `european` (grid, carry-cancelled forwards, random) | 57,296 | 1–22 ULP per region; zero variance 1; Bachelier ≤ 5 |
| Prices: displaced Black | `displaced` (exact sums) | 41,760 | 1–15 ULP per region |
| Implied volatility | `iv` (exact roots and rounding cells) | 8,254 | every outcome class matches; Black-family roots within their derived bound (Bachelier: rounding cell or 4 ULP) (Black-family worst 4–7 ULP from the exact root) |
| Greeks | `greeks` (closed form vs mpmath differentiation) | 66,400 | ≤ 7 ULP for every Greek; underflow and kink classes exact |
| Properties | `test/properties.ml` (random, fixed seed) | 22,000 | bounds, parity, monotonicity, Greek signs, exact homogeneity, translation, IV within 2.10× attainable, finite differences |
| Cross-quantity consistency | `test/consistency.ml` | 128 | displaced = Black-76 bit for bit; IV inverts the served price; Greeks match finite differences |

### 2. Iteration speed

Measured on an Apple M1 Pro with OCaml 5.3.0 + flambda `-O3`. The library is about 2,100 lines and the tests about 700.

| Step | Wall time |
| --- | --- |
| Clean build | 0.71–0.76 s |
| Incremental rebuild after editing `normal.ml` (at the root of the dependency graph) | 0.13 s |
| Incremental rebuild after editing `black.ml` | 0.22–0.24 s |
| Full test suite: every oracle, the consistency, property and compile-failure tests | 0.54–0.55 s, with the 41,760-row displaced oracle and double-double intrinsics |
| One mutant: rebuild plus the full suite | 0.73 s |

The mutation catalog (`dune exec scripts/mutation/mutation.exe`) removes each claimed mechanism and requires the test that guards it to fail. All 18 are killed. Three lessons for mutation testing:

- **Equivalent mutants are common.** A last-digit change to a 17-digit literal often parses to the same double, and a mutant that only breaks compilation, such as an unused variable under warnings-as-errors, is not a kill.
- **Budgets come from the error analysis, not from the mutants.** Tightening a measured budget until a mutant dies proves nothing. The scorers check derived bounds (docs/error-analysis.md §1, §5.1, §6), and a survivor means either the bound or the mechanism is wrong.
- **Some mechanisms cannot be decided.** A mechanism that lowers a certified bound by less than the certified slack elsewhere cannot be made to fail a bound. Two such are justified in the analysis and left out of the catalog.

### 3. Types

| Hypothesis | Status | Evidence |
| --- | --- | --- |
| Admission is a type | Shown | Each model application has its own abstract `admitted`. A forged one is rejected, and so is a BSM contract given to Black-76. |
| Volatility coordinate in the type | Shown | `Vol.lognormal Vol.t` and `Vol.normal Vol.t` do not unify, and the same holds for IV outcomes and per-volatility Greeks. |
| Units in the type | Shown | A daily theta is not an annual rate. A Black vega and a Bachelier vega do not net. |
| Exhaustive outcome variants | Shown | `Iv.t` covers FerroRisk's #448 classes. `Greeks.value` puts a payoff kink in the one Greek it affects. |
| One kernel per family | Shown | BSM, Black-76 and displaced Black are `Black.Make` over three ~10-line carries. |
| Exercise style unrepresentable | Shown | A European slice has no exercise-style input. |

All six compile-failure tests pin the compiler's diagnostic, so a change in why something is rejected is visible.

## Where FerroRisk's references disagree with each other

- **Displaced Black shift.** #440 uses binary64-shifted coordinates; the IV and Greek references use exact sums. This project defines displaced Black on the exact sums, owns an oracle for that definition, and labels #440's displaced rows `black76_shifted` (docs/model-contracts.md). It's being taken up in FerroRisk separately.
- **Oracle versions.** The IV reference at the `!551` head predates #448's rounded zero-volatility bound. Scoring needs the #448 stack tip.

## Not attempted in this slice

The following were out of scope (see SLICE.md):
- American models, Heston, Merton, local vol, surfaces, risk, SIMD and batch APIs.
- Performance against Rust, which was explicitly not measured.
