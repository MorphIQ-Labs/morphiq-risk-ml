# Optimized Exchange candidate qualification

Candidate: `d9967018b219f8b68c0e485e5a78a7973a101a1c`. Engineering assessor: Codex, executing the maintainer's
closeout instruction. [Candidate workflow](https://github.com/MorphIQ-Labs/morphiq-risk-ml/actions/runs/37222093671).
This is a source-bound experimental qualification, not independent human review
or institutional deployment/release approval. Package version remains 0.3.0.

## Executed results

| Check | Result |
| --- | --- |
| Build, format and ordinary suite | Pass on Ubuntu x86-64, Ubuntu ARM64 and macOS ARM64 |
| Source archive and isolated package installation | Pass; source archive bytes identical on all three platforms |
| Installed existing scalar/Batch/Scenario/Planner and Exchange smoke | Native and bytecode pass on all three platforms |
| Installed full Exchange corpus | All 649 outcomes/value/radius rows match in each of six platform/compiler-mode runs |
| Exchange outcome accounting per run | 625 served, 10 numerical failures, 5 accuracy refusals, 7 invalid inputs, 2 invalid-accuracy controls |
| Canonical certified portfolio replay | 720 rows / 8,640 price/Greek/IV outcomes matched per platform |
| Full curated mutation catalog | Clean baseline; all 84 compiled mechanisms killed by designated numerical guards |
| Installed notices | All ten files match source bytes on all three platforms |

Source archive SHA-256: `32a6a3c19fdc5b1db6e63debf415ac1dca109b2f642b51b70a8436715a2d0a30`.
Exchange output SHA-256: `0b9430f73d941565f194a416837294d12de2316883f9a1db2686a2a20827ab0a`.
The local collector also compares decompressed archives with a fresh `git archive`
of the candidate and rejects missing modes, wrong counts/hashes and changed output.
Seven deliberately corrupted receipt/output controls are rejected.

## Evidence and inheritance

The [receipt](evidence/qualified-exchange-candidate/receipt.json),
[artifact inventory](evidence/qualified-exchange-candidate/SHA256.json), per-platform
reports, raw native/bytecode outputs and compressed build/test/mutation logs are
retained under `docs/evidence/qualified-exchange-candidate/`. Original downloaded
artifacts are additionally preserved locally under
`~/Library/Application Support/MorphIQ Labs/acceptance/morphiq-risk-ml/d9967018b219f8b68c0e485e5a78a7973a101a1c/`.
Private storage is not a public build dependency; the pinned Git source reproduces
the archive. Compiled binaries are not claimed identical across platforms.

The [Exchange qualification](exchange-qualification.md) supplies the independently
bounded references, canonical discrepancies and availability limits. This campaign
replays those qualified outcomes; it does not regenerate the independent references.
The [allocation report](results-certificate-allocation.md) establishes the storage
change, exact replay and local paired measurements. No new cross-platform timing
claim is made. The [earlier adversarial handoff](adversarial-assurance-closeout.md)
and its unresolved references remain source-bound; this receipt does not rerun or
resolve them. [Independent review](independent-review-package.md) still must assess
the Exchange and shared-enclosure deltas at actual call sites.

## Reproduction and remaining obligations

Use the candidate's own `scripts/candidate_artifact.py`, a fresh output directory,
and the pinned OCaml 5.3.0 Flambda toolchain. For the full manual matrix:

```sh
gh workflow run candidate.yml --repo MorphIQ-Labs/morphiq-risk-ml --ref main \
  -f commit=d9967018b219f8b68c0e485e5a78a7973a101a1c
```

Follow [installed Exchange validation](installed-exchange-validation.md) and
[mutation policy](mutation-policy.md). Default PR CI still selects seven core
mutants. This documentation receipt changes no runtime source or expected result.
It does not tag, publish or accept a release. Independent human review (#15),
operational workload/requirements (#8/#16), and exact-candidate owner decisions
(#17) remain open; the prior owner approval is not extended by automation.
