# IV termination and failure audit

The public inverse now requires an exact-model runtime certificate. Fast
Black/Bachelier inverses supply proposals only; their rounded comparisons or
convergence checks cannot classify a quote or accept a public root. This
addresses Bug #14's numerical contract; independent review, production use,
portfolio validation and version acceptance remain Epic #27 obligations.

## Path audit

| Path | Enforced result |
| --- | --- |
| Invalid original input or quote | Typed `Refusal` before inversion. |
| Expiry | `Not_identifiable_at_expiry`. |
| Intrinsic/maximum | Original-input expansion enclosures, including unscaled displaced low words. An inconclusive cheaper attempt retries the full enclosure; unresolved signs fail. |
| Rounded intrinsic | Zero only after exact equality or a proved intrinsic rounding-cell decision, including tie parity. |
| Initialization and Newton | Bounded fast computations supply untrusted proposals; a failed proposal falls back to 1.0 for certified bracketing. |
| Price/residual evaluation | Independently enclosed real model. Quote scaling retains subnormal-quote information; nonfinite arithmetic or unresolved signs fail. |
| Stagnation | No small-step or rounded-price-equality success. |
| Bracket and stopping | At most 64 encoding expansions and 63 bisections, then a proved exact midpoint decision; alternatively a proved rounding cell. |
| Iteration exhaustion | `Non_convergence`; no last iterate becomes a root. Forced exhaustion is tested. |
| Final coordinate | Certification evaluates annual volatility directly. A positive root is nearest-even binary64; under/overflow cannot impersonate a representability classification. |
| Extreme representability | `Below_smallest_volatility` or `Above_maximum` requires a proved endpoint comparison. Otherwise numerical failure. |
| Accuracy | All 5,575 positive reference roots must match the correctly rounded reference, alongside analytical transport and historical quality checks. |

See [runtime arithmetic](runtime-enclosures.md), [model enclosures](model-enclosures.md)
and [exact-model IV acceptance](certified-iv.md) for the derivations.

The sparse shifted contract `F=K=2^64`, displacement `2^-1074`, T=1, r=0,
quote `2^64` has a finite real inverse: its maximum is strictly greater than
the quote. Losing the displacement during currency scaling would incorrectly
classify it as above maximum. Original input words now preserve that distinction;
the unresolved inverse explicitly returns `Numerical_failure`. The tiny-carry
price path is similarly not evidence that a classification can be resolved.

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

The current public contract is stronger: all 5,575 exact-quote reference roots
are correctly rounded (zero ULP from the rounded reference), with no refusals
in that corpus. The tables below retain the earlier proposal/termination-stage
evidence at `55d4d9e`; they do not describe final certified acceptance.


Adding two cases to the exhaustive `Iv.t` variant is a breaking API change
under [the stability policy](stability.md). Callers must handle computational
failure separately from mathematical classifications. No release is tagged
by this work.

At the first termination stage, baseline `7b93c2a` versus `55d4d9e`:

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

## Historical proposal-stage performance evidence

The current certified inverse is substantially more expensive. The
[current A/B/B/A benchmark and profile](performance.md) report its cost,
allocation, GC and measurement limitations. The numbers in this historical
section must not be used for the runtime-certified API.

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
- Extend availability where needed by the supported production use. Runtime
  enclosures now enforce uncertainty rather than claiming every admitted input
  can be successfully resolved. Price/Greek production guarantees are separate.
- Measure the additional cost of runtime certification; the historical timings
  above cover proposal generation and are not current public inverse timings.
- Complete independent review, representative-engine shadow validation,
  operational performance requirements, and named acceptance of an exact
  candidate (#15, #16, #17). None is supplied by a passing local test suite.
