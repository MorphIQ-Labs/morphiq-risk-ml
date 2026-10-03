# Numerical source provenance

Audit date: 2026-10-03. Tracked in [#64](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/64).
Implementation baseline: `9f792d6b2a46b9e49256ec51810b915358d50d18`.

The actual sources for all three questioned implementations are now identified.
Their unrestricted redistribution status is **not cleared** by this audit.
The maintainer selected replacement planning rather than permission outreach;
see the [replacement plan](numerical-replacement-plan.md).

## Evidence and scope

The [machine-readable record](evidence/source-provenance-2026-10-03.json)
contains source URLs, exact hashes and sizes, acquisition dates, and selected
development events. The original development session recorded successful
downloads, source reads, and subsequent implementation writes. Its original
scratch files survived. Fresh downloads of AS241, CALERF and the QD tarball
on 2026-10-03 match those original bytes.

The private research library preserves eight original source/rights artifacts
under `sources/morphiq-risk-ml-64/`, indexed in its catalog, plus selected event
metadata under `notes/morphiq-risk-ml/`. Unrelated conversation is not copied.
These private records are audit evidence, not a build or test dependency.
Public readers can compare the recorded hashes with the original-source URLs.
This chronology establishes direct source consultation; it does not prove every
possible influence or decide the legal protection of individual expressions.

## AS241: source-informed adaptation

- Actual source: [StatLib `apstat/241`](https://lib.stat.cmu.edu/apstat/241),
  Wichura's 1988 PPND7/PPND16 file, 6,298 bytes.
- Downloaded on 2026-10-02 at 10:48:03 UTC; both sections were read before
  `lib/normal.ml` was written at 10:50:01 UTC. Introduced in
  [`65fb764`](https://github.com/MorphIQ-Labs/morphiq-risk-ml/commit/65fb764f3c6af48175de2b0a54780dd06e19b236).
- Scope: `As241.central`, `intermediate`, `far`, and the branch/reduction
  structure in `norm_inv`; this is not the provenance of every normal-density
  or CDF operation in the file. Coefficients and regions follow PPND16;
  OCaml helpers, endpoint handling and later elementary-function calls differ.

The [StatLib policy](https://lib.stat.cmu.edu/apstat/index) identifies RSS
copyright and permits distribution subject to a no-fee condition. That is not
a recorded unrestricted grant for this project's intended distribution.
The [R maintainers' account](https://stat.ethz.ch/pipermail/r-devel/2010-February/056608.html)
describes permission obtained for R; it does not establish permission for us.
The earlier failed browser retrieval is superseded by successful direct
retrieval of both the source and the policy. Do not claim a paper-only origin
or borrow R's GPL permission to relabel this implementation.

**Disposition:** source identity resolved; permission unresolved; replace the
AS241-derived inverse implementation under the numerical change process.

## CALERF: source-informed adaptation

- Actual source: [Netlib SPECFUN `erf`](https://netlib.org/specfun/erf),
  W. J. Cody, March 19, 1990 revision, 13,926 bytes.
- Downloaded alongside AS241, read at 10:48:07 UTC, followed by the write of
  `lib/cody.ml` at 10:49:19 UTC; introduced in the same `65fb764` commit.
- Scope: coefficient sets A/B, C/D and P/Q, interval selection, machine
  constants, split-square exponential evaluation and sign reconstruction.
  The source's multiplexed Fortran routine became separate OCaml helpers;
  later changes removed the XMAX flush and use project elementary functions.

Neither the inspected source nor its [SPECFUN README](https://netlib.org/specfun/readme)
contains an explicit permission grant. Related SPECFUN material also appears
as Algorithm 715 in [ACM CALGO](https://calgo.acm.org/), whose index references
an ACM software agreement. This is an additional rights question, not proof
that a particular ACM license applies to the independently hosted Netlib copy.
Do not infer public-domain status from the author's laboratory affiliation,
a different Netlib package's license, or downstream reuse by other libraries.

**Disposition:** source identity resolved; permission unresolved; replace the
CALERF-derived implementation and coefficient tables. A paper citation alone
would not erase the recorded source consultation.

## QD: original distribution differs from the GitHub notices

**Current-tree update:** the exponential adaptation described below has been
replaced by the project-derived direct Taylor/Horner implementation. The
[qualification report](results-dd-exponential.md) records its generated
coefficients, new operation graph and numerical checks. This is a replacement
after inspecting the old source, not a claim of clean-room development. The
following findings and retained notices remain the historical record.

- Actual source: [Bailey's `qd-2.3.24.tar.gz`](https://www.davidhbailey.com/dhbsoftware/qd-2.3.24.tar.gz),
  downloaded at 13:37:04 UTC on 2026-10-02, SHA-256
  `a47b6c73f86e6421e86a883568dd08e299b20e36c11a99bdfbe50e01bde60e38`.
- The session read `src/dd_real.cpp`'s exp/log functions at 13:38:01 UTC and
  wrote the adaptation at 13:38:28 UTC. The merged change is
  [`5d71ce9` / PR #6](https://github.com/MorphIQ-Labs/morphiq-risk-ml/commit/5d71ce9db0b72ca52779b6b53bd4d39b04511354).
- Historical scope: exponential reduction by 512, the Taylor accumulation and
  stopping structure, nine doublings, and their reuse in `expm1_reduced`.
  The project generates factorial coefficients, extends exponent handling and
  has its own tiny-expm1 handling. The trial QD Newton logarithm was discarded
  before merge. Basic double-word operations cite separate published algorithms;
  this audit does not label the entire `Dd` module a QD port.

The original tarball has **no root `LICENSE` file**. Its `COPYING` points to
`BSD-LBNL-License.doc`. The GitHub v2.3.24 files retained in PR #65 instead
pointed to a root `LICENSE` with a different copyright notice. They were not
the license-bearing files in the distribution actually used.

This correction replaces those GitHub-derived notices with the original
[COPYING](../LICENSES/QD-COPYING.txt), unchanged
[license DOC](../LICENSES/QD-BSD-LBNL-License.doc), and its complete
[text extraction](../LICENSES/QD-BSD-LBNL-License.txt). The original DOC is
authoritative; the text was extracted with macOS `textutil` without editing.
The superseded GitHub notices remain in Git history; their replacement is
explicit and is not removal of the actual source distribution's notices.

The agreement includes redistribution conditions, a warranty disclaimer, and
an enhancements provision; it also contains licensee fields and the label
`Software: main.cpp library`. `COPYING` includes commercial-contact language.
[Bailey's software page](https://www.davidhbailey.com/dhbsoftware/) still directs
commercial users to LBNL. Retaining these documents does not resolve the form's
scope or establish that the contact language can be ignored. Do not describe
this as a verified, ordinary BSD-3-Clause grant without resolving those points.

**Disposition:** adaptation and original terms identified; notice packaging
corrected; unrestricted commercial-distribution assessment remains unresolved.
The replacement decision was to replace the QD-derived exponential portion rather than silently substituting
another distribution's terms.

## What this change establishes

All three source identities and the QD notice mismatch are documented. Original
project licensing remains Apache-2.0; it does not supersede upstream rights.
All retained notices, this report, and the source-fingerprint record accompany
installed documentation. The original audit changed no numerical operation,
coefficient, fixture, dependency pin or tolerance. The subsequent DD replacement
is qualified separately in its linked report; AS241 and CALERF remain unchanged.

Issue #64 stays open until each replacement is qualified and its current-source
provenance is recorded. Historical provenance and applicable notices remain
preserved; replacement does not rewrite Git history or retrospectively grant
permissions. No author/publisher outreach, agreement signing, or release is
part of this change.
