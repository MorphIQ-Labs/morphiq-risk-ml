#!/usr/bin/env python3
"""Frozen independent Arb references for exact stopping-model reductions (#116)."""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import platform
from fractions import Fraction
from flint import arb, ctx, __FLINT_VERSION__, __version__

ROOT=Path(__file__).resolve().parents[1]

def cases():
    rows=[]
    def add(kind,side,s=100.,k=100.,r=0.,q=0.,sigma=.2,t=1.,opens=0.,expected='ok',name=None,limit=None):
        if limit is None: limit=max(math.ulp(0.), math.ldexp(max(s,k),-36))
        values=[s,k,r,q,sigma,t,opens,limit]
        rows.append(dict(id=name or f'case-{len(rows):04d}',kind=kind,side=side,words=[float(v).hex() for v in values],expected=expected))
    for s,r,sigma in itertools.product((80.,100.,120.),(0.,.05),(0.,.2,.8)):
        for kind,opens in [('american',0.),('american',.5),('bermudan',0.),('bermudan',.5)]:
            add(kind,'call',s=s,r=r,sigma=sigma,opens=opens)
    for s,r,q,sigma,side,kind in itertools.product((80.,100.,120.),(-.05,0.,.05),(-.03,.02),(0.,.2,.8),('call','put'),('american','bermudan')):
        add(kind,side,s=s,r=r,q=q,sigma=sigma,opens=1.)
    for s,k in [(0.,0.),(0.,100.),(100.,0.),(1.,2.**-54),(1.,math.ulp(0.)),(math.ulp(0.),0.),(math.ulp(0.)*2,math.ulp(0.)),(float.fromhex('0x1.fffffffffffffp+1023'),1.)]:
        for side,kind in itertools.product(('call','put'),('american','bermudan')):
            add(kind,side,s=s,k=k,r=-.05,q=.02,t=0.,sigma=.8,opens=0.)
    for scale in (2.**-500,2.**500):
        for side,kind in itertools.product(('call','put'),('american','bermudan')):
            add(kind,side,s=scale,k=scale,r=.05,q=.02,opens=1.)
    for side in ('call','put'):
        for s,k in [(0.,100.),(100.,0.),(0.,0.)]:
            add('american',side,s=s,k=k,r=-.05,q=.02,opens=1.)
        add('american',side,t=2.**-100,opens=2.**-100)
    add('american','call',r=-0.,q=-0.,name='negative-zero')
    add('american','call',r=-math.ulp(0.),expected='unsupported',name='negative-rate-neighbor')
    add('american','call',q=math.ulp(0.),expected='unsupported',name='positive-yield-neighbor')
    add('american','call',q=-math.ulp(0.),expected='unsupported',name='negative-yield-outside-scope')
    for side in ('call','put'):
        add('american',side,r=.05,q=.02,expected='unsupported',name='general-'+side)
        add('cash',side,opens=1.,expected='cash_unsupported')
        add('zero_cash',side,opens=1.,expected='cash_unsupported')
        add('empty_cash',side,opens=1.,expected='cash_unsupported')
        add('bermudan_cash',side,opens=1.,expected='cash_unsupported')
    add('american','put',s=80.,r=.05,sigma=0.,expected='unsupported',name='immediate-put-counterexample')
    add('american','call',s=120.,r=-.05,sigma=0.,expected='unsupported',name='negative-rate-call-counterexample')
    add('american','call',s=120.,q=.03,sigma=0.,expected='unsupported',name='yield-call-counterexample')
    add('american','call',r=512.,name='finite-arithmetic-exhaustion',expected='arithmetic')
    return rows

def reference(row):
    fs=list(map(float.fromhex,row['words']));s,k,r,q,sigma,t,_,_=map(arb,fs)
    sign=1 if row['side']=='call' else -1
    def positive(x):return x.max(arb(0))
    if fs[5]==0:return positive(sign*(s-k))
    a=s*(-q*t).exp();b=k*(-r*t).exp()
    if fs[4]==0 or fs[0]==0 or fs[1]==0:return positive(sign*(a-b))
    total=sigma*t.sqrt();d1=((s/k).log()+(r-q)*t)/total+total/2;d2=d1-total
    cdf=lambda x:(-x/arb(2).sqrt()).erfc()/2
    return sign*(a*cdf(sign*d1)-b*cdf(sign*d2))

def rational(x):
    m,e=map(int,x.man_exp())
    return Fraction(m)*Fraction(2)**e

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    a.output.mkdir(parents=True,exist_ok=False)
    corpus=cases();(a.output/'cases.json').write_text(json.dumps(dict(schema=1,rows=corpus),indent=2)+'\n')
    records=[];lines=[]
    for row in corpus:
        bounds=['-','-'];attempts=[]
        fs=list(map(float.fromhex,row['words']))
        exact_payoff=fs[5]==0 or (fs[4]==0 and fs[2]==0 and fs[3]==0)
        if row['expected']=='ok' and exact_payoff:
            x=(1 if row['side']=='call' else -1)*(Fraction(fs[0])-Fraction(fs[1]))
            x=max(x,Fraction(0));bounds=[str(x),str(x)]
            attempts.append(dict(precision='exact-rational payoff',lower=str(x),upper=str(x),resolved=True))
        elif row['expected']=='ok':
            for precision in (256,512,1024,2048):
                with ctx.workprec(precision):
                    value=reference(row);assert value.is_finite(),row['id']
                    lo,hi=rational(value.lower()),rational(value.upper())
                    # Reference precision is fixed independently of candidate radii.
                    scale=Fraction(max(map(float.fromhex,row['words'][:2])))
                    resolved=hi-lo<=max(scale,Fraction(1,2**1074))*Fraction(1,2**200)
                    attempts.append(dict(precision=precision,lower=str(lo),upper=str(hi),resolved=resolved))
                    if resolved:bounds=[str(lo),str(hi)];break
            assert bounds[0]!='-',row['id']+' unresolved reference'
        records.append(dict(id=row['id'],attempts=attempts))
        lines.append(' '.join([row['id'],row['kind'],row['side'],*row['words'],row['expected'],*bounds]))
    (a.output/'references.tsv').write_text('\n'.join(lines)+'\n')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    (a.output/'manifest.json').write_text(json.dumps(dict(schema=1,rows=len(corpus),python=platform.python_version(),python_flint=__version__,flint=__FLINT_VERSION__,sources={'scripts/generate_american_certification.py':sha(Path(__file__))},files={name:sha(a.output/name) for name in ('cases.json','references.tsv')},references=records),indent=2)+'\n')
    print(json.dumps(dict(rows=len(corpus),enclosed=sum(bool(x['attempts']) for x in records))))
if __name__=='__main__':main()
