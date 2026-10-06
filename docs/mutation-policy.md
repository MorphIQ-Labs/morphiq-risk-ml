# Mutation execution policy

The ordinary `ci` workflow retains the full accuracy/certification test suite
on Linux x86-64, Linux arm64 and macOS arm64. Its required `mutation` job runs
seven core mutants. The catalog currently contains **121
mechanisms**; the smaller counts below describe its historical growth. Each
selected mutant still requires a clean baseline, a successful mutated
build and failure of the designated independent numerical guard; compiler
errors and replay-bit changes do not count as kills.

The full ordinary baseline runs once under the mutation profile. Each mutant
must then build successfully and fail its designated guard, invoked with the
same fixtures as its ordinary Dune action. Every selected direct guard must
also pass before mutations start. Both price fixture actions are retained.
This avoids repeating unrelated numerical campaigns for each primitive fault.
Missing binaries/fixtures, unmapped guards and signal-terminated tests are
harness failures, never kills. Reference-input errors use exit 3 and are also
invalid, never numerical kills. Ordinary tests exercise these failure controls.

| Core mutant | Reason for default coverage |
| --- | --- |
| `split-root-nonoverlap` | Square-root output must satisfy DD consumer preconditions. |
| `dd-scale-nonoverlap` | Subnormal scaling must preserve DD nonoverlap. |
| `reference-expansion` | Reference scoring must retain cancelling low words. |
| `scaled-exp-prefactor` | A large currency prefactor can rescue a representable Gaussian tail. |
| `certified-rounding-cell` | A fast proposal must not bypass exact-model root acceptance. |
| `greeks-theta-dd` | Black Greek cancellation needs double-word arithmetic. |
| `bachelier-theta-dd` | Bachelier Greek cancellation needs double-word arithmetic. |

The optional `ulp-distance-overflow` mechanism challenges the shared finite
scorer; [oracle assurance](oracle-assurance.md) records its witness.

This is a small sentinel set, not a proof that all other mechanisms are covered.
Selection is an engineering workload decision; it does not change error bounds
or certify the remaining IV assumptions. `core_ids` in
`scripts/mutation/mutation.ml` is the executable selection. Missing or ambiguous
core entries fail, and CLI regression checks run in the ordinary test suite.

The **full mutation assurance** workflow runs the full catalog of mechanisms on
manual dispatch and each Monday at 06:00 UTC on the default branch. It has no
PR/push trigger and is not a required PR check. A survivor or invalid mutation
still fails this workflow and its log is retained as an artifact: optional
execution does not turn a failed curated kill claim into a passing result.
GitHub enables the schedule/manual workflow once its definition is on the
default branch. Manual runs can then select another branch.

Run the same lanes locally:

```sh
dune exec scripts/mutation/mutation.exe -- --core
dune exec scripts/mutation/mutation.exe
dune exec scripts/mutation/mutation.exe -- --core --list
dune exec scripts/mutation/mutation.exe -- quotient-remainder
```

For changes to a mechanism outside the core, run its named mutant locally as
part of the affected checks; use the full catalog for broader assurance. The
separate `--probe` diagnostics are excluded from the passing catalog.

## Reconciled after runtime IV certification

The 13-mechanism affected campaign killed eight faults and found five compiled
survivors. `iv-rounded-bound`, `iv-beta-bar` and `iv-ln-beta` now change only
untrusted proposal computations; runtime classification/correction preserved
every tested public outcome. `bachelier-iv-quantum` and `iv-maximum-error` change historical
root-error scorers whose rounded-reference difference is now zero on all
correctly rounded IV rows. Their former end-to-end witnesses no longer establish
the necessity of those terms. None of these observations proves universal
redundancy or permits removing the corresponding numerical mechanism.

Those five now live alongside `intrinsic-terms` under `--probe`. At that stage the
catalog had 37 mechanisms, including the new runtime acceptance, discarded-word
and original-shift witnesses. The default core still has seven: the compiled
acceptance-bypass fault replaces the surviving proposal `iv-beta-bar` fault.
`iv-complement-correction` still fails the independent near-maximum regression
and remains curated. No bound or successful-root requirement was loosened to
make this reconciliation pass.

## Adaptive certification controls

This stage brought the curated catalog to 40 mechanisms. Three additional optional
controls cover the first attempt's exponential remainder, the exact product
quantum shortcut and the fallback needed to preserve full-evaluator availability.
The default core remains the same seven. Both arithmetic configurations run
the independent ordinary primitive and model reference checks.

## Zero-volatility boundary regressions

This stage brought the catalog to 43 mechanisms. Three optional witnesses cover Black ATM
time smoothness, Bachelier ATM rho and the generally nonzero boundary veta.
Their designated guard is `boundary_greeks`, which checks independent price
derivatives and exact varied-coordinate identities. None is added to the
seven default core mechanisms.

## Production acceptance boundary

Four additional optional witnesses cover the requested accuracy limit, served
certificate radius, BSM versus forward rho and time-unit conversion. The
catalog reached 47 mechanisms at this stage; default CI retained the same seven
core witnesses.
The guards use independent reference error and contract rejection, not replay
bit changes or compiler failures.

