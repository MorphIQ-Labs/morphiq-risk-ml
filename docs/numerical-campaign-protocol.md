# Numerical boundary campaign protocol v1 (#54)

This protocol is fixed before scoring the new campaign. It extends the
[oracle assurance controls](oracle-assurance.md), using original binary64 inputs
and independent exact-rational/Arb references. It does not create an availability
promise over all mathematically admitted inputs. Version 1 is a deterministic
coverage design, not a proof that the chosen grid finds all boundary defects.

## Coverage matrix

Every generated case has a stable ID, region, model, side, quantity, interface,
original input words and reference outcome. Both sides and all four models are
represented where the mathematical contract supports the mechanism.

| Region | Input construction before scoring | Quantities and observations |
| --- | --- | --- |
| expiry | T = 0 and its next positive binary64 neighbor; negative T control | exact payoff, IV expiry classification, explicit production Greek exclusion |
| zero variance | sigma = 0 and its next positive neighbor, at and adjacent to ATM | price, ten Greek fields; coordinate-specific kinks versus unsupported production capability |
| shifted positivity | displaced F+d/K+d exactly below, at and above zero; finite-high-word overflow | admission checked separately, original sparse sums retained |
| scale | dyadic scales from subnormal to large finite; scale normal volatility in currency units | prices and all ten Greeks, finite certificate/fast-output availability |
| cancellation/Greek zeros | S/K around one, exact forward ATM, carry cancellation, rT around 1/2 | absolute errors around zeros; no relative-only success gate |
| sparse low words | independent mantissas and widely separated exponents in original shifted coordinates | price/Greek/IV; no rounded shifted inputs substituted for the model |
| arithmetic thresholds | adjacent binary64 rates at model exponential arguments ±256 and ±1024, Gaussian/tail transitions | availability by region, original-input Arb references |
| intrinsic quotes | zero-variance price rounded down/up and quote neighbors | zero-root convention versus below-intrinsic versus positive inverse |
| maximum quotes | exact/rounded discounted asset or cash leg and quote neighbors | above-maximum classification versus unresolved sparse gap |
| IV cells | quotes at/adjacent to an independently evaluated volatility midpoint | independently checked positive-root rounding cells; unresolved comparisons retained |
| IV exact ties | exact dyadic monotone residuals at even/odd root-cell boundaries | certified solver owner; synthetic controls explicitly separate from financial cases |
| arbitrary low words | exact sums of arbitrary finite high/low words through `Enclosure.of_words`, including overlap/cancellation | independent rational enclosure checks; DD normalized-word preconditions are not assumed for arbitrary inputs |
| overflow interactions | finite individual inputs with overflowing shifted sum, distance, discount product or scaled derivative | admission versus computational failure versus incorrect successful output |

The fixed central `greek_zeros` neighborhood (S/K around 1, T=1, sigma=0.25,
zero rates) requires successful values as a bounded availability regression.
This finite obligation does not extend to extreme-scale/capability regions.

Smoke and full memberships are chosen by a versioned deterministic generator,
not by observed pass/fail results. Full mode adds exponent/mantissa combinations
and a fixed-seed sample. The smoke subset includes each region and all models;
its independently generated references are committed for offline ordinary CI.
The full campaign is manual and strict: a quality excursion returns nonzero.
Ordinary CI explicitly uses `--contracts-only`: it enforces certificate, input,
class and central-availability contracts and still emits all quality excursions
as findings. It never asserts the observed faulty words as expected outputs.
A green contract gate is not a clean accuracy campaign. Neither lane changes
the seven core CI mutants.

## Reference and scoring rules

1. Inputs denote their exact binary64 values. Financial validity is checked from
   those originals; exact shifted sums use rational arithmetic. Input refusal,
   production capability exclusion and a numerical failure are distinct.
2. Price references use independent Arb erfc formulas; smooth Greeks use formal
   price-series differentiation and polarization. Expiry/payoff and supported
   boundary identities use exact rational arithmetic or independently derived
   boundary formulas. Unsupported reference formulas remain unresolved.
3. Escalation uses 256, 512, 1024, 2048 and 4096 bits. Narrow intervals are retained
   as exact dyadic endpoints. Repeated precision agreement alone is not accepted.
   Tiny positive time value at a midpoint retains the existing independent
   one-sided proof. Reference uncertainty is never discarded before scoring.
4. A production certificate succeeds only if its finite reported radius meets
   the caller's preselected limit and contains the entire independent reference
   enclosure. Disjoint intervals prove failure; overlap without containment is
   unresolved reference precision, never an accuracy success. Limits are fixed
   before results: a generous finite maximum for arithmetic capability and
   selected zero/tight limits for accuracy-request refusal controls.
5. Positive IV roots require independently resolved exact midpoint residual signs
   or an exact tie decision, not repricing equality. Mathematical outcome classes
   require independent boundary evidence. `Numerical_failure`/`Non_convergence`
   remain availability outcomes and do not prove a mathematical classification.
6. Fast finite values are compared with independently resolved rounding cells.
   Greek allowances come from `Budget_greeks`; additional price diagnostics use
   `Bounds.price_ulp_budget_max` (32 ULP for Black, 8 for Bachelier). The original
   corpus retains all its stronger region-specific and derived price gates.
   These new diagnostics do not replace or widen those gates; errors are retained.
   The empirical envelopes do not become universal guarantees for new extreme
   inputs. Excursions are findings, not silently expanded budgets. Nonfinite
   fast price results and explicit Greek failures are reported separately;
   successful nonfinite Greek payloads violate their contract.
7. Record successful value checks, supported class checks, input refusals,
   capability exclusions, numerical failures, reference uncertainty and quality
   excursions separately by model/quantity/region. Every requested ID has one
   outcome; duplicate, missing, corrupt or truncated rows fail the campaign.

## Work and provenance limits

The generator has explicit smoke/full row caps (at most 50,000 requests), fixed
seeds, finite neighbor/exponent lists and no adaptive search based on successes.
Reference construction uses at most five precision levels. A reference worker
and each runtime batch have wall-clock limits; timeout, malformed output or a
failed executable is a tool failure, never a numerical finding. Excessive real
exponents that cannot be serialized within the reference representation are
explicitly unresolved rather than allocated without bound. Exact input words
remain available even for these rows.

Retain generator version, seed, membership/row count, transitive source hashes,
compiler/tool versions, exact runtime source revision, output identities and
reproducible commands. Existing fixtures and canonical comparator outputs are
not silently repaired. Findings retain original cases and use #55's independently
resolved reduction principles; permanent regressions and disposition are linked
from #57. This campaign is experimental engineering evidence, not independent
human sign-off, institutional deployment acceptance, or a release/tag.
