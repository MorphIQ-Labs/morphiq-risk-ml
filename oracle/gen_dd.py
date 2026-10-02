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
            yield 'split_sqrt', x, 0., 0., 0.
    for n in (1, 2, 3, 5, 511, 1023):
        for d in (1, 3, 5, 7, 513):
            for fn in ('div','split_quotient'):
                yield fn, math.ldexp(n, -1074), 0., math.ldexp(d, -1074), 0.
    for _ in range(2500):
        ea, eb = rng.randint(-1074, 1022), rng.randint(-1074, 1022)
        a, b = math.ldexp(rng.uniform(1., 2.), ea), math.ldexp(rng.uniform(1., 2.), eb)
        if -1073 <= ea-eb <= 1022 and a > 0. and b > 0.:
            row = (*pair(a), *pair(b))
            for fn in ('div','split_quotient'): yield fn, *row

    normals = [i/32 for i in range(-192,193)]
    normals += [rng.uniform(-6.,6.) for _ in range(1600)]
    for x in normals:
        for ah,al in ((x,0.),pair(x)):
            yield 'normal_pdf',ah,al,0.,0.
            yield 'normal_cdf',ah,al,0.,0.

    scalar = [0.,.46875,4.,6.71e7]
    scalar += [math.ldexp(1.,e) for e in range(-1074,1024,17)]
    scalar += [rng.uniform(0.,64.) for _ in range(1200)]
    for x in scalar:
        for a in (math.nextafter(x,0.),x,math.nextafter(x,math.inf)):
            yield 'erfcx',a,0.,0.,0.
            if a <= math.ldexp(1.,400): yield 'y_prime',-a,0.,0.,0.
    for _ in range(1800):
        sd = math.exp(rng.uniform(math.log(1e-10),math.log(40.)))
        h = rng.uniform(-40.,0.)
        x = h*sd
        if abs(x)>500.: continue
        for ah,al in ((x,0.),pair(x)):
            bh,bl=pair(sd)
            yield 'black_kernel',ah,al,bh,bl


def reference(fn, ah, al, bh, bl, precision):
    extra = 2 * max(0, -math.floor(math.log10(abs(ah)))) if ah else 0
    if fn == "expm1" and ah < 0:
        extra = max(extra, int(-ah / math.log(10)) + 5)
    if fn == "y_prime" and abs(ah)>1:
        # Powers of two can have exceptionally sparse reference expansions:
        # G(a)=a^-2(1-3/a²+15/a⁴-...). Resolve the third word as well.
        extra = max(extra, math.ceil(4*math.log10(abs(ah)))+30)
    with mp.workdps(precision + extra):
        a, b = mp.mpf(ah) + mp.mpf(al), mp.mpf(bh) + mp.mpf(bl)
        y = {'exp': lambda: mp.exp(a), 'expm1': lambda: mp.expm1(a),
             'log': lambda: mp.log(a), 'sqrt': lambda: mp.sqrt(a),
             'div': lambda: a/b, 'split_quotient': lambda: a/b,
             'split_sqrt': lambda: mp.sqrt(a),
             'normal_pdf': lambda: mp.exp(-a*a/2)/mp.sqrt(2*mp.pi),
             'normal_cdf': lambda: mp.erfc(-a/mp.sqrt(2))/2,
             'erfcx': lambda: (mp.exp(a*a)*mp.erfc(a) if a<64 else
                              mp.hyperu(mp.mpf('.5'),mp.mpf('.5'),a*a)/mp.sqrt(mp.pi)) if a else mp.mpf(1),
             'y_prime': lambda: (1+a*mp.sqrt(mp.pi/2)*mp.exp(a*a/2)*mp.erfc(-a/mp.sqrt(2)) if abs(a)<128 else
                                mp.hyperu(1,mp.mpf('.5'),a*a/2)/2) if a else mp.mpf(1),
             'black_kernel': lambda: mp.exp(a/2)*mp.erfc(-(a/b+b/2)/mp.sqrt(2))/2-mp.exp(-a/2)*mp.erfc(-(a/b-b/2)/mp.sqrt(2))/2}[fn]()
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