## Scenario-planner integration

Four optional witnesses exercise snapshot isolation, the post-expiry outcome,
scalar certificate error in weighted aggregates, and incomplete totals. The
catalog has 51 mechanisms; the seven default core witnesses
are unchanged. The designated planner test checks behavior, including exact
rational aggregate containment, rather than a replay digest alone.

## Direct DD exponential replacement and optimization

`dd-exp-degree` replaces the retired QD stopping-rule mutation: a degree-12
polynomial must fail the unchanged DD oracle budget. `expm1-tiny` now injects
a zero result for a nonzero tiny input. Removing the old outer tiny branch is
no longer the same fault, since the shared reduced helper owns that handling.
The optimized degree-22 loop uses the same degree-truncation witness.
The catalog still contains 51 mechanisms, with the same seven default core
witnesses. Historical mutation logs retain their original names.

## Generated error-function replacement

Five optional witnesses cover local erfcx degree, tail degree, small-erf degree,
the exact square in the erfc tail, and the leading-coefficient residual needed
by a cancelling BSM theta. These bring the catalog to 56 mechanisms. The first
four use the independent normal/error-function oracle; the leading-residual
witness uses the existing Greek oracle and its unchanged 8-ULP theta gate.
The seven default core mechanisms are unchanged.

### Inverse-normal replacement witnesses

Two optional mechanisms check the six-step iteration budget and the double-word
final correction. The iteration mutant must fail the numerical inverse oracle;
the correction mutant must fail its adjacent-input monotonicity guard. Neither
uses a changed replay digest as a kill. The seven core selections are unchanged.

### Prepared divisor reuse

Three optional numerical witnesses cover the prepared reciprocal's low word,
divisor exponent restoration and extreme-dividend normalization. They use
canonical-word comparison plus independent exact-rational quotient checks.
The existing seven core mechanisms remain unchanged; the full optional catalog
now contains 61 mechanisms.

### Finite Greek outcomes and rho scaling

Four optional mutants bypass field finiteness, hide an unresolved intrinsic,
or restore premature maturity multiplication in live/zero-volatility BSM rho.
Their independent exact-input Greek references reject successful nonfinite
values, false finite zeros and incorrect subnormal values. The core remains
seven mechanisms; the complete optional catalog contains 66.

## Severe carry-cancellation price refinement (#76)

Two additional optional mechanisms remove original-input refinement or accept an
uncertified expansion centre. The exact-word `carry_cancellation` guard checks
independently rounded reference values and refusal of an unresolved cell. The
full catalog at #76 contained 68 mechanisms; the seven default core mutants are
unchanged. Execution evidence is retained with the carry-cancellation report.

## Greek cancellation (#80)

Four optional mutants cover bypassing exhausted-coordinate refusal, treating
underflowed carry as an exact zero, restoring the inaccurate binary64
zero-variance theta subtraction, and bypassing smooth-theta cancellation refusal. All use the independent `greek_cancellation`
guard. The full catalog at #80 had 72 mechanisms; the default seven remain unchanged.

## Rho subnormal rounding (#77)

Five optional mutants cover bypassing original-input rho refinement,
rounding away the normal-probability correction, removing the proved tail
zero path, restoring the wrong tail exponent and weakening the cheap zero
proof threshold. Each uses the direct `rho_midpoint` witness. The catalog has 77
mechanisms; the seven default core mutants are unchanged.

## Adversarial closeout reconciliation (#57)

The full campaign after #77 found that `greek-live-rho-scale` and
`greek-zero-rho-scale` survived: final subnormal refinement repaired their old
guard inputs. Premature multiplication still damages normal-range outputs.
Four exact/independently enclosed ITM rho witnesses now require the correct
normal results for both sides and zero/positive volatility. The catalog and
seven default core selections are unchanged. The [closeout report](adversarial-assurance-closeout.md)
retains the initial survivors, derivation, original words and affected guard
rerun rather than treating survival as evidence of universal redundancy.


## Certified exchange prices (#60)

Six optional mechanisms cover the correlation cross term, rounded covariance
misclassification, premature discounted-leg rounding, the deliver leg's yield,
certificate radius and final absolute-limit enforcement. Each uses
`exchange_reference`; only resolved independent intervals adjudicate numerical
accuracy. The catalog now has 83 mechanisms; the default seven are unchanged.


## Expansion allocation optimization (#8)

The optional `enclosure-grow-residual` mechanism drops nonzero TwoSum residuals
from the private scratch buffer. The existing exact-rational
`enclosure_reference` guard must reject it. Discarded-word, product-guard,
series-tail and FMA-underflow mechanisms remain applicable; the discarded-word
locator follows the equivalent reverse array traversal. The current catalog
has 84 mechanisms, with the same seven in default CI. See the
[optimization evidence](results-certificate-allocation.md).

