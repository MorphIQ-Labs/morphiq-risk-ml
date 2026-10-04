# Research bibliography

This bibliography identifies publications used in the numerical implementation
and its analysis. Follow the original-source links below to obtain a paper under
the source’s terms. PDFs are not bundled with the current source tree.

The [acquisition manifest](manifest.json) and [SHA-256 list](SHA256SUMS) retain
the exact versions inspected in the original research campaigns. They describe
historical acquisitions, not redistribution permissions or files required for a
build. Historical `cited_in` paths, including the retired `SLICE.md`, refer to
prior revisions; see the [original proposal](https://github.com/MorphIQ-Labs/morphiq-risk-ml/blob/8125b70fa0c3fa62ab74d81196010545451c5796/SLICE.md).

## Publications

| Publication | Version inspected | Original source |
| --- | --- | --- |
| Louis Bachelier (1900), *Théorie de la spéculation* | Annales scientifiques de l’École Normale Supérieure, série 3, tome 17, 21–86; original French article with NUMDAM cover | [Source](https://www.numdam.org/item/ASENS_1900_3_17__21_0.pdf) |
| W. J. Cody (1969), *Rational Chebyshev approximations for the error function* | Mathematics of Computation 23(107), 631–637; original journal PDF supplied by the user | [Source](https://www.ams.org/mcom/1969-23-107/S0025-5718-1969-0247736-4/S0025-5718-1969-0247736-4.pdf) |
| T. J. Dekker (1970), *A floating-point technique for extending the available precision* | CWI report MR 118/70; predecessor to the cited 1971 journal article | [Source](https://ir.cwi.nl/pub/9159/9159D.pdf) |
| T. J. Dekker (1971), *A Floating-Point Technique for Extending the Available Precision* | Numerische Mathematik 18, 224–242; university-hosted journal scan | [Source](https://csclub.uwaterloo.ca/~pbarfuss/dekker1971.pdf) |
| Fischer Black; Myron Scholes (1973), *The Pricing of Options and Corporate Liabilities* | Journal of Political Economy 81(3), 637–654; Princeton-hosted journal scan with JSTOR cover | [Source](https://www.cs.princeton.edu/courses/archive/fall02/cs323/links/blackscholes.pdf) |
| Robert C. Merton (1973), *Theory of Rational Option Pricing* | The Bell Journal of Economics and Management Science 4(1), 141–183; researcher-hosted journal scan with JSTOR cover | [Source](https://finance.martinsewell.com/option-pricing/Merton1973.pdf) |
| Michael J. Wichura (1988), *Algorithm AS 241: The Percentage Points of the Normal Distribution* | Journal scan with JSTOR cover; university-hosted copy | [Source](https://csg.sph.umich.edu/abecasis/gas_power_calculator/algorithm-as-241-the-percentage-points-of-the-normal-distribution.pdf) |
| Ping Tak Peter Tang (1989), *Table-driven implementation of the exponential function in IEEE floating-point arithmetic* | ACM TOMS 15(2), 144–157; original journal PDF supplied by the user | [Source](https://dl.acm.org/doi/pdf/10.1145/63522.214389) |
| George Marsaglia (2004), *Evaluating the Normal Distribution* | Journal of Statistical Software 11(4), 1–11; publisher PDF | [Source](https://www.jstatsoft.org/index.php/jss/article/download/v011i04/13) |
| Yozo Hida; Xiaoye S. Li; David H. Bailey (2008), *Library for Double-Double and Quad-Double Arithmetic* | Author technical report dated 2008-05-08 | [Source](https://www.davidhbailey.com/dhbpapers/qd.pdf) |
| Peter Jäckel (2015), *Let’s be rational* | Author revision dated 2016-03-25; first version 2013-11-24 | [Source](http://www.jaeckel.org/LetsBeRational.pdf) |
| Peter Jäckel (2017), *Implied Normal Volatility* | Author revision dated 2017-06-06; first version 2016-12-02 | [Source](http://www.jaeckel.org/ImpliedNormalVolatility.pdf) |
| Mioara Joldes; Jean-Michel Muller; Valentina Popescu (2017), *Tight and rigorous error bounds for basic building blocks of double-word arithmetic* | HAL v3 | [Source](https://hal.science/hal-01351529v3/document) |
| Jean-Michel Muller; Laurence Rideau (2022), *Formalization of double-word arithmetic, and comments on “Tight and rigorous error bounds for basic building blocks of double-word arithmetic”* | HAL v2 | [Source](https://hal.science/hal-02972245v2/document) |
| Sylvie Boldo; Claude-Pierre Jeannerod; Guillaume Melquiond; Jean-Michel Muller (2023), *Floating-point arithmetic* | Acta Numerica 32, 203–290; publisher PDF | [Source](https://www.cambridge.org/core/services/aop-cambridge-core/content/view/287C4D5F6D4A43FBEEB1ABED2A405AAF/S0962492922000101a.pdf/floatingpoint_arithmetic.pdf) |
| Vincent Lefèvre; Nicolas Louvet; Jean-Michel Muller; Joris Picot; Laurence Rideau (2023), *Accurate calculation of Euclidean norms using double-word arithmetic* | HAL v2 | [Source](https://hal.science/hal-03482567v2/document) |
| Jonathan Richard Shewchuk (1997), *Adaptive Precision Floating-Point Arithmetic and Fast Robust Geometric Predicates* | Author report CMU-CS-96-140R, dated October 1, 1997; from Discrete & Computational Geometry 18(3), 305–363 | [Source](https://people.eecs.berkeley.edu/~jrs/papers/robustr.pdf) |
| Fredrik Johansson (2016), *Arb: Efficient Arbitrary-Precision Midpoint-Radius Interval Arithmetic* | arXiv:1611.02831v1, 9 November 2016, author preprint | [Source](https://arxiv.org/pdf/1611.02831v1) |

## Unavailable reference

**Fischer Black (1976), The pricing of commodity contracts.** [Publisher](https://www.sciencedirect.com/science/article/pii/0304405X76900246).
No verified PDF was obtained in the campaign recorded on 2026-10-02.
The manifest retains the original retrieval result; this is not a claim about
current availability.

## Books and implementation references

- Cody and Waite (1980), *Software Manual for the Elementary Functions*. No book PDF is distributed.
- Knuth’s TwoSum: *The Art of Computer Programming*, volume 2, *Seminumerical Algorithms*. The source does not pin a book edition.
- [Cody CALERF](https://netlib.org/specfun/erf), March 19, 1990 revision.
- [fdlibm `s_log1p.c`](https://netlib.org/fdlibm/s_log1p.c).
- [QD 2.3.24 `dd_real.cpp`](https://github.com/BL-highprecision/QD/blob/v2.3.24/src/dd_real.cpp).
- [Let’s Be Rational source archive](http://www.jaeckel.org/LetsBeRational.7z).

See [third-party notices](../../THIRD_PARTY_NOTICES.md) for retained source
notices and unresolved provenance questions. A reference to an algorithm does
not itself establish an error bound or a source-code license.

## Preservation and access

The 18 acquired originals are preserved in the private
[MorphIQ Labs research library](https://github.com/MorphIQ-Labs/research-library),
with unchanged bytes and notices, the original acquisition records, and a
catalog of versions, consuming projects and unresolved rights reviews. Stable
document IDs are the canonical filenames in this manifest without `.pdf`.
The archive's project index maps these IDs to `morphiq-risk-ml`.

Library access is optional and restricted; public readers should use the original
source links above. This project retains its own derivations, contracts, tests,
fixtures, generators and validation evidence. Its build and CI do not use the
private library. Research PDFs are durable assets, not disposable planning files.

Publication redistribution rights are reviewed per document, separately from
source-code licensing. A public download URL is not recorded permission to
redistribute. The archive's initial rights records are explicitly unreviewed;
private storage does not settle permission for broader sharing. Papers may be
included publicly when the applicable permission is documented.

## Optional local reference copies

The subsequent #59 exchange-model selection adds Margrabe's **1976 working
paper No. 13-76**, not the later 1978 journal edition. The unchanged 20-page
[institutional scan](https://rodneywhitecenter.wharton.upenn.edu/wp-content/uploads/2014/03/7613.pdf)
is preserved privately as `1976-margrabe-exchange-option-working-paper.pdf`:
SHA-256 `bd6442ef8152a227bac084806e7f057f13e84c60b6213786fc80de6d10f00904`,
412,637 bytes, acquired 2026-10-04. Rights remain unreviewed and public
redistribution is not cleared. The [new acquisition/source inventory](../evidence/model-selection/sources.json)
is separate from the immutable original campaign's manifest and checksum list.
The [selection contract](../first-model-extension.md) records inspected pages,
the explicit continuous-yield extension and pinned canonical implementation.

Existing local PDFs are preserved unchanged and ignored by Git. If you obtain
a reference yourself, keep its original notices and use the canonical filename
in the manifest. To compare local copies with the historical acquisition:

```sh
cd docs/research
shasum -a 256 -c SHA256SUMS
```

This command needs every listed local file and is not a build or CI prerequisite.
Archived versions may differ from the file currently served by an upstream URL.
The manifest retains acquisition routes, page counts, and inspection notes,
including the user-supplied Cody and Tang papers and PDF parser warnings.

Removing tracked copies does not remove them from prior Git history, existing
clones, or old archives. No history rewrite is part of this cleanup.

## Generated error-function mathematics

The replacement derives its coefficients from the defining Gaussian integral,
its moment recurrence and the erfcx differential equation. Consulted online
2026-10-03: NIST DLMF version 1.2.8 (2026-09-15), sections
[7.7](https://dlmf.nist.gov/7.7), [7.9](https://dlmf.nist.gov/7.9),
[7.10](https://dlmf.nist.gov/7.10), and [7.12](https://dlmf.nist.gov/7.12).
No implementation or coefficient table was imported. No PDF was acquired for
this step. The [derivation](../error-function-replacement.md) and exact-rational
generator are public, reproducible project artifacts.

### Gaussian inversion mathematical references

NIST DLMF version 1.2.8, [§7.17](https://dlmf.nist.gov/7.17) and
[§7.8](https://dlmf.nist.gov/7.8), consulted 2026-10-03: inverse definitions and
Mills inequalities used in the [construction](../inverse-normal-replacement.md).
No implementation/coefficient table or PDF was acquired for this stage.

- Kornerup, Lefèvre, Louvet and Muller, *On the Computation of Correctly-Rounded Sums*, [author-hosted manuscript](https://perso.ens-lyon.fr/jean-michel.muller/TC-2010-04-0248.R1.pdf), Theorem 1 and Algorithms 1–3, pp. 2–3. Inspected via the public source on 2026-10-04 for magnitude-ordered enclosure sums. No PDF or source implementation is distributed by this project; [the local derivation](../runtime-enclosures.md#magnitude-ordered-exact-sums) records the preconditions and adaptations.
