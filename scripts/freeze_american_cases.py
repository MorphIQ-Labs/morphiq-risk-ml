#!/usr/bin/env python3
"""Emit the fixed #110 corpus; never infer acceptance from measured prices."""
import argparse
import json
import math
import struct


def word(x):
    return struct.pack('>d', float(x)).hex()


def corpus():
    rows = []
    base = dict(spot=100., strike=100., rate=.05, yield_=.02,
                volatility=.2, time=1., opens=0.)

    def add(name, side='put', category='regular', **changes):
        p = base | changes
        epsilon = math.ldexp(max(p['spot'], p['strike']), -16)
        rows.append(dict(id=name, side=side, category=category,
                         inputs={k: word(v) for k, v in p.items()}, epsilon=word(epsilon)))

    for side in ('call', 'put'):
        for spot in (80., 100., 120.):
            add(f'{side}-{int(spot)}', side, spot=spot)
        add(f'{side}-short', side, category='short', time=1/360)
        add(f'{side}-long-high-vol', side, category='long-high-vol', time=10., volatility=1.)
        add(f'{side}-zero-rate-yield', side, category='zero-carry', rate=0., yield_=0.)
        add(f'{side}-negative-rate', side, category='negative-rate', rate=-.05)
        add(f'{side}-negative-yield', side, category='negative-yield', yield_=-.03)
        add(f'{side}-low-vol', side, category='low-vol', volatility=.005)
        add(f'{side}-delayed', side, category='delayed', opens=.5)
        add(f'{side}-expiry', side, category='expiry', spot=105., time=0.)
        add(f'{side}-zero-spot', side, category='zero-spot', spot=0., rate=-.125, time=2.)
        add(f'{side}-zero-strike', side, category='zero-strike', strike=0., yield_=-.125)
        add(f'{side}-zero-scale', side, category='zero-scale', spot=0., strike=0.)
    add('call-no-early', 'call', category='european-reduction', yield_=0.)
    add('call-dividend-yield', 'call', category='exercise', spot=120., yield_=.15)
    add('put-deep-exercise', category='exercise', spot=50.)
    for spot in (60., 90., 100., 140.):
        add(f'negative-boundaries-{int(spot)}', category='negative-rates-region',
            spot=spot, rate=-.005, yield_=-.01, volatility=.04, time=5.)
    add('probability-stress', category='lattice-domain-stress', volatility=.00001, rate=.125)
    add('deterministic-interior', 'call', category='deterministic', spot=100., strike=90.,
        rate=.25, yield_=.125, volatility=0., time=8.)
    add('deterministic-negative-call', 'call', category='deterministic', spot=100., strike=90.,
        rate=-.125, yield_=0., volatility=0.)
    add('deterministic-put', category='deterministic', spot=100., strike=110.,
        rate=.125, yield_=.0625, volatility=0.)
    for exponent in (-20, 20):
        add(f'put-scaled-{exponent}', category='scaling',
            spot=math.ldexp(100., exponent), strike=math.ldexp(100., exponent))
    return dict(schema='american-reference-corpus-v1', financial_contract_issue=108,
                acceptance_policy_issue=109,
                policy=dict(epsilon_scale_power=-16, reference_radius_fraction='1/8',
                            lattice_levels=[512, 1024, 2048, 4096], paired_offset=1,
                            extrapolation='2*A(2N)-A(N); empirical candidate only',
                            radius='4*max(last two extrapolate differences) + roundoff screen',
                            roundoff_screen='256*2^-52*max_level*max(spot,strike)',
                            quantlib_levels=[128, 256, 512, 1024], damping_steps=2,
                            mpmath_digits=[80, 160], precision_steps=[64, 128],
                            arb_bits=[256, 512], process_timeout_seconds=600,
                            comparator='Retain every finite outcome, exclusion and exception; no canonical output defines truth'),
                rows=rows,
                relations=[dict(kind='scaling', base='put-100', other=f'put-scaled-{k}', power=k)
                           for k in (-20, 20)],
                extension_cases=[
                    dict(id='cash-call-before', kind='zero-carry-cash', side='call', spot=100,
                         strike=90, dividends=[[.5, 20]], exercise='american', opens=[0, 'regular'],
                         expiry=[1, 'regular'], exact='10'),
                    dict(id='cash-call-after-open', kind='zero-carry-cash', side='call', spot=100,
                         strike=90, dividends=[[.5, 20]], exercise='american', opens=[.5, 'after'],
                         expiry=[1, 'regular'], exact='0'),
                    dict(id='cash-bermudan-after', kind='zero-carry-cash', side='call', spot=100,
                         strike=90, dividends=[[.5, 20]], exercise='bermudan',
                         rights=[[.5, 'after'], [1, 'regular']], exact='0'),
                    dict(id='cash-bermudan-both', kind='zero-carry-cash', side='call', spot=100,
                         strike=90, dividends=[[.5, 20]], exercise='bermudan',
                         rights=[[.5, 'before'], [.5, 'after'], [1, 'regular']], exact='10'),
                    dict(id='cash-expiry-before', kind='zero-carry-cash', side='put', spot=100,
                         strike=110, dividends=[[.5, 20]], exercise='european', rights=[[.5, 'before']], exact='10'),
                    dict(id='cash-expiry-after', kind='zero-carry-cash', side='put', spot=100,
                         strike=110, dividends=[[.5, 20]], exercise='european', rights=[[.5, 'after']], exact='30'),
                    dict(id='cash-limited-liability', kind='zero-carry-cash', side='put', spot=3,
                         strike=2, dividends=[[.5, 1], [.5, 4]], exercise='european', rights=[[1, 'regular']], exact='2'),
                    dict(id='cash-zero-horizon', kind='zero-carry-cash', side='put', spot=100,
                         strike=110, dividends=[[0, 20]], exercise='european', rights=[[0, 'after']], exact='30'),
                    dict(id='curve-zero-stock', kind='absorbing-put-curve', spot=0, strike=100,
                         rate_knots=[[0, -.25], [1, .125]], expiry=2,
                         exact_expression='100*exp(1/4)', maximizer=1)
                ])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version', action='version', version='american-corpus 1')
    p.add_argument('arguments', nargs='*', help=argparse.SUPPRESS)
    if p.parse_args().arguments:
        p.error('no positional arguments accepted')
    print(json.dumps(corpus(), indent=2, allow_nan=False))


if __name__ == '__main__':
    main()
