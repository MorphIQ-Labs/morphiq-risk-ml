# Research library

This inventory covers the research papers explicitly cited in this repository’s source, documentation, and PR #12 numerical audit at `130ce0a`. It does not recursively collect the bibliographies inside those papers. Downloaded files are the original PDFs, with their notices and cover pages intact. Their original terms apply; they are not relicensed under the project’s source-code license.

As of 2026-10-02: **all 11 identified cited papers are archived**, plus **2 supplemental reports** (13 PDFs, 338 pages, about 9.7 MB). The collection has no outstanding paper-retrieval gaps. Cody (1969) and Tang (1989) were supplied by the user after automated publisher downloads failed.

## File naming

All PDFs use `YYYY-first-author-short-title[-version].pdf`: publication year, the first author’s surname, and a concise title, in lowercase ASCII separated by hyphens. HAL revisions, dated author revisions, and report identifiers remain explicit suffixes. The manifest preserves full author lists, exact titles, publication details and archived version dates. Renaming does not change the PDF bytes or their SHA-256 hashes.

## Cited papers

| Paper / local PDF | Archived version and source | Cited by |
| --- | --- | --- |
| [Mioara Joldes; Jean-Michel Muller; Valentina Popescu (2017), *Tight and rigorous error bounds for basic building blocks of double-word arithmetic*](2017-joldes-double-word-error-bounds-hal-v3.pdf) | HAL v3; [download source](https://hal.science/hal-01351529v3/document); [DOI](https://doi.org/10.1145/3121432) | [`lib/dd.ml`](../../lib/dd.ml), [`lib/dd.mli`](../../lib/dd.mli), [`docs/error-analysis.md`](../../docs/error-analysis.md), [`CHANGELOG.md`](../../CHANGELOG.md) |
| [Jean-Michel Muller; Laurence Rideau (2022), *Formalization of double-word arithmetic, and comments on “Tight and rigorous error bounds for basic building blocks of double-word arithmetic”*](2022-muller-double-word-formalization-hal-v2.pdf) | HAL v2; [download source](https://hal.science/hal-02972245v2/document); [DOI](https://doi.org/10.1145/3484514) | [`docs/error-analysis.md`](../../docs/error-analysis.md) |
| [Vincent Lefèvre; Nicolas Louvet; Jean-Michel Muller; Joris Picot; Laurence Rideau (2023), *Accurate calculation of Euclidean norms using double-word arithmetic*](2023-lefevre-double-word-euclidean-norms-hal-v2.pdf) | HAL v2; [download source](https://hal.science/hal-03482567v2/document); [DOI](https://doi.org/10.1145/3568672) | [`lib/dd.ml`](../../lib/dd.ml), [`lib/dd.mli`](../../lib/dd.mli), [`docs/error-analysis.md`](../../docs/error-analysis.md), [`CHANGELOG.md`](../../CHANGELOG.md) |
| [Sylvie Boldo; Claude-Pierre Jeannerod; Guillaume Melquiond; Jean-Michel Muller (2023), *Floating-point arithmetic*](2023-boldo-floating-point-arithmetic.pdf) | Acta Numerica 32, 203–290; publisher PDF; [download source](https://www.cambridge.org/core/services/aop-cambridge-core/content/view/287C4D5F6D4A43FBEEB1ABED2A405AAF/S0962492922000101a.pdf/floatingpoint_arithmetic.pdf); [DOI](https://doi.org/10.1017/S0962492922000101) | [`docs/error-analysis.md`](../../docs/error-analysis.md) |
| [Peter Jäckel (2015), *Let’s be rational*](2015-jaeckel-lets-be-rational-rev-2016-03-25.pdf) | Author revision dated 2016-03-25; first version 2013-11-24; [download source](http://www.jaeckel.org/LetsBeRational.pdf) | [`lib/lbr.ml`](../../lib/lbr.ml), [`lib/lbr.mli`](../../lib/lbr.mli), [`lib/normalised_black.ml`](../../lib/normalised_black.ml), [`SLICE.md`](../../SLICE.md), [`docs/error-analysis.md`](../../docs/error-analysis.md), [`docs/results-iv.md`](../../docs/results-iv.md), [`docs/results-pricing.md`](../../docs/results-pricing.md) |
| [Peter Jäckel (2017), *Implied Normal Volatility*](2017-jaeckel-implied-normal-volatility-rev-2017-06-06.pdf) | Author revision dated 2017-06-06; first version 2016-12-02; [download source](http://www.jaeckel.org/ImpliedNormalVolatility.pdf) | [`SLICE.md`](../../SLICE.md) |
| [Michael J. Wichura (1988), *Algorithm AS 241: The Percentage Points of the Normal Distribution*](1988-wichura-as241-normal-percentage-points.pdf) | Journal scan with JSTOR cover; university-hosted copy; [download source](https://csg.sph.umich.edu/abecasis/gas_power_calculator/algorithm-as-241-the-percentage-points-of-the-normal-distribution.pdf); [DOI](https://doi.org/10.2307/2347330) | [`lib/normal.ml`](../../lib/normal.ml), [`lib/normal.mli`](../../lib/normal.mli), [`SLICE.md`](../../SLICE.md) |
| [George Marsaglia (2004), *Evaluating the Normal Distribution*](2004-marsaglia-evaluating-normal-distribution.pdf) | Journal of Statistical Software 11(4), 1–11; publisher PDF; [download source](https://www.jstatsoft.org/index.php/jss/article/download/v011i04/13); [DOI](https://doi.org/10.18637/jss.v011.i04) | [`lib/normal_dd.ml`](../../lib/normal_dd.ml), [`docs/error-analysis.md`](../../docs/error-analysis.md), [`docs/results-greeks.md`](../../docs/results-greeks.md) |
| [T. J. Dekker (1971), *A Floating-Point Technique for Extending the Available Precision*](1971-dekker-extending-floating-point-precision.pdf) | Numerische Mathematik 18, 224–242; university-hosted journal scan; [download source](https://csclub.uwaterloo.ca/~pbarfuss/dekker1971.pdf); [DOI](https://doi.org/10.1007/BF01397083) | [`lib/dd.ml`](../../lib/dd.ml) |
| [Ping Tak Peter Tang (1989), *Table-driven implementation of the exponential function in IEEE floating-point arithmetic*](1989-tang-table-driven-exponential.pdf) | ACM TOMS 15(2), 144–157; user-supplied original journal PDF; [publisher PDF](https://dl.acm.org/doi/pdf/10.1145/63522.214389); [DOI](https://doi.org/10.1145/63522.214389) | [`lib/elementary.ml`](../../lib/elementary.ml) |
| [W. J. Cody (1969), *Rational Chebyshev approximations for the error function*](1969-cody-rational-chebyshev-error-function.pdf) | Mathematics of Computation 23(107), 631–637; user-supplied original journal PDF; [publisher PDF](https://www.ams.org/mcom/1969-23-107/S0025-5718-1969-0247736-4/S0025-5718-1969-0247736-4.pdf); [DOI](https://doi.org/10.1090/S0025-5718-1969-0247736-4) | [`lib/cody.ml`](../../lib/cody.ml), [`SLICE.md`](../../SLICE.md) |

The review cited as “Muller, Floating-point arithmetic” has four authors: Boldo, Jeannerod, Melquiond and Muller. The index records the full authorship. The three HAL PDFs and *Let’s be rational* match the exact SHA-256 values already recorded in [the source audit](../error-analysis.md#pr-12-source-and-assumption-audit).

Jäckel’s filenames use the cited publication year; the version dates printed inside the saved PDFs are recorded separately above. *Implied Normal Volatility* is a reference from the slice specification; the current Bachelier solver is a custom bracketed Newton solver, not a literal implementation of that paper’s analytic inverse. Archiving a reference does not extend any certification claim.

## Supplemental reports

| Local PDF | Source and relationship |
| --- | --- |
| [T. J. Dekker (1970), *A floating-point technique for extending the available precision*](1970-dekker-extending-floating-point-precision-cwi-report.pdf) | [Source](https://ir.cwi.nl/pub/9159/9159D.pdf). The institution’s original report preceding the separately archived 1971 journal article. |
| [Yozo Hida; Xiaoye S. Li; David H. Bailey (2008), *Library for Double-Double and Quad-Double Arithmetic*](2008-hida-double-double-quad-double-arithmetic.pdf) | [Source](https://www.davidhbailey.com/dhbpapers/qd.pdf). Documentation for the cited QD implementation; added as supporting material, not a previously cited proof of our elementary-function bounds. |

## User-supplied papers

Automated downloads of Cody (1969) and Tang (1989) failed at their publisher endpoints. The user supplied `S0025-5718-1969-0247736-4-2.pdf` and `63522.214389.pdf`, respectively. Both were verified against the paper title, author, date and page range before archiving unchanged. Their manifest entries identify this acquisition route separately from their canonical publisher URLs. Both retrieval gaps are now closed.

## Books and implementation references

These references are recorded separately because they are not research-paper PDFs:

- **Cody and Waite (1980), *Software Manual for the Elementary Functions*.** Book cited in `lib/elementary.ml`; no book PDF is archived.
- **Knuth’s TwoSum.** `lib/elementary.ml` and `lib/split.ml` name Knuth without a book edition. The usual reference is *The Art of Computer Programming*, volume 2, *Seminumerical Algorithms*. No edition is inferred or book PDF archived; the collected DD papers discuss the transformation.
- **Cody CALERF (1990).** This is the revision date of the [Netlib implementation](https://netlib.org/specfun/erf), not an additional 1990 paper.
- **fdlibm.** [Canonical `s_log1p.c`](https://netlib.org/fdlibm/s_log1p.c); source code rather than a paper. The shorthand “fdlibm/Tang 1989” does not make Tang’s algorithm a proof of this implementation.
- **QD 2.3.24.** [Pinned `dd_real.cpp`](https://github.com/BL-highprecision/QD/blob/v2.3.24/src/dd_real.cpp); the supporting 2008 report is archived above.
- **Let’s Be Rational reference implementation.** [Author source archive](http://www.jaeckel.org/LetsBeRational.7z); its audit hash remains in `docs/error-analysis.md`. This PDF collection does not vendor the source archive.

## Integrity and provenance

[manifest.json](manifest.json) records titles, authors, publication years, archived versions, original download URLs, citation locations, retrieval date, sizes, page counts, and SHA-256 hashes. The previously audited PDFs were copied unchanged from the source-audit downloads made earlier on 2026-10-02. Other PDFs were retrieved or supplied by the user on the same date. Cody’s and Tang’s manifest entries distinguish their user-supplied acquisition from the canonical publisher URLs. University-hosted scans are identified as such.

Validate all saved PDF bytes locally:

```sh
cd docs/research
shasum -a 256 -c SHA256SUMS
```

Each PDF was parsed with Poppler, its full text extracted, and its first page rendered and inspected to check document identity. That validates the archive files, not the papers’ mathematical claims. PDF downloads are not part of builds or CI.
