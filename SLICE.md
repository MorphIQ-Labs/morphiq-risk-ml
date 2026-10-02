# Slice 1: the exact European family

This experiment rebuilds one slice of FerroRisk in OCaml. It works from the
literature and first principles and is scored against FerroRisk's
*independent* references. It is not a line-by-line port of the Rust engine.

## In scope

| Layer | Content | Literature |
| --- | --- | --- |
| Numerics | `norm_pdf`, `norm_cdf`, `log_norm_cdf`, `erfcx`, `norm_inv` | Cody (1969, 1990) `calerf`; Wichura AS241 |
| Models | European price for BSM, Black-76, displaced Black and Bachelier, calls and puts, including expiry (T = 0) and zero-volatility limits | Black–Scholes (1973), Merton (1973), Black (1976), Bachelier (1900) |
| Implied volatility | Normalised Black function, "Let's Be Rational" plus a bracketed fallback, the Bachelier inverse, and the #448 identifiability outcomes (unique root, rounding-resolved set, below intrinsic, above maximum, effectively zero, unresolved) | Jäckel (2015, 2017) |
| Greeks | Analytic delta, gamma, theta, vega, rho, vanna, volga, charm, veta and color, with their units, for all four models | closed-form derivatives |
| Contracts | Domain admission, typed refusals, and validity outcomes for every served quantity | FerroRisk SPEC §7.0 format |

## Out of scope

The following are excluded from this slice:

- American models: BS2002, BS1993, the deterministic stopping solver
- Heston, Merton, local vol, PDE and Monte Carlo pricing
- surfaces, risk, streaming
- SIMD, batch/parallel APIs, serialization
- finite-difference Greeks and stencil provenance, which no model in this slice needs

## Design goals the type system should carry

These are the reasons to use OCaml. Each one is a hypothesis the slice either
demonstrates or refutes.

1. **Admission is a type, not a convention.** Each model exposes an abstract
   `Admitted.t` whose only constructor is the domain check. A kernel can't
   receive un-admitted inputs, and no second owner can re-derive admission.
2. **The volatility coordinate is in the type.** Lognormal and normal
   (Bachelier) volatilities are distinct types, so they can't be mixed up.
3. **Units are in the type.** Theta per calendar day and per year are distinct,
   and so are vega per unit volatility and per vol point.
4. **Outcomes are exhaustive variants.** The IV outcome classes of FerroRisk
   #448 are one closed variant, and callers must handle every class.
5. **One kernel per family.** BSM, Black-76 and displaced Black are one
   functor-parameterised lognormal kernel over the carry and shift choices.

## Contracts

[docs/model-contracts.md](docs/model-contracts.md) defines what each model computes. Every input is exact, and price, implied volatility and Greeks describe one function. Accuracy is measured against those definitions.

## Oracle

Scoring uses this project's own oracles (docs/oracles.md). FerroRisk's
references remain an optional cross-check. Historically they were the first
oracle, and they are independent of the Rust implementation. `oracle/fetch.sh` reads them from
pinned FerroRisk commits into `oracle/data/`, which is git-ignored. Most
fixtures are pinned to the `!551` head. The IV reference and FerroRisk's
observed IV envelope are pinned to the #448 stack tip (`c1d2b66f`), because
only that commit has #448's rounded zero-volatility bound. Both pins move to
their squash-merge commits as the MRs land.

| Fixture | Use |
| --- | --- |
| `normal_premium_reference.json` | Normal CDF and premium tails |
| `public_iv_reference.json`, `public_iv_observed_envelope.json` | IV outcome classes and rounding cells for all four models, with FerroRisk's own per-row σ errors |
| `440-*.jsonl.gz` (#440 study) | 50,094 exact-input European prices with regions. Its displaced rows price on binary64-shifted coordinates, so they are scored as `black76_shifted` (Black-76 on fl(F + d), fl(K + d)). |
| `oracle/gen_displaced.py` (this project's own) | 41,760 displaced Black prices on the exact sums, at mpmath 60/120 digits. 26,400 of them have F + d or K + d unrepresentable. |
| `iv_inverse_reference.json` | Normalised-inverse rounding cells |
| `bachelier_quantlib_reference.json` | Bachelier price and IV |
| `greek_derivative_reference.json`, `black_greek_boundary_reference.json` | Analytic Greeks |

## Exit criteria

1. **Accuracy.** Every oracle row for the slice is either reproduced within the
   FerroRisk SPEC budget for that quantity, or listed with a reviewed
   explanation.
2. **Iteration speed.** Reported as measured: wall time for a clean build, an
   incremental rebuild after editing `normal.ml`, and one mutant. There is no
   Rust baseline. The numbers are recorded as absolute values.
3. **Types.** Each of design goals 1–5 is either shown in the code or written
   up as not working.
