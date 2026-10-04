# Documentation guide

Start with the [project README](../README.md) for installation and a certified
pricing example. The current implementation includes the European scalar family,
typed batches, and bounded scenario planning. The original slice proposal has
been retired; it remains in Git history.

- [Experimental baseline](experimental-baseline.md): claim owners, exact-candidate evidence and limitations.
- [Open-source closeout](opensource-closeout.md): current provenance, packaging and security disposition.

## Current contracts

- [First model extension design](first-model-extension.md): selected certified scalar exchange prices, original-input contract, references and implementation gate; [implementation evidence](exchange-prices.md) is separate and broader qualification remains open.
- [Model contracts](model-contracts.md): exact input meaning, model definitions, Greek conventions, and IV outcomes.
- [Production boundary](production-boundary-design.md): per-request numerical acceptance and explicit capability exclusions.
- [Scenario planner](scenario-planner.md): shocks, date rolls, resource limits, aggregation, and execution failures.
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

The [0.3.0 experimental qualification](candidate-0.3.0.md) records the current
qualified source and retained evidence.

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