Shared model preparation adds `multi-output-limit`, witnessed by explicit zero,
invalid and finite per-output limits in `production_multi`. The full catalog now
has 85 mechanisms; the default seven-mutant CI selection is unchanged.

Shared Greek intermediates add `greek-eager-inverse-time`: ATM normal vega
must remain available when unrelated inverse-maturity arithmetic overflows.
The optional catalog now has 86 mechanisms; default CI remains the same seven.

### Enclosure summation optimization

`enclosure-sum-order` removes the enforced magnitude ordering for FastTwoSum;
`enclosure-sum-finite` removes overflow refusal. Both use the independent
exact-rational `enclosure_sum` guard. The optional catalog now contains 88
mechanisms. The seven default CI selections remain unchanged.

### Fixed-word enclosure allocation

`enclosure-packed-word` removes a retained low word from the fixed representation;
`enclosure-normal-exponent` biases the normal-input exponent and can omit a needed
product quantum. The independent rational `enclosure_reference` guard owns both.
The discarded-word mechanism now targets the same outward allowance in its
array loop. The optional catalog has 90 entries; default CI still selects seven.

The optional `fast-batch-finite` and `fast-batch-order` mechanisms exercise
nonfinite scalar-result refusal and original-index preservation through mixed
compiled fast requests. `fast_batch` is their direct guard. Neither expands
the seven-mutant default lane.

The optional `fast-planner-tile` and `fast-planner-side` mechanisms exercise
foreign-plan rejection and original option-side dispatch through fast scenarios.
The shared snapshot/post-expiry mechanisms still protect both planner paths.

The fast-allocation round adds `dd-exp-accumulator-low` and
`dd-log-accumulator-low`: the independent DD reference guard must reject losing
the low word between Horner iterations. The default core selection is unchanged.

The native Bachelier batch adds `native-bachelier-exponent`, checked against
independent original-input price references before replay compatibility, and
`native-bachelier-mode`, checked by deliberate rejected foreign dispatch modes.
The former's replay check is disabled in the mutation profile. These two optional
mechanisms bring the catalog to 98; the seven core mutants remain unchanged.

The optional `native-planner-order` mechanism reverses packed native tile
results. Its dense-tile original-input guard includes expiry and invalid rows,
so restoring a value to the wrong original index fails. The full catalog now
contains 100 mechanisms including `native-planner-chunk-offset`, which repeats
the first chunk instead of advancing its original offset. The dense-tile guard
checks whole ordered rows across 256/257/512/513-row tiles; the seven-mutant core
is unchanged.

The optional `bermudan-finite-deterministic`, `bermudan-valuation-projection`
and `bermudan-next-right-boundary` mutants use `bermudan`: a finite deterministic
stopping strategy, immediate intrinsic payoff at a listed valuation date, and
analytical discounted-strike bounds before the first right. These are optional;
default PR CI still runs only the seven core mutants.

The optional `american-cash-opening-side`, `american-cash-liquidator` and
`american-cash-refinement` mutants are guarded by `american_cash`: event-side
exercise eligibility, the limited-liability jump and independent mapping
refinement. These do not change the seven-mutant default CI selection.

The optional `american-stationary-stopping` and `american-delayed-opening`
mechanisms exercise the original 250/9 deterministic maximum and rejection of
pre-opening exercise through `american_pricing`. They add two entries to the
optional catalog; the default seven remain unchanged. These are financial-model
witnesses, not continuum accuracy proofs.

### Scalar enclosure fusion and American setup reuse (#119)

Three optional mechanisms cover transported scalar input radii, stale packing
scratch slots and the orientation of a reused American stencil. The scalar
witness checks exact-rational containment before compatibility fingerprints;
changed replay bits alone are not a kill. The American witness requires the
existing independently checked price capability. The full catalog at #135 contains 113
mechanisms; default CI still selects the same seven core mutants.

The optional `american-spatial-grid-key` fault omits domain expansion from the
request-local preparation key. The reused-band length precondition must explicitly
reject the wrong grid through the ordinary American capability witness after a
successful build; source/replay identity alone is not the kill. Default core
remains seven.

Boundary reuse adds `bermudan-boundary-slab-key`: deliberately dropping slab
and next-right identity must fail a numerical boundary or dependency witness.
The catalog at #135 has 113 entries; the seven-mutant core is unchanged.

### Piecewise coefficient schedules (#114)

Four optional faults use `american_piecewise`: replacing the profile by its
average, selecting a knot's left coefficient, omitting interior future discount
optima, and keeping stale spatial coefficients across a knot. Their witnesses
use distinct equal-integral exercise profiles, original-input analytical
stationary/discount extrema and the independently refined volatility-profile
reference. The #114 catalog contained 117 mechanisms; the core remains seven.

The #119 allocation follow-up adds four optional faults: omitting stencil
coefficient identity, aliasing cached snapshots to mutable working bands,
omitting the call upper-boundary grid endpoint, and retaining matrix bands
across changed constant slabs. Independent varying-volatility references and complete public outcomes across cache-disabled/partial/full
workspace budgets witness these dependencies. The catalog now has 121 entries;
default CI still runs seven.
