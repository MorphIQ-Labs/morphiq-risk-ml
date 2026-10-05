# Documentation guide

Start with the [project README](../README.md) for installation and a certified
pricing example. The current implementation includes the European scalar family,
typed batches, and bounded scenario planning. The original slice proposal has
been retired; it remains in Git history.

- [Experimental baseline](experimental-baseline.md): claim owners, exact-candidate evidence and limitations.
- [Open-source closeout](opensource-closeout.md): current provenance, packaging and security disposition.

## Current contracts

- [Fast scenario streaming](fast-planner.md): shared structural/scheduler contracts, distinct approximate prices and bounded output.

- [Compiled fast price batches](fast-batch.md): frozen admission reuse, explicit failures and separation from runtime certificates.

- [First model extension design](first-model-extension.md): selected certified scalar exchange prices, original-input contract, references and implementation gate; [implementation evidence](exchange-prices.md) is separate and broader qualification remains open.
- [Model contracts](model-contracts.md): exact input meaning, model definitions, Greek conventions, and IV outcomes.
- [Production boundary](production-boundary-design.md): per-request numerical acceptance and explicit capability exclusions.
- [Shared Greek intermediates](shared-greek-intermediates.md): dependency identity and deferred per-quantity failures.
- [Shared certified preparation](shared-certification.md): typed multi-output requests, per-output limits and call-local reuse.
- [Scenario planner](scenario-planner.md): shocks, date rolls, resource limits, aggregation, and execution failures.
- [Operational campaign](operational-campaign.md): configurable concurrent clients, plan lifecycle, cancellation and pending deployment criteria.
- [Worker and tile tuning](planner-worker-tuning.md): throughput, startup, first output and memory tradeoffs.
- [Planner stress evidence](planner-stress-results.md): forced failure schedules, bounded output accounting and separate process-memory observations.
- [Public interface](../lib/morphiq_risk.mli) and [type audit](type-boundary-audit.md).
- [Stability](stability.md), [determinism](determinism.md), and [numerical backend](numerical-backend-contract.md).

## Numerical methods and verification

- [Adversarial assurance closeout](adversarial-assurance-closeout.md): current source, finding dispositions, retained uncertainty and review obligations.
- [Subnormal rho qualification](results-rho-midpoint.md): original-input rounding cells, zero proofs, availability and timing evidence.
- [Error analysis](error-analysis.md): derivations and the current certification scope.
- [Greek cancellation qualification](results-greek-cancellation.md): explicit coordinate/theta limits, independent references and compatibility evidence.
- [Carry-cancellation price refinement](results-carry-cancellation.md): original-input correction, explicit availability limits and timing cost.
- [Numerical boundary campaign](numerical-campaign-results.md): frozen coverage, independent references, availability and retained findings.
- [Oracle assurance and reduction](oracle-assurance.md): finite scoring, input failure controls and independently resolved counterexamples.
- [Oracles](oracles.md), [midpoint rounding](oracle-midpoint-rounding.md), and [mutation policy](mutation-policy.md).
- [Runtime enclosures](runtime-enclosures.md), [model enclosures](model-enclosures.md), and [Greek enclosures](production-greek-enclosures.md).
- [Certified IV](certified-iv.md), [adaptive certification](adaptive-certification.md), and [zero-volatility Greeks](zero-volatility-greeks.md).
- [Research bibliography](research/README.md): original publications, source links, and historical acquisition checksums.
- [Numerical source provenance](source-provenance.md): actual implementation sources, retained terms and unresolved distribution status.
- [Numerical replacement plan](numerical-replacement-plan.md): staged replacement of AS241, CALERF and the QD-derived exponential, with qualification requirements.

## Evidence and history

[Fast-batch SIMD integration](fast-simd-integration.md) records the staged
preparation, native batch and planner ownership contracts.
Its [native batch](results-native-bachelier-batches.md) and
[bounded planner](results-native-planner.md) reports separate reused-kernel gains
from full scenario jobs, including fallback costs and deferred parallel adoption.

[Optional Fast-batch SIMD experiment](results-fast-simd.md) compares bounded
Bachelier preparation, native scalar, SIMD and SLEEF, including one-shot
regressions and the decision to retain the current production backend.

