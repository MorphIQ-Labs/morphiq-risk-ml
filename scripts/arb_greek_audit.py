#!/usr/bin/env python3
"""Optional independent formal-power-series price derivatives using FLINT/Arb.

No analytic Greek formulas or production coefficient tables are imported.
Taylor coefficients encode derivatives with factorials, not finite differences.
Reference uncertainty is the fixture's normalized three-word 2^-158 allowance.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import importlib.metadata
import json
from pathlib import Path
import struct
from flint import arb, arb_series, ctx, __FLINT_VERSION__


def word(x):
    return struct.unpack('>d', bytes.fromhex(x.zfill(16)))[0]


def series_price(model, side, inputs, direction):
    # S,K,T,r,q,sigma,shift are exact binary64 constants; derivatives vary
    # S/forward, T, rate and volatility in their declared model coordinates.
    s,k,t,r,q,sigma,shift = [arb_series([arb(v), direction.get(i,0)], prec=4)
                            for i,v in enumerate(inputs)]
    theta = 1 if side == 'call' else -1
    if model != 'bsm':
        q = r
    if model == 'displaced':
        s,k = s+shift,k+shift
    total = sigma*t.sqrt()
    def cdf(x):
        return (-x/arb(2).sqrt()).erfc()/2
    discount = (-r*t).exp()
    if model == 'bachelier':
        d=(s-k)/total
        density=(-d*d/2).exp()/(2*arb.pi()).sqrt()
        return discount*(theta*(s-k)*cdf(theta*d)+total*density)
    d1=((s/k).log()+(r-q)*t)/total+total/2
    d2=d1-total
    return theta*(s*(-q*t).exp()*cdf(theta*d1)-k*discount*cdf(theta*d2))


def derivative(model, side, inputs, name):
    def coeff(direction, order):
        return series_price(model,side,inputs,direction)[order]
    # Coefficients: D_v^n(price)/n!. Polarization obtains the mixed derivatives.
    if name == 'delta': return coeff({0:1},1)
    if name == 'gamma': return 2*coeff({0:1},2)
    if name == 'vega': return coeff({5:1},1)
    if name == 'volga': return 2*coeff({5:1},2)
    if name == 'rho': return coeff({3:1},1)
    if name == 'theta': return -coeff({2:1},1)/365
    if name == 'vanna': return coeff({0:1,5:1},2)-coeff({0:1},2)-coeff({5:1},2)
    if name == 'charm': return -(coeff({0:1,2:1},2)-coeff({0:1},2)-coeff({2:1},2))/365
    if name == 'veta': return -(coeff({5:1,2:1},2)-coeff({5:1},2)-coeff({2:1},2))/365
    if name == 'color': return -(coeff({0:1,2:1},3)-coeff({0:1,2:-1},3)-2*coeff({2:1},3))/365
    raise ValueError(name)


def certify(model, side, inputs, name, exponent, words):
    for precision in (256,512,1024,2048,4096):
        with ctx.workprec(precision):
            scale=arb(2)**exponent
            reference=sum(map(arb,words))*scale
            uncertainty=arb(2)**(exponent-158)
            value=derivative(model,side,inputs,name)
            difference=value-reference
            if difference > uncertainty or difference < -uncertainty:
                raise ArithmeticError(f'{model} {side} {name}: reference outside independent derivative enclosure')
            if difference < uncertainty and difference > -uncertainty:
                return precision
    return None


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    counts,precisions=Counter(),Counter()
    unresolved=[]
    wrong_control=False
    with gzip.open(args.fixture,'rt') as stream:
        for line_number,line in enumerate(stream,1):
            if not line.strip() or line.startswith('#'): continue
            model,side,name,*f=line.split()
            inputs=list(map(word,f[:7])); exponent=int(f[7]); words=list(map(word,f[8:11]))
            p=certify(model,side,inputs,name,exponent,words)
            counts[model+'/'+name]+=1
            if p is None: unresolved.append(dict(line=line_number,input=line.strip()))
            else:
                precisions[p]+=1
                if not wrong_control and words[0] != 0:
                    try: certify(model,side,inputs,name,exponent,[-x for x in words])
                    except ArithmeticError: wrong_control=True
                    else: raise ArithmeticError('opposite-sign reference was not rejected')
    report=dict(method='Order-3 Arb formal price series; factorial-aware directional coefficients and polarization for mixed Greeks',
                documentation='https://python-flint.readthedocs.io/en/stable/arb_series.html',
                python_flint=importlib.metadata.version('python-flint'),flint=__FLINT_VERSION__,
                source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.fixture,Path(__file__)]},
                rows=dict(counts),precision_counts=dict(precisions),unresolved=unresolved,
                wrong_reference_rejected=wrong_control,
                scope='Independent interval differentiation of price, not an independent human review or a universal OCaml proof.')
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(rows=sum(counts.values()),precisions=dict(precisions),unresolved=len(unresolved))))
    if not counts or unresolved or not wrong_control: raise SystemExit(1)


if __name__ == '__main__': main()
