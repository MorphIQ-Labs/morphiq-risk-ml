# Third-party notices and provenance

The Apache-2.0 license in [LICENSE](LICENSE) covers original contributions to
this project. It does not replace upstream terms, license research publications,
or establish that every referenced implementation has been cleared for reuse.
This inventory was checked on 2026-10-03 against source commit
`8125b70fa0c3fa62ab74d81196010545451c5796` and the upstream sources below.

## Retained notices

| Material | Project use | Notice |
| --- | --- | --- |
| Peter Jäckel, Let's Be Rational, 2024 reference revision | Derived portions in `lib/lbr.ml`, `lib/normalised_black.ml`, and the generated polynomial replay from `oracle/lift_polynomials.py` | [Upstream permission and warranty notice](LICENSES/LetsBeRational.txt); existing source headers remain intact |
| QD 2.3.24, Hida, Li, and Bailey | `lib/dd.ml` explicitly follows `dd_real.cpp` exponential reduction and stopping logic, with documented differences | [BSD-3-Clause license](LICENSES/QD-BSD-3-Clause.txt) and [upstream COPYRIGHT/COPYING text](LICENSES/QD-COPYING.txt), retained verbatim |
| Sun fdlibm | `lib/elementary.ml` references the split logarithm constant, tiny-input rule, and related elementary-function constructions | [Sun permission notice](LICENSES/Sun-fdlibm.txt) |

Sources:

- [Jäckel's source archive](http://www.jaeckel.org/LetsBeRational.7z). The source audit in [error-analysis.md](docs/error-analysis.md#pr-12-source-and-assumption-audit) records the numerical reference provenance. The license text here matches the notice already retained in the derived OCaml files.
- QD v2.3.24: [implementation](https://github.com/BL-highprecision/QD/blob/v2.3.24/src/dd_real.cpp), [LICENSE](https://github.com/BL-highprecision/QD/blob/v2.3.24/LICENSE), and [COPYING](https://github.com/BL-highprecision/QD/blob/v2.3.24/COPYING).
- [Canonical fdlibm `s_log1p.c`](https://netlib.org/fdlibm/s_log1p.c), including the Sun copyright and permission notice.

The preserved notices travel with installed documentation as well as source
archives. Listing an algorithm reference does not assert that the entire file
is a literal port. Conversely, citing a paper alone does not establish reuse
permission for source code adapted from an implementation.

## Outstanding provenance review

These items remain open before a release is described as fully cleared for
third-party distribution. They are specific provenance questions, not findings
that all uses of the mathematical algorithms are restricted.
Tracked in [#64](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/64), under
the experimental baseline Epic #47.

1. **AS241 (`lib/normal.ml`).** The file identifies Wichura's 1988 algorithm and
   retains its coefficient/region structure, but the repository does not record
   the exact implementation source or a permission applicable to this project.
   Establish whether this is an independent implementation from the publication
   or an adaptation requiring upstream permission, and retain the evidence.
   The [R maintainers' first-person account](https://stat.ethz.ch/pipermail/r-devel/2010-February/056608.html)
   records that R sought permission from the Royal Statistical Society; R's
   permission must not be assumed to cover this project. The
   [canonical StatLib location](https://lib.stat.cmu.edu/apstat/241) could not be
   retrieved during this audit. Do not infer terms from an unrelated mirror.
2. **Cody CALERF (`lib/cody.ml`).** The source cites the published coefficients
   and [Netlib CALERF](https://netlib.org/specfun/erf). Neither that file nor the
   [SPECFUN README](https://netlib.org/specfun/readme) supplied an explicit license
   grant in this audit. Record the implementation's provenance and applicable
   terms rather than applying a license from another Netlib package.
3. **QD scope (`lib/dd.ml`).** Retain both upstream files above. `COPYING`
   includes additional attribution and commercial-contact language. Establish
   which portions, if any, were adapted from code rather than independently
   implemented mathematical constructions, and resolve the applicable terms
   without silently dropping either upstream notice.

Any replacement made to resolve provenance needs the ordinary numerical
change-control process: independent references, compatibility evidence, and
unchanged assurance requirements. A licensing cleanup is not authorization to
substitute numerical kernels silently.

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

## Dependencies and optional comparison tools

OCaml, opam, Dune, Zarith, the test libraries, mpmath, FLINT/Arb, QuantLib, and
optional comparison implementations have their own licenses. Dependency pins
and generator provenance are not substitutes for those terms. The project does
not vendor or relicense those complete dependencies through Apache-2.0.

FerroRisk code/data remain governed by that separate project's terms. Its
optional comparison scripts do not make it a build or runtime dependency, and
this project's license grants no rights to it or other MorphIQ Labs projects.
