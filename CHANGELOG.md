# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Numerical changes carry evidence per [docs/stability.md](docs/stability.md).

## [Unreleased]

### Numerical assurance audit

- Fixed DD division on subnormal operands (`minsub/(3*minsub)`: 0.5 → correctly rounded 1/3), normalized DD square root, and preserved tiny expm1 arguments before division by 512.
- Fixed early underflow of tiny zero-variance intrinsics. For BSM S=K=2^1000, T=2^-1074, r=1, q=0, σ=0, the call changes from 0 to 2^-74. Tests cover both sides, three scales and three rates. A displaced F=2^-573, K=2^-574, d=2^500 contract also changes from 0 to its exact zero-volatility call value 2^-574. This is a served-value change beyond the published budget: a major numerical change, expressed as a minor release while version 0.y.z. No release/version bump is performed here.
- Replaced the DD 2^-100 measured envelopes with analytical majorants and exact-rational inequality checks. Added 24,451 generated DD cases with nonzero low words and 2,005 direct coordinate/near-maximum IV regressions, pinned in `oracle/MANIFEST`.
- Fixed fail-open NaN scoring, rho's binade-dependent error propagation and log-CDF's reference-rounding/minimum-denominator composition. Missing normal fixtures now fail.
- Removed the price scorer's 4-ULP bypass. Bachelier's norm includes its volatility time value. Its IV scorer now transports price error through vega instead of accepting rounding-cell membership.
- Corrected the log1p derivation to 0.14u|y|; the former 0.085 estimate omitted a denominator rounding and lacked margin.
- Included maximum-leg error divided by the complement gap in the IV budget, replaced the arbitrary threshold guard with normalization uncertainty, and removed the unsupported negligible-Newton-remainder claim. The kernel/Greek envelopes remain measured premises; `docs/error-analysis.md` lists the remaining proof obligations explicitly.
- Against the unchanged six public-model fixture files, all rows pass and the determinism digest is unchanged from 15b5f7a. New boundary cases expose changes beyond that historical corpus. Fixture generators and hashes are recorded in `oracle/MANIFEST`; this does not claim universal correctness over all admitted inputs.

### Added
- **Deterministic elementary functions** (`Internal.Elementary`: exp, expm1, log, log1p, cbrt) from IEEE basic operations and fma, each within 1 ULP. The library no longer calls the platform libm.
- **A cross-platform determinism digest** (`test/determinism.ml`, docs/determinism.md).
- The public surface is `Morphiq_risk` minus `Internal`. Numerical building blocks moved under `Morphiq_risk.Internal`, outside the stability policy.
- `Morphiq_risk.version`, a stability policy and this changelog.

- **This project's own oracles for every layer** (docs/oracles.md): elementary functions, the normal distribution, European and displaced prices, implied volatility with exact roots and rounding cells, and Greeks by two independent routes. They are committed as fixtures with a SHA-256 manifest (`scripts/manifest.py check`), so the tests no longer depend on FerroRisk's data. `scripts/ferro_crosscheck.sh` keeps FerroRisk as a second opinion.
- **Property-based tests** (`test/properties.ml`, QCheck, fixed seed): bounds, parity, monotonicity, Greek signs, exact homogeneity, translation invariance, IV accuracy and finite differences.
- **An error analysis** (docs/error-analysis.md).

### Fixed
- **Platform-dependent rounding.** OCaml's arm64 backend contracted `a +. b *. c` into fused multiply-adds (about 500 in the library), so Linux x86-64 served different bits; CI's new platform matrix found it. Every multiplication in `lib/` is now an explicitly rounded product (`Morphiq_fp`), and fused multiply-adds are explicit `Float.fma`: this project's Horner helper, and the exact remainders. docs/determinism.md, which claimed OCaml never contracts, is corrected. The determinism digest is re-recorded and must match on all three CI platforms.
- **Budgets composed from their inputs:**
  - `logcdf` (from the CDF's budget through 1/(1 − Q) or 1/Φ);
  - forward-model rho: RN(−T·V) bit for bit, within the price error transported through multiplication by T, plus output/reference rounding.

  Each replaced a fixed budget smaller than its input's own, which held only under contraction.

### Changed
- **CI** (`.github/workflows/ci.yml`): the whole suite on Linux x86-64, Linux arm64 and macOS arm64 with locked dependencies and flambda required, the format check, and the mutation catalog.
- **The fixture manifest is checked in OCaml.** `oracle/MANIFEST` records BLAKE2b-256 hashes, and `test/manifest.ml` (part of `dune test`) verifies them with `Digest.BLAKE256`. This replaces `scripts/manifest.py check` and `oracle/MANIFEST.json`.
- **Budgets derived from the error analysis replace measured ones where the mutation catalog depends on them.**
  - **Zero-variance prices:** checked per row against the intrinsic's analytical error budget (§5.1), replacing "4 ULP".
  - **Black-family implied volatility:** checked per root against a derived bound with the better-conditioned of β and β̄ and the intrinsic's error near the money (§6). This replaces "in the rounding cell, or 4× attainable", which accepted roots 8e14 ULP off near the maximum.
  - **log1p's reduced path:** checked against ulp/2 + 0.14·u·|y| using references that now carry their residual (§1).
- **log1p returns x for |x| < 2^-54** (fdlibm). The reduced path rounded log1p(2^-1074) to 0.
- **The mutation catalog** (`dune exec scripts/mutation/mutation.exe`, OCaml): 28 mechanisms, each removed and required to fail the test that guards it, in a temporary copy under a `mutation` dune profile. The quotient remainder now has a direct coordinate oracle. The intrinsic branch guard remains a provisional, explicitly runnable surviving probe (§5.1).
- **Double-double primitives are the published algorithms with proved error bounds** (docs/error-analysis.md §0): Joldes, Muller and Popescu (ACM TOMS 2017) for `mul_float` (Algorithm 9, 2u²), `mul` (Algorithm 12, 5u²), `add_float` (Algorithm 4, 2u²) and `div` (Algorithm 18, 9.8u²), and Lefèvre et al. (ACM TOMS 2023) for `sqrt` (25/8 u²). They replace Algorithms 8 and 10, QD's unproved three-quotient division, and an unproved Newton square root. `add` already was Algorithm 6. `div` now normalizes both operands; normalizing the divisor alone allowed intermediate underflow even for a normal quotient. Worst-case ULP is unchanged in every oracle region; the determinism digest is re-recorded.
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
- **IV accuracy is now stated per contract.** It composes normalization and kernel envelopes, including the maximum-gap error and minimum-vega error transport. The random property composes forward and inverse uncertainty; its former 4× rule is removed. The previous "≤ 2 ULP of the exact root" held on FerroRisk's grid but not in general; the worst found over random contracts is 4 ULP from a 2-ULP cell.

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
