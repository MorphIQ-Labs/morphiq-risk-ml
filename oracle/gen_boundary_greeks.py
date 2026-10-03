#!/usr/bin/env python3
"""Independent nested differentiation of ATM prices at sigma=0, T>0.

The analytic mixed derivative is a cross-check, not the reference source.
Both precisions recompute original binary64 inputs, including displaced sums.
"""
import math
import random
import sys
from mpmath import mp
from common import bits


def corpus():
    cases = [(1., 1., r, 0.) for r in
             (-.125, 0., .125, math.nextafter(.5, 0.), .5,
              math.nextafter(.5, math.inf))]
    cases += [(100., t, r, 0.) for t in (.125, .7, 4., 32.)
              for r in (-.1, 0., .05)]
    cases += [(1., math.ldexp(1., e), 0., 0.) for e in (-500, -100, 100, 500)]
    cases += [(1., 1., .05, math.ldexp(1., e)) for e in (-1074, -54, -20)]
    cases += [(-.25, 2., -.03, 1.), (math.ldexp(1., 500), math.ldexp(1., -500), 0., 0.)]
    rng = random.Random(340027)
    cases += [(rng.uniform(.5, 200), rng.uniform(.05, 10), rng.uniform(-.1, .2), .125)
              for _ in range(40)]
    for model in ('bsm', 'black76', 'displaced', 'bachelier'):
        for s, t, r, shift in cases:
            if model != 'displaced':
                shift = 0.
            if model != 'bachelier' and s + shift <= 0:
                continue
            for side in ('call', 'put'):
                yield model, side, s, t, r, shift


def reference(model, s, t, r, shift, digits):
    with mp.workdps(digits):
        s, t, r, shift = map(mp.mpf, (s, t, r, shift))
        weight = s + shift if model == 'displaced' else s
        def price(sigma, maturity):
            if model == 'bachelier':
                return mp.exp(-r*maturity)*sigma*mp.sqrt(maturity/(2*mp.pi))
            return weight*mp.exp(-r*maturity)*mp.erf(sigma*mp.sqrt(maturity/8))
        derivative = -mp.diff(lambda maturity: mp.diff(lambda sigma: price(sigma, maturity), 0), t)/365
        w = mp.mpf(1) if model == 'bachelier' else weight
        formula = w*mp.exp(-r*t)*(r*t-mp.mpf('.5'))/mp.sqrt(2*mp.pi*t)/365
        if formula == 0:
            # The differentiated coefficient has the stationary point rT=1/2.
            if abs(derivative) > mp.power(10, -digits//2):
                raise ArithmeticError('stationary-point derivative mismatch')
            return bits(0.)
        if abs((derivative-formula)/formula) > mp.power(10, -digits//2):
            raise ArithmeticError('price derivative/formula mismatch')
        return bits(float(derivative))


def main(path):
    rows = 0
    with open(path, 'w') as f:
        f.write('# model side S T r displacement veta_nearest_even\n')
        for model, side, s, t, r, shift in corpus():
            low = reference(model, s, t, r, shift, 400)
            high = reference(model, s, t, r, shift, 800)
            if low != high:
                raise ArithmeticError('precision disagreement')
            f.write(' '.join((model, side, *map(bits, (s, t, r, shift)), high))+'\n')
            rows += 1
    print(f'{rows} boundary Greek references', file=sys.stderr)


if __name__ == '__main__':
    main(sys.argv[1])
