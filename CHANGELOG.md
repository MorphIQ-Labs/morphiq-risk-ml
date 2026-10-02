# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Numerical changes carry evidence per [docs/stability.md](docs/stability.md).

## [Unreleased]

### Added
- **Deterministic elementary functions** (`Internal.Elementary`: exp, expm1, log, log1p, cbrt) from IEEE basic operations and fma, each within 1 ULP. The library no longer calls the platform libm.
- **A cross-platform determinism digest** (`test/determinism.ml`, docs/determinism.md).
- The public surface is `Morphiq_risk` minus `Internal`. Numerical building blocks moved under `Morphiq_risk.Internal`, outside the stability policy.
- `Morphiq_risk.version`, a stability policy and this changelog.

- **This project's own oracles for every layer** (docs/oracles.md): elementary functions, the normal distribution, European and displaced prices, implied volatility with exact roots and rounding cells, and Greeks by two independent routes. They are committed as fixtures with a SHA-256 manifest (`scripts/manifest.py check`), so the tests no longer depend on FerroRisk's data. `scripts/ferro_crosscheck.sh` keeps FerroRisk as a second opinion.
- **Property-based tests** (`test/properties.ml`, QCheck, fixed seed): bounds, parity, monotonicity, Greek signs, exact homogeneity, translation invariance, IV accuracy and finite differences.
- **An error analysis** (docs/error-analysis.md).

### Changed
- **CI** (`.github/workflows/ci.yml`): the whole suite on Linux x86-64, Linux arm64 and macOS arm64 with locked dependencies and flambda required, the format check, and the mutation catalog.
- **The fixture manifest is checked in OCaml.** `oracle/MANIFEST` records BLAKE2b-256 hashes, and `test/manifest.ml` (part of `dune test`) verifies them with `Digest.BLAKE256`. This replaces `scripts/manifest.py check` and `oracle/MANIFEST.json`.
- **Budgets derived from the error analysis replace measured ones where the mutation catalog depends on them.**
  - **Zero-variance prices:** checked per row against the intrinsic's certified error (§5.1), replacing "4 ULP".
  - **Black-family implied volatility:** checked per root against a derived bound with the better-conditioned of β and β̄ and the intrinsic's error near the money (§6). This replaces "in the rounding cell, or 4× attainable", which accepted roots 8e14 ULP off near the maximum.
  - **log1p's reduced path:** checked against ulp/2 + 0.085·u·|y| using references that now carry their residual (§1).
- **log1p returns x for |x| < 2^-54** (fdlibm). The reduced path rounded log1p(2^-1074) to 0.
- **The mutation catalog** (`dune exec scripts/mutation/mutation.exe`, OCaml): 18 mechanisms, each removed and required to fail the test that guards it, in a temporary copy under a `mutation` dune profile. Two mechanisms are justified by the analysis but cannot be decided by a test; §5.1 records why.
- **Double-double primitives are the published algorithms with proved error bounds** (docs/error-analysis.md §0): Joldes, Muller and Popescu (ACM TOMS 2017) for `mul_float` (Algorithm 9, 2u²), `mul` (Algorithm 12, 5u²), `add_float` (Algorithm 4, 2u²) and `div` (Algorithm 18, 9.8u²), and Lefèvre et al. (ACM TOMS 2023) for `sqrt` (25/8 u²). They replace Algorithms 8 and 10, QD's unproved three-quotient division, and an unproved Newton square root. `add` already was Algorithm 6. `div` scales its divisor into [1, 2) to stay inside the theorem's domain. Worst-case ULP is unchanged in every oracle region; the determinism digest is re-recorded.
- **Double-double exp and expm1 follow QD's `dd_real::exp`** (Hida, Li and Bailey): reduction by 512 and nine doublings instead of a long series. Worst-case ULP is unchanged in every oracle region; `test/dd_reference.ml` pins exp, expm1 and log against mpmath. The determinism digest changes, because low-order bits of intermediates differ.

### Changed (numerical)
- Every libm call now goes through `Internal.Elementary`. Served values move by at most their previous rounding; every worst-case region ULP is unchanged or better (docs/results-*.md).
- **Zero-variance price:** the log-moneyness remainder is now double-double, which fixes a cancellation case: 8 → 1 ULP.
- **Black theta** is now double-double near the money: 17 → 4 ULP (Bachelier: 13 → 3).
- **Expiry theta** `θ(qS − rK)/365` is now formed from exact products: up to 413 → ≤ 7 ULP where S ≈ K.
- **Zero-variance intrinsic** is taken as A − C from the double-double legs when x's parts (|ln S/K| + |(r−q)T|) exceed 1. A forward placed at the strike through carry goes from 13 → 1 ULP.
- **Implied volatility:**
  - m and β come from the double-double legs;
  - a positive quote that underflows on rescaling is no longer inverted to σ = 0;
  - the log-space correction for β < 2^-900 is restored. Removing it was an error, because no oracle row exercised it.
- **Exact homogeneity.** The internal scale exponent uses floor division, so price(2^j S, 2^j K) = 2^j price(S, K) bit for bit.

### Changed (claims)
- **IV accuracy is now stated per contract.** It is held to 4× Jäckel's attainable accuracy, (1 + |b/(s·b′)|)·ε. The previous "≤ 2 ULP of the exact root" held on FerroRisk's grid but not in general; the worst found over random contracts is 4 ULP from a 2-ULP cell.

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
