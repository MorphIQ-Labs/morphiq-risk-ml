# Forward pricing optimization protocol (#119)

Frozen on integration baseline `07916c6d706eb3c2193deba3dc475c8f3ab218bb`
before runtime edits or candidate scoring. Scope: exact terminal-cash call
reduction, measured general-solver bottlenecks and a bounded specialized-method
evaluation. Keep broad #119 open for any remaining backend/compiled obligations.

The first implementation uses the pathwise identity
`(max(X-D,0)-K)+ = (X-(K+D))+` for nonnegative K,D. All payments must occur
at expiry and all exercise rights must be at that physical time. If pre-cash
exercise is allowed, its call payoff dominates post-cash payoff, so use K;
after-only exercise uses the exact original K+D sum. Constant and deterministic
piecewise coefficients have lognormal terminal stock in the absence of earlier
cash jumps. Earlier exercise/cash, puts and existing exact boundary routes retain
their own methods. Admission, complete schedule traversal, cancellation and
resource accounting precede this shortcut. No scalar or inverse certificate is
added; general cash-put inversion stays unsupported.

Retain K+D as an enclosure of the original sum. Constant-coefficient evaluation
may use its retained two-word centre in the existing European enclosure, plus
an outward discounted strike-uncertainty allowance: call payoffs are 1-Lipschitz
in strike, hence currency sensitivity is at most exp(-rT). Piecewise evaluation
must retain the full strike enclosure through the existing integral formula.
No rounded effective-strike substitution without its propagated uncertainty.
Tail/overflow/cancellation limitations must remain explicit. Preserve all
unaffected public arithmetic and method identities.

Before implementation, generate precision-refined independent Arb terminal
references from exact input rationals, covering event sides, multiple coincident
amounts, lost low words, signed rates/yields, scales, terminal Bermudan and
varying coefficients. Run the pinned canonical European comparator for matching
representable-effective-strike constant cases; record unrepresentable-model
mismatches rather than treating its rounded substitute as an exact reference.
Compare all existing 572 price outcomes, affected Greeks and inverse corpus,
retaining original refusals and intentional newly available reductions. Each
changed price is scored against independent references at unchanged targets;
unchanged rows retain complete payload identity. New arithmetic indicators must
contain independent terminal reference intervals in the exercised cases.

Use unchanged `bench/american_iv.ml` for matched controls (same exact quotes,
width .005, 64 price calls, 128/128 cells, three domain expansions and budgets).
For the terminal cash price and inverse/end-to-end paths, require at least 90%
less median latency and cumulative allocation. General American put and
analytical controls allow at most 10% latency/5% allocation regression. These
are engineering adoption criteria, not an SLA or universal budget. Include a
separate piecewise terminal-call price control with the same model before/after.
Any subsequent general-solver optimization gets its own derived change and
frozen acceptance criteria before scoring, preserving full results unless an
independently qualified numerical change is explicitly intended.

Run development/release ordinary, affected compiled mutations, native/bytecode
installed consumers and complete independent campaigns. Finish owned compute
before five alternating fresh-process timing pairs; retain identities, all raw
samples, GC, per-child RSS, failures and host load. Do not change accuracy,
resolution, requests or targets to meet an improvement threshold. Default CI
remains five jobs and seven core mutants. Publish remaining general cost and an
explicit adopt/defer disposition for specialized-method evaluation.
