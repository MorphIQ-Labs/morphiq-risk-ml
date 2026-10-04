# Integrated fast and certified candidate qualification

Candidate: `f703546ea736d456f64e74be6ef9d2da2c10ef88` (merged PR #102).
Package: **0.3.0, unreleased**. Engineering assessor: Codex, executing the
maintainer's qualification instruction. This record covers a pinned source
artifact; it is not independent human review or deployment/release approval.
Later documentation/evidence commits do not change the qualified runtime.

## Executed results

[Manual candidate workflow](https://github.com/MorphIQ-Labs/morphiq-risk-ml/actions/runs/37238843530) and
[exact-main CI](https://github.com/MorphIQ-Labs/morphiq-risk-ml/actions/runs/37238293731) both pass for this exact source.

| Check | Result |
| --- | --- |
| Development build, format and ordinary suite | Pass on Ubuntu x86-64, Ubuntu ARM64 and macOS ARM64 |
| Release ordinary suite | Pass on all three platforms in the exact-main CI run |
| Deterministic source archive and isolated installation | Pass; byte-identical source archives on all three platforms |
| Installed public API consumers, including Fast batch/planner | Native and bytecode pass on all three platforms |
| Installed Exchange corpus | 649 identical qualified outcomes per mode/platform: 625 served, 10 numerical failures, 5 accuracy refusals, 7 invalid inputs, 2 invalid-accuracy controls |
| Canonical certified portfolio replay | 720 rows / 8,640 price, Greek and IV outcomes match per platform |
| Full curated mutation catalog | Clean baseline and all 96 compiled probes killed by their designated guards |
| Installed notices | All ten files match source bytes on all three platforms |

Source archive SHA-256: `14d6829fce370610363cb1012376ccceab5b510cdfd52574aa0c3f59dadeaeff`.
The [collector receipt](evidence/qualified-fast-candidate/receipt.json) verifies
archive bytes against a fresh `git archive`, exact platform/job membership,
source/consumer/reference/lock/notice hashes and mutation membership/guards.
It rejects all 12 deliberately corrupted workflow, artifact, replay and
mutation controls. The [experimental integrity record](evidence/qualified-fast-candidate/dossier.json)
indexes the retained evidence. Local build/install/format and receipt integrity
checks also pass; no numerical runtime source changes in this closeout.


## Changes since the previous qualified candidate

The previous [optimized Exchange candidate](candidate-exchange-optimized.md)
was `d9967018b219f8b68c0e485e5a78a7973a101a1c`. Its reports remain unchanged.
The [library delta inventory](evidence/qualified-fast-candidate/source-deltas.json)
fingerprints every changed library source between that baseline and this one.

| Change | Contract and source-bound evidence | Review obligation |
| --- | --- | --- |
| Shared certified preparation (#91) | [Preparation contract](shared-certification.md), [measurements and replay](results-shared-certification.md) | Check grouping identity, original inputs, per-output limits and independent failure propagation. |
| Shared Greek intermediates (#92) | [Dependency design](shared-greek-intermediates.md), [qualification](results-shared-greeks.md) | Check lazy ownership, coordinate-specific formulas and partial-output failures. |
| Ordered exact sums and packed storage (#93–94) | [Sum analysis](results-certified-expansion-sums.md), [allocation qualification](results-certification-allocation.md), [runtime enclosures](runtime-enclosures.md) | Check exact-sum preconditions, finite exponents, low words, private scratch bounds and outward radii across IV/Exchange/Greek consumers. |
| Compiled fast batches (#99) | [Fast batch contract](fast-batch.md), [evidence](results-fast-batch.md) | Separate approximate results from certificates; check frozen admission, ordered failures, output ownership and concurrent reuse. |
| Fast scenario streaming (#100–101) | [Fast planner contract](fast-planner.md), [integration qualification](fast-integration-qualification.md) | Check shared scheduling, bounded tiles, original option side, time mapping, cancellation, sink failure and separation from certified totals. |
| Native DD allocation (#102) | [Profiles and compatibility](results-fast-allocation.md), [backend contract](numerical-backend-contract.md) | Check operation order and compiler assumptions in both profiles/modes; preserve the reported bytecode allocation tradeoff. |

Stable existing certified signatures remain; additive grouped/fast APIs and
unstable internal storage changes require review. The fast API offers approximate
finite nonnegative prices with explicit failures, not runtime error radii.
`Planner.Fast` emits unweighted prices with quantity metadata, not synthetic
certificates or portfolio totals. Certified `Production`/Batch/Planner and IV
retain their separate acceptance contracts. Scalar Exchange still has no Greeks,
inverse API or portfolio adapter.

## Evidence scope and retained limitations

The ordinary suite re-exercises independent fixtures, exact-rational guards,
certificates, type rejection and planner failure controls. It covers 99,088
fast batch fixture outcomes and 77,744 planner outcomes whose original
maturities are representable by the civil-day API. The 21,344 other maturities
remain explicit exclusions. Installed public consumers exercise both Fast APIs,
including four-model compiled batch reuse/output isolation and Fast planner
post-expiry outcomes plus one/two-worker replay, in native and bytecode.
Certified planner installation controls additionally cover cancellation, sink
failure and partial totals. These are smoke/control tests, not the entire
fixture or fast-scheduler fault corpus executed against every installed binary.

The canonical replay reuses the independently audited 720-row campaign;
Exchange replay reuses the 649-case qualification, including refusals and invalid
inputs. Neither replay regenerates independent references. The earlier
[adversarial campaign](adversarial-assurance-closeout.md) retains 166 unresolved
references, 281 numerical failures and 17 nonfinite scalar fast prices in its
7,095-request source-bound campaign. Those outcomes are not accuracy successes;
this qualification does not rerun or resolve that full optional campaign.
Batch/Planner Fast explicitly classify nonfinite/negative scalar results as
numerical failures.

Source provenance follows the [current-source closeout](opensource-closeout.md).
Installed notices are verified against this exact source. No new third-party
numerical implementation is introduced by these deltas; the historical
AS241/CALERF/QD rights record and earlier Git history remain distinct.
The [research policy](../AGENTS.md#research-references-and-preservation) keeps
public build/replay independent of private research-library access.

Performance remains tied to each report's source, compiler/profile and workload.
The latest native release mixed-batch measurements show 697 allocated bytes and
0.674 µs amortized execution per price; single-worker scenarios show 2,651 bytes
and 1.425 µs per row. These shared-M1 means are not single-request latency or
cross-platform SLAs. Bytecode ITM pricing allocates 5.1% more after the native
optimization. Four-worker scaling, actual business workload and target-host
operational criteria remain open under #8/#16. Runtime certification retains
material MB-scale allocation.

## Reproduction and retention

Use OCaml 5.3.0 Flambda, the locked dependency graph and ocamlformat 0.27.0.
The library uses `-O3`; record development versus release profiles separately.

```sh
gh workflow run candidate.yml --repo MorphIQ-Labs/morphiq-risk-ml --ref main \
  -f commit=f703546ea736d456f64e74be6ef9d2da2c10ef88
```

The candidate lane performs development build/format/ordinary checks, artifact
installation, native/bytecode public consumers, canonical replay and the full
catalog. The separately retained exact-main `ci` run covers ordinary tests in
both development and release on all three platforms. Full mutation assurance
stays in the manual/scheduled lane; default PR CI still selects seven probes.

Raw receipts, output hashes and compressed logs are retained under
`docs/evidence/qualified-fast-candidate/`. Original downloaded artifacts,
including deterministic source archives, are also retained under
`~/Library/Application Support/MorphIQ Labs/acceptance/morphiq-risk-ml/f703546ea736d456f64e74be6ef9d2da2c10ef88/`.
That local copy is not a public build dependency. Git reproduces the pinned
source archive; compiled files are not claimed identical across platforms.

## Remaining decisions

[Independent review](independent-review-package.md) (#15) still requires an
appointed reviewer, independence/conflict declaration, theorem/call-site review,
findings dispositions and a signed source-specific report. #16 still requires
target-environment operational acceptance and an owner deployment recommendation.
#17 still requires exact-candidate model-validation and release-owner decisions.
The earlier owner approval retains its original source scope. The [current institutional record](acceptance/pending-fast-candidate.json)
remains pending and must fail its acceptance checker. Its evidence/artifact
hashes are checked separately from the missing human/operational decisions.
No version change, release tag, publication or deployment is part of this work.
