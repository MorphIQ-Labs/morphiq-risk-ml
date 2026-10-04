#!/usr/bin/env python3
"""Frozen original-word exchange cases and two independent Arb reference routes."""
import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PRECISIONS = [256, 512, 1024, 2048, 4096]
QUADRATURE = dict(deg_limit=128, eval_limit=20000, depth_limit=30)
FIELDS = ('s1', 's2', 'q1', 'q2', 'sigma1', 'sigma2', 'rho', 'time', 'limit')


def bits(x):
    return struct.pack('>d', x).hex()


def value(x):
    return struct.unpack('>d', bytes.fromhex(x))[0]


def cases():
    rows = []
    base = dict(s1=100., s2=95., q1=.01, q2=.02, sigma1=.2, sigma2=.3,
                rho=.5, time=1., limit=1e-9)
    def add(name, required=False, **changes):
        p = base | changes
        rows.append(dict(id=name, required=required, inputs={k: bits(p[k]) for k in FIELDS}))
    add('ordinary', True)
    add('reverse', True, s1=95., s2=100., q1=.02, q2=.01, sigma1=.3, sigma2=.2)
    add('equal-assets', True, s1=100., s2=100., q1=0., q2=0., sigma1=.2, sigma2=.2, rho=0.)
    for rho in (-1., math.nextafter(-1., 0.), 0., math.nextafter(1., 0.), 1.):
        for sigma2 in (.2, math.nextafter(.2, 0.), math.nextafter(.2, 1.), 0., .3):
            add(f'correlation-{len(rows)}', s2=100., q1=0., q2=0., sigma2=sigma2, rho=rho)
    for s1, s2 in ((100., 95.), (95., 100.), (100., 100.), (0., 100.), (100., 0.), (0., 0.)):
        add(f'expiry-{len(rows)}', True, s1=s1, s2=s2, time=0., limit=0.)
    add('zero-receive', True, s1=0., limit=0.)
    add('zero-deliver', s2=0.)
    add('zero-variance', sigma1=0., sigma2=0.)
    add('zero-variance-atm', True, s1=100., s2=100., q1=.01, q2=.01, sigma1=.2, sigma2=.2, rho=1., limit=0.)
    for exponent in (-1000, -500, 500, 1000):
        add(f'currency-{exponent}', s1=math.ldexp(1., exponent), s2=math.ldexp(.95, exponent))
    tiny = math.ulp(0.)
    for t in (tiny, math.ldexp(1., -1022), .5, 2.):
        add(f'time-{len(rows)}', time=t, s2=100., q1=0., q2=0.)
    for sigma in (tiny, math.ldexp(1., -537), math.ldexp(1., -511), 1e150):
        add(f'volatility-{len(rows)}', sigma1=sigma, sigma2=sigma, s2=100., q1=0., q2=0., rho=0.)
    add('negative-yield', q1=-.1, q2=-.2)
    add('discount-overflow', q1=-1000., q2=-1000.)
    add('carry-cancellation', s1=100., s2=100., q1=.01, q2=math.nextafter(.01, 1.), sigma1=0., sigma2=0.)
    add('deep-otm', s1=1., s2=1000.)
    add('deep-itm', s1=1000., s2=1.)
    add('exact-only', limit=0.)
    add('demanding-limit', limit=1e-20)
    for field, x in (('s1', -1.), ('s2', float('inf')), ('time', -1.), ('q1', float('nan')),
                     ('rho', math.nextafter(1., 2.)), ('rho', math.nextafter(-1., -2.)),
                     ('sigma1', -1.), ('limit', -1.), ('limit', float('inf'))):
        add(f'invalid-{len(rows)}', **{field: x})
    return dict(schema=1, precision_bits=PRECISIONS, quadrature=QUADRATURE,
                worker_seconds=60, rows=rows)


