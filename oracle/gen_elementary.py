#!/usr/bin/env python3
"""Correctly rounded references for exp, expm1, log and log1p.

mpmath at 80 digits evaluates the exact binary64 argument, and the result is
rounded to nearest binary64 (subnormals exact). The corpus covers:
- every binade of both signs within each function's domain;
- the reduction boundaries (multiples of ln 2 / 2, sqrt(1/2), sqrt 2);
- arguments near 0, the overflow and underflow thresholds;
- a fixed-seed random sample.

Output lines: `<fn> <arg hex bits> <reference hex bits> <residual hex bits>`.
The residual is the exact value minus the reference, rounded to binary64,
so a scorer can measure error in fractions of an ULP against a derived bound.
"""
import math
import random
import struct
import sys

import mpmath
from mpmath import mp, mpf

mp.dps = 80


def bits(x):
    return struct.pack(">d", x).hex()


def round_binary64(v):
    if v == 0:
        return 0.0
    sign, man, e, bc = v._mpf_
    top = e + bc - 1
    if top >= 1024:
        return -math.inf if sign else math.inf
    if top < -1076:
        return -0.0 if sign else 0.0
    quantum = max(top - 52, -1074)
    shift = quantum - e
    if shift <= 0:
        n = int(man) << (-shift)
    else:
        n, rem = int(man) >> shift, int(man) & ((1 << shift) - 1)
        half = 1 << (shift - 1)
        if rem > half or (rem == half and n & 1):
            n += 1
    r = math.ldexp(float(n), quantum)
    return -r if sign else r


def neighbours(x, n=2):
    i = struct.unpack(">q", struct.pack(">d", x))[0]
    return [struct.unpack(">d", struct.pack(">q", i + k))[0] for k in range(-n, n + 1)]


def corpus(rng):
    xs = set()
    for e in range(-1074, 1024):
        for m in (1.0, 1.37, 1.9):
            x = m * 2.0**e if e > -1022 else 2.0**e
            if math.isfinite(x) and x != 0:
                xs.update((x, -x))
    for k in range(-1100, 1100):
        for v in neighbours(k * math.log(2) / 2, 1):
            xs.add(v)
    for c in (math.sqrt(0.5), math.sqrt(2), 709.782712893384, -745.1332191019412, 0.34657359027997264, -40.0):
        for v in neighbours(c, 3):
            xs.update((v, -v))
    for _ in range(6000):
        xs.add(rng.uniform(-750, 750))
        xs.add(rng.uniform(-1, 1))
        xs.add(math.ldexp(rng.uniform(1, 2), rng.randint(-1074, 1023)))
    return sorted(x for x in xs if math.isfinite(x))


def main(out):
    rng = random.Random(20261002)
    with open(out, "w") as w:
        w.write(f"# mpmath {mpmath.__version__} dps {mp.dps}\n")
        def row(fn, x, exact):
            ref = round_binary64(exact)
            residual = round_binary64(exact - mpf(ref)) if math.isfinite(ref) else 0.0
            w.write(f"{fn} {bits(x)} {bits(ref)} {bits(residual)}\n")

        for x in corpus(rng):
            X = mpf(x)
            if x < 760:
                row("exp", x, mpmath.exp(X))
                row("expm1", x, mpmath.expm1(X))
            if x > 0:
                row("log", x, mpmath.log(X))
            if x > -1:
                row("log1p", x, mpmath.log1p(X))


if __name__ == "__main__":
    main(sys.argv[1])
