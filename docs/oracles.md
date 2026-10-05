# Oracles

This project's own references check accuracy independently of its analytical error bounds. They are generated from the model definitions (docs/model-contracts.md) in mpmath, independently of the library's algorithms. The fixtures are committed, hashed and checked in CI, so the tests need no downloaded reference data. Test builds use Python 3's standard library to verify the analytical majorants; mpmath is needed only to regenerate fixtures.

The oracle workflow uses pinned generators, agreement between precisions, provenance hashes, and analytic bounds for values below binary64. External comparison data provides supplementary evidence, not ground truth.

See [oracle assurance](oracle-assurance.md) for the exact finite ULP scorer,
complete-input gates, failure controls and bounded independent counterexample
reduction. Precision agreement alone never establishes a reference proof.

## Fixtures

| Fixture | Generator | Content |
| --- | --- | --- |
| `elementary` | `gen_elementary.py` | exp, expm1, log, log1p over every binade, the reduction boundaries and a random sample (111k); each reference carries its residual, exact − reference, for fractional-ULP scoring |
| `normal` | `gen_normal.py` | Φ, φ, ln Φ, erf, erfc, erfcx and Φ⁻¹ over every binade, old/new interval neighbors, underflow and overflow (130,394; all original 82,000 rows retained) |
| `european` | `gen_european.py` | BSM, Black-76 and Bachelier prices (57k), in three families: a grid over scale, moneyness, maturity and volatility, carry-cancelled forwards (`cancel`), and a fixed-seed random sample |
| `displaced` | `gen_displaced.py` | displaced Black on exact sums (41,768); 63% have an unrepresentable F + d or K + d |
| `iv` | `gen_iv.py` | implied-volatility outcomes, exact roots and rounding cells for all four models, on a grid and a random sample |
| `dd` | `gen_dd.py` | 86,145 three-word/exponent references, including 47,719 nonzero low words, every exponential reduction boundary and subnormals |
| `regressions` | `gen_regressions.py` | five exact near-maximum ATM roots, 2,000 near-unit log-coordinate references and two rescued-tail regressions |
| `greek_bits` | `gen_greek_bits.py` | 2,506 three-word/exponent Greek references, including 51 contracts at or adjacent to zeros of cancelling Greeks |
| `model_enclosures` | `gen_model_enclosures.py` | 1,670 three-word/exponent original-input model prices, including sparse shifts, tiny carry/variance and tails; 110/220 or 400/800 digits |
| `finite_greeks` | `gen_finite_greeks.py` | 880 exact-input Greek value/refusal challenges at 1280/2560 digits, 80 price-differentiation cross-checks and an analytical tail-gamma witness |
| `boundary_greeks` | `gen_boundary_greeks.py` | 532 positive-maturity zero-volatility ATM veta references from nested price differentiation at 400/800 digits, cross-checked with the analytical derivative |
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

### Intrinsic midpoint rounding

The price generators and IV quote construction first apply the exact rational
[positive-time-value rounding rule](oracle-midpoint-rounding.md) where its
premises resolve a cell. It prevents two finite mpmath precisions from agreeing
on an intrinsic midpoint after both lose a positive tail. Remaining rows use
their existing refinement, with independent Arb audit evidence over the committed
corpus; precision agreement alone is not promoted to a universal proof.
Unresolved European/displaced/IV rows now fail regeneration instead of being
dropped. The generators' transitive helper provenance is in `MANIFEST`.

The expanded normal fixture agrees at 80/160 decimal digits, escalating to
320/640 when needed. Large positive erfcx references use mpmath's independent
Tricomi-U formulation instead of an unjustified fixed 30-term asymptotic sum.
All 82,000 original records remain unchanged. Direct erf/erfc gates are 4 ULP;
existing gates are unchanged. The scalar scorer checks finite/infinite and
endpoint classes explicitly, so adjacent finite/infinite words cannot pass an
ULP-only comparison. `MORPHIQ_ORACLE_TRACE` emits fixture-aligned result words;
`scripts/compare_exponential_traces.py --normal` and
`scripts/audit_error_function_changes.py` retain and refine changed rows.

## Provenance

- **Building fixtures.** `oracle/build.sh [name…]` regenerates fixtures. Each is compressed with `gzip -n -9`, so the bytes are reproducible.
- **The manifest.** `oracle/write_manifest.py` (run by `oracle/build.sh`) writes `oracle/MANIFEST`, one line per fixture:
  - its generator's BLAKE2b-256, the shared `common.py`'s, and transitive local generator imports;
  - the mpmath and Python versions;
  - the row count and the fixture's own BLAKE2b-256.
- **The check.** `test/manifest.ml`, part of `dune test` and so of CI, recomputes the hashes with OCaml's `Digest.BLAKE256`. It fails if a fixture's bytes changed, if a generator or `common.py` changed without regeneration, or if a fixture is missing. A Python standard-library check also verifies the dependency graph, row counts and complete record set. Partial rebuilds preserve unselected provenance and fail if an unselected fixture is stale; calling the writer without names only validates.
- **Toolchain.** The generators need mpmath 1.3.0: `python3 -m venv oracle/.venv && oracle/.venv/bin/pip install mpmath==1.3.0`.

## What the oracles have caught

These were found by this project's own oracles and property tests. The details are in docs/results-*.md and the error analysis.

