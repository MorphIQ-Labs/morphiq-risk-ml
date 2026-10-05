#!/usr/bin/env python3
"""Optional serial #110 campaign; no runtime pricing imports or private assets."""
import argparse
from fractions import Fraction as F
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import platform
import sys

from american_reference_data import (BASE, FIELDS, ROOT, capture, decode, first_index,
    inputs, parse_raw, require, runner_input, score_price, strict_json, validate_corpus,
    validate_fixture)


def bounds(ball):
    require(ball.is_finite(), 'nonfinite analytical interval')
    if ball.is_zero():
        return F(0), F(0)
    from flint import arb
    # Bound export size even for probabilities with millions of exponent bits.
    lo = math.nextafter(float(ball.lower()), -math.inf)
    hi = math.nextafter(float(ball.upper()), math.inf)
    require(math.isfinite(lo) and math.isfinite(hi), 'unrepresentable analytical endpoints')
    low, high = F(lo), F(hi)
    require(arb(low.numerator)/low.denominator <= ball and
            ball <= arb(high.numerator)/high.denominator, 'outward endpoint verification')
    return low, high


def maximum(candidates):
    ranges = [bounds(v) for v in candidates]
    return max(v[0] for v in ranges), max(v[1] for v in ranges)


def analytic(row, precision):
    from flint import arb, ctx
    ctx.prec = precision
    p = {k: F(v) for k, v in inputs(row).items()}
    def ball(f):
        return arb(f.numerator)/arb(f.denominator)
    s, k, r, q, sig, t, opening = [ball(p[f]) for f in FIELDS]
    call = row['side'] == 'call'
    if p['time'] == 0:
        value = max(p['spot']-p['strike'] if call else p['strike']-p['spot'], F(0))
        return dict(american=(value, value), european=(value, value), route='exact-expiry')
    if p['spot'] == 0:
        european = arb(0) if call else k*(-r*t).exp()
        exercise_time = opening if p['rate'] >= 0 else t
        price = arb(0) if call else k*(-r*exercise_time).exp()
        return dict(american=bounds(price), european=bounds(european), route='absorbing-zero')
    if p['strike'] == 0:
        european = s*(-q*t).exp() if call else arb(0)
        exercise_time = opening if p['yield_'] >= 0 else t
        price = s*(-q*exercise_time).exp() if call else arb(0)
        return dict(american=bounds(price), european=bounds(european), route='zero-strike')
    if p['volatility'] == 0:
        def discounted(time):
            spread = s*(-q*time).exp()-k*(-r*time).exp()
            return spread if call else -spread
        european = maximum([arb(0), discounted(t)])
        times = [opening, t]
        ratio = p['rate']*p['strike']/(p['yield_']*p['spot']) if p['yield_'] else F(0)
        if ratio > 0 and p['rate'] != p['yield_']:
            stationary = ball(ratio).log()/(r-q)
            if stationary > opening and stationary < t:
                times.append(stationary)
            elif not (stationary <= opening or stationary >= t):
                raise ValueError('ambiguous stationary-time inclusion')
        price = maximum([arb(0), *[discounted(time) for time in times]])
        return dict(american=price, european=european, route='deterministic-stopping')
    st = sig*t.sqrt()
    d1 = ((s/k).log()+(r-q)*t)/st+st/2
    d2 = d1-st
    cdf = lambda z: (-z/arb(2).sqrt()).erfc()/2
    a, b = s*(-q*t).exp(), k*(-r*t).exp()
    euro = a*cdf(d1)-b*cdf(d2) if call else b*cdf(-d2)-a*cdf(-d1)
    european = bounds(euro)
    american = european if call and p['yield_'] == 0 and p['rate'] >= 0 else None
    return dict(american=american, european=european,
                route='no-early-call' if american else 'European-terminal-only')


