#!/usr/bin/env python3
"""Exact-input European prices for BSM, Black-76 and Bachelier.

This is this project's own price oracle. Every value comes from mpmath, refined
until two consecutive precisions round to the same binary64 (common.agreed).

Families:
- grid: strike scales 1e-300..1e300, forward/strike ratios from 1e-6 to 1e6
  including 1 ± 1e-15, carry pairs with discounts e^-6..e^1.5, and σ from
  0 to 10 (the design of FerroRisk's #440 study);
- cancel: forwards placed at the strike through carry, where
  ln(S/K) + (r - q)T cancels to ~1e-18 and the zero-variance price is far
  below its legs;
- random: a fixed-seed sample over wide, mostly log-uniform ranges.

Output lines:
  <model> <call|put> <region> <family> <s> <k> <t> <r> <q> <sigma> <shift> <reference>
"""
import math
import random
import sys

import mpmath
from mpmath import mp

from common import Contract, agreed, bits, region

RATIOS = (1e-6, 1e-3, 0.1, 0.5, 0.9, 0.99, 1 - 1e-6, 1 - 1e-10, 1 - 1e-15, 1.0,
          1 + 1e-15, 1 + 1e-10, 1 + 1e-6, 1.01, 1.1, 2.0, 10.0, 1e3, 1e6)
SIGMAS = (0.0, 1e-300, 1e-12, 1e-8, 1e-4, 0.01, 0.1, 0.3, 1.0, 3.0, 10.0)
CARRY = ((1.0, 0.0, 0.0), (1.0, 0.05, 0.02), (1.0, -0.01, 0.03), (0.25, 0.03, 0.03),
         (30.0, 0.2, 0.0), (30.0, -0.05, 0.1), (1e-200, 0.05, 0.0), (5.0, 0.02, 0.02))


def grid():
    for k in (1e-300, 1e-150, 1e-100, 1e-3, 1.0, 1e3, 1e150, 1e300):
        for ratio in RATIOS:
            for t, r, q in CARRY:
                s = k * ratio * math.exp(-(r - q) * t)
                if not (math.isfinite(s) and s > 0):
                    continue
                for sigma in SIGMAS:
                    for call in (True, False):
                        yield Contract("bsm", call, s, k, t, r, q), sigma
    for k in (1e-100, 1.0, 1e3, 1e100):
        for ratio in RATIOS:
            for t, r, _ in CARRY[:4]:
                for sigma in SIGMAS:
                    for call in (True, False):
                        yield Contract("black76", call, k * ratio, k, t, r), sigma
    for k in (1e-3, 1.0, 1e3):
        for ratio in RATIOS:
            for t, r, _ in CARRY[:4]:
                for sigma in SIGMAS:
                    for call in (True, False):
                        # Bachelier's normal volatility is in price units: σ K.
                        yield Contract("bachelier", call, k * ratio, k, t, r), sigma * k


def cancel():
    for k in (1e-150, 1e-3, 1.0, 37.5, 1e150):
        for r, q, t in ((-0.01, -0.03, 1.0), (0.05, 0.02, 1.0), (0.2, 0.0, 30.0), (0.03, 0.01, 0.25)):
            base = k * math.exp(-(r - q) * t)
            for ulps in range(-3, 4):
                s = base
                for _ in range(abs(ulps)):
                    s = math.nextafter(s, math.inf if ulps > 0 else 0.0)
                for sigma in (0.0, 1e-12, 1e-6):
                    for call in (True, False):
                        yield Contract("bsm", call, s, k, t, r, q), sigma


def random_family(rng, n=6000):
    for _ in range(n):
        call = rng.random() < 0.5
        t = math.exp(rng.uniform(math.log(1e-4), math.log(30.0)))
        r, q = rng.uniform(-0.05, 0.1), rng.uniform(-0.05, 0.1)
        sigma = 0.0 if rng.random() < 0.05 else math.exp(rng.uniform(math.log(1e-4), math.log(3.0)))
        s = math.exp(rng.uniform(math.log(1e-6), math.log(1e6)))
        k = s * math.exp(rng.gauss(0.0, 1.0) * max(0.05, sigma * math.sqrt(t)) * 3.0)
        yield Contract("bsm", call, s, k, t, r, q), sigma
        yield Contract("black76", call, s, k, t, r), sigma
        f, kk = rng.uniform(-0.05, 0.1), rng.uniform(-0.05, 0.1)
        normal = 0.0 if sigma == 0 else math.exp(rng.uniform(math.log(1e-5), math.log(0.05)))
        yield Contract("bachelier", call, f, kk, t, r), normal


def main(out):
    rng = random.Random(20261003)
    kept = dropped = 0
    with open(out, "w") as w:
        w.write(f"# morphiq-risk-ml European price oracle, mpmath {mpmath.__version__}, dps 60..960 agreement\n")
        for family, source in (("grid", grid()), ("cancel", cancel()), ("random", random_family(rng))):
            for contract, sigma in source:
                ref = 0.0 if contract.below_binary64(sigma) else agreed(lambda: contract.price(sigma), contract.digits(sigma))
                if ref is None:
                    dropped += 1
                    continue
                with mp.workdps(60 + contract.digits(sigma)):
                    reg = region(contract, sigma, ref if ref == 0.0 else contract.price(sigma))
                w.write(" ".join([contract.model, "call" if contract.call else "put", reg, family]
                                 + [bits(v) for v in contract.fields()[:5] + [sigma, contract.shift, ref]]) + "\n")
                kept += 1
    print(f"kept {kept}, dropped {dropped}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
