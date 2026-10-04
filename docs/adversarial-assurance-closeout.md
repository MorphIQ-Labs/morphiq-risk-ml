# Adversarial assurance adjudication (#57)

The version-1 numerical, reference and planner campaigns have been rerun against
source `76128fd99b9649d92f5a473fa4fcc3de44e04cd2` on 2026-10-04. The original
runtime findings are corrected or have enforced, documented capability limits.
Strict numerical scoring has no remaining quality excursions or contract
violations on these corpora. Unavailable results and unresolved references
remain separate outcomes; they are not successful accuracy comparisons.

This closes the engineering campaign/report scope of #53/#57. It does not
appoint a reviewer, supply independent human sign-off, approve institutional
deployment, publish a release or replace the historical 0.3.0 candidate dossier.
The [updated review package](independent-review-package.md) identifies the
expanded scalar/Batch/Scenario/Planner scope and remaining obligations under #15.

## Source, protocol and execution

The [numerical protocol](numerical-campaign-protocol.md) predates scoring
(`d25f8ba`), with generator version 1, seed 540055 and immutable original-input
membership. The [reference controls](oracle-assurance.md) and [planner
protocol](planner-stress-protocol.md) define their own bounded workloads and
failure conditions. No inputs, budgets or exclusions were changed in this
closeout. Historical findings and per-row reports remain intact.

The exact source includes PRs #75/#78/#79/#81/#82 and the #77 correction in
PR #83. Its runtime tree equals measured commit
`dd15dcb811799c601f5cad725999a5c0987c0a4f`; `76128fd` adds only documentation
and retained evidence. The execution receipt records both revisions and
runner hashes. PR #83 merged that identical tree as
`eaf20a4c252b927c437596ed6089cb84dcf974c9`. Closeout commit
`2345081b2b2e60ad6dca00a6412f3b98288b7868` adds four test witnesses;
runtime, numerical budgets and reference fixtures are unchanged. Later edits
retain documentation/evidence only.
The host is Apple M1 Pro, macOS 27 arm64, OCaml 5.3.0 Flambda with `-O3`,
Dune 3.24.2 and ocamlformat 0.27.0. Reference work uses Python 3.14.8,
mpmath 1.3.0, python-flint 0.9.0 and FLINT 3.6.0.

| Numerical outcome | Smoke | Full |
| --- | ---: | ---: |
| Independent value checks | 1,880 | 6,193 |
| Supported class checks | 436 | 438 |
| Unresolved references | 54 | 166 |
| Explicit numerical failures | 127 | 281 |
| Nonfinite float-returning fast prices | 14 | 17 |
| Quality excursions | 0 | 0 |
| Contract violations | 0 | 0 |
| Total requests | 2,511 | 7,095 |

Both runs use strict scoring and exit zero. Per-region/model/interface/quantity
totals and every result are retained. The 54/166 unresolved comparisons include
interval overlap without proved certificate containment, unresolved rounding
cells and bounded IV reference limitations. The 127/281 numerical failures and
14/17 fast-price nonfinite outputs remain computational availability limits,
not evidence of a wrong mathematical classification or a successful value.
The fixed central Greek neighborhood's availability requirement still passes.

The deliberately faulty precision-agreement reference is reproduced and reduced
again; both its wrong cell and the corrected one-sided cell are independently
resolved. The seven normalization attempts retain three accepted reductions,
two invalid, one non-failing and one unresolved proposal. This is the historical
#39 mechanism, not a newly broken committed reference. Conversion, cancellation,
wide-interval and exact-midpoint controls remain explicit. Historical independent
fixture audits cover 99,088 prices, 59,200 smooth Greeks, 5,579 positive IV roots
and 2,506 extra-precision Greek references; the receipt verifies unchanged audit
sources. They are inherited fixture evidence, not falsely reported new runtime
runs. The ordinary suite checks current served values and certificates separately.

Five fresh planner subprocesses each pass all 44 checks, with largest observed
completed-output retention of 153 slots and every plan within its own compiled
bound. This includes 1/2/3/4-worker execution, tile sizes 1/2/5/19, forced order,
slow sinks, spawn/evaluation/join failures, cancellation and partial totals.
Independent rational sums check aggregate containment. Four public-planner
memory subprocesses complete 256/2,048/4,096/32,768 rows at the same 384-slot
bound, with peak RSS 15,876,096/17,743,872/21,725,184/24,150,016 bytes.
RSS includes runtime, book storage, domains, scratch and GC; these observations
do not prove an asymptotic or hard process-memory bound. Timings were collected
alongside other assurance work and are not performance qualifications.

## Finding dispositions

