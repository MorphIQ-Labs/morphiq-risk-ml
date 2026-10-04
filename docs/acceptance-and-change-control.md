# Candidate acceptance and change control

The current package is experimental **0.3.0**, with its separate
[experimental qualification](experimental-baseline.md). The dated 0.2.0 record
below remains unchanged and pending for institutional use.

The institutional acceptance process establishes engineering evidence toward Epic #27. It does not
approve deployment or freeze a release. The authoritative machine-readable
[acceptance record](acceptance/pending.json) is deliberately pending. No release
tag, package version change or deployment is authorized by a passing test alone.
The historical candidate package declared 0.2.0: the public outcome/type changes require
a minor increment under the pre-1.0 policy in [stability](stability.md).
This selects candidate metadata, without tagging or publishing a release.

The owner has since [reviewed and approved the delivered baseline](acceptance/owner-review-2026-10-03.md)
and authorized canonical generated datasets. The resulting
[720-row qualification](results-canonical-dataset.md) passes its fixed numerical
criteria after explicit comparator adjudication. Those decisions and results
are now retained. The [0.2.0 candidate dossier](candidate-0.2.0.md) identifies
the exact source, source-compatibility evidence, artifacts and validation.
Independent-review and deployment decisions are assessed separately rather
than treating all owner review as absent.

## Dossier and decision

The [independent review package](independent-review-package.md) maps model,
source, paper, arithmetic, oracle, runtime boundary and operational evidence.
The [supported capability](production-boundary-design.md) requires explicit
per-request limits. [Shadow results](results-shadow.md) state the synthetic
coverage, comparator findings and material operational cost. These documents
are the review package, not signatures of its acceptance.

To accept a candidate, designated model-validation and engineering/release
owners must supply dated decisions tied to one full commit SHA and intended
use. Retain their actual reports, independence declaration, material finding
dispositions, numerical/economic thresholds, permitted failure rates and
operational requirements. No unresolved material finding may be waived by
widening a test tolerance. An enforced scope exclusion requires explicit impact
and owner acceptance. A post-review numerical/compiler/API change requires a
recorded delta review against the new candidate.

Create an accepted record using the fields in `scripts/check_acceptance.py`:
full candidate SHA, version, intended use, no unresolved blockers, all ten
evidence categories, both owner decisions, and artifact paths/hashes. Every
evidence and decision entry has `path`, `sha256`, `candidate_commit`; decisions
also have `name`, ISO `date` and `decision: accept`. Artifacts use the same
hash/commit fields relative to the separately supplied artifact directory.
Run the read-only integrity check before a release decision is acted on:

```sh
python3 scripts/check_acceptance.py docs/acceptance/pending.json \
  --artifact-root /path/to/candidate-artifacts
```

The current pending record must fail. The check verifies completeness, identity
and file integrity; it cannot authenticate people, evaluate the truth of a
report or grant release authority. Preserve approvals through the existing
reviewed repository process. Its executable negative controls reject missing
owners, unresolved blockers, wrong commits, changed evidence and path escape.
There is no automated publishing/tagging workflow here.

## Artifact rehearsal and final freeze

Use a fresh destination outside the repository:

```sh
python3 scripts/candidate_artifact.py --commit FULL_CANDIDATE_SHA \
  --output /tmp/risk-candidate-FULL_CANDIDATE_SHA
```

The tool independently reproduces a deterministic source tar, records its
checksum, builds/installs from the extracted artifact into an isolated prefix,
and compiles/runs native and bytecode consumers of the public certificate/IV
API. It checks that the consumer resolves that installed package. Retain the
source artifact, installation file hashes, lock/toolchain versions and build
log. This demonstrates packaging on the tested host, not bit-identical compiled
artifacts across platforms. Re-run on the final selected candidate; a rehearsal
against an earlier source is not that candidate's acceptance evidence.

The final dossier must identify successful checks on the exact final head:
Ubuntu x86-64, Ubuntu ARM64 and macOS ARM64 ordinary/backend/replay tests,
formatting and the seven core mutations. Retain full curated mutations in the
manual/release lane and all independent/reference reports with source hashes.
Preserve surviving diagnostic probes separately; do not count a probe as a
curated kill. Full mutations stay outside default PR CI.

The manual [candidate workflow](../.github/workflows/candidate.yml) takes one
full commit SHA already merged into main, repeats build/format/ordinary checks
on all three platforms and verifies that platform's source artifact and
isolated native/bytecode consumers. A separate manual job runs the full catalog.
Each platform also replays all 720 canonical rows against the captured,
independently certified price/Greek/IV output words without an oracle dependency.
This is a replay identity check, distinct from the original independent audit.
Reports, logs and source archives are retained as Actions artifacts for 90 days;
download them into the controlled acceptance archive before that expiry.
There is no publishing or tagging action. Dispatch with:

```sh
gh workflow run candidate.yml --ref main -f commit=FULL_CANDIDATE_SHA
```

## Change-impact matrix

