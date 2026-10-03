#!/usr/bin/env python3
"""Exact-input reference prices for displaced Black.

Contract: displaced Black is Black-76 on the real numbers F + d and K + d
for the binary64 inputs F, K and d (docs/model-contracts.md). No
intermediate rounding of the shift is part of the model. Values come from
common.Contract and are refined until two consecutive precisions round
alike (common.agreed), with exact one-sided tail rounding where it decides.
Values below 2^-1100 by the analytic tail bound round to 0; this does not
claim that their exact real value is zero.

The grid stresses what the definition decides:
- shifts from 5bp to 100;
- forwards near the floor -d;
- forward and strike values whose sum with the shift is not representable;
- maturities from a day to 30 years;
- volatilities from 0 to 3.

Output lines (european_price_reference format, with a family column):
  displaced <call|put> <region> grid <F> <K> <T> <r> <q> <sigma> <d> <reference>
"""
import math
import sys

import mpmath
from mpmath import mp

from common import Contract, agreed, bits, region
from price_rounding import price_reference

SHIFTS = (0.0005, 0.01, 0.03, 0.05, 1.0, 100.0)
STRIKES = (-0.004, 0.0, 0.0123, 0.031, 1.37)
MONEYNESS = (-5.0, -1.0, -0.1, -1e-4, 0.0, 1e-4, 0.1, 1.0, 5.0)
TIMES = (1 / 365, 0.25, 1.0, 5.0, 30.0)
SIGMAS = (0.0, 1e-8, 1e-4, 0.01, 0.1, 0.3, 1.0, 3.0)
RATES = (-0.01, 0.03)


def main(out):
    kept = dropped = 0
    with open(out, "w") as w:
        w.write(f"# morphiq-risk-ml displaced Black exact-sum oracle, mpmath {mpmath.__version__}\n")
        for d in SHIFTS:
            for k in STRIKES:
                if k + d <= 0:
                    continue
                for m in MONEYNESS:
                    # The exact shifted forward is near (K + d) e^m; F + d is
                    # generally not representable, which is what the grid tests.
                    f = (k + d) * math.exp(m) - d
                    if not math.isfinite(f) or f + d <= 0:
                        continue
                    for t in TIMES:
                        for sigma in SIGMAS:
                            for r in RATES:
                                for call in (True, False):
                                    c = Contract("displaced", call, f, k, t, r, 0.0, d)
                                    ref = price_reference(c, sigma, lambda: 0.0 if c.below_binary64(sigma) else agreed(lambda: c.price(sigma), c.digits(sigma)))
                                    if ref is None:
                                        raise ArithmeticError(f'unresolved displaced reference: {vars(c)} sigma={sigma.hex()}')
                                    with mp.workdps(60 + c.digits(sigma)):
                                        reg = region(c, sigma, ref if ref == 0.0 else c.price(sigma))
                                    fields = ["displaced", "call" if call else "put", reg, "grid"]
                                    fields += [bits(v) for v in (f, k, t, r, 0.0, sigma, d, ref)]
                                    w.write(" ".join(fields) + "\n")
                                    kept += 1
        for sigma in (1e-300,1e-12,1e-4,.01):
            for call in (True,False):
                c=Contract('displaced',call,math.nextafter(1.,math.inf),2.**-53,1.,0.,0.,2.**-54)
                ref=price_reference(c,sigma,lambda: agreed(lambda:c.price(sigma),c.digits(sigma)))
                if ref is None:
                    raise ArithmeticError('unresolved adversarial midpoint reference')
                with mp.workdps(120): reg=region(c,sigma,ref)
                fields=['displaced','call' if call else 'put',reg,'halfway']
                fields += [bits(v) for v in (c.s,c.k,c.t,c.r,c.q,sigma,c.shift,ref)]
                w.write(' '.join(fields)+'\n')
                kept+=1
    print(f"kept {kept}, dropped {dropped}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
