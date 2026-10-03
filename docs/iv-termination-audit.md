# IV termination and failure audit

This change addresses the silent-success and false-classification paths in
Bug #14. It does **not** close that issue or qualify Epic #27 for production.
The remaining exact-model boundary and runtime uncertainty obligations below
must be resolved before claiming that scope complete.

## Path audit

| Path | Result and remaining scope |
| --- | --- |
| Invalid original input or quote | Typed `Refusal`, before inversion; unchanged. |
| Expiry | `Not_identifiable_at_expiry`; unchanged. |
| Black maximum/intrinsic and Bachelier intrinsic | DD comparison retained after finite-coordinate checks. It is still an approximation; uncertainty at an unresolved boundary needs enforcement. |
| Rounded intrinsic | Historical zero-volatility convention retained and tested; not an assertion that arbitrary DD evaluation is correctly rounded. |
| Black initialization | LBR's fixed Householder count produces a proposal. It no longer establishes successful inversion by itself. |
| Black complement/log/ordinary correction | Each uses the appropriate evaluator in final validation. A failed local bracket returns `Numerical_failure`. |
| Bachelier initialization | Outward upper endpoint plus evaluated zero lower endpoint. Both residual signs are checked. |
| Newton proposal | A nonfinite or out-of-bracket proposal falls back to bisection. |
| Price evaluation | A nonfinite evaluation is an explicit computational failure. |
| Stagnation | Small steps are not success; an evaluated match or adjacent-float sign bracket is required. |
| Iteration exhaustion | `Non_convergence`, with no candidate exposed as `Root`. Forced exhaustion is tested. |
| Final coordinate conversion | Nonfinite/nonpositive positive-root results are `Numerical_failure`. Overflow/underflow alone does not prove `Above_maximum`/`Below_smallest_volatility`. |
| Exact-root accuracy | Executed price/vega certificates plus unchanged historical quality gates on all 5,575 positive oracle roots. These are test evidence, not runtime enclosures. |

See [the derivation](error-analysis.md#6-implied-volatility) for the integer
bisection termination bound and nonlinear certificate transport.

## Canonical reference

The author's 2024 C++ archive was built and executed at SHA-256
`da2f6870b213e04ef35b4d309269ee5ce12be5830d9733e5f29542bf7b652470`.
The unchanged sources compile with Homebrew GCC 16.2.0, C++17, `-O3`,
`-ffp-contract=off`, `-DNO_XL_API`. Apple Clang rejects the author's half-fraction
identifier; the reference was built with GCC rather than editing its source.

[The retained comparison](evidence/iv-canonical-baseline.json) records 25
normalized cases, including boundary quotes, and exact-quote inverse references
refined at 100/200 decimal digits. Agreement at two precisions is evidence,
not an interval proof. The author's binary64 forward value supplies the exact
quote; the generating total volatility is not used as the inverse reference.
The same script also resolves a Bachelier put with `F=max_float`,
`K=-max_float`, `T=1`, `r=0`, quote 1 at 100/200 digits: its finite real root
rounds to `0x1.b64a6da11aae1p+1019`. The displacement overflows the current
evaluator, which now reports `Numerical_failure`; claiming `Above_maximum`
would be mathematically false. The regression retains that distinction.

This is a smoke comparison, not the adversarial independent review required
by #15. The Bachelier implementation remains a safeguarded Newton method;
it is not represented as a port of Jäckel's normal-volatility approximation.

Reproduce with the recorded archive and pinned mpmath environment:

```sh
oracle/.venv/bin/python scripts/canonical_iv.py /path/to/LetsBeRational.7z \
  --compiler g++-16 --output /tmp/iv-canonical-baseline.json
```

The script also requires libarchive's `bsdtar`. It checks the archive hash
before extracting, builds in a temporary directory, and records compiler
flags and every comparison. It is optional research tooling, outside CI.

## Compatibility and observed accuracy

Adding two cases to the exhaustive `Iv.t` variant is a breaking API change
under [the stability policy](stability.md). Callers must handle computational
failure separately from mathematical classifications. No release is tagged
by this work.

On the existing exact-input IV fixture, baseline `7b93c2a` versus this change:

| Model | Positive roots | Worst root ULPs before | After | Existing quality gate |
| --- | ---: | ---: | ---: | --- |
| BSM | 1,754 | 4 | 5 | passes unchanged |
| Black-76 | 1,802 | 4 | 4 | passes unchanged |
| Displaced | 1,162 | 5 | 5 | passes unchanged |
| Bachelier | 857 | 8,992,716,596 | 6,084,654,728 | passes unchanged |

The very large normal-model ULP counts are ill-conditioned subnormal quotes;
the absolute price quantum and inverse vega determine attainable root
accuracy. They are not uniform-ULP promises. Bachelier rounding-cell membership
increases from 687 to 765 rows, but membership is diagnostic, not acceptance.
The oracle generators and compressed fixtures are unchanged.

The intentional IV changes move the determinism digest from
`f402d24368b0028ab140dcecbed0b767dbdcf8456c978829a0187353f4d8c44a` to
`a7748579580fce931e2b271d66f2822f99f1fa1e737d5738209d3b282b57a5e4`.
Cross-platform CI must validate the new digest; a local digest alone does not
establish platform agreement.

## Performance evidence

[Four retained ABBA runs](evidence/iv-termination-bench.json) compare baseline
`7b93c2a` with the candidate library source hashes on an Apple M1 Pro, OCaml
5.3.0 Flambda `-O3`. Each run uses the existing benchmark's warm-up and median
of seven passes. Ranges below are the two run medians, in microseconds per
operation; they measure scalar throughput, not request latency.

| Model / regime | Baseline | Candidate |
| --- | ---: | ---: |
| BSM / near money | 2.636–2.639 | 3.219–3.238 |
| BSM / OTM tail | 2.644–2.647 | 3.205–3.221 |
| BSM / ITM | 2.754–2.822 | 3.368–3.369 |
| Bachelier / near money | 3.295–3.341 | 6.077–6.078 |
| Bachelier / OTM tail | 6.135–6.531 | 6.584–6.587 |
| Bachelier / ITM | 5.750–5.826 | 6.620–6.628 |

Additional evaluation and bracket validation have a measurable cost. The
initial implementation forced an encoding midpoint every second step and
spent about 13 microseconds per normal inverse; retaining a mandatory fourth-
step split and using checked arithmetic midpoints otherwise avoids needless
excursions across exponent ranges while preserving the finite bound. A small
Newton proposal only prompts an adjacent evaluation, never success by itself.

This shared-workstation comparison has no host isolation or production SLA.
Allocation/GC, operational load, representative portfolios and requirements
fixed before performance acceptance remain #8/#16 work. The current scalar
benchmark does not establish safe parallel throughput or institutional fitness.

## Remaining release blockers

- Enforce a supported production domain and the error/materiality requirements
  fixed for it (#13). Current model admission still accepts more than the
  executed certificate domains.
- Bound classification uncertainty at intrinsic/maximum and exponent extremes,
  including the special tiny-carry price path. Finite DD words alone do not
  establish an exact mathematical comparison.
- Expose an exact-model enclosure or an explicit unresolved outcome when a
  caller needs a runtime error guarantee. An adjacent bracket for a rounded
  evaluator is not automatically a bracket for the exact real model.
- Complete independent review, representative-engine shadow validation,
  operational performance requirements, and named acceptance of an exact
  candidate (#15, #16, #17). None is supplied by a passing local test suite.
