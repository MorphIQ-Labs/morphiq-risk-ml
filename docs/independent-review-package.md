# Independent numerical review package

Epic #27 / #15 requires an independent human assessment in addition to the
engineering evidence here. No reviewer has been appointed or contacted, no
conflict/independence declaration exists, and no human sign-off is implied by
Arb agreement, mutation results or this document. Review must identify the exact
source commit and every later numerical/API/compiler delta needing re-review.

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