def mp_tree(row, n, digits):
    import mpmath as mp
    with mp.workdps(digits):
        # Explicit original binary64 rationals; no decimal reconstruction.
        def number(value):
            a, b = F(value).as_integer_ratio()
            return mp.mpf(a)/b
        p = {k: number(v) for k, v in inputs(row).items()}
        if p['volatility'] == 0 or p['spot'] == 0 or p['time'] == 0:
            return dict(status='unavailable', reason='analytical boundary')
        dt = p['time']/n
        h = p['volatility']*mp.sqrt(dt)
        prob = mp.expm1((p['rate']-p['yield_'])*dt+h)/mp.expm1(2*h)
        if not 0 <= prob <= 1:
            return dict(status='unavailable', reason='inadmissible probability')
        discount = mp.exp(-p['rate']*dt)
        def payoff(stock):
            return max(stock-p['strike'] if row['side']=='call' else p['strike']-stock, mp.mpf(0))
        # Direct node exponentials, independent of the C++ stock recurrence.
        values = [payoff(p['spot']*mp.exp((2*j-n)*h)) for j in range(n+1)]
        first = first_index(row, n)
        for i in reversed(range(n)):
            for j in range(i+1):
                value = discount*((1-prob)*values[j]+prob*values[j+1])
                values[j] = max(value, payoff(p['spot']*mp.exp((2*j-i)*h))) if i>=first else value
        return dict(status='finite', value=mp.nstr(values[0], digits), steps=n, digits=digits)


def rational_events(case):
    """Independent exact path replay for the zero-carry/zero-vol extension specs."""
    phase = {'before': 0, 'regular': 1, 'after': 2}
    instant = lambda item: (F(item[0]), phase[item[1]])
    if case['exercise'] == 'american':
        start, end = instant(case['opens']), instant(case['expiry'])
        rights = {start, end}
        for time, _ in case['dividends']:
            rights.update([(F(time), 0), (F(time), 2)])
        rights = sorted(x for x in rights if start <= x <= end)
    else:
        rights = [instant(x) for x in case['rights']]
    joint = {}
    for time, amount in case['dividends']:
        joint[F(time)] = joint.get(F(time), F(0))+F(amount)
    outcomes = []
    for right in rights:
        stock = F(case['spot'])
        for time, amount in sorted(joint.items()):
            if time < right[0] or (time == right[0] and right[1] == 2):
                stock = max(stock-amount, F(0))
        payoff = stock-F(case['strike']) if case['side']=='call' else F(case['strike'])-stock
        outcomes.append(max(payoff, F(0)))
    return max(outcomes)


def exact_extension(case):
    value = rational_events(case)
    require(value == F(case['exact']), 'incorrect extension expectation')
    return dict(id=case['id'], status='exact', value=str(value))


def serializable_analytic(value):
    return {k: [str(x) for x in v] if isinstance(v, tuple) else v for k,v in value.items()}


def make_reference(row, lattice, policy):
    attempts = [analytic(row, bits) for bits in policy['arb_bits']]
    low, high = attempts
    euro = high['european']
    require(max(low['european'][0], euro[0]) <= min(low['european'][1], euro[1]),
            'analytical precision disagreement')
    from flint import arb, ctx
    ctx.prec = policy['arb_bits'][-1]
    p = {k: F(v) for k, v in inputs(row).items()}
    coefficient = max(-p['yield_'] if row['side']=='call' else -p['rate'], F(0))*p['time']
    scale = p['spot'] if row['side']=='call' else p['strike']
    cap = (arb(scale.numerator)/scale.denominator *
           (arb(coefficient.numerator)/coefficient.denominator).exp())
    upper = bounds(cap)
    common = dict(analytical=[serializable_analytic(x) for x in attempts],
                  global_upper=list(map(str, upper)))
    epsilon = F(decode(row['epsilon']))
    if high['american'] is not None:
        lo, hi = high['american']
        require(low['american'] is not None and max(lo,low['american'][0]) <= min(hi,low['american'][1]),
                'American analytical precision disagreement')
        require((hi-lo)/2 <= epsilon/8, 'analytical reference too wide')
        return dict(status='resolved', kind='analytic_interval', lower=str(lo), upper=str(hi),
                    route=high['route'], **common)
    precision = []
    precision_ok = False
    for n in policy['precision_steps']:
        checks = [mp_tree(row, n, digits) for digits in policy['mpmath_digits']]
        precision.append(checks)
        raw = lattice[(row['id'],n)]
        if all(x['status']=='finite' for x in checks) and raw['status']=='finite':
            a, b = [F(x['value']) for x in checks]
            delta = abs(a-b)
            float_error = abs(F(float.fromhex(raw['american']))-b)
            precision_ok = delta <= epsilon/1024 and float_error <= epsilon/64
            precision[-1].append(dict(precision_difference=str(delta), float_error=str(float_error),
                                      screen_pass=precision_ok))
            break
    common['precision_replay'] = precision
    means = []
    for n in policy['lattice_levels']:
        pair = [lattice[(row['id'], m)] for m in (n,n+policy['paired_offset'])]
        if any(p['status']!='finite' for p in pair):
            return dict(status='unresolved', reason='lattice unavailable at a frozen level', **common)
        means.append(sum(F(float.fromhex(p['american'])) for p in pair)/2)
    candidates = [2*b-a for a,b in zip(means,means[1:])]
    p = inputs(row)
    screen = F(256)*F(2)**-52*max(policy['lattice_levels'])*max(F(p['spot']),F(p['strike']))
    radius = 4*max(abs(b-a) for a,b in zip(candidates,candidates[1:]))+screen
    center = candidates[-1]
    common['empirical_candidate'] = dict(center=str(center), radius=str(radius),
        paired_means=list(map(str,means)), extrapolates=list(map(str,candidates)), roundoff_screen=str(screen))
    if not precision_ok:
        return dict(status='unresolved', reason='precision replay unavailable or screen failed', **common)
    if radius > epsilon/8:
        return dict(status='unresolved', reason='empirical reference width exceeds frozen goal', **common)
    lo, hi = center-radius, center+radius
    if lo > upper[1] or hi < euro[0] or hi < 0 or (p['opens']==0 and hi < max(F(p['spot'])-F(p['strike'])
                                    if row['side']=='call' else F(p['strike'])-F(p['spot']),F(0))):
        return dict(status='unresolved', reason='candidate contradicts analytical bound', **common)
    return dict(status='resolved', kind='empirical', lower=str(lo), upper=str(hi),
                route='paired-CRR-extrapolation', **common)


