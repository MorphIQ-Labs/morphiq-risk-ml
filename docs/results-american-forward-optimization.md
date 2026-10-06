# Terminal cash-call acceleration and general-solver evaluation (#119)

Scalar terminal-cash calls now use an exact European payoff reduction, retaining
original-input arithmetic and event-side semantics. Earlier exercise, earlier
cash, puts and independently qualified Greek evaluations retain their existing
routes. This is an estimated-only price improvement, not a new certificate.

## Derivation and numerical compatibility

The [protocol](evidence/american-forward-optimization/protocol.md) precedes runtime
edits. For nonnegative strike K and joint payment D,
`(max(X-D,0)-K)+ = (X-(K+D))+`. If pre-cash exercise is permitted at that same
terminal instant, its payoff dominates. Positive expiry, terminal-only exercise
and all cash at expiry are enforced after complete admission/schedule processing.
Constant coefficients use the retained two-word strike centre and an outward
`exp(-rT)`-Lipschitz allowance for its remaining uncertainty. Piecewise
coefficients retain the entire strike enclosure through the integrated formula.
Existing boundary reductions have precedence. Arithmetic failures and the
original tolerance/64 allowance remain authoritative.

The [original generator](../scripts/generate_terminal_cash.py) computes 40
exact-binary-input cases at 256 and 512 Arb bits, using erfc independently of the
runtime CDF. Every case exercises both American and Bermudan admission: 80
prices. The strict tolerance is `2^-30 * max(S,K,individual cash amounts)`.
Cases include signed rates/yields, both event sides, simultaneous amounts,
piecewise coefficients, low strike words, extreme scales and zero effective
strike. All 80 candidate intervals contain their complete independent reference
intervals; all 80 old requests refused at identical settings. References were
committed before the runtime change. The ordinary offline checker binds exact
TSV inputs/intervals to the generator and precision records; five negative
controls challenge that checker.

Of the original 572 price outcomes, only the two terminal cash-call contracts
change across four configurations. Six previously unavailable requests now pass;
the two already served loose/refined prices improve their independent worst
errors from approximately 0.00365/0.00189 to below 7e-16. The other 564 complete
payloads and independent classifications are identical. All 920 Greek rows and
full base-price/diagnostic payloads remain identical. Greek base/perturbed prices
retain the qualified PDE route: the scalar identity alone does not qualify
spatial extraction or fixed-event theta, so their estimates may differ visibly
from separate scalar price requests.

IV compatibility and controlled measurements are recorded in the accompanying
raw evidence and the measurement section below. Changed endpoints must still
contain the complete independent reference interval at the unchanged width.
No cash-put inverse, piecewise inverse or certification claim is added.

## Canonical comparison and specialized-method disposition

The supplementary comparator is clean QuantLib revision
`79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c` (1.44.0), built externally. The
[original adapter](../scripts/american_acceleration_reference.cpp) is research
infrastructure, not a runtime dependency or translated third-party implementation.
QuantLib's license and source/library/compiler identities are retained as hashes.
No research PDF or third-party source is redistributed by this change.

For 31 matching constant terminal contracts, QuantLib BlackCalculator differs
from the independent exact-input references by at most 1.98e-14 currency units.
Nine cases are explicitly excluded for piecewise coefficients, unrepresentable
exact effective strikes or zero effective strike. Its binary64 forward/discount
construction is a distinct rounded evaluation and does not define truth.

For general American pricing, evaluate QdFpAmericanEngine's fast, accurate and
high-precision schemes on all 16 eligible original corpus cases: positive
spot/strike/volatility, nonnegative rate/yield, one-year full exercise window,
constant coefficients and no cash. All 30 scheme/case comparisons with resolved
independent references meet the original case epsilon. The remaining 18 have
unresolved independent references and remain unresolved; scheme agreement does
not convert them into accuracy passes. Every other original case has a recorded
scope exclusion. QuantLib reconstructs rates from discounts, so this also
contains input-conversion effects.

**Disposition: pursue a separately qualified specialized method; defer production
adoption in this change.** The primary
[Healy 2021 treatment, sections 5.1–5.4](https://arxiv.org/html/2109.15157v1)
explains the exercise-boundary integral approach and the extra difficulties
under negative rates. The local canonical implementation was inspected at the
recorded revision; the ALO paper's
[primary abstract](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2547027)
was available, but its full text was not acquired. Before adoption, derive an
original-input arithmetic/error contract, convergence/failure handling, bounded
work/cancellation and price/Greek/IV interoperability; obtain/read the full
original algorithm and audit any implementation reuse terms. Cash jumps,
delayed/Bermudan rights, piecewise coefficients and multiple-boundary regimes
need separate derivations, not relaxed dispatch guards. The small eligible
research corpus cannot qualify that wider domain.

## Remaining general-solver cost

Fresh standalone-put CPU sampling still identifies `slab_constant` as the
largest leaf. Of 519 Memprof samples, approximately 48.7% arise in stencil
preparation, 37.4% in time-slab work, 3.9% in grids and 10.0% elsewhere. These
sampled shares are attribution evidence, not exact allocation budgets.

The terminal reduction removes an unnecessary grid solve; it does not accelerate
ordinary American put time stepping. A next focused native-loop experiment should
compare policy selection and tridiagonal elimination/back substitution using
actual policy matrices and complete requests. Preserve original operation order,
explicit FMA versus rounded multiplication, pivot/failure order, logical work and
bounded cancellation checkpoints. Factor reuse is valid only for an unchanged
operator **and complete policy system**; changing IV sigma invalidates the
operator. No factor cache, new tridiagonal backend or general native solver is
adopted here. Broad #119 retains those comparisons, compiled portfolio/worker
campaigns and independently qualified derivative alternatives. Deployment targets
and final source-artifact qualification remain separate.
