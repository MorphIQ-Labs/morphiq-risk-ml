# Experimental 0.3.0 candidate qualification

Candidate: `83b541e02ce3467536a6febc54a5eeb49004bc8a`, merged by
[PR #73](https://github.com/MorphIQ-Labs/morphiq-risk-ml/pull/73).
Assessment date: 2026-10-04. Scope: the
[experimental European family and planner baseline](experimental-baseline.md).
The engineering assessor is Codex, carrying out the maintainer's closeout
instruction. This records automated engineering qualification, not a signature
from an independent reviewer or approval for institutional use.

**Decision: qualified experimental baseline.**
The [immutable candidate run](https://github.com/MorphIQ-Labs/morphiq-risk-ml/actions/runs/37176687849)
executes on the source above. Later commits adding this dossier and retained
reports are documentation/evidence-only deltas, not fresh numerical executions.
The 0.2.0 dossier and institutional pending decision remain unchanged.

## Exact-source results

| Check | Result |
| --- | --- |
| Build, format and ordinary tests | Pass on Linux x86-64, Linux ARM64 and macOS ARM64 |
| Isolated installation from deterministic source archive | Pass on all three platforms |
| Installed scalar, four-model Batch, Scenario and Planner consumers | Native and bytecode pass on all three platforms |
| Installed LICENSE, NOTICE, SECURITY and third-party notices | All ten files match source bytes on all three platforms |
| Canonical independent-campaign replay | 720 rows and 8,640 price/Greek/IV outcomes matched on each platform |
| Full curated mutation catalog | 65 of 65 compiled mutants killed; clean ordinary baseline and direct guards |
| Source inventory | All 220 reviewed source/evidence files match the recorded hashes |
| Notice-only arithmetic delta | Elementary body unchanged; generated replay arithmetic byte-identical |

The source archive is identical across the three platform runs, SHA-256:

```text
65a196e90b92722054dafd608a59b4450149c3c19b418e258a33b4ed49b784c3
```

The generated replay body after its notice has SHA-256
`efcdc0d7321c659b0ea907672a134e32adcacefb150c1add8f83fce4af3fe676`,
unchanged from the pre-closeout source. This identity check establishes the
scope of the comment-only edit; numerical assurance comes from the separate
references, bounds and executable witnesses.

Every platform report records its OCaml configuration, installed package
versions, lockfile/tool/consumer hashes and installed file hashes. The supported
compiler is OCaml 5.3.0 Flambda with the existing `-O3` numerical-library flags.
Native and bytecode execution are both tested, but identical compiled binaries
across platforms are not claimed. The [baseline evidence map](experimental-baseline.md)
records numerical campaign inheritance and the explicit semantic deltas since
0.2.0. No coefficient, operation, signature or tolerance changed in closeout.

## Retained evidence and reproduction

The [machine-readable dossier](evidence/experimental-0.3.0/dossier.json) indexes
platform reports, logs, source provenance, numerical/planner reports and the
workflow receipt by SHA-256. Full workflow and test/mutation logs are compressed
under `docs/evidence/experimental-0.3.0/`, so they survive CI's 90-day retention.
Original downloaded artifacts and the source archives are also preserved at:

```text
~/Library/Application Support/MorphIQ Labs/acceptance/morphiq-risk-ml/83b541e02ce3467536a6febc54a5eeb49004bc8a/
```

That local preservation copy is not a public build dependency. The public Git
commit is the source of truth for reproducing the archive. From a checkout
containing the candidate and the retained dossier:

```sh
python3 scripts/check_experimental.py docs/evidence/experimental-0.3.0/dossier.json --root .
python3 scripts/candidate_artifact.py \
  --commit 83b541e02ce3467536a6febc54a5eeb49004bc8a \
  --output /tmp/risk-0.3.0-reproduction
```

The artifact tool requires the documented OCaml switch and a new output path.
It reconstructs the source archive twice, installs it independently, checks the
resolved package origin and notices, then compiles and runs the consumers.
The candidate tool's bytes must match the archived version; use that revision
of the tool if later tooling changes. For the entire matrix and full mutations:

```sh
gh workflow run candidate.yml --repo MorphIQ-Labs/morphiq-risk-ml --ref main \
  -f commit=83b541e02ce3467536a6febc54a5eeb49004bc8a
```

The [repository settings receipt](evidence/opensource-settings-2026-10-04.json)
records required PR/CI rules, private vulnerability reporting and historical
artifact preservation. The [current-source audit](opensource-closeout.md)
records the replaced AS241/CALERF/QD code, permissive retained material and
historical rights caveats. Neither source hashes nor passing tests are legal
permission for old distributions.

## Limits and decision boundaries

This is an experimental open-source engineering baseline. Finite corpora and
supported-platform checks do not prove correctness over every admitted input.
Explicit numerical failures, unsupported boundaries and incomplete planner
results remain part of the public contract. Broader boundary/oracle/scorer and
scheduling challenges remain #53–57; independent review, representative business
portfolios and institutional release decisions remain #15–17 and #27. No tag,
package publication, deployment approval or production SLA is created here.
