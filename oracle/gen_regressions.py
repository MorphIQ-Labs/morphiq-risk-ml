#!/usr/bin/env python3
"""Independent reproductions of the numerical review's boundary cases."""
import math
import random
import sys
from mpmath import mp
from common import bits

RATES = ['0x1.99d0829717c22p-1', '0x1.06cd10acd449dp+0',
         '0x1.637c573ce4789p-3', '0x1.0cf102fa7045ap-4',
         '0x1.f6f08029f0d81p+0']

def fields(value):
    m, e = mp.frexp(value) if value else (mp.mpf(0), 0)
    h = float(m); l = float(m-h); t = float(m-h-mp.mpf(l))
    return [str(e), bits(h), bits(l), bits(t)]

def main(path):
    rng = random.Random(20261002)
    rows = []
    for text in RATES:
        r = float.fromhex(text)
        with mp.workdps(220):
            maximum = mp.exp(-mp.mpf(r)); quote = float(maximum)
            if mp.mpf(quote) >= maximum: quote = math.nextafter(quote, 0.)
        roots = []
        for precision in (110, 220):
            with mp.workdps(precision):
                roots.append(fields(2*mp.sqrt(2)*mp.erfinv(mp.mpf(quote)*mp.exp(mp.mpf(r)))))
        assert roots[0] == roots[1]
        rows.append(['iv', bits(r), bits(quote), *roots[0]])
    for _ in range(2000):
        k = rng.uniform(.5, 2.)
        s = math.nextafter(k, math.inf if rng.random() < .5 else 0.)
        values = []
        for precision in (110, 220):
            with mp.workdps(precision): values.append(fields(mp.log(mp.mpf(s)/mp.mpf(k))))
        assert values[0] == values[1]
        rows.append(['coordinate', bits(s), bits(k), *values[0]])
    with open(path, 'w') as w:
        w.write('# kind input1 input2 exponent reference_hi reference_lo reference_tail\n')
        w.writelines(' '.join(row)+'\n' for row in rows)

if __name__ == '__main__': main(sys.argv[1])
