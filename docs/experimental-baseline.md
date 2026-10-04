# Experimental 0.3.0 baseline

The supported experiment is the exact European family—BSM, Black-76, displaced
Black and Bachelier—with prices, certified IV, ten typed Greeks, typed batch
requests and deterministic scenario planning. A qualified experimental baseline
means an identified source artifact builds, installs and passes the declared
engineering checks on the supported platforms, with explicit limitations and
retained evidence. It does not mean institutional deployment approval, a release
publication, a numerical proof over all inputs, or an independent human review.

The source declares 0.3.0, currently unreleased. The
[current integrated candidate dossier](candidate-fast-optimized.md) records
`f703546ea736d456f64e74be6ef9d2da2c10ef88`: shared certified preparation and
Greeks, optimized certificate storage, compiled Fast batches/scenarios and native
DD allocation changes. Its receipt retains the exact reports, source deltas,
platform checks, full 96-mutant campaign and limits. Later evidence/documentation
commits are distinct from the runtime candidate they describe.

The [initial 0.3.0 dossier](candidate-0.3.0.md),
[optimized Exchange dossier](candidate-exchange-optimized.md),
[0.2.0 dossier](candidate-0.2.0.md) and
[pending institutional decision](acceptance/pending.json) retain their original
source scope. Institutional requirements continue under #27 and
[acceptance and change control](acceptance-and-change-control.md).
The [adversarial adjudication](adversarial-assurance-closeout.md) retains its
source-bound unresolved references and failures; a new packaging/replay run
does not retroactively resolve that numerical campaign.

## Claims, owners and executable evidence

The following index connects current claims to their owning implementation and
witnesses. Linked contracts are normative; dated results and corpora describe
only their identified inputs, arithmetic and toolchains.

| Claim and domain | Enforcing owner | Definition/derivation | Executable evidence and limit |
| --- | --- | --- | --- |
| Exact input semantics and four-model admission | `Black`, `Bachelier`, `Vol`, `Coordinates` | [Model contracts](model-contracts.md) | `test/types`, `test/properties.ml`, model consistency; types do not prove the real model |
| Greek units and finite fast results | `Units`, `Greeks`, `Black`, `Bachelier` | [Finite results](finite-greek-results.md), model contracts | `test/finite_greeks.ml`, independent fixtures; fast values have finite-corpus assurance, no runtime accuracy certificate |
| Binary64 arithmetic and explicit FMA | `lib/fp`, `Dd`, `Elementary` | [Backend](numerical-backend-contract.md), [error analysis](error-analysis.md) | primitive, oracle and replay tests; supported hardware/compiler only, no compiler formal proof |
| Accepted price/Greek error <= caller's typed absolute limit | `Production`, enclosure modules | [Runtime](runtime-enclosures.md), [model](model-enclosures.md), [Greek enclosures](production-greek-enclosures.md) | exact-rational replay, certificates and production tests; explicit refusal for unresolved arithmetic or unsupported boundaries |
| Certified scalar exchange price within requested currency limit | `Exchange`, enclosure modules | [Exchange contract](exchange-prices.md) | [649-case qualification and gate status](exchange-qualification.md); no exchange Greeks, inverse parameters or portfolio adapters |
| Correctly rounded positive IV or explicit outcome | certified IV solver | [Certified IV](certified-iv.md) | rounding-cell witnesses, independent price-to-IV fixtures and termination mutants; no claim every valid quote resolves |
| Frozen approximate price batches and bounded fast scenarios | `Batch.Fast`, `Planner.Fast` | [Batch](fast-batch.md), [fast planner](fast-planner.md) | [Integrated qualification](fast-integration-qualification.md), fixture equivalence, concurrent reuse and failure controls; no runtime certificates or weighted totals |
| Frozen inputs, lazy bounded scenarios and checked work counts | `Scenario`, `Planner.compile` | [Scenario contract](scenario-planner.md) | `test/planner_contract.ml`, `test/planner_groups.ml`; finite limits and field/coordinate validation |
| Weighted enclosures, compatible aggregation, incomplete totals | `Planner` reduction | scenario contract | exact-rational aggregate checks, 2,376 independently checked price/Greek cells; not economic P&L or settlement |
| Ordered outcomes across workers, cancellation and sink failure | `Planner.execute` coordinator | scenario contract, [determinism](determinism.md) | planner contract/adversarial tests with failures and 1–4 workers; tested schedules, not general race/deadlock proof |
| Public package usable without source/test libraries | Dune packaging and artifact verifier | [Artifact procedure](acceptance-and-change-control.md) | isolated native/bytecode Batch/Scenario/Planner consumers and byte-exact notice checks on three platforms |

Prices support expiry and zero volatility when arithmetic resolves. Smooth
certified Greeks require positive maturity and volatility. Volatility and time
units remain model/quantity-specific; callers choose absolute error limits,
handle every `Production.error`/`Iv.t`, respect limits, and distinguish partial
results from complete totals. Fast APIs do not inherit Production certificates.
See the linked contracts for each field, unit and boundary variant.

