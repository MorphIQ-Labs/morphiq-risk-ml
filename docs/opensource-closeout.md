# Current-source open-source closeout

This audit applies to the experimental 0.3.0 source distribution after the three
numerical replacements, not to earlier Git commits. The exact candidate and
validation receipts are recorded in the [experimental baseline](experimental-baseline.md).
The [original source audit](source-provenance.md) remains the historical record.
Original contributions use Apache-2.0; retained third-party portions use their
preserved permissions. No replacement is described as clean-room work.

## Source and terms disposition

| Material | Current disposition | Evidence |
| --- | --- | --- |
| AS241 | Its tables and reductions are replaced by project-derived, bounded Gaussian inversion | [Construction](inverse-normal-replacement.md), [qualification](results-inverse-normal.md), [optimization](results-inverse-optimization.md); PRs #69–70 |
| CALERF | Its coefficient tables and branches are replaced by generated Gaussian-integral approximations and rational bounds | [Construction](error-function-replacement.md), [qualification](results-error-functions.md); PR #68 |
| QD exponential | Its reduction, recurrence and stopping rule are replaced by project-generated Taylor/Horner arithmetic | [Replacement](results-dd-exponential.md), [optimization](results-dd-exponential-optimization.md); PR #67 |
| Let's Be Rational | Retained kernel formulas, thresholds and solver/rational interpolation adaptations in `lib/normalised_black.ml`, `lib/lbr.ml`, and generated polynomial replay | Complete 2013–2024 permission and warranty notice in [LICENSES](../LICENSES/LetsBeRational.txt), both source headers and generated replay |
| fdlibm | Retained split-logarithm constants and elementary constructions in `lib/elementary.ml` | Complete Sun permission notice in the source header and [LICENSES](../LICENSES/Sun-fdlibm.txt) |
| Numerical derivations, generators, fixtures and certificates | Project material with primary mathematical references and recorded generator provenance | [Error analysis](error-analysis.md), [oracle methodology](oracles.md), `oracle/MANIFEST`, replacement reports |

The retained Let's Be Rational notice was compared with the source header in
the original author's archive, SHA-256
`da2f6870b213e04ef35b4d309269ee5ce12be5830d9733e5f29542bf7b652470`,
acquired 2026-10-02 and already identified in the numerical audit. The Sun
notice was checked against [Netlib s_log1p.c](https://netlib.org/fdlibm/s_log1p.c),
retrieved 2026-10-04, SHA-256
`f72f255a022fad06c3fe222ad90f961ac5624958373a4fbdae9df3f344135373`.
Their permissions require preserving the notice; they do not impose the
historical AS241 no-fee condition. Generated replay now carries the complete
upstream notice, including its warranty disclaimer.

The review covers library sources, C primitives, generators, scripts, tests,
optional experiments, coefficient tables, and tracked compressed evidence.
The [audit inventory](evidence/opensource-source-inventory.json) fingerprints
that scope. Searches for historical routine names and characteristic arithmetic
were combined with inspection of replacement constructions and compressed
contents; keyword absence alone is not a provenance determination. Historical
comparison values and measurements remain evidence, not active old algorithms.

Two overlooked experiment artifacts were found and removed from the current
tree: the portable patch still contained the old QD reduction/accumulation;
the full OxCaml 5.2 opam export embedded base64-encoded third-party source
patches. Unchanged originals were preserved and hash-verified in private
research-library PR #4 before removal. Their [public disposition record](evidence/retired-experiment-artifacts.json)
retains exact hashes, sizes and acquisition paths. The public compiler/package
pins and measured evidence remain available; current builds need no private
access. The portable preparation option fails explicitly until a new patch is
independently qualified. The 5.4 export contains package metadata without an
embedded `extra-files` source payload and remains a historical dependency record.

## Dependencies and distribution

There is no third-party OCaml runtime library dependency beyond the OCaml
standard runtime: `morphiq_fp` is this project's C primitive. OCaml 5.3 uses
LGPL-2.1-or-later with its OCaml linking exception; Dune and test/oracle tools are build-time
or optional dependencies, not vendored implementations. The pinned opam graph
remains in `morphiq_risk_ml.opam.locked`. Installing those tools retains their
own package terms; this project's Apache license does not replace them.
Zarith/GMP and Python oracle dependencies are not imported by the public library.

Source distributions retain LICENSE, NOTICE, THIRD_PARTY_NOTICES and LICENSES.
The artifact verifier checks installed copies against the source bytes,
including all historical notices; missing or changed copies fail. A source
archive is built from an immutable Git commit, not the developer's working tree.
Downloaded papers, external comparison sources and build output are excluded.
The optional `scripts/canonical_iv.py` requires separately acquired source and
can compile upstream CALERF for comparison; that code is not vendored, linked
into the library or needed by ordinary builds.

Historical AS241, CALERF and QD permissions remain unresolved for older source
versions. Removing current adaptations does not erase history, relicense old
archives or authorize further distribution of historical artifacts. Current
source closeout is an engineering provenance assessment, not an upstream
agreement or a claim that every historical distribution was cleared.

## Repository readiness

The README describes the current API and directs callers to explicit numerical
failures. [SECURITY.md](../SECURITY.md) provides the private reporting route;
GitHub private vulnerability reporting is enabled. Main remains protected by
pull requests and all five required CI checks, while supporting solo-maintainer
merges. Exact-candidate qualification runs separately from the seven-mutant PR
lane. No release tag, package publication or institutional acceptance follows
merely from these checks.
