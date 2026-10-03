# Version 0.2.0 candidate evidence

The frozen source candidate is
`dcdd9a7f44c96fc8ecda042d95ce790bc7e6e17f`, merged into main in PR #44.
It declares package version **0.2.0**. No release has been tagged, published
or deployed. The [acceptance record](acceptance/pending.json) distinguishes
completed engineering from outstanding independent review and deployment decisions.

## Source and prior owner review

The owner [reviewed and approved baseline `72878e3`](acceptance/owner-review-2026-10-03.md)
and authorized canonical generated datasets. That resolves the declared library
boundary's owner review in #13. The [source delta](evidence/candidate-0.2.0-source-delta.json)
records every library file's before/after hash: only `Morphiq_risk.version`
changes. All other library files, oracle sources/fixtures, model contracts,
dependency pins and default CI/mutation policy are unchanged. The project
version advances from 0.1.0 to 0.2.0 for the previously introduced breaking
outcome/type and boundary-classification changes, as explained in the
[release notes](../CHANGELOG.md).

The scientific evidence inherited from the reviewed baseline therefore has
an explicit source-compatibility record. This is not a substitute for the
independent theorem/call-site review still required by #15. The new optional
dataset, validation and packaging tools have their own checks and provenance.

## Exact-candidate validation

[Main CI](evidence/candidate-0.2.0-ci.json) passes all five required checks
on the exact candidate: three platforms, formatting and seven core mutants.
The [manual candidate run](https://github.com/MorphIQ-Labs/morphiq-risk-ml/actions/runs/37118922351)
also passes ordinary/build/format checks, artifact installation and canonical
replay on all three platforms:

| Platform | Isolated native + bytecode install | Canonical replay |
| --- | --- | --- |
| Ubuntu 24.04 x86-64 | [Pass](evidence/candidate-0.2.0-ubuntu-24.04-artifact.json) | [720 rows / 8,640 outcomes](evidence/candidate-0.2.0-ubuntu-24.04-replay.json) |
| Ubuntu 24.04 ARM64 | [Pass](evidence/candidate-0.2.0-ubuntu-24.04-arm-artifact.json) | [720 rows / 8,640 outcomes](evidence/candidate-0.2.0-ubuntu-24.04-arm-replay.json) |
| macOS ARM64 | [Pass](evidence/candidate-0.2.0-macos-15-artifact.json) | [720 rows / 8,640 outcomes](evidence/candidate-0.2.0-macos-15-replay.json) |

The [full mutation log](evidence/candidate-0.2.0-full-mutations.txt) records a
passing baseline and **47 of 47** compiled mutants detected by their designated
witnesses. The [completed manual run](evidence/candidate-0.2.0-validation.json)
is successful. Full mutations remain in the manual/scheduled lanes, outside
default PR CI.

The candidate uses OCaml **5.3.0 Flambda**, the unchanged numerical `-O3`
flags and locked dependencies. Every source artifact is independently archived,
built, installed in a fresh prefix and consumed outside the source build in
both native and bytecode modes. The [local artifact check](evidence/candidate-0.2.0-local-artifact.json)
also passes. Installed-file hashes and compiler identities are retained per host;
compiled binaries are not claimed to be identical across architectures.

All four generated source archives are byte-identical, verified after download:

```text
source.tar.gz SHA-256
56c057ddf737ecc5e25b27b0f514d46dd5c1aba4bf67595feb0f13204b07352b
uncompressed tar SHA-256
ed1eac54a4f32f977ca25f58ececb1f007fe8e7519bb29d5e018b2940ff046ac
```

## Canonical dataset and assurance scope

The [fixed generated-workload specification](canonical-dataset.md) predates
scoring. The [qualification report](results-canonical-dataset.md) retains
7,920 independently certified price/Greek outputs and 720 independently
certified positive IV rounding cells, nine identical native repetitions,
complete aggregates and all 671 material comparator findings with dispositions.
The initial failed comparator gate remains intact beside its explicit rho
adjudication. The three-platform replay above compares all captured values,
bounds and IV outcomes; it does not replace the independent interval audit.

The intended library capability remains scalar exact-model European pricing
with typed quantities, explicit caller-selected absolute limits, certified
positive IV rounding, and explicit refusals. The dataset exercises four models,
both sides, maturities/moneyness/volatility and deterministic scale/carry samples.
It is generated data, with documented coverage gaps; no observed business book,
market/model calibration guarantee, calendar-roll engine, concurrency planner
or million-instrument throughput claim is implied. Shared-workstation timings
are evidence for their recorded workload, not a production SLA.

## Retention and reproduction

Source archives and full downloaded Actions artifacts are retained locally at:

```text
/Users/stephen/Development/MorphIQ-Labs/.artifacts/morphiq-risk-ml/0.2.0/
  dcdd9a7f44c96fc8ecda042d95ce790bc7e6e17f/
```

`local/` contains the local source archive, isolated installation and report;
`actions/` contains the downloaded platform artifacts. GitHub retains the
manual run's artifacts for 90 days; the local copy is retained separately.
The checksummed reports are committed here. An early local attempt used a
destination under the checkout, contrary to the tool's documented external-
directory requirement; Dune refused that workspace layout. Its diagnostic log
is retained outside the repository, and the valid final invocation uses the
external destination above.

To rebuild, select the full frozen commit and a fresh directory outside any
Dune workspace, then follow [the artifact command](acceptance-and-change-control.md#artifact-rehearsal-and-final-freeze).
To repeat remote validation, manually dispatch `candidate.yml` with that full
SHA. Later dossier-only commits do not silently change the selected candidate.

## Remaining decisions

The owner review and generated-workload authorization are genuine and recorded.
Still required are the independent reviewer's documented expertise/conflicts,
theorem/call-site review and findings report; target-deployment operational
requirements and the responsible owner's recommendation; and final exact-
candidate model-validation/release decisions. Those are not signatures supplied
by this agent. The acceptance integrity check must remain rejecting until its
missing evidence and decisions are actually present. No unresolved numerical
finding is being waived or hidden behind those remaining decision items.
