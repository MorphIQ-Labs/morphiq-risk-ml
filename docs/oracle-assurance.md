# Oracle assurance and counterexample reduction (#55)

The scoring and input controls below qualify references before counting an
accuracy comparison. They do not widen a numerical allowance or change runtime
arithmetic, generators, committed fixture bytes, or replay identities.

## Finite ULP distance

`test/float_score.ml` owns the common test-only scorer. For a finite binary64
word, let its magnitude bits (sign removed) be the nonnegative integer `m`.
Its rank is `-m` for a negative value and `m` otherwise. The exact distance is
`abs(rank(a) - rank(b))`, evaluated in Zarith, an existing test-only dependency.
Both signed zeros have rank zero. The largest distance is
`18437736874454810622`, between opposite maximum finite values; it exceeds a
signed 64-bit integer. There is no numeric distance for NaN or infinity.

The old signed subtraction and absolute value returned `-9223372036854775808`
for `+2` versus `-2`. A nonnegative budget could accept that value. The exact
answer is `9223372036854775808`. `oracle_assurance` tests this witness, the
maximum distance, signed zeros, subnormal crossings, adjacent words around every
binade, budget validity, and fixed-seed metric properties. The optional
`ulp-distance-overflow` mutant reinstates the signed calculation and must be
rejected by that test after a clean baseline and successful compilation.

`within` compares the integer distance with the floor of a finite nonnegative
budget. `ulps` rounds diagnostics upward when the integer is not exactly
representable as a float; using it with an existing finite floating budget
cannot underestimate distance. The `2^53+1` control exercises that distinction.

Six legacy scorers (`oracle_normal`, `oracle_elementary`, `oracle_price`,
`oracle_greeks`, `oracle_iv`, `consistency`) and `finite_greeks` share the owner.
Normal endpoints retain exact-bit checks. Elementary nonfinite expectations use
explicit NaN or signed-infinity classification, rather than an adjacent-word
allowance. Such class checks are counted separately from finite ULP statistics.
IV consistency rejects nonfinite roots/prices before any alternative tolerance
can accept them; its finite-difference/relative-error alternatives also require
finite error bounds. Other derived-error checks retain `Bounds.within`'s finite
error/bound preconditions and their existing thresholds.

The same-pattern audit also examined `lib/certified_iv.ml`: its endpoint
subtraction operates on nonnegative finite volatility words, so the difference
fits signed `int64`; the opposite-sign witness does not establish a defect
there. Python's existing integer rank calculations do not have fixed-width
signed overflow. Runtime code is unchanged.

## Complete reference inputs and failure controls

`fixture_catalog.py` verifies archive bytes against `oracle/MANIFEST`, checks
nonzero declared row counts, and generates the uncompressed byte fingerprints
for test builds. Each of the 16 OCaml fixture consumers reads one immutable
snapshot, checks its fingerprint and shape, and only then scores rows. Original
repeated inputs remain legitimate: the exact snapshot fixes their multiplicity
and order. A missing, duplicated, reordered, corrupted, empty or truncated file
fails before evaluation. The multi-file production checker validates both
argument roles and complete snapshots before evaluating either one, so a
duplicate/swapped second dataset cannot hide behind an earlier result.
Five old streaming readers no longer catch parser
`End_of_file` as normal completion of a possibly truncated last row.

Input failures exit **3** with `REFERENCE INPUT ERROR`; the mutation harness
classifies that outcome as invalid, never as a numerical kill. Ordinary tests
exercise the real normal scorer with a valid baseline and damaged inputs, the
catalog itself, missing/crashed/timed-out/malformed reference workers, and the
minimizer's treatment of unresolved outcomes. Mutation guard controls explicitly
exercise exit 3. The optional Arb price/Greek/IV audits use the same verified
archive reader; the IV report separately counts excluded non-root rows.

The optional Ferro comparison passes an explicit `--external` argument. Its
inputs have shape checks and a reported fingerprint, but no claim of committed
corpus completeness or provenance. This mode is never used by ordinary mutation
guards. Fingerprints establish identity, not mathematical correctness; the
existing transitive generator provenance checks and independent references remain
necessary. No fixture or generator was repaired as part of this work.

## Independent reduction witness

`scripts/oracle_challenge.py` challenges the known incomplete reference
`common.agreed(Contract.price)` **without** the existing rational rounding repair.
This deliberately reproduces a historical precision-agreement weakness; it is
not evidence of a new error in the repaired generator or runtime.

The smooth BSM call has zero rate/carry and positive maturity/volatility. Its
original monetary scale is 128 and maturity is 4. The bounded reduction reduces
maturity to 1, replaces volatility with a simpler dyadic value, and removes the
common monetary scale. The final exact binary64 words are:

| Input | Word | Value |
| --- | --- | --- |
| spot | `3ff0000000000001` | `1 + 2^-52` |
| strike | `3ca0000000000000` | `2^-53` |
| maturity | `3ff0000000000000` | `1` |
| rate, carry, shift | `0000000000000000` | `0` |
| volatility | `3f10000000000000` | `2^-14` |

The intrinsic value is exactly `1 + 2^-53`, a rounding midpoint. Strictly
positive time value puts the real price above it. The incomplete reference
agrees on `3ff0000000000000`; the correctly rounded price is
`3ff0000000000001`. An exact rational open bracket from
[`price_rounding.py`](../oracle/price_rounding.py) and an independent Arb
one-sided tail argument both resolve the discrepancy. The JSON retains exact
rational endpoints, original/minimized words, observed/expected words, Arb
precision and method, every reduction attempt, versions, and source/tool hashes.

Only a financially valid proposal with both the independent wrong-reference
and correct-reference predicates resolved is accepted. The seven-proposal
normalization pass records two invalid proposals, one non-failing proposal and
one unresolved proposal, along with three accepted reductions. The final input
is independently rechecked. This is a finite normalization procedure, not a
claim of a globally smallest counterexample. An uncertain reference is not a
successful accuracy comparison and cannot justify a reduction.

Arb escalation is bounded to 256, 512, 1024, 2048 and 4096 bits. The existing
`common.agreed` routine allows at most six working precisions; agreement is the
challenged observation, not the proof. Each reduction worker has a 60-second
limit (nine evaluations at most). Tool failures make the campaign incomplete.
Controls retain exact midpoints, ties-to-even, half-minimum-subnormal conversion,
a deliberately wide unresolved interval, adjacent corrupted references, and
tiny one-sided time values for all four models. The actual mpmath-to-binary64
conversion is also checked against Arb on both sides of the normal and
half-subnormal midpoints, with an explicit cancellation control. Arb's interval semantics are
documented by [python-flint](https://python-flint.readthedocs.io/en/stable/arb.html)
and [FLINT](https://flintlib.org/doc/arb.html); the financial tail derivation is
in [midpoint rounding](oracle-midpoint-rounding.md).

## Reproduction and retained evidence

From the repository root, using OCaml 5.3.0 Flambda and ocamlformat 0.27.0:

```sh
opam exec --switch=morphiq-risk-ml -- dune build @install @fmt @runtest -j 2
opam exec --switch=morphiq-risk-ml -- dune exec test/oracle_assurance.exe
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- ulp-distance-overflow
python3 -m venv /tmp/oracle-assurance-env
/tmp/oracle-assurance-env/bin/pip install python-flint==0.9.0 mpmath==1.3.0
/tmp/oracle-assurance-env/bin/python scripts/oracle_challenge.py --output /tmp/oracle-challenge.json
```

The challenge exits zero when it successfully reproduces, independently resolves
and reduces the deliberately faulty reference. `complete: false`, a reference
tool failure, or a failed control is not a successful campaign. To reproduce the
minimized failure alone:

```sh
/tmp/oracle-assurance-env/bin/python scripts/oracle_challenge.py --worker \
  3ff0000000000001 3ca0000000000000 3ff0000000000000 \
  0000000000000000 0000000000000000 3f10000000000000 0000000000000000
```

Expect `status: failure`, with both independent cell decisions in the output.
The result is retained in [oracle-challenge.json](evidence/oracle-assurance/oracle-challenge.json).
The [validation record](evidence/oracle-assurance/validation.json) binds source
and artifact hashes and distinguishes the initial affected campaign from the
final source-bound scorer/input-role rechecks. Build, format and the ordinary
suite passed; all 15 selected mutants were killed. The changed final guards
also passed fresh copied baselines and rejected their designated mutants.

The independent audits retained here certified [99,088 prices and 59,200 smooth
Greeks](evidence/oracle-assurance/arb-references.json), with 7,200 boundary Greek
rows explicitly excluded, [5,579 IV roots](evidence/oracle-assurance/arb-iv.json),
with 2,751 non-root rows excluded, and [2,506 extra-precision Greek
references](evidence/oracle-assurance/arb-greeks.json). None had wrong or
unresolved references in its stated scope. These are local macOS arm64 results.
Optional Arb and mutation campaigns
remain manual; default PR CI retains ordinary correctness checks and the same
seven core mutants. The full catalog gains one mechanism (66 total).

This evidence covers the exercised witnesses and committed corpora. It does not
certify all admitted numerical inputs, supply independent human review, or
constitute a release/tag or institutional deployment approval. The historical
[0.3.0 candidate record](candidate-0.3.0.md) remains bound to its original source;
this report is a subsequent assurance delta.
