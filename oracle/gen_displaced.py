#!/usr/bin/env python3
"""Exact-input reference prices for displaced Black, owned by this project.

Contract: displaced Black is Black-76 on the real numbers F + d and K + d
for the binary64 inputs F, K and d. No intermediate rounding of the shift is
part of the model. mpmath evaluates each contract at 60 and 120 digits; a row
is kept only if both precisions round to the same binary64, and the reference
is that correctly rounded value.

The grid stresses what the definition decides:
- shifts from 5bp to 100;
- forwards near the floor -d;
- forward and strike values whose sum with the shift is not representable;
- maturities from a day to 30 years;
- volatilities from 0 to 3.

Output lines (european_price_reference format):
  displaced <call|put> <region> <F> <K> <T> <r> <q> <sigma> <d> <reference>
Regions follow FerroRisk #440's region(), without its strike-scale region.
"""
import math
import struct
import sys

import mpmath
from mpmath import mp, mpf, ncdf, exp, log, sqrt

SHIFTS = (0.0005, 0.01, 0.03, 0.05, 1.0, 100.0)
STRIKES = (-0.004, 0.0, 0.0123, 0.031, 1.37)
MONEYNESS = (-5.0, -1.0, -0.1, -1e-4, 0.0, 1e-4, 0.1, 1.0, 5.0)
TIMES = (1 / 365, 0.25, 1.0, 5.0, 30.0)
SIGMAS = (0.0, 1e-8, 1e-4, 0.01, 0.1, 0.3, 1.0, 3.0)
RATES = (-0.01, 0.03)


def bits(x):
    return struct.pack(">d", x).hex()


def round_binary64(value):
    """Nearest binary64, ties to even, subnormals exact."""
    if value == 0:
        return 0.0
    sign, man, e, bc = value._mpf_
    top = e + bc - 1
    if top >= 1024:
        return -math.inf if sign else math.inf
    if top < -1076:  # below half the smallest subnormal: rounds to zero
        return -0.0 if sign else 0.0
    quantum = max(top - 52, -1074)
    shift = quantum - e
    if shift <= 0:
        n = int(man) << (-shift)
    else:
        n, remainder = int(man) >> shift, int(man) & ((1 << shift) - 1)
        half = 1 << (shift - 1)
        if remainder > half or (remainder == half and n & 1):
            n += 1
    result = math.ldexp(float(n), quantum)
    return -result if sign else result


def price(call, f, k, t, r, sigma, d):
    """Displaced Black on the exact sums, at the current precision."""
    F, K = mpf(f) + mpf(d), mpf(k) + mpf(d)
    disc = exp(-mpf(r) * mpf(t))
    a, c = F * disc, K * disc
    theta = 1 if call else -1
    if sigma == 0:
        return max(theta * (a - c), mpf(0))
    s = mpf(sigma) * sqrt(mpf(t))
    x = log(a / c)
    d1 = x / s + s / 2
    d2 = d1 - s
    return theta * (a * ncdf(theta * d1) - c * ncdf(theta * d2))


def region(call, f, k, t, r, sigma, d, value):
    if sigma == 0:
        return "zero_variance"
    with mp.workdps(40):
        F, K = mpf(f) + mpf(d), mpf(k) + mpf(d)
        x = log(F / K)
        if abs(x) <= mpf("1e-2") and mpf(sigma) * sqrt(mpf(t)) <= mpf("1e-4"):
            return "near_atm_tiny_variance"
        disc = exp(-mpf(r) * mpf(t))
        intrinsic = (1 if call else -1) * (F - K) * disc
    if intrinsic > 0:
        return "deep_itm" if intrinsic >= value / 2 else "itm"
    return "otm"


def main(out):
    kept = dropped = 0
    with open(out, "w") as w:
        w.write(f"# morphiq-risk-ml displaced Black exact-sum reference, mpmath {mpmath.__version__}, dps 60/120\n")
        for d in SHIFTS:
            for k in STRIKES:
                if k + d <= 0:
                    continue
                for m in MONEYNESS:
                    # F chosen so the exact shifted forward is near (K + d) e^m; F + d
                    # is generally not representable, which is what the grid tests.
                    f = (k + d) * math.exp(m) - d
                    if not math.isfinite(f) or float(mpf(f) + mpf(d)) <= 0:
                        continue
                    for t in TIMES:
                        for sigma in SIGMAS:
                            for r in RATES:
                                for call in (True, False):
                                    refs = []
                                    for dps in (60, 120):
                                        with mp.workdps(dps):
                                            refs.append(round_binary64(price(call, f, k, t, r, sigma, d)))
                                    if bits(refs[0]) != bits(refs[1]):
                                        dropped += 1
                                        continue
                                    with mp.workdps(120):
                                        value = price(call, f, k, t, r, sigma, d)
                                    reg = region(call, f, k, t, r, sigma, d, value)
                                    fields = ["displaced", "call" if call else "put", reg] + [
                                        bits(v) for v in (f, k, t, r, 0.0, sigma, d, refs[1])]
                                    w.write(" ".join(fields) + "\n")
                                    kept += 1
    print(f"kept {kept}, dropped {dropped} (precisions disagree on the rounded value)", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
