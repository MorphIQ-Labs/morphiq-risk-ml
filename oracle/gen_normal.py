#!/usr/bin/env python3
"""Independent references for the standard normal primitives.

mpmath at 80/160 digits (with escalation) evaluates the exact binary64 argument. Each
row stores the reference rounded to nearest binary64. The corpus covers:
- every finite binade of both signs
- signed zero
- historical cuts and every generated-polynomial boundary and its neighbours
- a dense body/tail grid
- probabilities across the full open unit interval for the inverse

Output lines: `<fn> <arg hex bits> <reference hex bits>`.
"""
import math
import random
import struct
import sys

import mpmath as mp
from mpmath.libmp import to_float

mp.mp.dps = 80


def bits(x):
    return struct.pack(">d", x).hex()


def from_bits(h):
    return struct.unpack(">d", bytes.fromhex(h))[0]


def neighbours(x, n=3):
    i = struct.unpack(">q", struct.pack(">d", x))[0]
    return [struct.unpack(">d", struct.pack(">q", i + k))[0] for k in range(-n, n + 1)]


def to_double(v):
    # Correct rounding including the subnormal range: mpmath rounds to a
    # 53-bit mantissa first, so round explicitly at the subnormal quantum.
    if v == 0:
        return 0.0
    if abs(v) < mp.mpf(2) ** -1022:
        q = mp.mpf(2) ** -1074
        return math.copysign(float(mp.nint(v / q)) * 5e-324, float(mp.sign(v)))
    if abs(v) >= mp.mpf(2) ** 1024:
        return float("inf") if v > 0 else float("-inf")
    return to_float(mp.mpf(v)._mpf_, rnd="n")


# Beyond this |x| every binary64 pdf/cdf value is an endpoint: x^2/2 >= 2048
# exceeds the 744.4 needed to fall below the smallest subnormal.
SATURATED = 64


def erfcx(x):
    x = mp.mpf(x)
    if x > 45:
        # Independent Tricomi-U identity; no production polynomial/continued
        # fraction or fixed-length asymptotic oracle is used.
        return mp.hyperu(mp.mpf('.5'),mp.mpf('.5'),x*x)/mp.sqrt(mp.pi)
    return mp.erfc(x) * mp.exp(x * x)


def phi(x):
    return mp.mpf(0) if abs(x) > SATURATED else mp.npdf(x)


def cdf(x):
    if x > SATURATED:
        return mp.mpf(1)
    if x < -SATURATED:
        return mp.mpf(0)
    return mp.ncdf(x)


def logcdf(x):
    x = mp.mpf(x)
    if x > SATURATED:
        return -mp.mpf(10) ** -400  # -Q(x): rounds to -0.0
    if x > 0:
        return mp.log1p(-mp.ncdf(-x))
    if x < -20:
        z = -x / mp.sqrt(2)
        return mp.log(erfcx(z) / 2) - z * z
    return mp.log(mp.ncdf(x))


def inv(p):
    p = mp.mpf(p)
    if p == mp.mpf("0.5"):
        return mp.mpf(0)
    target = mp.log(p) if p < mp.mpf("0.5") else mp.log(1 - p)
    side = -1 if p < mp.mpf("0.5") else 1
    # Start from the asymptotic tail estimate; converge in log space.
    t = mp.sqrt(-2 * target)
    x0 = -t if side < 0 else t

    def f(x):
        return (logcdf(x) if side < 0 else logcdf(-x)) - target

    return mp.findroot(f, x0, tol=mp.mpf(10) ** (-(mp.mp.dps-10)))


def arguments():
    xs = {0.0, -0.0}
    rng = random.Random(20261002)
    for e in range(-1074, 1024):
        for m in (1.0, 1.5) if e > -1022 else (1.0,):
            x = m * 2.0**e if e > -1022 else 2.0**e
            if x != 0 and x != float("inf"):
                xs.update((x, -x))
    for e in range(-40, 10):
        for _ in range(16):
            x = rng.uniform(1, 2) * 2.0**e
            xs.update((x, -x))
    cuts = [0.46875, 4.0, 26.543, 26.628, 6.71e7] # retain historical cuts
    cuts += [i/4 for i in range(1,49)] + [2.0**27,27.0,28.0]
    with mp.workdps(160):
        cuts += [float(mp.sqrt(mp.log(mp.mpf(sys.float_info.max)/2))),
                 float(mp.findroot(lambda x: mp.log(mp.erfc(x))+1075*mp.log(2),27))]
    for c in cuts:
        for v in neighbours(c):
            xs.update((v, -v))
        for v in neighbours(c * 1.4142135623730951):
            xs.update((v, -v))
    for k in range(-40 * 64, 40 * 64 + 1):
        xs.add(k / 64.0)
    for _ in range(4000):
        xs.add(rng.uniform(-40, 40))
    return sorted(xs)


def probabilities():
    ps = set()
    rng = random.Random(1988)
    for e in range(-1074, 0):
        for m in (1.0, 1.5, 1.9):
            p = m * 2.0**e
            if 0 < p < 1:
                ps.add(p)
    for _ in range(4000):
        ps.add(rng.random())
    for k in range(1, 2048):
        ps.add(k / 2048.0)
    for c in (0.075, 0.925, 0.5):
        for v in neighbours(c):
            ps.add(v)
    for e in range(1, 53):
        ps.add(1.0 - 2.0**-e)
    # Preserve every old probability; add the replacement's switches and
    # adjacent representable probabilities at all forward-polynomial cuts.
    for c in (0.25,0.5,0.75):
        ps.update(neighbours(c,32))
    for k in range(1,129):
        ps.add(k*2.0**-1074)
        ps.add(from_bits(f'{0x3ff0000000000000-k:016x}'))
    for e in range(2,54):
        for c in (0.5-2.0**-e,0.5+2.0**-e):ps.update(neighbours(c))
    with mp.workdps(160):
        tail=to_double(mp.erfc(6/mp.sqrt(2))/2)
        ps.update(neighbours(tail,32));ps.update(neighbours(1-tail,32))
        for i in range(1,113):
            tail=to_double(mp.erfc(mp.mpf(i)/4)/2)
            if tail>0:
                ps.update(neighbours(tail))
                if 1-tail<1:ps.update(neighbours(1-tail))
    return sorted(p for p in ps if 0 < p < 1)


def agreed(function, x):
    last = None
    for precision in (80,160,320,640):
        with mp.workdps(precision):
            value = to_double(function(mp.mpf(x)))
        if last is not None and bits(value)==bits(last):return value
        last=value
    raise ArithmeticError(f'unresolved reference for {x.hex()}')


def erf(x):
    if abs(x)>SATURATED:return mp.sign(x)
    return mp.erf(x)


def erfc(x):
    if x>SATURATED:return mp.mpf(0)
    if x<-SATURATED:return mp.mpf(2)
    return mp.erfc(x)


def main(out):
    with open(out, "w") as f:
        f.write(f"# mpmath {mp.__version__}; 80/160 digits with escalation\n")
        for x in arguments():
            for name,fn in [('pdf',phi),('cdf',cdf),('logcdf',logcdf),
                            ('erf',erf),('erfc',erfc)]:
                ref=agreed(fn,x)
                if x==0 and name=='erf':ref=x
                f.write(f"{name} {bits(x)} {bits(ref)}\n")
            if x > -27:
                ref=agreed(erfcx,x)
                f.write(f"erfcx {bits(x)} {bits(ref)}\n")
        for p in probabilities():
            ref=agreed(inv,p)
            f.write(f"inv {bits(p)} {bits(ref)}\n")


if __name__ == "__main__":
    main(sys.argv[1])
