# Slice 1: findings

Status as of 2026-10-02. The exact European family (BSM, Black-76, displaced Black and Bachelier) has prices, implied volatility and ten analytic Greeks. All are scored against FerroRisk's independent references, and every row with an expectation passes.

## Exit criteria (SLICE.md)

### 1. Accuracy

| Layer | Oracle | Rows | Result | Detail |
| --- | --- | ---: | --- | --- |
| Normal primitives | mpmath, 80 digits | 82,000 | all within FerroRisk's SPEC budgets; tail tightened to 6 ULP | [results-numerics.md](results-numerics.md) |
| Prices | FerroRisk #440 | 50,094 | worst 3–16 ULP per region, against FerroRisk's 37–3,504 (4.3e15 at zero variance) | [results-pricing.md](results-pricing.md) |
| Implied volatility | FerroRisk public IV at the #448 tip | 3,522 | every class matches; Black roots ≤ 2 ULP from exact | [results-iv.md](results-iv.md) |
| Greeks | FerroRisk Greek reference | 61,621 | worst ≤ 17 ULP for every Greek (charm 4 after a double-double Φ) | [results-greeks.md](results-greeks.md) |

### 2. Iteration speed

Measured on an Apple M1 Pro with OCaml 5.3.0 + flambda `-O3`. The library is about 2,100 lines and the tests about 700.

| Step | Wall time |
| --- | --- |
| Clean build | 0.71–0.76 s |
| Incremental rebuild after editing `normal.ml` (at the root of the dependency graph) | 0.13 s |
| Incremental rebuild after editing `black.ml` | 0.22–0.24 s |
| Full test suite: every oracle, the property tests and the compile-failure tests | 0.31–0.41 s (0.40 s with the double-double charm) |
| One mutant: rebuild plus the full suite | 0.73 s |

Every mechanism claimed in the results docs has a mutant that fails rows when it is removed, and about 20 such mutants were run during development. Two lessons for mutation testing:

- **Equivalent mutants are common.** A last-digit change to a 17-digit literal often parses to the same double, and a mutant that only breaks compilation, such as an unused variable under warnings-as-errors, is not a kill.
- **Budgets must be tight enough to see each mechanism.** Several mechanisms passed FerroRisk-level budgets with or without them. Their budgets were tightened to the measured worst before their mutants failed.

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

- **Displaced Black shift.** #440 uses binary64-shifted coordinates; the IV and Greek references use exact sums (see results-greeks.md).
- **Oracle versions.** The IV reference at the `!551` head predates #448's rounded zero-volatility bound. Scoring needs the #448 stack tip.

## Not attempted in this slice

The following were out of scope (see SLICE.md):
- American models, Heston, Merton, local vol, surfaces, risk, SIMD and batch APIs.
- Performance against Rust, which was explicitly not measured.
