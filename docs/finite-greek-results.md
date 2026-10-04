# Finite fast Greek results (#62)

Initial reproduction: `377a36fb252c1285ec203beee0ba1ae81471e756`.
Final baseline: merged optimization `e8ed54219a473c72a18a318b90381ed0d91ff80a`.
The optimization did not change these outputs.

## Contract and derivation before scoring

Every field returned by a fast model Greek API must be either a finite binary64
value in its declared units, `Payoff_kink` for its existing coordinate-specific
boundary, or `Numerical_failure` for unresolved arithmetic. Finite acceptance is
not an error certificate. The production adapter keeps its separate enclosure
and caller-limit requirements. Existing output bits are comparison evidence,
not correctness criteria: independently check finite results too, and correct
or refuse unsound outputs. Do not replace nonfinite arithmetic with a guessed zero.

For the reported exact-input cases F=100, K=101, T=1, r=0 and the binary64
number denoted by `1e-310`, gamma is positive but rounds to +0. The volatility
lies strictly between 2^-1030 and 2^-1029. In Bachelier, |d|=1/sigma>2^1000.
For Black-76, ln(101/100)>1/101 (integrating 1/x on [1,1.01]); hence
|d1|=ln(101/100)/sigma-sigma/2>2^1000 as well. Both gamma prefactors are below
2^1030, since 1/sqrt(2*pi)<1 and the Black prefactor also divides by F=100.
Thus gamma < 2^1030 exp(-2^1999) < 2^-1076, strictly below half the smallest
positive subnormal, 2^-1075. This argument uses original exact model inputs,
not the fast kernel's overflowing intermediate coordinates.

The existing split quotient/square/prefactor operations can already be
nonfinite before the tail exponential sees them. Applying a zero tail to an
infinite or NaN prefactor does not recover the original real quantity. This
fix retains the existing scaling where it works and reports explicit failure
otherwise. No new tail cutoff or approximation is introduced. Refusal remains an honest
capability outcome when the existing scaled arithmetic cannot resolve a value.

## Wrong finite results and root-cause corrections

Independent formulas revealed two further mechanisms; baseline agreement is
not an acceptance rule:

- At S=100, K=101, r=q=0 and T=2^-1074, put BSM rho was -128 times the
  subnormal quantum instead of -101 times it: 27 ULP wrong, outside its
  existing 16-ULP gate. Both zero volatility and sigma=0.2 expose premature
  multiplication of T by a normalized cash leg before currency rescaling.
- At F=100, K=101, T=1, r=-2000 and sigma=0, Black-76/displaced put rho was
  finite zero although its real magnitude exceeds binary64. The fast intrinsic
  had become NaN; `i.hi > 0` was false, converting unresolved arithmetic into
  a zero price, which rho then consumed.

For the first mechanism, keep each factor's exact binary exponent until final
currency scaling. `frexp` mantissas lie in [1/2,1) in magnitude; their products
remain in [1/4,1), are renormalized by exact powers of two, and retain the usual
per-multiplication rounding. The sign factor is exact. Only final `ldexp` can
round into the subnormal range. In the tail term, split T=m*2^e and add e to
the existing scaled exponential's exponent, preserving the same real formula
and existing exponential allowances. The exact-rational/per-input certificate
replay follows these operations and transports its existing error bounds.
No new empirical threshold or larger tolerance is used. Exact out-of-money
zero-variance rho remains +0; an initial draft's unnecessary negative zeros
were identified by replay and removed before acceptance.

For the second mechanism, a nonfinite double-word intrinsic cannot establish
its sign or a zero payoff. Propagate NaN through the existing float-returning
fast price API; the Greek result owner then returns Numerical_failure. The
production adapter continues to enforce its independently computed enclosure.
This deliberately changes some previously finite zeros into explicit failures,
including conservatively refused zeros when the intermediate sign is unresolved.
Soundness takes priority over availability. The generic fast price signature
is not redesigned in this fix.

