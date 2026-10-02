#!/usr/bin/env python3
"""Extra-bit original-input model references for runtime enclosure checks.

No runtime implementation is called. common.Contract evaluates the model
with mpmath erfc, exp and log; two independently recomputed precisions must
agree on all three normalized output words. Extreme low words explicitly
raise working precision rather than trusting agreement after input loss.
"""
import math
import random
import sys
from mpmath import mp
from common import Contract, bits


def corpus():
    rng = random.Random(2714)
    for model in ('bsm', 'black76', 'displaced', 'bachelier'):
        for _ in range(160):
            s, k = rng.uniform(.5, 2), rng.uniform(.5, 2)
            t, r, q = rng.uniform(.25, 4), rng.uniform(-.125, .125), rng.uniform(-.125, .125)
            sigma = rng.uniform(.125, 2)
            shift = 1.0 if model == 'displaced' else 0.0
            for call in (True, False):
                yield 'ordinary', Contract(model, call, s, k, t, r, q, shift), sigma, 110
        for s in (.5, 1., 2.):
            for t in (0., .25, 1., 4.):
                for r in (-.125, 0., .125):
                    for call in (True, False):
                        yield 'zero', Contract(model, call, s, 1., t, r, r), 0., 110
        for x in (-32., -16., -8., -4., 0., 4., 8., 16., 32.):
            # F-K or log(F/K) produces a broad range of normal arguments.
            s = x if model == 'bachelier' else math.exp(x / 8)
            k = 0. if model == 'bachelier' else 1.
            for call in (True, False):
                yield 'tail', Contract(model, call, s, k, 1., 0.), (1. if model == 'bachelier' else .125), 110
    for e in (-1074, -1000, -500, -100, -54):
        tiny = math.ldexp(1., e)
        for call in (True, False):
            yield 'sparse', Contract('displaced', call, 1., 2., 1., 0., shift=tiny), .5, 400
            yield 'tiny_variance', Contract('bsm', call, 1., 1., 1., 0.), tiny, 400
            yield 'tiny_carry', Contract('bsm', call, 1., 1., 1., tiny), 0., 400


def reference(c, sigma, precision):
    with mp.workdps(precision):
        value = c.price(sigma)
        m, exponent = mp.frexp(value) if value else (mp.mpf(0), 0)
        h = float(m)
        l = float(m - h)
        tail = float(m - h - mp.mpf(l))
        return int(exponent), bits(h), bits(l), bits(tail)


def main(path):
    count = 0
    with open(path, 'w') as stream:
        stream.write('# model side family S K T r q sigma displacement ref_exp ref_hi ref_lo ref_tail\n')
        for family, c, sigma, precision in corpus():
            first = reference(c, sigma, precision)
            second = reference(c, sigma, precision * 2)
            if first != second:
                raise ArithmeticError(f'precision disagreement: {family} {vars(c)} {sigma}')
            inputs = (c.s, c.k, c.t, c.r, c.q, sigma, c.shift)
            stream.write(' '.join((c.model, 'call' if c.call else 'put', family,
                *map(bits, inputs), str(first[0]), *first[1:])) + '\n')
            count += 1
    print(f'{count} model enclosure references', file=sys.stderr)


if __name__ == '__main__':
    main(sys.argv[1])
