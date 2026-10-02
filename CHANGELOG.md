# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Numerical changes carry evidence per [docs/stability.md](docs/stability.md).

## [Unreleased]

### Added
- **Deterministic elementary functions** (`Internal.Elementary`: exp, expm1, log, log1p, cbrt) from IEEE basic operations and fma, each within 1 ULP. The library no longer calls the platform libm.
- **A cross-platform determinism digest** (`test/determinism.ml`, docs/determinism.md).
- The public surface is `Morphiq_risk` minus `Internal`. Numerical building blocks moved under `Morphiq_risk.Internal`, outside the stability policy.
- `Morphiq_risk.version`, a stability policy and this changelog.

### Changed (numerical)
- Every libm call now goes through `Internal.Elementary`. Served values move by at most their previous rounding; every worst-case region ULP is unchanged or better (docs/results-*.md).
- **Zero-variance price:** the log-moneyness remainder is now double-double, which fixes a cancellation case: 8 → 1 ULP.
- **Black theta** is now double-double near the money: 17 → 4 ULP (Bachelier: 13 → 3).

## [0.1.0] - 2026-10-02

The first slice: the exact European family.

### Added
- **Models:** BSM, Black-76, displaced Black (Black-76 on exact sums F + d, K + d) and Bachelier. Each has prices, implied volatility (the #448 outcome classes as `Iv.t`) and ten analytic Greeks with typed units.
- **Normal distribution:** Cody erfcx, `norm_cdf`/`pdf`/`log_cdf`, and AS241 `norm_inv`. A double-double normal distribution for cancelling Greeks.
- **Model contracts** (docs/model-contracts.md).
- **Oracles and evidence:** see docs/results-*.md.

### Numerical evidence (worst ULP per region, against the oracles in docs/results-slice.md)
- Prices: 1–16 ULP per region; Bachelier ≤ 3.
- Implied volatility: Black-family roots ≤ 2 ULP from the exact root; every outcome class matches.
- Greeks: ≤ 6 ULP for every Greek in both families.
