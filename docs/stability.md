# Stability policy

The library follows [semantic versioning](https://semver.org). The version is in `dune-project` and `Morphiq_risk.version`. Releases are tagged `vX.Y.Z` from `main`.

## What the policy covers

Everything exported by `Morphiq_risk` except `Morphiq_risk.Internal`. `Internal` exposes numerical building blocks for testing and research and may change in any release.

## Served values are part of the contract

For a pricing library, a release that changes a number a caller receives is as consequential as one that changes a signature. Every change is classified by both its API effect and its numerical effect.

| Change | Version |
| --- | --- |
| Removing or changing an exported signature, record field or variant | major |
| Changing a model definition (docs/model-contracts.md), such as a convention, a refusal or an outcome class | major |
| Adding a variant to an exhaustive outcome type (`Iv.t`, `Refusal.t`, `Greeks.why`), which breaks callers' matches | major |
| A served value moves by more than its region's published ULP budget, or changes sign, class or refusal | major, with per-row evidence |
| A served value moves within its budget (improved rounding, a tighter method) | minor, with the measured before/after worst error per region |
| New models, quantities or functions | minor |
| Documentation, tests, oracles and internals with no served-value change | patch |

While the version is `0.y.z`, majors are expressed as minors, per semver. The classification and evidence requirements apply from the first release.

## Evidence for numerical changes

Any change to a served value lists, in `CHANGELOG.md`:
- the regions affected;
- the worst error before and after against the oracles, using the tables in `docs/results-*.md`;
- the oracle commit or generator version it was measured against.

A change that relaxes a budget states why the tighter budget cannot be held. "The test failed" is not a reason.
