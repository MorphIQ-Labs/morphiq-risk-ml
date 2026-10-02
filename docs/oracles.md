# Oracles

Every accuracy claim in this project is measured against this project's own references. They are generated from the model definitions (docs/model-contracts.md) in mpmath, independently of the library's algorithms. The fixtures are committed, hashed and checked in CI, so the tests need no downloaded reference data. Test builds use Python 3's standard library to verify the analytical majorants; mpmath is needed only to regenerate fixtures.

The approach is modelled on FerroRisk's oracle practice: pinned generators, agreement between precisions, provenance hashes, and analytic bounds for values below binary64. FerroRisk's data serves only as an optional second opinion (`scripts/ferro_crosscheck.sh`). It is never ground truth.

## Fixtures

| Fixture | Generator | Content |
| --- | --- | --- |
| `elementary` | `gen_elementary.py` | exp, expm1, log, log1p over every binade, the reduction boundaries and a random sample (111k); each reference carries its residual, exact − reference, for fractional-ULP scoring |
| `normal` | `gen_normal.py` | Φ, φ, ln Φ, erfcx and Φ⁻¹ over every binade, Cody's interval cuts and the tails (82k) |
| `european` | `gen_european.py` | BSM, Black-76 and Bachelier prices (57k), in three families: a grid on the design of FerroRisk #440, carry-cancelled forwards (`cancel`), and a fixed-seed random sample |
| `displaced` | `gen_displaced.py` | displaced Black on exact sums (41,760); 63% have an unrepresentable F + d or K + d |
| `iv` | `gen_iv.py` | implied-volatility outcomes, exact roots and rounding cells for all four models, on a grid and a random sample |
| `dd` | `gen_dd.py` | 24,451 three-word/exponent references, including 13,041 nonzero low words, reduction boundaries and subnormals |
| `regressions` | `gen_regressions.py` | five exact near-maximum ATM roots and 2,000 near-unit log-coordinate references |
| `greeks` | `gen_greeks.py` | the ten Greeks for all four models, including the defined limits at expiry |

## Generation rules

1. **Exact inputs.** Every input is a binary64 value, taken as the exact real number it represents.
2. **Refinement to agreement.** A value is refined over doubling precision until two consecutive levels round to the same binary64 (`common.agreed`). Escalating rather than dropping keeps the hard cases in the oracle.
3. **Agreement is not enough on its own.** Two precisions can share an error. A difference below both can make both compute exactly 0, which this project's first price generator did at T = 1e-200. So:
   - formulas avoid analytic cancellation. The zero-variance price is `C·expm1(x)` with `x = ln(S/K) + (r − q)T` built from exact parts;
   - the starting precision exceeds each contract's cancellation depth (`Contract.digits`): the decades of |x|, plus those of σ√T near the money in σ units;
   - an agreed zero is accepted only once it survives to 480+ digits;
   - a value is an exact 0 without refinement only when an analytic upper bound puts it below 2^-1100 (`Contract.below_binary64`).
4. **Roots are solved, not guessed.** Implied-volatility roots use Illinois with guaranteed bisection, to 1e-(dps − 15). A solve that doesn't converge is reported as unresolved, never returned as a value. An earlier version returned its bracket midpoint, and both precisions agreed on the wrong root.
5. **Greeks have two routes.** Route 1 is the closed form; route 2 differentiates the mpmath price itself with `mpmath.diff`, including mixed and third-order partials. A value is resolved only when they agree to 1e-25.
6. **Fixed-seed random families** in every generator test away from the grid (`random.Random(2026100x)`).

## Provenance

- **Building fixtures.** `oracle/build.sh [name…]` regenerates fixtures. Each is compressed with `gzip -n -9`, so the bytes are reproducible.
- **The manifest.** `oracle/write_manifest.py` (run by `oracle/build.sh`) writes `oracle/MANIFEST`, one line per fixture:
  - its generator's BLAKE2b-256 and the shared `common.py`'s;
  - the mpmath and Python versions;
  - the row count and the fixture's own BLAKE2b-256.
- **The check.** `test/manifest.ml`, part of `dune test` and so of CI, recomputes the hashes with OCaml's `Digest.BLAKE256`. It fails if a fixture's bytes changed, if a generator or `common.py` changed without regeneration, or if a fixture is missing. It needs no Python.
- **Toolchain.** The generators need mpmath 1.3.0: `python3 -m venv oracle/.venv && oracle/.venv/bin/pip install mpmath==1.3.0`.

## What the oracles have caught

These were found by this project's own oracles and property tests, not FerroRisk's. The details are in docs/results-*.md and the error analysis.

- **The log-moneyness quotient remainder** was rounded. That cost about 1e-33 in x, and the error survives a cancellation to 1e-18.
- **The intrinsic's formulation** needed choosing by the size of x's parts. A carry-cancelled forward was 13 ULP off at zero variance.
- **The scale exponent** used truncating division, which broke exact homogeneity.
- **A subnormal quote** lost bits to rescaling before the inverse's final correction.
- **"Within 2 ULP of the exact root"** held on FerroRisk's grid but not in general. The scorer composes normalization and kernel errors and accounts for conditioning; Jäckel's attainable accuracy alone is not an implementation error guarantee.
- **In the generators themselves:** a false agreed zero at T = 1e-200, and an unconverged root returned as a value. Both are fixed by rules 3 and 4.

## Bound and scorer controls

`python3 oracle/verify_bounds.py` verifies rational majorants without numerical samples. Dune runs it to generate `Component_bounds`, so scorers and derivation constants cannot silently diverge. The DD fixture uses 110/220 digits plus cancellation-dependent extra precision, and scores at a separate reference exponent. Nonfinite results fail. The `dd-reference-nan` mutant explicitly verifies that failure.

The near-maximum regression fixture evaluates the ATM inverse through `erfinv`, independently of the library's iteration and the general oracle's root solver. Quotient-remainder mutation is checked at the coordinate level, where extra reference bits distinguish errors hidden by final price rounding.
