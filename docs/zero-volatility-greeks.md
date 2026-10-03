# Zero-volatility ATM derivatives

Bug #34 concerns positive maturity. A kink in the underlying coordinate does
not imply a kink in every coordinate. Volatility derivatives at sigma=0 are
right derivatives on the admitted nonnegative volatility domain.

For a fixed-forward model with F=K, the zero-volatility value is identically
zero for every finite rate and positive maturity. Consequently rho and theta
are exactly zero. For displaced Black the same identity holds on exact shifted
coordinates. For BSM the corresponding time identity holds when S=K and r=q;
rho remains undefined because varying r holds q fixed and moves the forward
through the strike. A rounded zero log-moneyness is insufficient to establish
any of these identities: the original coordinates must establish equality.

At ATM the Black price is A [2 Phi(sigma sqrt(T)/2)-1], where
A=(F+shift) exp(-rT), or S exp(-qT) for the BSM identity. Its right vega at zero
is A sqrt(T)/sqrt(2 pi). For Bachelier the ATM price is exactly
exp(-rT) sigma sqrt(T)/sqrt(2 pi), and its right vega is the coefficient of
sigma. Thus in each smooth time case

    veta = W exp(-rT) (rT-1/2) / (365 sqrt(2 pi T)),

where W=F+shift for Black, W=S for BSM with r=q, and W=1 for Bachelier.
The factor rT-1/2 is formed before division; it avoids forming 1/T and exposes
the exact zero when rT=1/2. All original words of a displaced sum are retained.
This formula is independent of call/put. Differentiating the ATM price also
shows that the one-sided volga at zero is zero. Delta, gamma and the mixed
Greeks requiring a defined spot derivative retain their payoff-kink refusal.

Numerical evaluation uses outward runtime enclosures of the original inputs,
pi, sqrt and exp. A new successful boundary veta is accepted only when its
whole enclosure is in one finite binary64 rounding cell (including the exact
zero identity). Arithmetic or rounding uncertainty is a numerical failure,
never a payoff kink. This additional refusal is an explicit exhaustive-variant
API change. Existing smooth positive-volatility fast Greeks keep their current
certificate scope; this fix is not a universal certification of that API.

The proof concerns T>0. Expiry time derivatives have a separate one-sided
maturity contract; this change must not silently infer an expiry derivative
from the positive-maturity identity.

## Compatibility evidence

The [replay comparison](evidence/boundary-greeks-replay.json) covers 30,240
model records. Only previously refused fields change: 350 theta, 270 rho and
350 veta results. Prices, IV outcomes/values and all previously served Greek
values are unchanged. The digest becomes
`f37fbff0dd5af9c27ad88322802ebab43d961de60f916504076356a50501de8b`.

The independent generator `oracle/gen_boundary_greeks.py` differentiates the
ATM price with respect to volatility and then maturity at 400/800 decimal
digits, and checks the analytic derivative. All 532 binary64 references must
match exactly. Before this fix the newly supported fields were refused, so
there is no finite pre-fix ULP error to compare; the corrected veta references
are nearest-even with zero ULP displacement. The regression also exercises
rate/maturity invariance, adjacent off-ATM contracts, retained kink classes
and explicit arithmetic-capability failure.

FLINT/Arb independently encloses all 532 reference rounding cells at 256-bit
precision, with no unresolved cases and a deliberately adjacent wrong-reference
rejection control. [The report](evidence/arb-boundary-greeks.json) records tool
versions and source/fixture hashes. Reproduce with python-flint 0.9.0:

```sh
python scripts/arb_boundary_audit.py oracle/fixtures/boundary_greeks.txt.gz \
  --output /tmp/arb-boundary-greeks.json
```

The complete local ordinary suite and install/format checks pass. All ten
[affected/core mutation witnesses](evidence/boundary-greeks-mutations.txt) are
killed after a clean baseline and successful builds. Default CI retains seven;
three new boundary mechanisms are optional; they brought the catalog to 43 at
this stage. See [mutation policy](mutation-policy.md) for the current count.

The [A/B/B/A scalar check](evidence/boundary-greeks-bench.json) against
`0681217` retains all 768 successful IV outcomes in every run. Positive-volatility
all-Greek batches span 6.81–20.13 µs before and 6.84–19.30 µs after; IV spans
0.38–1.03 ms before and 0.38–1.01 ms after. These shared-host ranges show no
material regression on those exercised workloads. They do not measure the new
zero-volatility certification path, which performs additional enclosed work,
or establish an operational SLA. No test/profile ran concurrently.
