# Exchange implementation reference protocol, version 1

This preparatory record belongs to #60 and follows `../../first-model-extension.md`.
It is not a completed qualification report. Case membership in `cases-v1.json`
is frozen before running references or changing runtime code. Hexadecimal words
are the original binary64 inputs, including invalid-input controls. No row is
removed on timeout, arithmetic failure, disagreement or tool failure.

The independent Python generator uses exact rational covariance from those
words, then Arb exp/log/erfc for the closed form. Its second positive-variance
route integrates the positive branch of the lognormal payoff. The integrand
is entire, so the analytic callback never applies a nonsmooth positive-part
operator. For the uncertain strike crossing [lo,hi], its omitted strip is
bounded by (hi-lo) * a * exp(-v/2+s*hi) / sqrt(2*pi); the normal exponential
is at most one. Clipping the strip and integration endpoints to [-L,L]
handles crossings outside the integration interval.

L = upper(s)+16. The omitted tails are at most
`a * (exp(-(L-s)^2/2)/((L-s)*sqrt(2*pi)) +
      exp(-(L+s)^2/2)/((L+s)*sqrt(2*pi)))`.
All terms, endpoint uncertainty and quadrature error remain enclosed. The
strip and tail are added symmetrically as a conservative radius. Boundary
rows instead use exact expiry/zero identities or independent discounted
intrinsic intervals; they do not pretend to be two quadrature observations.

Before scoring, resource limits are fixed: precisions 256, 512, 1024, 2048,
4096 bits; one row per isolated 60-second worker; quadrature degree 128,
20,000 evaluations and depth 30. The quadrature capability guard is s<64.
The reference width goal is 1e-25 * max(1,a), distinct from the runtime
absolute-error request. A route disagreement is an error, never a pass;
route overlap alone is not certificate acceptance. Both full intervals are
retained for later certificate containment checks. Hard rows may remain
unresolved and must appear in the denominator and outcome table.

Reproduce with the pinned optional Python/Arb environment described in the
selection contract:

```sh
python scripts/exchange_reference.py freeze /tmp/exchange-cases.json
cmp /tmp/exchange-cases.json docs/evidence/exchange-implementation/cases-v1.json
python scripts/exchange_reference.py run \
  docs/evidence/exchange-implementation/cases-v1.json /tmp/exchange-references.json
```

No production runtime change is part of this protocol freeze. QuantLib's
pinned canonical build, date/curve input mapping, runner and baseline will
be retained before runtime implementation. Performance and broader #61
qualification remain separate evidence, not implied by this reference setup.
