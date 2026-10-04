# Independent numerical review package

Epic #27 / #15 requires an independent human assessment in addition to the
engineering evidence here. No reviewer has been appointed or contacted, no
conflict/independence declaration exists, and no human sign-off is implied by
Arb agreement, mutation results or this document. Review must identify the exact
source commit and every later numerical/API/compiler delta needing re-review.

The owner has separately [reviewed and approved the delivered baseline](acceptance/owner-review-2026-10-03.md).
The [0.2.0 candidate dossier](candidate-0.2.0.md) identifies the final source,
its compatibility with that baseline, canonical generated qualification and
platform artifacts. This owner approval is retained without substituting it
for the independent reviewer deliverables below.

## Current engineering delta (2026-10-04, after #88)

Runtime source `7fb59a3ae282fad60709bbbb123b2e4414772c1e` adds certified scalar
Exchange and the private-buffer enclosure optimization to the earlier handoff
below. Review the [exchange model and boundaries](first-model-extension.md),
[649-case independent qualification](exchange-qualification.md), and
[allocation change](results-certificate-allocation.md). Exchange has no Greeks,
IV or portfolio adapter; its correlation/covariance, discount scaling, exact
boundaries and caller-selected currency limits need their own review.

The shared enclosure storage change preserves the ordered arithmetic, with a
[capacity and read/write argument](runtime-enclosures.md#allocation-preserving-arithmetic-order).
Review that argument and mutable-scratch lifetime across both configurations
and all consumers. Native/bytecode replay, finite corpus agreement and observed
allocation reductions do not replace independent review of this delta.

The [installed-package campaign](installed-exchange-validation.md) now makes
all 649 Exchange outcomes a required native/bytecode replay in the optional
candidate artifact lane. A successful run must retain source-bound reports;
adding the gate does not assert that a new three-platform run has completed.
No reviewer has been appointed or contacted, and no earlier owner decision is
transferred to these later numerical/API changes.

## Earlier engineering handoff (2026-10-04, #57)

The earlier campaign source is `76128fd99b9649d92f5a473fa4fcc3de44e04cd2`,
covering scalar BSM/Black-76/displaced Black/Bachelier prices, certified IV,
ten Greek fields, typed Batch, Scenario and Planner. The [adjudication
report](adversarial-assurance-closeout.md) retains exact inputs, independent
uncertainty, dispositions, strict numerical reruns, reference reduction,
planner stress and remaining coverage gaps. No reviewer has been appointed
or contacted by this handoff. The historical owner approval and candidate
dossiers are tied to their own revisions and do not approve later deltas.

Relative to experimental candidate `83b541e02ce3467536a6febc54a5eeb49004bc8a`:

- #55 changes test/reference scoring and input completeness, including the
  overflowing signed ULP distance and historical one-sided midpoint reduction.
  Committed fixture audits remain explicitly source-bound.
- #54/#56 add versioned numerical and execution challenges. Batch, Scenario
  and Planner runtime source is unchanged, but its expanded stress evidence
  covers real-domain failure/cancellation boundaries and aggregate containment.
- #76 changes selected Black prices to original-input cell refinement, with
  NaN on unresolved cells; review the coordinate selector, stable `expm1`
  identity, `Enclosure_round` and finite-exponent restoration.
- #80 changes selected Greek availability, original-input kink classification,
  zero-variance theta assembly and smooth-theta capability. Review the DD
  cancellation majorants and field/all-field refusal boundaries.
- #77 adds BSM rho final-cell refinement, normalized products, Mills tails and
  analytical zero proofs. Review strict midpoint direction, negative-side
  signs, exact exponent bounds and outward inequalities at actual call sites.

These served-value/outcome changes require a new numerical delta review.
They do not expand Production or IV acceptance contracts, or automatically
transfer old fast-path accuracy claims. The [source delta inventory](evidence/adversarial-closeout/source-deltas.json)
lists changed runtime files. Full revised derivations and per-row compatibility,
availability and performance evidence are linked from the adjudication.

The numerical campaign still has 166 unresolved references, 281 explicit
failures and 17 nonfinite fast prices in 7,095 full requests. A successful
strict diagnostic run is not whole-domain accuracy or availability. Reviewer
attention must include these boundaries and the unselected normal-range fast
paths, not only the corrected witnesses.

The #57 full mutation run also exposed two rho-scaling guards masked by the
new refinement. Commit `2345081b2b2e60ad6dca00a6412f3b98288b7868` adds four
normal-range output witnesses with exact/Arb proofs, without changing runtime
arithmetic or budgets. Review the original survivor log and affected rerun
separately; the earlier campaign is not retroactively described as passing.

## Mandate and deliverables

The appointing owner should select a reviewer with floating-point error-analysis
and derivative-pricing expertise, document independence/conflicts and access,
and agree a scope before review. Deliverables are: a signed/dated report tied
to the candidate; independently reproduced experiments; findings with severity,
exact inputs and evidence; dispositions/exclusions; and a recommendation against
the owner's intended use and economic/operational requirements. A reviewer
must be able to reject a claim without negotiating its tolerance after scoring.

## Review map

| Obligation | Source and evidence | Questions requiring review |
| --- | --- | --- |
| Real model and units | [Model contracts](model-contracts.md), [typed boundary audit](type-boundary-audit.md), public `.mli` files | Are varied coordinates, exact displaced sums, time signs, units and zero/expiry semantics consistent? |
| Intended capability | [Production boundary](production-boundary-design.md), [Greek enclosures](production-greek-enclosures.md) | Does every successful request enforce its stated bound? Are explicit failures acceptable for the proposed use? |
| Published arithmetic | [Error analysis](error-analysis.md), [research archive](research/README.md), `lib/dd.ml` | Recheck cited algorithm boxes, corrections and theorem preconditions at real call sites, including low words and finite exponents. |
| Runtime certification | [Enclosure derivation](runtime-enclosures.md), [model enclosures](model-enclosures.md), [adaptive certification](adaptive-certification.md) | Check TwoSum/expansion truncation, FMA product residuals, subnormal outward error, reciprocal/sqrt residuals and all analytic tails independently. |
| IV outcomes | [Certified IV](certified-iv.md), [termination](iv-termination-audit.md) | Recheck original-model intrinsic/maximal comparisons, the rounded-intrinsic exception, ties, representability endpoints and every exit. The proposal is untrusted. |
| Boundary derivatives | [Zero-volatility Greeks](zero-volatility-greeks.md) | Distinguish a spot payoff kink from rate/time smoothness and numerical failure. Check fixed-forward versus BSM rate variation. |
| Reference independence | [Oracle methodology](oracles.md), [midpoint correction](oracle-midpoint-rounding.md) | Precision agreement can be wrong. Verify one-sided positivity, uncertainty, exact rounding cells and no dropped hard rows. |
| Canonical comparisons | [Shadow specification](shadow-campaign.md), [results](results-shadow.md) | Reproduce mapping effects and all material formula discrepancies; do not treat a comparator as ground truth. |
| Compiler/platform | [Numerical backend](numerical-backend-contract.md), [determinism](determinism.md) | Check contraction, explicit FMA, subnormals, rounding mode and supported-platform evidence. A digest is not an accuracy proof. |
| Operational use | [Performance](performance.md), [shadow results](results-shadow.md) | Are scalar cost/allocation/failure rates acceptable for the actual workload? The separate GC trace covers the diagnostic; business workload coverage remains incomplete. |
| Typed Batch and scenarios | [Scenario contract](scenario-planner.md), `lib/batch.ml`, `lib/scenario.ml`, type rejection and scalar/Batch equivalence tests | Do coordinate/result types, frozen inputs, quantity units, fixed expiry/day count and post-expiry outcomes match the intended use? |
| Planner execution and totals | [Stress protocol](planner-stress-protocol.md), [results](planner-stress-results.md), [current rerun](adversarial-assurance-closeout.md), `lib/planner.ml` | Recheck checked counts, resource bounds, wave/join ordering, cancellation checkpoints, sink commits and independent aggregate intervals. Finite schedules do not prove race freedom or durable delivery. |

The research manifest records original PDF hashes and versions. Black (1976)
remains unavailable in the archive. The source audit distinguishes published
results, project derivations, interval checks, finite-corpus certificates and
measurements; none is formal verification of the whole compiler/program stack.

## Reproduction order

1. Resolve the exact source SHA and use the pinned OCaml 5.3.0 Flambda toolchain,
   locked dependencies and ocamlformat 0.27.0. Build/install, format and run the
   ordinary suite as specified in `AGENTS.md`.
2. Check fixture transitive provenance, archived PDF hashes and replay identity.
   Reference regeneration is separate and must preserve unresolved failures.
3. Run the independent Arb full price/smooth-Greek, positive-IV, formal derivative
   and zero-variance boundary audits. Reports retain their input/source hashes,
   working precision and rejection controls. These are independent arithmetic
   implementations, not independent human authorship.
4. Reproduce the synthetic shadow campaign, including per-trade/gross aggregates,
   failures and canonical-source discrepancies. Bring an independently selected
   representative business book and predeclared materiality requirements.
5. Run the full curated mutation catalog manually and inspect survivors/probes.
   A failed build, missing input or changed digest is not a numerical kill.
   The excluded proposal/branch probes are documented limits, not impossibility
   proofs. Default CI remains the seven reviewed core mutants.
6. Reproduce artifact installation in a fresh prefix with both native and
   bytecode consumers using `scripts/candidate_artifact.py`.

## Finding record

For each finding retain: ID; candidate SHA; model/quantity/coordinate; exact
binary64 inputs or deterministic generator seed; expected real quantity and
independent uncertainty; observed outcome; severity/economic impact; theorem
or code assumptions violated; minimal reproducer; owner; correction or enforced
exclusion; regression/mutation evidence; reviewer disposition and date. Preserve
superseded evidence. Any unexplained material discrepancy blocks acceptance.

The engine's current exact-input assurance excludes market/model uncertainty.
The owner must define those risks and the actual production boundary. A reviewer
cannot supply institutional acceptance merely by checking this repository's
finite test corpus.