## Independent challenge references

The fixed 880 outcomes span four models, both sides, all ten fields, ordinary
inputs, tiny volatility, subnormal time, subnormal coordinates, overflowing
discounts, zero variance and expiry. Displaced cases use displacement 0.125.
The fixture stores all original binary64 input words. Its generator uses
real-model closed forms at 1280/2560 decimal digits and exact boundary identities;
80 ordinary results also agree with independent price differentiation.

The initial 640-digit run lost a tiny tail-price contribution (zero-sign
agreement failed). Precision was increased, without dropping the case or
weakening the comparison. A rational exact-input witness separately proves
the reported Black-76 and Bachelier gammas round to zero. Precision agreement
and these finite checks are not a universal interval proof of the oracle.

Successful challenge outputs must meet the existing per-field ULP budgets;
a zero reference requires an actual zero. Refusals are counted separately,
never as accuracy successes. Kinks must match the defined varied coordinate.
The new scorer rejects nonfinite inputs and avoids signed-integer distance
overflow; it has explicit NaN, adjacent-value, signed-zero and opposite-sign
rejection controls.

## Scope and ownership

Audit all ten fields in Black.Make (BSM, Black-76 and displaced Black), Bachelier,
positive-variance, zero-variance and expiry paths. The Greeks owner checks the
completed per-field result in its output units. Existing classifications must
be justified by the model/capability contract;
one failed field does not automatically discard sound successful siblings.
Public raw unit constructors remain trusted labels; this does not turn them
into certificates or restrict callers constructing their own records.

A change from `Ok nan`/`Ok infinity` to an explicit refusal is a **major outcome
change** under the stability policy (a minor version increment while 0.y.z),
even though it fixes a defect and adds no variant. No version bump is implied
by the implementation PR. Ordinary reference budgets remain fixed. Finite-value
changes require independent correctness evidence and explicit compatibility
records. Expanded adversarial coverage remains under #54.

## Qualification and compatibility

[Per-case changes](evidence/finite-greeks-changes.json.gz) and the
[summary](evidence/finite-greeks-compatibility.json) retain exact input/reference
words and source hashes. Of 880 challenges, the final implementation serves
582 independently checked finite values, 200 explicit numerical failures and
98 coordinate kinks. Refusals are availability outcomes, not accuracy passes.

Compared with the final baseline, 188 successful nonfinite values become
Numerical_failure. Four finite zero rhos become explicit failures: two put
values are mathematically outside binary64, while two out-of-money call zeros
are conservatively refused after unresolved intrinsic arithmetic. Two BSM put
rhos change from -128 to -101 subnormal quanta, reducing error 27 → 0 ULP for
positive and zero volatility. All ten Greek fields have nonfinite regression
coverage; neither a baseline match nor a finite payload establishes correctness.
[Before](evidence/finite-greeks-before.txt.gz) and
[after](evidence/finite-greeks-after.txt.gz) retain every challenge outcome.

All 66,400 existing Greek oracle outputs remain identical, with unchanged
regional maxima and budgets; [baseline](evidence/finite-greeks-ordinary-before.txt.gz)
and [candidate](evidence/finite-greeks-ordinary-after.txt.gz) scorer reports
retain the per-Greek errors. Both established replay digests remain unchanged:
financial `e2fae65de27c7f4add63b5a476c833fcc91f1efdafde9a73950ba34db3382593`
and inverse `91bedc0a4352538aa60ae7c831f27bcaf16be0058a45daa3d6c33f2501344c19`.
Their fixed corpora do not include every new challenge; the new fixture provides
separate independent evidence rather than weakening the existing digests.

Build/install/format and full ordinary suites pass in
[development](evidence/finite-greeks-development.txt.gz) and
[release](evidence/finite-greeks-release.txt.gz), including numerical bounds,
exact-rational/per-input certificates, production limits, IV and planner tests.
All [seven affected mutants](evidence/finite-greeks-mutations.log) build and
fail their designated numerical guard after a clean baseline: four new
finiteness/intrinsic/rho mechanisms and three existing intrinsic/scaling
mechanisms. The default seven-core selection remains unchanged; the full
optional catalog now has 65 mechanisms.