[Fast allocation optimization](results-fast-allocation.md) records native gains,
bytecode tradeoffs, exact word compatibility and paired workload measurements.

[Integrated fast pricing qualification](fast-integration-qualification.md) covers
fixture equivalence, concurrent ownership, bounded memory and measured reuse.

The `results-*.md` reports, `evidence/` artifacts, and dated candidate dossiers
retain the inputs, toolchains, limitations, and outcomes of specific campaigns.
They are reproducibility records, not disposable build output. Use each report's
recorded commit and date; an older report does not redefine a current contract.

Start with [DD exponential optimization](results-dd-exponential-optimization.md),
[initial DD exponential replacement](results-dd-exponential.md),
[planner qualification](results-planner.md),
[canonical datasets](results-canonical-dataset.md),
[performance](performance.md), and the original
[scalar experiment results](results-slice.md).

The [integrated fast/certified candidate](candidate-fast-optimized.md) records the
current qualified source and retained evidence. The [initial 0.3.0 dossier](candidate-0.3.0.md)
remains a historical source-bound record.

The [0.2.0 candidate dossier](candidate-0.2.0.md), [independent review package](independent-review-package.md),
and [acceptance controls](acceptance-and-change-control.md) retain the distinction
between engineering evidence, independent review, and institutional acceptance.
The [OxCaml experiment](../experiments/oxcaml/README.md) is optional research;
it is not the supported compiler or a prerequisite for ordinary builds.

## Repository retention

| Material | Treatment |
| --- | --- |
| Original `SLICE.md` proposal | Removed from the current tree; retained at its recorded Git revision |
| Downloaded research PDFs | Originals preserved in the private research library; optional local copies ignored; [bibliography and preservation policy](research/README.md) retain public provenance and source links |
| Research metadata and checksums | Retained to identify the exact references used in numerical work |
| Numerical fixtures, generators, certificates, and evidence | Retained with their provenance |
| Candidate and acceptance records | Retained as dated records; never rewritten to imply a later acceptance |
| Build output, Python caches, local environments | Ignored; not included in source distributions |
| `AGENTS.md` and `CLAUDE.md` | Retained as contributor/tool guidance |

Removing a file from the current tree does not remove it from existing Git
history, clones, or older archives. This cleanup does not rewrite history.

- [Generated error functions](error-function-replacement.md): construction and rational bounds replacing CALERF.
- [Error-function qualification](results-error-functions.md): compatibility, boundary references and performance.

- [Inverse-normal construction](inverse-normal-replacement.md) and [qualification](results-inverse-normal.md): AS241 replacement, independent references and IV consumer costs.

- [Inverse-normal optimization](results-inverse-optimization.md): exact intermediate reuse, numerical replay and measured costs.

- [Finite Greek results](finite-greek-results.md): per-field failures, subnormal rho scaling and independent extreme-input references.

- [Planner compilation scaling](results-planner-compilation.md): distinct-group counting, limit/replay controls and homogeneous/heterogeneous timings.

- [Certified scalar exchange prices](exchange-prices.md): additive API, numerical capability, focused implementation evidence and remaining #61 qualification.

- [Exchange qualification](exchange-qualification.md): frozen 649-case scalar campaign, independent expectation references, package/platform evidence and explicit gate status.

- [Certificate allocation optimization](results-certificate-allocation.md): identical-arithmetic private scratch, reference replay and paired exchange/IV measurements.

- [Installed Exchange validation](installed-exchange-validation.md): full qualified native/bytecode replay through the isolated public package in the optional candidate lane.

- [Optimized Exchange candidate](candidate-exchange-optimized.md): exact-source three-platform installation, six full Exchange replays and 84-mutant closeout.

- [Certified expansion sum optimization](results-certified-expansion-sums.md): magnitude-ordered exact residuals, finite guards, scalar/portfolio/Exchange/IV measurements and complete certificate replay.
- [Certification allocation optimization](results-certification-allocation.md): packed immutable words, private buffers, 77% less representative price allocation, GC counts and IV timing tradeoffs.

- [Fast planner measurements](results-fast-planner.md): bounded scenario costs, worker scaling and certified compatibility.
- [Fast batch measurements](results-fast-batch.md): compile/reuse costs, direct scalar comparison, fixture equivalence and installed consumers.
