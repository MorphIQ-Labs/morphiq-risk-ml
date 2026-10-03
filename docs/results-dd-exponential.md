# DD exponential replacement qualification

**Historical initial candidate:** this report records the degree-24 version
at `a186cb251aceee06c536d47fe67b406ee1eba218`. The subsequent
[focused optimization report](results-dd-exponential-optimization.md) owns the
current degree-22 implementation, compatibility results and updated timings.
The original evidence below is retained unchanged.

Date: 2026-10-03. Partial implementation of [#64](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/64).
Baseline: `3260a56217a2270005f12717bc9a15e4a016d48f`, the provenance-audit
head subsequently squash-merged as `e9591b29bb5d75e5bd90c110308a2c6557bbff39`.

## Construction and provenance

`Dd.exp` and `Dd.expm1` now use a directly evaluated degree-24 Taylor polynomial
on |r| < .347. Coefficients come from exact rational factorials, split into
nearest-even binary64 words by `oracle/dd_exp_coefficients.py`. The ln(2)
split is independently regenerated from rational enclosures of 2 atanh(1/3);
its bits match the existing constant. No approximation table is imported.
The former QD division by 512, adaptive stopping, DD-generated factorials and
nine doubling steps are removed. Generic integer-ln(2) range reduction and
power-of-two reconstruction follow the mathematical exponential identity.

This is independently derived replacement work after examining the old source,
**not a clean-room claim**. Historical QD evidence and original notices remain.
The paper-derived DD primitives, logarithm and square root are unchanged.
A current-tree search of production, tests, generators and experiment sources
found no remaining copy of the former QD exponential routine. AS241 and CALERF
are unchanged and still block completion of #64.

## Bounds, domains and checks

The [derivation](error-analysis.md#12-double-word-exp-and-expm1) is checked with
exact rational arithmetic before oracle scoring. Reduced expm1's derived
majorant is 19.499846499u², below the existing 80u² ceiling; exp retains
(40+3|x|)u². All downstream budgets are unchanged. The stored coefficients and
ln(2) are checked against their mathematical definitions during ordinary builds.

The tiny-input branch belongs to the shared reduced helper. Omitting it first
exposed an overlapping subnormal product residual in the exact primitive replay
when exp called Horner with a tiny input. Returning r for |r.hi| < 2^-104 has
relative Taylor error below 2u² and avoids that path for both entry points.
The existing exact-rational replay and independent reference fixtures exercise
this condition; the primitive witnesses and their allowances were not weakened.

The domain remains normalized finite input pairs with finite computed results;
final component scaling carries an absolute subnormal-quantum allowance.
For the unchanged outer cutoff x.hi < −745.2, normalized low words cannot move
x above −1075 ln(2), so exp(x) rounds to zero. Similarly x.hi > 709.8 is above
the binary64 overflow threshold. Interior values use integer range reduction
and component scaling. This work does not add a universal correctly-rounded
exponential, an arbitrary-low-word contract, or new NaN/infinity semantics.
The finite fixture sweep stops on the finite side of the upper range boundary;
it does not exhaust every two-word input adjacent to the overflow rounding cell.

The DD fixture grows from 48,203 to **86,145** rows, including **47,719** nonzero
low words. It preserves the old random stream and adds both binary64 neighbors
and both low-word signs at every reduction switch, the direct/tiny expm1
switches, and finite exponent-limit cuts. Every reference expansion agrees at
110/220 digits plus cancellation-dependent precision. Manifest provenance:

- Generator BLAKE2b-256: `478a55cf9807a0589f0ff1453c12b048a80beff5bce989dd54456c75989b4b59`.
- Fixture BLAKE2b-256: `5a5b3d4d95e0779f70bb2fa61c27d91c6a062470387082c9f8f04b178744c8df`.
- mpmath 1.3.0; Python 3.14.8. Other fixture generators and bytes are unchanged.

Both implementations pass the expanded DD corpus. Worst fractions of the
unchanged DD bounds are exp 0.718825 → 0.718825 and expm1
0.283898 → 0.282185. The maximum exp ratio includes component underflow;
it is not a pure relative-error estimate. `dune build @install @fmt @runtest` passes locally. An isolated package install
retains byte-identical current notices, original QD license files, the provenance
report and this qualification report. The [scorer and mutation logs](evidence/dd-exponential-validation.txt)
retain the numerical checks. The ordinary suite includes pricing,
IV, Greek, runtime-enclosure, exact primitive/replay, property, type, manifest
and determinism checks. Existing unresolved diagnostic enclosure cases remain
explicit and are not counted as successful certifications.

## Served-value compatibility

Identical trace instrumentation ran against both implementations with identical
fixtures. The [summary](evidence/dd-exponential-compatibility.json) records trace
hashes, all regions and counts; the [compressed per-row changes](evidence/dd-exponential-compatibility-changes.json.gz)
retain exact inputs, references and both output words/bits.

| Corpus | Rows | Changed outputs | Largest scalar movement |
| --- | ---: | ---: | ---: |
| dd | 86,145 | 37,250 | two-word changes |
| displaced | 41,768 | 0 | 0 ULP |
| european | 57,320 | 26 | 3 ULP |
| greek_bits | 2,506 | 1 | 1 ULP |
| greeks | 66,400 | 0 | 0 ULP |

There are no observed scalar sign, class or refusal changes. The 26 changed
prices are in Black deep-ITM, extreme-scale, tiny-variance and zero-variance
regions; the one changed extra-bit Greek is BSM theta near a zero. All 27 were
re-evaluated at 220/440 digits plus input-dependent extra precision, confirming
the original fixture references. Theta additionally agrees with differentiation
of the high-precision price. [Signed fractional-ULP discrepancies for every
changed served row](evidence/dd-exponential-refined-changes.json) retain this
check and the source hashes needed to reproduce it.

Tiny changes to DD low words become visible after discounted-leg cancellation
in zero-variance prices and near-zero theta. This is not uniformly improved
rounding: the zero-variance worst error increases from 1 to 3 ULP, within its
existing 4-ULP budget and analytical certificate (maximum excess over final
rounding is 0.00182 of its analytical allowance). Per-region worst price errors,
combining the European and displaced fixtures, are:

| Family / region | Before ULP | After ULP |
| --- | ---: | ---: |
| bachelier price deep_itm | 2 | 2 |
| bachelier price itm | 3 | 3 |
| bachelier price near_atm_tiny_variance | 2 | 2 |
| bachelier price otm | 5 | 5 |
| bachelier price zero_variance | 0 | 0 |
| black price deep_itm | 2 | 2 |
| black price extreme_scale | 18 | 18 |
| black price itm | 8 | 8 |
| black price near_atm_tiny_variance | 6 | 6 |
| black price otm | 22 | 22 |
| black price zero_variance | 1 | 3 |

All ordinary Greek regional maxima are unchanged; the extra-bit Greek
certificate maximum remains 0.95761 of its bound. All IV reference outcomes
still pass their exact-model acceptance requirements. The fixed public digest
remains `f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b`
over 6,069,960 bytes. Its unchanged value does not erase changes outside that
particular corpus. **Compatibility classification: minor numerical change**
under the stability policy; no API or model definition changes. No release or
version bump is performed here.

## Performance

Apple M1 Pro, macOS 27.0 (26A428), OCaml 5.3.0 with Flambda, library and
benchmarks at -O3 in the Dune development profile. Three alternating paired
runs used identical benchmark sources and fixed inputs. No other task-owned
numerical test ran during timing. The host was not dedicated; starting load
averages, individual batches, allocation and GC counters are retained in the
[raw benchmark record](evidence/dd-exponential-bench.json). These timings do not
establish an SLA or a cross-platform performance result.

The primitive harness uses 20,000 inputs with nonzero normalized low words,
one warm-up and nine measured batches per invocation. The table reports the
median of the three invocation medians and their observed range in ns/op:

| Primitive | Baseline median (range) | Candidate median (range) | Change |
| --- | ---: | ---: | ---: |
| exp_reduced | 627.3 (614.4–637.1) | 744.4 (740.6–744.7) | +18.7% |
| exp_wide | 619.0 (616.3–635.3) | 742.6 (742.2–747.0) | +20.0% |
| expm1_reduced | 562.5 (556.3–568.2) | 692.0 (691.4–692.5) | +23.0% |
| expm1_wide | 646.8 (636.1–651.3) | 811.2 (810.1–811.5) | +25.4% |

Primitive allocation rises from about 710 to 876 words/exp and 649 to 815
words/reduced expm1. `bench/assurance.exe --count 64 --runs 7` separately measures
admission, price, IV, all Greeks and the complete workflow for all four models
in ATM/OTM/ITM regimes. Across these paired medians, affected ATM/ITM price calls
are about 23–31% slower and Greek bundles about 4–21% slower. IV changes range
roughly −2% to +2%; complete workflows range −3.4% to +2.5% and are dominated
by runtime IV certification. Admission costs are effectively unchanged within
measurement variation. All 768 benchmark IV inputs return roots in each run.
The raw record includes per-run spreads and GC/allocation data; the zero-length
empty-harness timing is a clock-resolution control, not a claimed zero-cost API.

**Decision:** submit this correct, provenance-documented candidate for review
with its explicit scalar-performance and rounding tradeoffs. Do not claim a
speedup or silently relax an accuracy/performance requirement. Future
optimization needs the same operation-level derivation and qualification.

## Reproduction

Use the pinned compiler/dependencies and mpmath environment from
[oracles.md](oracles.md). Run `python3 oracle/dd_exp_coefficients.py --check`,
`python3 oracle/verify_bounds.py`, `oracle/build.sh dd`, then
`dune build @install @fmt @runtest`. Run the affected named mutations:
`dune exec scripts/mutation/mutation.exe -- expm1-tiny dd-exp-degree`.
Both affected mutants were killed after a clean mutation-profile baseline
(56 seconds), successful mutated builds, and numerical failures in
`dd_reference`. The seven default core mechanisms are unchanged.

For row comparisons, use a detached baseline worktree at the revision above.
Copy only the candidate's trace instrumentation (`test/bounds.ml`,
`test/dd_reference.ml`, `test/oracle_price.ml`, `test/oracle_greeks.ml`,
`test/greek_reference.ml`) into that disposable baseline. Compile both sets of
scorers. Run each directly against the candidate fixtures, setting
`MORPHIQ_ORACLE_TRACE` to distinct `PREFIX-dd.tsv`, `PREFIX-european.tsv`,
`PREFIX-displaced.tsv`, `PREFIX-greeks.tsv`, and `PREFIX-greek_bits.tsv` paths.
Use `scripts/compare_exponential_traces.py BASE_PREFIX CANDIDATE_PREFIX OUT_PREFIX`
and run `scripts/audit_exponential_changes.py` in the pinned mpmath environment.
The latter uses the recorded paths under `docs/evidence/`.

For timing, copy only `bench/dd_exponential.ml` and its executable stanza into
the disposable baseline; the existing assurance harness is already identical.
Build each at -O3. Alternate baseline/candidate order between three pairs,
invoking `bench/dd_exponential.exe` and `bench/assurance.exe --count 64 --runs 7`
without concurrent task-owned build/test work. Retain load and raw output.

This is engineering evidence over the exercised inputs, not universal
verification, institutional model-risk acceptance, or legal clearance of
historical QD versions or the remaining AS241/CALERF implementations.
