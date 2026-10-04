# Integrated candidate evidence

Candidate `f703546ea736d456f64e74be6ef9d2da2c10ef88` is described in the
[dossier](../../candidate-fast-optimized.md). The public receipt is engineering
qualification only. `SHA256.json` inventories this directory; `dossier.json`
is checked by `scripts/check_experimental.py` from the repository root.

- `receipt.json`: exact source, candidate/main CI runs, platform membership,
  archive identity, all 96 mutation IDs and rejected collector fault controls.
- `workflow.json`: manual candidate workflow jobs/steps and conclusions.
- `ci-workflow.json`, `ci.log.gz`: exact-main CI, including development and
  release ordinary suites on all three supported platforms.
- `*-artifact.json`: installed package/toolchain/lock/notice/source hashes and
  successful native/bytecode consumers. `*-build.log.gz` retains isolated build
  logs; `*-candidate-*.log.gz` retains candidate gate output.
- `*-canonical.json`: 720 rows and 8,640 exact qualified price/Greek/IV outcomes
  per platform, pinned to the captured independent campaign.
- `*-exchange-{native,bytecode}.txt.gz`: every installed Exchange outcome, value
  and radius, including refusals and invalid inputs; 649 rows per run.
- `full-mutations.log.gz`: clean baseline and all successfully compiled mutants
  killed by their designated guards. No mutation workload is added to PR CI.
- `source-deltas.json`: library file hashes from the prior qualified Exchange
  candidate to the current source; not an accuracy claim.
- `pending-acceptance-check.json`: expected rejection of the new institutional
  record for incomplete review/decisions, with all supplied file/artifact hashes
  intact. The historical acceptance record remains unchanged.
- `integrity-controls.json`: deliberate faults rejected by the dossier checker.
- `collect.py`: campaign-specific artifact reconciliation and negative controls.
  It validates all inputs before writing to a fresh output directory.

Original downloads, including identical source archives and workflow metadata,
are preserved under the maintainer's acceptance directory for this full SHA.
The public source archive can be reproduced from Git. No private paper,
research-library access, compiled output or business data is required.

To repeat collection, download the manual run's four artifacts with `gh run
download 37238843530 --repo MorphIQ-Labs/morphiq-risk-ml --dir ARTIFACTS`.
Save JSON metadata for candidate run `37238843530` and exact-main CI run
`37238293731` using `gh run view RUN --json
databaseId,status,conclusion,jobs,headSha,url,event,workflowName,createdAt,updatedAt`;
save the latter's `--log` output separately. Then run:

```sh
python3 docs/evidence/qualified-fast-candidate/collect.py \
  --artifacts /path/to/ARTIFACTS \
  --workflow /path/to/workflow.json --ci-workflow /path/to/ci-workflow.json \
  --ci-log /path/to/ci.log --output /tmp/fresh-reconciled-evidence
```

The collector compares decompressed archives against a fresh `git archive` of
the pinned commit, verifies exact consumer/reference/notice/lock hashes,
rejects missing modes/rows/jobs/guards, and exercises deliberately corrupted
inputs. This verifies evidence integrity, not human authorship or a universal
numerical proof. Existing campaign references are replayed, not regenerated.
Historical dossiers must be interpreted at their recorded revisions; current
documentation updates do not rewrite their source or acceptance scope.