def generate(corpus_path, lattice_exe, canonical_exe, output, reuse_raw=None):
    import mpmath
    import flint
    require(mpmath.__version__=='1.3.0' and flint.__version__=='0.9.0', 'unpinned oracle package')
    corpus = strict_json(corpus_path.read_text())
    rows = validate_corpus(corpus)
    policy = corpus['policy']
    levels = sorted(set(policy['precision_steps']+[m for n in policy['lattice_levels']
                    for m in (n,n+policy['paired_offset'])]))
    raw_maps = {}
    if reuse_raw:
        manifest = strict_json((reuse_raw/'manifest.json').read_text())['sha256']
        build = strict_json((reuse_raw/'build.json').read_text())
        for name in ('scripts/american_lattice.cpp', 'scripts/american_quantlib.cpp',
                     'scripts/american_runner_io.hpp'):
            require(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==manifest[name],
                    'reused raw runner source mismatch')
    for label, executable, grids in [('lattice',lattice_exe,levels),
                                     ('quantlib',canonical_exe,policy['quantlib_levels'])]:
        text = runner_input(rows,grids)
        (output/f'{label}-input.txt').write_text(text)
        if reuse_raw:
            require(hashlib.sha256(executable.read_bytes()).hexdigest()==build['binaries'][label],
                    'reused raw binary mismatch')
            require((reuse_raw/f'{label}-input.txt').read_text()==text, 'reused raw input mismatch')
            path=reuse_raw/f'{label}.tsv'
            key='docs/evidence/american-references/'+path.name
            require(hashlib.sha256(path.read_bytes()).hexdigest()==manifest[key],
                    'reused raw stream mismatch')
            raw=path.read_text()
            (output/path.name).write_text(raw)
            (output/(path.name+'.stderr')).write_text((reuse_raw/(path.name+'.stderr')).read_text())
        else:
            raw = capture([str(executable)],text,output/f'{label}.tsv',policy['process_timeout_seconds'])
        raw_maps[label] = parse_raw(raw,{(r['id'],n) for r in rows for n in grids})
        print(f'{label}: {len(raw_maps[label])} raw outcomes retained',flush=True)
    results = []
    for row in rows:
        ref = make_reference(row,raw_maps['lattice'],policy)
        checks = []
        epsilon = decode(row['epsilon'])
        for n in policy['quantlib_levels']:
            outcome = raw_maps['quantlib'][(row['id'],n)]
            comparison = (score_price(ref,float.fromhex(outcome['american']),epsilon)
                          if outcome['status']=='finite' else dict(status='excluded',reason=outcome['detail']))
            tight=(score_price(ref,float.fromhex(outcome['american']),epsilon/4)
                   if outcome['status']=='finite' else dict(status='excluded',reason=outcome['detail']))
            checks.append(dict(level=n,outcome=outcome,comparison=comparison,
                               epsilon_quarter_comparison=tight))
        nested = []
        for n in policy['lattice_levels']:
            raw = raw_maps['lattice'][(row['id'],n)]
            if raw['status']=='finite':
                a,e,b = [F(float.fromhex(raw[k])) for k in ('american','european','bermudan')]
                screen = F(256)*F(2)**-52*n*max(F(inputs(row)['spot']),F(inputs(row)['strike']))
                require(e <= b+screen and b <= a+screen, 'nested exercise violation')
                nested.append(dict(level=n, status='pass', screen=str(screen)))
            else:
                nested.append(dict(level=n,status='unavailable',reason=raw['detail']))
        results.append(dict(id=row['id'],inputs=row['inputs'],reference=ref,canonical=checks,
                            nested_exercise=nested,
                            lattice=[dict(level=n,**raw_maps['lattice'][(row['id'],n)]) for n in levels]))
        print(row['id'],ref['status'],ref.get('reason',ref.get('route')),flush=True)
    extensions=[]
    for case in corpus['extension_cases']:
        if case['kind']=='zero-carry-cash':
            extensions.append(exact_extension(case))
        else:
            require(case['exact_expression']=='100*exp(1/4)', 'unknown curve expectation')
            # S=0, put K: integrate each rate slab, maximize at knots/endpoints.
            from flint import arb,ctx
            ctx.prec=512
            integral=F(0);candidates=[arb(case['strike'])]
            knots=case['rate_knots']
            for i,(start,rate) in enumerate(knots):
                end=knots[i+1][0] if i+1<len(knots) else case['expiry']
                integral+=F(rate)*(F(end)-F(start))
                candidates.append(arb(case['strike'])*(-arb(integral.numerator)/integral.denominator).exp())
            lo,hi=maximum(candidates)
            expected=arb(100)*(arb(1)/4).exp()
            elo,ehi=bounds(expected)
            require(max(lo,elo)<=min(hi,ehi), 'incorrect curve expectation')
            extensions.append(dict(id=case['id'],status='analytic_interval',lower=str(lo),upper=str(hi)))
    scaling=[]
    by_id={r['id']:r for r in results}
    for relation in corpus['relations']:
        left,right=[by_id[relation[k]]['reference'] for k in ('base','other')]
        if left['status']=='resolved' and right['status']=='resolved':
            scale=F(2)**relation['power']
            lo,hi=F(left['lower'])*scale,F(left['upper'])*scale
            require(max(lo,F(right['lower']))<=min(hi,F(right['upper'])), 'scaling interval disagreement')
            scaling.append(dict(**relation,status='overlap'))
        else:
            scaling.append(dict(**relation,status='unresolved_reference'))
    fixture=dict(schema='american-references-v1',complete=True,rows=results,
                 extensions=extensions,scaling=scaling,policy=policy,
                 environment=dict(python=sys.version,platform=platform.platform(),
                     mpmath=mpmath.__version__,python_flint=flint.__version__,flint=flint.__FLINT_VERSION__))
    validate_fixture(corpus,fixture)
    temporary=output/'references-v1.json.tmp'
    temporary.write_text(json.dumps(fixture,indent=2,allow_nan=False)+'\n')
    temporary.replace(output/'references-v1.json')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='american-reference-generator 1')
    p.add_argument('--corpus',type=Path,default=BASE/'cases-v1.json')
    p.add_argument('--lattice',type=Path,required=True)
    p.add_argument('--quantlib',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--reuse-raw',type=Path,help='verified prior campaign directory')
    p.add_argument('arguments',nargs='*',help=argparse.SUPPRESS)
    args=p.parse_args()
    if args.arguments: p.error('no positional arguments accepted')
    try:
        args.output.mkdir(parents=True,exist_ok=False)
    except FileExistsError:
        p.error('output directory already exists')
    try:
        generate(args.corpus,args.lattice.resolve(),args.quantlib.resolve(),args.output,args.reuse_raw)
    except Exception as error:
        if args.output.exists():
            (args.output/'failure.json').write_text(json.dumps(dict(complete=False,error=str(error)))+'\n')
        raise


if __name__=='__main__':
    main()
