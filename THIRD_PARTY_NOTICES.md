# Third-party notices and provenance

The Apache-2.0 license in [LICENSE](LICENSE) covers original contributions to
this project. It does not replace upstream terms, license research publications,
or establish that every referenced implementation has been cleared for reuse.
The source audit was updated on 2026-10-03 against implementation commit
`9f792d6b2a46b9e49256ec51810b915358d50d18`. The [provenance report](docs/source-provenance.md)
records the actual downloaded sources, development chronology and hashes.

## Retained notices

| Material | Project use | Notice |
| --- | --- | --- |
| Peter Jäckel, Let's Be Rational, 2024 reference revision | Derived portions in `lib/lbr.ml`, `lib/normalised_black.ml`, and the generated polynomial replay from `oracle/lift_polynomials.py` | [Upstream permission and warranty notice](LICENSES/LetsBeRational.txt); existing source headers remain intact |
| QD 2.3.24 author-hosted tarball, Hida, Li, and Bailey | Historical exponential adaptation, now replaced in `lib/dd.ml` by the [project-derived polynomial](docs/results-dd-exponential-optimization.md); retained notices identify earlier versions | [Original COPYING](LICENSES/QD-COPYING.txt), [original license DOC](LICENSES/QD-BSD-LBNL-License.doc), and [complete text extraction](LICENSES/QD-BSD-LBNL-License.txt); terms review remains open |
| Wichura AS241 / Royal Statistical Society | Adapted inverse-normal regions and coefficient evaluation in `lib/normal.ml` | [StatLib distribution notice](LICENSES/AS241-StatLib.txt); no unrestricted grant established |
| Cody CALERF, March 19, 1990 | Historical adaptation, replaced by [project-generated error functions](docs/error-function-replacement.md) in `lib/cody.ml` | Original author attribution retained; no explicit grant in the inspected source/README |
| Sun fdlibm | `lib/elementary.ml` references the split logarithm constant, tiny-input rule, and related elementary-function constructions | [Sun permission notice](LICENSES/Sun-fdlibm.txt) |

Sources:

- [Jäckel's source archive](http://www.jaeckel.org/LetsBeRational.7z). The source audit in [error-analysis.md](docs/error-analysis.md#pr-12-source-and-assumption-audit) records the numerical reference provenance. The license text here matches the notice already retained in the derived OCaml files.
- [QD 2.3.24 original tarball](https://www.davidhbailey.com/dhbsoftware/qd-2.3.24.tar.gz). Its actual license-bearing files differ from the GitHub v2.3.24 notices retained in PR #65; this audit corrects that mismatch explicitly.
- [AS241 source](https://lib.stat.cmu.edu/apstat/241) and [StatLib policy](https://lib.stat.cmu.edu/apstat/index).
- [CALERF source](https://netlib.org/specfun/erf) and [SPECFUN README](https://netlib.org/specfun/readme).
- [Canonical fdlibm `s_log1p.c`](https://netlib.org/fdlibm/s_log1p.c), including the Sun copyright and permission notice.

The preserved notices travel with installed documentation as well as source
archives. Listing an algorithm reference does not assert that the entire file
is a literal port. Conversely, citing a paper alone does not establish reuse
permission for source code adapted from an implementation.

## Distribution status and replacement decision

The actual sources are identified: the original development record shows
CALERF and AS241 downloaded and read before the OCaml files were written, and
QD's exponential implementation read before adaptation. These are not
paper-only provenance claims. See the [source audit](docs/source-provenance.md)
for the exact scope and preserved fingerprints.

1. **AS241:** StatLib's policy attributes copyright to the Royal Statistical
   Society and makes its distribution permission conditional on no fee.
   Unrestricted downstream redistribution under the project's intended model
   is not established. R's separately obtained permission does not cover us
   by inference.
2. **CALERF:** the actual Netlib source and README have no explicit grant.
   Related SPECFUN material is listed by ACM CALGO; the terms applicable to this
   Netlib copy remain unresolved. Do not infer a license from another package
   or from downstream reuse. The current implementation and tables have been replaced from mathematical definitions; this does not grant permission for historical versions.
3. **QD:** the original tarball's COPYING and BSD-LBNL-License.doc are now
   retained, replacing the mismatched GitHub-derived notices. The agreement's
   scope and commercial-contact language remain unresolved; this is not
   represented as an ordinary verified BSD-3-Clause grant. The current
   exponential has been replaced by independently generated coefficients and a
   project-derived operation graph; this does not relicense historical versions.

The maintainer selected [replacements with documented provenance](docs/numerical-replacement-plan.md).
Issue [#64](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/64) stays open
until that work is qualified. Retaining notices does not establish clearance.
Numerical replacements require independent references, compatibility evidence,
updated certificates, and unchanged assurance requirements. The [DD exponential replacement](docs/results-dd-exponential-optimization.md) changes the
current implementation. The [error-function replacement](docs/results-error-functions.md) replaces CALERF; AS241 remains pending. No release, outreach
or signing of an upstream agreement is implied.

## Research publications and historical evidence

The [bibliography](docs/research/README.md) links to original sources. Downloaded
PDFs are preserved in the private research library described in the bibliography
and excluded from the current tracked tree; optional local copies retain
their original bytes and notices. The acquisition manifest and SHA-256 list
identify the exact versions used for research and do not grant redistribution
rights. Earlier commits and existing clones may still contain the PDFs; this
change does not rewrite history.

Project-generated fixtures and numerical reports retain their provenance in
`oracle/MANIFEST` and `docs/evidence/`. Restricted third-party inputs downloaded
for an optional comparison belong in ignored `oracle/data/`, not a release.
The optional `oracle/canonical_iv.py` comparison can still compile externally
acquired `erf_cody.cpp` from the canonical archive; it is not vendored and is
not required by the build or ordinary CI.

## Dependencies and optional comparison tools

OCaml, opam, Dune, Zarith, the test libraries, mpmath, FLINT/Arb, QuantLib, and
optional comparison implementations have their own licenses. Dependency pins
and generator provenance are not substitutes for those terms. The project does
not vendor or relicense those complete dependencies through Apache-2.0.

FerroRisk code/data remain governed by that separate project's terms. Its
optional comparison scripts do not make it a build or runtime dependency, and
this project's license grants no rights to it or other MorphIQ Labs projects.
