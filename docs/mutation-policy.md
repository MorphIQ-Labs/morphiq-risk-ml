# Mutation execution policy

The ordinary `ci` workflow retains the full accuracy/certification test suite
on Linux x86-64, Linux arm64 and macOS arm64. Its required `mutation` job runs
seven core mutants. The integration-branch catalog currently contains **51
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
harness failures, never kills. Ordinary tests exercise these failure controls.

| Core mutant | Reason for default coverage |
| --- | --- |
| `split-root-nonoverlap` | Square-root output must satisfy DD consumer preconditions. |
| `dd-scale-nonoverlap` | Subnormal scaling must preserve DD nonoverlap. |
| `reference-expansion` | Reference scoring must retain cancelling low words. |
| `scaled-exp-prefactor` | A large currency prefactor can rescue a representable Gaussian tail. |
| `certified-rounding-cell` | A fast proposal must not bypass exact-model root acceptance. |
| `greeks-theta-dd` | Black Greek cancellation needs double-word arithmetic. |
| `bachelier-theta-dd` | Bachelier Greek cancellation needs double-word arithmetic. |

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
integration-branch catalog has 51 mechanisms; the seven default core witnesses
are unchanged. The designated planner test checks behavior, including exact
rational aggregate containment, rather than a replay digest alone.