Installed native and bytecode consumers both execute the complete 880-outcome
challenge and production certificate controls. The
[package record](evidence/finite-greeks-install.json) retains results, consumer
hashes and byte-for-byte checks of installed documentation/notices. For the
reported gamma request, the unmodified production Black-76 adapter certifies
zero with a positive bound covering the independent underflow proof; Bachelier
explicitly refuses. The tests accept sound certificates or appropriate explicit
numerical/accuracy failures rather than freezing those historical outcomes.

## Measured cost

[Raw ABBA evidence](evidence/finite-greeks-benchmark.json.gz) compares the final
baseline and candidate in release on Apple M1 Pro, macOS 27.0, OCaml 5.3.0
Flambda with `-O3`. Harness source and inputs are identical: 64 deterministic
inputs per model/regime, seven batches per run, sequential A/B/B/A processes,
with all task-owned checking stopped. One-minute host load spans 5.24–6.26.
Candidate source hashes identify the measured uncommitted state; the recorded
parent commit alone does not describe the final measured code.

All-ten-Greek median changes span -1.71% to +4.08%; full workflows span -1.13%
to +1.30%. These small shared-host timing differences are not an isolated
performance bound. Allocation changes are deterministic in this harness:
+11 words per Greek record for Black-76/displaced/Bachelier, and +67 for BSM
including retained-exponent rho products. For example, BSM ATM Greeks measure
7.039 → 7.289 microseconds and 1,858 → 1,925 words/call. Outcomes, batch ranges,
GC/heap samples and per-request distributions remain in the raw artifact.
No accuracy or failure requirement is traded for speed.

## Reproduction and remaining scope

```sh
oracle/build.sh finite_greeks
opam exec --switch=morphiq-risk-ml -- dune build -j 2 @install @fmt @runtest
opam exec --switch=morphiq-risk-ml -- dune build -j 2 --profile release --build-dir _build-release @install @runtest bench/assurance.exe
opam exec --switch=morphiq-risk-ml -- dune exec test/finite_greeks.exe -- _build/default/oracle/fixtures/finite_greeks.txt
# MORPHIQ_FINITE_GREEKS_RECORD_ONLY=1 prints comparison outcomes; it is not a passing accuracy run.
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- greek-finite-result intrinsic-nonfinite-price greek-live-rho-scale greek-zero-rho-scale intrinsic-coordinate-scale intrinsic-tiny-carry intrinsic-expm1
# Prepare the identical release assurance harness in the baseline; stop checks before timing.
python3 scripts/benchmark_assurance.py --baseline BASELINE/_build-release/default/bench/assurance.exe --baseline-revision e8ed54219a473c72a18a318b90381ed0d91ff80a --same-contract --candidate _build-release/default/bench/assurance.exe --count 64 --runs 7 --output BENCH.json
```

The usual three-platform/core-mutation CI gates remain required before merge.
Broader extreme-input availability and successful-value accuracy remain under
#54; this is not whole-domain certification. The same-pattern audit covers
Black.Make, Bachelier, expiry, zero variance, all ten fields, production result
acceptance and the price intrinsic consumed by forward rho. Public IV retains
its separate exact-model acceptance and passes its ordinary references.

The new scorer also exposed a separate legacy signed-distance defect:
`Int64.abs (Int64.sub (ordered 2.) (ordered (-2.)))` is negative by overflow.
Analogous existing scorer definitions are enumerated in
[#55](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/55), which owns their
separately reviewable consolidation and endpoint/nonfinite rejection controls.
This challenge scorer rejects that witness. Existing corpus identity and
per-input certificates are retained without claiming the legacy ULP scorers
are universally sound.
