# Mutation execution policy

The ordinary `ci` workflow retains the full accuracy/certification test suite
on Linux x86-64, Linux arm64 and macOS arm64. Its required `mutation` job runs
seven core mutants. Each still requires a clean baseline, a successful mutated
build and failure of the designated independent numerical guard; compiler
errors and replay-bit changes do not count as kills.

| Core mutant | Reason for default coverage |
| --- | --- |
| `split-root-nonoverlap` | Square-root output must satisfy DD consumer preconditions. |
| `dd-scale-nonoverlap` | Subnormal scaling must preserve DD nonoverlap. |
| `reference-expansion` | Reference scoring must retain cancelling low words. |
| `scaled-exp-prefactor` | A large currency prefactor can rescue a representable Gaussian tail. |
| `iv-beta-bar` | Near-maximum inversion needs the compensated distance to the maximum. |
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
separate `--probe intrinsic-terms` diagnostic remains provisionally excluded
and currently survives; it is not included in either passing catalog.