The planner freezes snapshots and rolls fixed expiries with explicit day-count
conventions. Post-expiry is reported, not silently clamped. Economic P&L,
settlement, American exercise, fitted surfaces, stochastic-volatility models,
SIMD, distributed execution and durable resume remain outside this baseline.
OxCaml remains historical optional research, not the qualified toolchain.

## Source-bound evidence and inheritance

The candidate workflow uses **OCaml 5.3.0 Flambda**, the numerical library's
`-O3` flags and the locked opam graph, with the pinned formatter. It executes
development build/format and the ordinary suite, isolated source-artifact installation and
native/bytecode public consumers on Ubuntu x86-64, Ubuntu ARM64 and macOS ARM64.
It replays the 720-row independently certified canonical portfolio on each
platform and runs the complete curated mutation catalog separately. The
catalog at this candidate contains 96 mechanisms; PR CI still selects seven.
Successful mutant builds and designated witness failures establish kills;
build/tool failures are not substitutes. The exact-main CI receipt separately
retains ordinary development and release suites on all three platforms.

Independent campaigns are inherited only within their actual source scope:

- DD [replacement](results-dd-exponential.md) and [optimization](results-dd-exponential-optimization.md),
  [error functions](results-error-functions.md), [inverse normal](results-inverse-normal.md)
  and [inverse optimization](results-inverse-optimization.md) replace the old
  numerical primitives and carry independently refined comparisons. Earlier
  scalar output identities are not silently reused after those changes.
- [Finite Greek results](finite-greek-results.md) records the result-type and
  extreme-input correction. It supersedes earlier nonfinite-result behavior;
  the current ordinary suite repeats its new witnesses.
- [Planner qualification](results-planner.md) establishes independent numerical
  cells and execution behavior. [Compilation optimization](results-planner-compilation.md)
  preserves arithmetic and rechecks the 2,376-cell reference while changing
  group lookup cost. It does not claim a new numerical model.
- The current [candidate change map](candidate-fast-optimized.md) and
  [review handoff](independent-review-package.md) enumerate subsequent shared
  certification, exact-sum/storage, Fast API and DD allocation deltas. Their
  independent tests and compatibility reports retain source-specific scope;
  packaging, replay and current ordinary checks are repeated for this candidate.
- [Performance evidence](performance.md) and the linked optimization reports
  remain measurements on their recorded shared workstation. They are not
  cross-platform SLAs or measurements of the final candidate on every platform.

[Oracle methodology](oracles.md), fixture provenance in `oracle/MANIFEST`,
[research sources](research/README.md), [current implementation provenance](opensource-closeout.md)
and the reports' source hashes remain part of the evidence chain. Precision
agreement, canonical agreement, analytical bounds, runtime certificates and
bitwise replay establish different facts. Unresolved reference rows and
reported canonical discrepancies remain visible in the original campaigns.

## Decision, retention and invalidation

The final receipt names its engineering assessor and exact source; it records
experimental qualification only. It must not manufacture a maintainer signature
or independent review. Source commit, dependency lock, deterministic archive
hashes, installed file hashes, consumer results, source audit, CI logs and full
mutation results are retained. Public evidence is committed under `docs/evidence/`;
source archives are reproducible from the immutable Git commit. The dossier
records an additional durable local artifact archive beyond GitHub's 90-day CI
retention. That local copy is not required for public builds or reproduction.

`python3 scripts/check_experimental.py docs/evidence/qualified-fast-candidate/dossier.json --root .` verifies the current receipt
identity, required categories/platforms and evidence hashes. Its failure
controls reject altered/missing files, mismatched candidates, missing platforms
and path escapes. This checks record integrity, not scientific truth or approval.
The institutional checker remains a distinct gate; the
[current pending record](acceptance/pending-fast-candidate.json) fails for its
explicit missing review and owner decisions, despite intact artifact hashes.

Numerical or compiler/flag changes invalidate affected arithmetic/reference and
mutation evidence; API changes invalidate public consumers/type controls;
planner scheduling/reduction changes invalidate relevant execution/reference
checks; dependency or packaging changes invalidate installation/provenance
checks. Documentation/evidence-only changes require integrity/link review and
an explicit delta, not relabeling old executions as new runs.

The engineering work under #53–57 is adjudicated in the
[current campaign closeout](adversarial-assurance-closeout.md): numerical
boundaries, scorer/input hardening, reference reduction, scheduling stress and
finding dispositions. Its finite coverage, unresolved references and explicit
availability limits remain constraints on experimental assurance.
Institutional review, representative business
portfolios and release decisions remain #15–17; none are satisfied by this
engineering closeout. There is no production SLA or blanket guarantee over all
finite admitted inputs.