Severity below describes the engineering contract affected. Actual economic
materiality requires a representative business book and predeclared requirements
under #16; a ULP count alone does not establish it. All fixes retain original
binary64 inputs, independent uncertainty and numerical regressions.

| Finding and scope | Violated assumption and source cause | Disposition and evidence |
| --- | --- | --- |
| #55 finite ULP scorer; high assurance risk | Signed 64-bit subtraction/absolute value overflows: +2 versus -2 produced a negative distance, allowing a false pass. | Test-only Zarith rank distance; finite/nonnegative budget checks and exact extreme witnesses. `ulp-distance-overflow` challenges the correction. Runtime arithmetic unchanged. |
| #55 reference-input integrity; high assurance risk | Streaming end-of-file and unchecked input snapshots could silently omit or substitute reference rows; a partial file is not a valid corpus. | Immutable fingerprint/shape/count checks before scoring, two-file role checks, damaged-file and worker-failure controls. Input-error exit 3 is never a mutation kill. No claim that a committed fixture was found truncated. |
| Historical #39 reference midpoint; high assurance risk | Repeated precision agreement loses a strictly positive time-value correction at an exact intrinsic midpoint. | Existing exact-rational repair plus independent Arb one-sided proof, reproduced and reduced by #55. Original/minimized words, intervals and all attempted reductions are retained in the new reference report. No new generator correction was required. |
| #76/#80 carry-cancellation family; high fast-API correctness risk | DD log-forward formation can lose low terms before cancellation; finite outputs do not establish accurate price or sensitivities. Rounded zero can also misclassify a kink. | #76 price refinement accepts an original-input rounding cell or returns NaN. #80 enforces a justified all-field capability restriction, preserves original ATM identity and stabilizes zero-variance theta; unresolved smooth-theta component cancellation fails only theta. Independent neighboring/scale/side/model corpora and affected mutants cover the siblings. |
| #77 rho midpoint; bounded fast-API rounding defect | Rounding a probability to one half before restoring the maturity/currency exponent loses the side of the final subnormal midpoint. | Original-input final-cell refinement, scaled Mills tails and proved zero shortcuts; unresolved cells fail only rho. The one-ULP original error is within the old 16-ULP budget, but violates the separate proved-zero diagnostic. |
| #56 planner execution campaign | No new implementation defect was found in the exercised schedules and fault boundaries. | Retain the bounded tests, independent aggregate checks, source instrumentation hashes and unexercised schedules; absence of findings is not a race-freedom proof. |

The exact runtime reproducers are:

- **#76:** BSM call S=`3ff0000000000001`, K=T=`3ff0000000000000`,
  r=`bcafffffffffffff`, q=sigma=`0000000000000000`. Old price
  `35f5555555555554`; Arb resolves `3615555555555556`, now served exactly.
  This is a 9,007,199,254,740,994-ULP discrepancy at a price near 3.65e-48.
- **#80:** the same original inputs with sigma=`35f0000000000000`.
  All ten old fast fields are inaccurate; delta alone was
  `3fed14cc3547f8d9` versus `3fefffffe61da6af`. The enforced capability
  restriction now refuses these unresolved coordinates. The shifted smooth-theta
  sibling uses F=`3ff0000000000001`, K=T=1, shift=2^54, r=0.125,
  sigma=2^-106, both sides; it has a field-specific refusal.
- **#77:** BSM call/put S=K=`3ff0000000000000`, T=`0000000000000001`,
  r=q=`0000000000000000`, sigma=`3fd0000000000000`. Strictly
  `0 < call rho < 2^-1075`; call rounds to zero, put to `8000000000000001`.
  Independent Arb resolves the original cell at 2048 bits.

The full independent enclosures, minimized words and regression/mutation mapping
are in the [price](results-carry-cancellation.md), [Greek
cancellation](results-greek-cancellation.md) and [rho](results-rho-midpoint.md)
qualifications. Their 2,748/10,760/11,630-row challenges deliberately account
for lost availability: respectively 21/738/72 formerly checked values become
unavailable. Those are intentional capability limits, not hidden successes.
The methods do not certify every other fast result. Production and certified
IV retain separate enforced contracts. No tolerance was widened.

## Exercised mechanisms and remaining obligations

