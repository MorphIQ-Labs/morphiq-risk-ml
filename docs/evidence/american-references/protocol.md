# Frozen American reference campaign v1 (#110)

Freeze this protocol and `cases-v1.json` before executing or scoring prices.
Inputs are original binary64 words, with the #108 immediate-settlement BSM
contract and #109 engineering epsilon=2^-16 max(S,K). No observed output may
change those thresholds. Zero-scale cases require exact zero.

The initial corpus covers both sides, moneyness, short/long expiry, low/high/zero
volatility, signed rates/yields, delayed opening, exact boundaries and powers-of-
two currency scaling. A deliberately extreme drift/volatility ratio can make a
finite CRR tree inadmissible; retain that failure. Future cash/Bermudan/curve
examples are separate versioned specifications, with exact deterministic witnesses;
this campaign does not qualify general stochastic extensions.

## Independent routes and uncertainty

1. Build the original project QuantLib adapter against commit
   `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c`. Reuse the previously built library
   only after its source/configuration/binary hashes match the recorded build
   and a build-system recheck succeeds. Record that reuse explicitly. Exercise
   the finite-difference engine with Crank–Nicolson, two damping steps and both
   grid dimensions at 128/256/512/1024. No source is imported into the runtime.
2. Independently derive a two-branch stock tree: u=exp(sigma sqrt(dt)), d=1/u,
   p=(exp((r-q)dt)-d)/(u-d), discount=exp(-r dt). Backward induction takes the
   maximum of payoff and continuation at permitted nodes. Probability outside
   [0,1], overflow, or a zero-volatility division are explicit unavailable routes.
   Use a standalone original C++ runner, not a QuantLib lattice.
3. Evaluate paired CRR sizes N,N+1 at N=512/1024/2048/4096. A(N) is their average;
   the three candidates 2*A(2N)-A(N) are an **empirical extrapolation**, not a
   proved convergence order or bound. Use the finest candidate and radius
   4*max(last two candidate differences), plus the frozen roundoff screen.
   Resolve an empirical fixture only if radius<=epsilon/8, precision checks pass,
   and financial checks do not contradict it. Otherwise retain it unresolved.
4. Replay discrete trees at 64 or 128 steps in mpmath 1.3.0 at 80 and 160 digits.
   Compare the same discrete target with the standalone runner, using epsilon/64
   as a screen. This checks arithmetic independently; it does not bound continuum
   error. Both precision outputs and the selected step count are retained.
5. Independently enclose analytical expiry/zero/deterministic/European-reduction
   cases and matching European terminal prices with python-flint 0.9.0 Arb at
   256 and 512 bits. Retain rational endpoints and route identity. No European
   certificate is transferred to a general American case. Ambiguous stationary
   point inclusion/signs remain unresolved. Exact cash-event examples also use
   a separate rational event replay against the stated expected values.

At each base tree size divisible by four, evaluate matching terminal European,
quarterly Bermudan (intersected with the American window), and American rights
on the same tree. Their sets are nested, so order must hold up to an explicitly
recorded floating-point screen. Delayed-opening indices use exact-rational ceil
of opens*N/T: this restricts exercise to eligible grid nodes and contributes
stopping-time discretization error; it does not redefine the input window.
Do not claim that the discrete Bermudan/European values bound the continuum
American price. Also compare American references with independently enclosed
European values, currently available intrinsic and general signed-rate bounds.
Scaling checks use exact powers of two and the independently recorded widths.

## Canonical conventions and scoring

QuantLib uses evaluation date 2025-01-01, Actual/360, flat continuously compounded
r/q, flat annual lognormal volatility and AmericanExercise with immediate payment.
Require each mapped year fraction to equal the original input word; otherwise
retain a mapping exclusion. Its same-date Instrument NPV=0 convention is not the
project's expiry payoff. Zero-stock/strike/volatility exceptions are retained;
no fallback turns a failed canonical call into a reference price. No cash events
or date rounding are silently inserted into the initial canonical comparator.

The independent reference's endpoints, status and radius are authoritative for
its *stated* scope only. Per-level canonical values and exceptions remain raw
evidence. A comparison passes only when max(|canonical-L|,|canonical-U|)<=epsilon
and reference radius<=epsilon/8. Missing/nonfinite/unresolved/incompatible rows
cannot pass. Empirical intervals support empirical comparisons, not rigorous
accuracy claims. Keep failures and discrepancies per case; investigate before
classifying a candidate as an accepted runtime implementation.

## Reproducibility and controls

Keep the corpus, source/compiler/build/binary identities, exact input streams,
raw output, all refinement and precision outcomes, reference fixture and a
transitive SHA-256 manifest. Generation is an optional serial campaign with
bounded process time; default CI checks committed fixtures and lightweight
failure controls offline, without QuantLib, mpmath, Arb or private research.

Exercise duplicate/missing rows, truncated and nonfinite output, corrupt fixture
bytes, changed source/corpus provenance and a deliberately incorrect price/
expectation. Assert the intended rejection. Failed processes preserve raw output
and cannot publish a complete fixture. Public runtime prices are not changed;
#111 must consume references and resolve its own unsupported/accuracy outcomes.