def reference(row):
    from flint import arb, acb, ctx
    p = {k: value(v) for k, v in row['inputs'].items()}
    if (any(not math.isfinite(x) for k, x in p.items() if k != 'limit')
        or any(p[k] < 0 for k in ('s1', 's2', 'sigma1', 'sigma2', 'time')) or abs(p['rho']) > 1):
        return dict(status='invalid_input')
    if not math.isfinite(p['limit']) or p['limit'] < 0:
        return dict(status='invalid_accuracy')
    f = {k: Fraction(x) for k, x in p.items()}
    v = f['time'] * ((f['sigma1']-f['sigma2'])**2 + 2*f['sigma1']*f['sigma2']*(1-f['rho']))
    def ball(q):
        return arb(q.numerator) / arb(q.denominator)
    attempts = []
    for precision in PRECISIONS:
        ctx.prec = precision
        try:
            t = ball(f['time'])
            a = ball(f['s1']) * (-ball(f['q1'])*t).exp()
            b = ball(f['s2']) * (-ball(f['q2'])*t).exp()
            if f['time'] == 0:
                closed = integral = ball(max(f['s1']-f['s2'], 0))
                route = 'exact-expiry'
            elif f['s1'] == 0:
                closed = integral = arb(0)
                route = 'exact-zero-receive'
            elif f['s2'] == 0 or v == 0:
                delta = a-b
                if f['s1'] == f['s2'] and f['q1'] == f['q2']:
                    closed = integral = arb(0)
                elif delta >= 0:
                    closed = integral = delta
                elif delta <= 0:
                    closed = integral = arb(0)
                else:
                    raise ValueError('unresolved deterministic sign')
                route = 'independent-discount-boundary'
            else:
                variance = ball(v)
                s = variance.sqrt()
                log_ratio = (ball(f['s1'])/ball(f['s2'])).log() + (ball(f['q2'])-ball(f['q1']))*t
                d1 = log_ratio/s+s/2
                d2 = d1-s
                phi = lambda z: (-z/arb(2).sqrt()).erfc()/2
                closed = a*phi(d1)-b*phi(d2)
                if not (s < 64):
                    raise ValueError('quadrature s<64 capability guard')
                # Entire integrand; max() is NEVER passed to analytic quadrature.
                z0 = (-log_ratio+variance/2)/s
                L = s.upper()+math.ceil(math.sqrt(2*precision))
                lo, hi = max(z0.lower(), -L), min(z0.upper(), L)
                start = max(-L, min(z0.upper(), L))
                norm = (2*arb.pi()).sqrt()
                def positive_branch(z, analytic):
                    return ((-variance/2+s*z).exp()-b/a)*(-z*z/2).exp()/norm
                integral = acb.integral(positive_branch, start, L,
                    rel_tol=arb(2)**(-precision//2), abs_tol=arb(2)**(-precision//2), **QUADRATURE).real * a
                strip = arb(0)
                if hi > lo:
                    strip = (hi-lo)*a*(-variance/2+s*hi).exp()/norm
                def mills_tail(x):
                    return (-x*x/2).exp()/(x*norm)
                tail = a*(mills_tail(L-s)+mills_tail(L+s))
                integral += arb(0, (strip+tail).upper())
                route = 'positive-payoff-quadrature'
            if not closed.is_finite() or not integral.is_finite():
                raise ValueError('nonfinite reference')
            if not closed.overlaps(integral):
                return dict(status='route_disagreement', precision=precision,
                            closed=closed.str(100, more=True), integral=integral.str(100, more=True))
            # A reference goal, not a runtime certificate tolerance.
            goal = min(a.abs_upper(), closed.abs_upper()) * arb(2)**(-256)
            if closed.is_zero():
                goal = arb(0)
            if closed.rad() <= goal and integral.rad() <= goal:
                return dict(status='interval', precision=precision, route=route,
                            closed=closed.str(100, more=True), integral=integral.str(100, more=True))
            attempts.append(dict(precision=precision, reason='reference width'))
        except (ValueError, OverflowError) as exc:
            attempts.append(dict(precision=precision, reason=str(exc)))
    return dict(status='unresolved', attempts=attempts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='exchange-reference 2')
    sub = parser.add_subparsers(dest='command', required=True)
    freeze = sub.add_parser('freeze'); freeze.add_argument('output', type=Path)
    run = sub.add_parser('run'); run.add_argument('corpus', type=Path); run.add_argument('output', type=Path)
    worker = sub.add_parser('worker'); worker.add_argument('input', type=Path)
    args = parser.parse_args()
    if args.command == 'freeze':
        args.output.write_text(json.dumps(cases(), indent=2)+'\n')
    elif args.command == 'worker':
        print(json.dumps(reference(json.loads(args.input.read_text()))))
    else:
        import importlib.metadata, platform
        from flint import __FLINT_VERSION__
        corpus = json.loads(args.corpus.read_text())
        rows = []
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'row.json'
            for row in corpus['rows']:
                path.write_text(json.dumps(row))
                try:
                    process = subprocess.run([sys.executable, __file__, 'worker', str(path)],
                        capture_output=True, text=True, timeout=60, check=True)
                    ref = json.loads(process.stdout)
                except subprocess.TimeoutExpired:
                    ref = dict(status='unresolved', reason='worker timeout')
                except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
                    ref = dict(status='tool_error', reason=str(exc), stderr=getattr(exc, 'stderr', ''))
                rows.append(row | dict(reference=ref))
                print(row['id'], ref['status'], flush=True)
        result = dict(schema=1, rows=rows, corpus_sha256=hashlib.sha256(args.corpus.read_bytes()).hexdigest(),
                      generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                      tools=dict(python=platform.python_version(), python_flint=importlib.metadata.version('python-flint'), flint=__FLINT_VERSION__))
        args.output.write_text(json.dumps(result, indent=2)+'\n')

if __name__ == '__main__':
    main()