| Area | Exercised evidence | Unexercised or unresolved |
| --- | --- | --- |
| Scalar numerical boundaries | All four models, both sides, price/IV/ten Greeks, scale/carry/shift/branch neighbors, original-input Arb and rational cells | Every finite admitted input, every interacting extreme, unresolved references and workload-wide availability; empirical fast envelopes are not universal theorems |
| Reference/scorer machinery | Exact metric extremes, finite rejection, corpus integrity, worker crash/timeout/malformed results, one-sided reduction and conversion controls | Independent human authorship; precision/algorithm choices outside the bounded fixtures |
| Batch/Scenario | Existing typed scalar/Batch equality, frozen snapshots, explicit day count and fixed expiries, limits and post-expiry controls in the ordinary suite | Settlement/P&L, new models, stochastic inputs, distributed execution, durable resume |
| Planner | Ordered results, bounded waves, partial totals, real domains, forced completion/cancellation/failure paths and rational aggregate containment | Arbitrary OS schedules, actual global exhaustion, process crashes, asynchronous interruption, indefinitely blocked consumers, every cancellation interleaving |
| Arithmetic/theorems | Original-input runtime enclosures, exact-rational operation checks, explicit FMA and subnormal witnesses, retained source derivations | Independent theorem/call-site review, whole-program/compiler proof, arbitrary platforms/rounding environments |
| Operational/economic | Source-bound experimental campaigns and separate recorded benchmarks | Representative institutional book, market/model uncertainty, workload SLA, business materiality and operational acceptance |

The full optional mutation campaign exposed two coverage gaps:
`greek-live-rho-scale` and `greek-zero-rho-scale` survived their old guards,
because the new subnormal rho owner corrected the deliberately damaged
proposal. Their numerical mechanisms were not redundant: premature maturity
multiplication can also corrupt a **normal-range** output that bypasses that
refinement. The original failures and their subsequent guard qualification are
retained separately; a survivor is not reclassified as a kill retrospectively.

Four new direct witnesses use K=1.5*2^900, T=3*2^-1074, r=q=0,
call S=2K or put S=K/2, and sigma=0 or 1/4. At zero volatility, signed rho
is exactly `+/-9*2^-175`, a normal binary64 value. At positive volatility,
total volatility is less than 2^-538 and ln(2)>1/2, so the ITM signed d2
exceeds 2^536. The Mills bound makes the omitted probability less than
`exp(-d2²/2) < 2^-64`. Its product with TK is less than half an ULP of
9*2^-175, which is 2^-225. The correctly rounded results are therefore
`3532000000000000` and `b532000000000000`, independently confirmed by
original-input Arb intervals at 256 bits. Premature normalized-cash times T
rounding changes these normal outputs. `finite_greeks` now requires the four
exact results in addition to its unchanged 880-row fixture.

The initial full run at `76128fd` compiled all 77 mutants, killed 75 and
reported these two survivors (exit 1). At `2345081`, a clean copied baseline
and all four affected `finite_greeks` mutants pass qualification: both restored
scaling witnesses, field finiteness and unresolved intrinsic. The only changed
source between these runs is `test/finite_greeks.ml`; the other 73 mutants and their guards,
and all runtime/catalog sources, are identical. All 77 curated mechanisms thus
have applicable kill evidence across the two source-bound runs. This is not
described as a single 77/77 full run on the later source. Ordinary build,
format and the complete test suite also pass at the later source.

The [mutation receipt](evidence/adversarial-closeout/mutation-reconciliation.json)
maps each mechanism to its actual run and source, separately from the seven
default CI sentinels. Historical diagnostic survivors remain
`intrinsic-terms`, `iv-rounded-bound`, `iv-beta-bar`, `iv-ln-beta`,
`bachelier-iv-quantum` and `iv-maximum-error`: their previous witnesses did not
establish necessity after other owners took over. They are not proved redundant
or impossible to kill, and this closeout does not remove their mechanisms.
See [mutation policy](mutation-policy.md) for exact scope and history.

## Reproduction and acceptance boundary

Use the pinned toolchain and commands in the numerical, oracle-assurance and
planner protocols. The [execution receipt](evidence/adversarial-closeout/execution.json)
records the exact invocations and statuses; replace its temporary runner path
with a local build of the identified source. Run full mutations explicitly with
`DUNE_JOBS=2 opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe`.
Ordinary PR CI remains three-platform correctness/format plus seven core mutants.
Reference generation and full mutation/stress campaigns remain manual/scheduled.
The [artifact inventory](evidence/adversarial-closeout/SHA256.json) binds reports,
protocols, source and reference evidence. Build/format, the ordinary suite and
documentation links are checked for this test/evidence change; runtime assurance is bound to the
identified source, not to a claim that every later commit was independently audited.

#15 retains reviewer appointment, expertise/conflicts, theorem/call-site
assessment, report, material-finding disposition and delta review. #16 retains
representative portfolio/economic work; #8 owns further performance work;
#17/#27 retain candidate acceptance/change controls and institutional readiness.
The old owner approval applies to its recorded source, not automatically to this
new numerical behavior. Experimental evidence does not supply those decisions.
