#!/usr/bin/env python3
"""Exact-input DD references, independently evaluated at 110 and 220 digits.

Inputs have nonzero low words, reduction boundaries, exponent extremes and
subnormals. References are three binary64 words at a separate binary exponent,
so neither the oracle nor its scorer loses the error to underflow.
"""
import math
import random
import sys
from mpmath import mp
from common import bits


def corpus():
    rng = random.Random(0xDDB0)
    def pair(x):
        return x, math.ulp(x) * rng.uniform(-0.49, 0.49)
    xs = [0., math.ldexp(1., -1074), -math.ldexp(1., -1074)]
    xs += [math.ldexp(s, e) for e in range(-1074, -1, 7) for s in (-1., 1.)]
    xs += [rng.uniform(-744., 709.) for _ in range(1800)]
    xs += [rng.uniform(-.35, .35) for _ in range(1800)]
    for n in range(-1020, 1021, 13):
        x = (n + .5) * math.log(2.)
        xs += [math.nextafter(x, -math.inf), x, math.nextafter(x, math.inf)]
    for x in xs:
        for hi, lo in ((x, 0.), pair(x)):
            for fn in ('exp', 'expm1'):
                yield fn, hi, lo, 0., 0.
    xs = [1., math.nextafter(1., 0.), math.nextafter(1., 2.),
          math.sqrt(.5), math.sqrt(2.), math.ldexp(1., -1074)]
    xs += [math.ldexp(rng.uniform(1., 2.), rng.randint(-1074, 1022)) for _ in range(2500)]
    for x in xs:
        if x > 0.:
            yield 'log', x, 0., 0., 0.
            yield 'sqrt', *pair(x), 0., 0.
    for n in (1, 2, 3, 5, 511, 1023):
        for d in (1, 3, 5, 7, 513):
            yield 'div', math.ldexp(n, -1074), 0., math.ldexp(d, -1074), 0.
    for _ in range(2500):
        ea, eb = rng.randint(-1074, 1022), rng.randint(-1074, 1022)
        a, b = math.ldexp(rng.uniform(1., 2.), ea), math.ldexp(rng.uniform(1., 2.), eb)
        if -1073 <= ea-eb <= 1022 and a > 0. and b > 0.:
            yield 'div', *pair(a), *pair(b)


def reference(fn, ah, al, bh, bl, precision):
    extra = 2 * max(0, -math.floor(math.log10(abs(ah)))) if ah else 0
    if fn == "expm1" and ah < 0:
        extra = max(extra, int(-ah / math.log(10)) + 5)
    with mp.workdps(precision + extra):
        a, b = mp.mpf(ah) + mp.mpf(al), mp.mpf(bh) + mp.mpf(bl)
        y = {'exp': lambda: mp.exp(a), 'expm1': lambda: mp.expm1(a),
             'log': lambda: mp.log(a), 'sqrt': lambda: mp.sqrt(a),
             'div': lambda: a/b}[fn]()
        m, e = mp.frexp(y) if y else (mp.mpf(0), 0)
        h = float(m); l = float(m-h); t = float(m-h-mp.mpf(l))
        return int(e), bits(h), bits(l), bits(t)


def main(path):
    n = 0
    with open(path, 'w') as w:
        w.write('# fn a_hi a_lo b_hi b_lo reference_exponent reference_hi reference_lo reference_tail\n')
        for row in corpus():
            a, b = reference(*row, 110), reference(*row, 220)
            if a != b:
                raise ArithmeticError(f'precision disagreement: {row}')
            w.write(' '.join([row[0], *map(bits, row[1:]), str(a[0]), *a[1:]])+'\n')
            n += 1
    print(f'{n} DD references', file=sys.stderr)

if __name__ == '__main__':
    main(sys.argv[1])
