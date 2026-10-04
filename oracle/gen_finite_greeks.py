#!/usr/bin/env python3
"""Issue #62 Greek challenges, independently refined at 1280/2560 digits.

Real-model closed forms and boundary identities are independent of the OCaml
arithmetic. The ordinary case is also checked by differentiating the price.
Agreement is finite-corpus evidence, not an interval proof. Reported tail gamma
has an exact-input analytic underflow witness. 640 digits proved insufficient
for one tail-price cancellation; require strict refined word agreement.
"""
import argparse
from fractions import Fraction
import math
import sys

from mpmath import mp
from common import Contract, bits, round_binary64
from gen_greeks import closed_form, differentiated, limits, GREEKS


CASES = [
    ('reported-tail', 100., 101., 1., 0., 0., 1e-310),
    ('overflowing-atm-gamma', 1., 1., 1., 0., 0., 1e-310),
    ('ordinary', 100., 101., 1., .02, .01, .2),
    ('subnormal-time', 100., 101., 2.**-1074, 0., 0., .2),
    ('zero-volatility-subnormal-time', 100., 101., 2.**-1074, 0., 0., 0.),
    ('tiny-coordinates', 2.**-1022, 2.**-1021, 1., 0., 0., .2),
    ('extreme-discount', 100., 101., 1., -2000., -2000., .2),
    ('zero-volatility-tail', 100., 101., 1., -2000., -2000., 0.),
    ('zero-volatility-atm', 100., 100., 1., -2000., -2000., 0.),
    ('expiry-extreme', 2.**1000, 2.**999, 0., 2.**100, 2.**101, .2),
    ('expiry-kink', 100., 100., 0., 0., 0., .2),
]


def tail_gamma_witness():
    sigma = Fraction.from_float(1e-310)
    assert Fraction(1, 2**1030) < sigma < Fraction(1, 2**1029)
    # ln(101/100) > 1/101 by integration of 1/x. Both |d| exceed 2^1000.
    assert 1 / (101 * sigma) - sigma / 2 > 2**1000
    assert 1 / sigma > 2**1000
    # gamma < 2^1030 exp(-2^1999) < 2^(1030-2106) < half-minsub.
    assert 2**1999 > 2106 and 1030 - 2106 < -1075


def calculate(contract, sigma):
    if contract.t == 0:
        return limits(contract, sigma)
    if sigma > 0:
        return closed_form(contract, sigma)
    s, k, t, r = map(mp.mpf, (contract.s, contract.k, contract.t, contract.r))
    discount = mp.exp(-r * t)
    theta = contract.theta
    # All zero-volatility challenge cases have q=r, so their carry is tied.
    assert contract.q == contract.r
    if s == k:
        weight = 1 if contract.model == 'bachelier' else s + mp.mpf(contract.shift)
        vega = weight * discount * mp.sqrt(t / (2 * mp.pi))
        return dict(delta='kink', gamma='kink', theta=0, vega=vega,
                    rho='kink' if contract.model == 'bsm' else 0, vanna='kink',
                    volga=0, charm='kink', veta=vega * (r - 1 / (2*t)) / 365,
                    color='kink')
    itm = theta * (s-k) > 0
    value = discount * max(theta * (s-k), mp.mpf(0))
    delta = theta * discount if itm else 0
    rho = (theta * discount * k * t if itm else 0) if contract.model == 'bsm' else -t * value
    return dict(delta=delta, gamma=0, theta=r * value / 365, vega=0, rho=rho,
                vanna=0, volga=0, charm=r * delta / 365, veta=0, color=0)


def main(path):
    tail_gamma_witness()
    count = 0
    with open(path, 'w') as out:
        out.write('# model side case greek status S K T r q sigma shift reference; 1280/2560 digits\n')
        for model in ('bsm', 'black76', 'displaced', 'bachelier'):
            for side in ('call', 'put'):
                for name, s, k, t, r, q, sigma in CASES:
                    shift = .125 if model == 'displaced' else 0.
                    contract = Contract(model, side == 'call', s, k, t, r, q, shift)
                    refined = []
                    for precision in (1280, 2560):
                        with mp.workdps(precision):
                            raw = calculate(contract, sigma)
                            refined.append({g: ('kink' if raw[g] == 'kink' else
                                                bits(round_binary64(mp.mpf(raw[g]))))
                                            for g in GREEKS})
                    if refined[0] != refined[1]:
                        raise ArithmeticError(('precision disagreement', model, side, name, refined))
                    if name == 'ordinary':
                        with mp.workdps(160):
                            derivatives = differentiated(contract, sigma)
                            for greek in GREEKS:
                                if bits(round_binary64(derivatives[greek])) != refined[1][greek]:
                                    raise ArithmeticError(('price derivative mismatch', model, side, greek))
                    for greek, reference in refined[1].items():
                        status = ('kink' if reference == 'kink' else
                                  'above_binary64' if reference in (bits(math.inf), bits(-math.inf))
                                  else 'resolved')
                        fields = [model, side, name, greek, status]
                        fields += [bits(v) for v in (s, k, t, r, q, sigma, shift)]
                        fields.append(bits(math.nan) if status == 'kink' else reference)
                        out.write(' '.join(fields) + '\n')
                        count += 1
    print(f'{count} refined Greek challenges; 80 independent price derivatives', file=sys.stderr)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='gen_finite_greeks 1')
    parser.add_argument('output')
    main(parser.parse_args().output)