- **The log-moneyness quotient remainder** was rounded. That cost about 1e-33 in x, and the error survives a cancellation to 1e-18.
- **The intrinsic's formulation** needed choosing by the size of x's parts. A carry-cancelled forward was 13 ULP off at zero variance.
- **The scale exponent** used truncating division, which broke exact homogeneity.
- **A subnormal quote** lost bits to rescaling before the inverse's final correction.
- **"Within 2 ULP of the exact root"** held on the historical reference grid but not in general. The scorer now executes price/vega certificates and retains historical conditioned quality gates; Jäckel's attainable accuracy alone is not an implementation error guarantee.
- **In the generators themselves:** a false agreed zero at T = 1e-200, and an unconverged root returned as a value. Both are fixed by rules 3 and 4.

## Bound and scorer controls

`python3 oracle/verify_bounds.py` verifies rational majorants without numerical samples. Dune runs it to generate `Component_bounds`, so scorers and derivation constants cannot silently diverge. The DD fixture uses 110/220 digits plus cancellation-dependent extra precision, and scores at a separate reference exponent. Nonfinite results fail. The `dd-reference-nan` mutant explicitly verifies that failure.

The near-maximum regression fixture evaluates the ATM inverse through `erfinv`, independently of the library's iteration and the general oracle's root solver. Quotient-remainder mutation is checked at the coordinate level, where extra reference bits distinguish errors hidden by final price rounding.

The twelve committed fixtures include extra-bit component, Greek and model-price references. The Greek-bit generator uses 110/220-digit closed forms and checks the zero-neighborhood cases against independent differentiation. Large erfcx and Y′ references use Tricomi U identities to avoid cancellation, with additional precision to resolve sparse low words. These checks establish agreement of independent calculations, not interval proofs of the oracle itself.

`erf_coefficients.py` generates Gaussian-integral coefficients with rational rounding witnesses; `erf_certificates.py` bounds their remainder and evaluation error. `kernel_certificates.py` includes those checks and separately encloses the rounded Jäckel coefficients’ differential residuals using exact Bernstein bounds. `lift_polynomials.py` checks the Black expansion coefficients against integral/moment identities and lifts their actual operation grouping into the test algebra. `Certified` propagates these component bounds through every committed price and finite Greek; no measured ULP envelope is a premise of those certificates. See [the derivations](error-analysis.md#8-rounded-kernels-and-complete-pricegreek-expressions).

The curated mutation mechanisms run with replay bit-identity assertions disabled, so numerical error must trigger the designated guard. Ordinary CI runs seven core mechanisms; the full catalog runs manually or weekly under the [mutation execution policy](mutation-policy.md). The separate `--probe intrinsic-terms` run still survives and exits 1; it is deliberately excluded provisionally, not classified as equivalent. Ordinary accuracy tests retain replay identity to detect drift between the arithmetic model and implementation.


The PR #12 audit adds exact rational primitive postconditions to a generated replay of the production DD source, including its elementary and normal-series callers. Allowances are fixed before execution. Nonoverlap checks apply to inputs and component results. They exposed both a binade-boundary defect in low-word sampling and missing normalization after subnormal scaling and split square root; see the [audit record](error-analysis.md#pr-12-source-and-assumption-audit). Zarith 1.14 is needed only for tests.

## American reference campaign

The [initial American references](american-references.md) follow the separately
frozen #108/#109 model and assurance contracts. They combine a pinned QuantLib
finite-difference comparator, an original stock lattice, high-precision discrete
replay and analytical Arb intervals. Empirical and analytical references retain
distinct labels; unresolved cases and comparator exclusions cannot pass scoring.
Default CI checks the committed manifest and failure controls offline. Optional
reference generation neither changes the European fixture guarantees above nor
adds an American runtime pricing capability.

## Canonical generated qualification dataset

The optional [canonical portfolio generator](../scripts/generate_canonical_dataset.py)
uses pinned QuantLib 1.43 formula quotes and independently certified Arb prices
from the original binary64 inputs. Its [frozen specification](canonical-dataset.md),
[results](results-canonical-dataset.md) and committed exact-word dataset retain
source/wheel hashes, mapped inputs, all discrepancies and explicit adjudications.
It supplements the reference fixtures above; it does not replace them or make
canonical binary64 outputs the definition of accuracy. Generation and interval
campaigns remain outside ordinary CI.

### Served-value compatibility traces

Set `MORPHIQ_ORACLE_TRACE` to a distinct output path when running `oracle_price`,
`oracle_greeks`, `greek_reference` or `dd_reference` directly. Each trace retains
the fixture row and computed bit pattern (both words for DD), including Greek
failure classifications. The ordinary tests perform no trace I/O. Compare
baseline and candidate with identical fixtures and trace instrumentation; the
[DD replacement report](results-dd-exponential.md) records such a campaign.

## Systematic boundary campaign

The [versioned protocol](numerical-campaign-protocol.md) and
[results](numerical-campaign-results.md) add deterministic original-word boundary
challenges with rational/Arb references, uncertainty and availability accounting.
The committed smoke gate requires no optional Python packages. Strict manual
scoring retains two fast-API quality findings (#76 and #77); ordinary CI checks
contracts explicitly without treating those findings as correct expected values.