The pending DD exponential replacement and optimization in
[PR #67](https://github.com/MorphIQ-Labs/morphiq-risk-ml/pull/67) is a numerical
delta after the reviewed baseline. Its [qualification](results-dd-exponential-optimization.md)
records the degree-22 derivation, unchanged budgets, 29 changed served oracle
rows versus QD, development/release validation and shared-host performance.
The public replay digest is unchanged, but that does not make the delta
bit-identical on all inputs or extend earlier acceptance to this candidate.
Independent delta review and final artifact qualification remain pending;
The AS241 implementation has since been replaced with its own [delta evidence](results-inverse-normal.md); final current-source provenance and exact-candidate acceptance under #64 remain release blockers. The CALERF replacement has its own delta evidence below. No acceptance
record or owner decision is changed by this engineering evidence.

| Change | Required analysis and refreshed evidence |
| --- | --- |
| Formula, constant, range reduction, threshold or bound | Re-derive before scoring; primary-source assumptions and call sites; independent original-input references; affected mutations; per-case compatibility; independent numerical delta review. |
| Domain, units, type, public outcome or failure classification | Owner/model approval; both-side boundary witnesses; exhaustive caller/API compatibility; intended-use and acceptance update; version assessment. |
| Compiler, C flags, CPU/backend or arithmetic primitive | Native/bytecode backend probes; FMA/contraction/subnormal obligations; cross-platform references and replay; operation-level review and performance evidence. |
| Oracle, reference uncertainty or scorer | Independent formulation/rejection controls; no dropped rows; regenerated transitive provenance; before/after row comparison; separate review from the implementation being scored. |
| Optimization or shared preparation/cache | Equal mathematical/accuracy contract; justified preconditions; bounded fallback; before/after operational measurement; deterministic ownership/replay; independent delta review. |
| Dependency, packaging or build | Pinned source/license/version assessment; artifact install/use; affected platform checks and reproducibility; numerical review if arithmetic changes. |
| Documentation/evidence only | Link/hash/command verification; distinguish corrections from changed claims; re-review any altered contract or acceptance assertion. |

Every accepted baseline is immutable. Keep its source, artifacts, dependency
locks, evidence and signed decision available independently of a moving branch.
Retain the old baseline until the replacement has its own complete acceptance.

## Rollout, monitoring and rollback

1. Shadow the actual business book with captured original input words, market
   identifiers, model/convention version, requested limits, outcomes and build
   identity. Protect confidential data in the deployment's controlled storage.
   Require per-trade/gross reconciliation and explicit complete aggregates.
2. The owner sets canary scope, duration, throughput/latency/GC and failure-rate
   limits before activation. No thresholds are supplied by this synthetic
   diagnostic. A canary never replaces failures with a fast unchecked number.
3. Monitor invalid inputs, unsupported requests, accuracy refusals, numerical
   failures and non-convergence separately; include their denominators. Track
   per-model/quantity latency, resource pressure, incomplete aggregates and
   changes in market/input distributions. Escalate a breached numerical
   certificate or unexplained material discrepancy immediately to validation
   and engineering owners; preserve the reproducer.
4. Stop promotion and quarantine affected results. Roll back to the immutable
   accepted artifact/configuration; replay captured cases against both versions.
   If no accepted baseline exists, stop serving the affected capability. A
   stale/missing result is explicit; do not invent a fallback valuation.
5. Resume only after cause, impact, correction, regression evidence and owner
   disposition are recorded against the replacement candidate.

The remaining owner/reviewer/business-workload decisions are release blockers,
not implicit approvals supplied by this engineering exercise.

## Retained engineering rehearsal

The [artifact report](evidence/candidate-artifact-rehearsal.json) pins source
`8f9dd83e08df8ccf1316a5ccc821682dc46c5fb3`, package 0.1.0, archive SHA-256
`8ffb985b1b1435e6531975fba2456b2289eb49313b55389a59ddcbdd730c8699`,
toolchain/lock hashes and every installed file hash. Native and bytecode consumers
both pass from the isolated prefix. The artifact remains at the path recorded
in the report's installation prefix's parent; this is local rehearsal retention,
not a published or accepted release artifact. Environment overrides for the
isolated bytecode stub path are applied after `opam exec` initializes its switch.

The [full catalog report](evidence/candidate-full-mutations.json) and
[log](evidence/candidate-full-mutations.txt) retain a passing ordinary baseline
and all 47 compiled numerical mutants detected. Their numerical source hashes
remain unchanged through this documentation/tooling work. The earlier pending
record [failed as intended](evidence/acceptance-pending-check.json). These checks
supply engineering evidence without manufacturing an owner/reviewer decision.

The [final 0.2.0 dossier](candidate-0.2.0.md) supersedes that packaging rehearsal:
its exact main commit passes all supported-platform checks, native/bytecode
artifact installation, canonical replay and the full 47-mutant catalog. The
[current acceptance check](evidence/candidate-0.2.0-acceptance-check.json) still
rejects the outstanding independent-review and final decision requirements.

## Error-function replacement delta

The [CALERF replacement evidence](results-error-functions.md) is a numerical
delta from the reviewed baseline. It requires its own candidate-specific delta
review; the earlier owner record is unchanged. Final current-source provenance
and candidate-specific acceptance remain unresolved under #64 and block release. This work does not
approve a new release, operational use or unrestricted historical distribution.

## Inverse-normal replacement delta

The [AS241 replacement report](results-inverse-normal.md) records the changed
public inverse values, independent refinements, IV consumer behavior and costs.
It is a numerical minor change under the existing stability policy, with no
version bump or release in this PR. The earlier owner acceptance does not
implicitly accept this later implementation. Historical rights findings and
notices remain; #64 needs a final source/artifact audit and exact-main-candidate
qualification after the stacked changes land.
