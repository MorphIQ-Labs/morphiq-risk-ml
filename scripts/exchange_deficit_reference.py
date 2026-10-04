#!/usr/bin/env python3
"""Independent split-payoff integration for unresolved intermediate variance."""
import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
from flint import arb,acb,ctx
from exchange_reference import value,PRECISIONS

def reference(row):
    f={k:Fraction(value(x)) for k,x in row['inputs'].items()}
    v=f['time']*((f['sigma1']-f['sigma2'])**2+2*f['sigma1']*f['sigma2']*(1-f['rho']))
    if v<=0 or f['s1']<=0 or f['s2']<=0:return None
    for precision in PRECISIONS:
        ctx.prec=precision
        ball=lambda q:arb(q.numerator)/arb(q.denominator)
        a=ball(f['s1'])*(-ball(f['q1'])*ball(f['time'])).exp()
        b=ball(f['s2'])*(-ball(f['q2'])*ball(f['time'])).exp()
        s=ball(v).sqrt();log_ratio=(ball(f['s1'])/ball(f['s2'])).log()+(ball(f['q2'])-ball(f['q1']))*ball(f['time'])
        x1=log_ratio/s+s/2;x2=s-x1
        if not (0<x1<40 and 0<x2<40):return None
        norm=(2*arb.pi()).sqrt()
        def tail(x):
            integrand=lambda t,analytic:(-x*t-t*t/2).exp()
            part=acb.integral(integrand,0,64,rel_tol=arb(2)**(-min(precision//2,1280)),abs_tol=arb(2)**(-min(precision//2,1280)),deg_limit=128,eval_limit=10000,depth_limit=30).real
            omitted=(-64*x-arb(2048)).exp()/(x+64)
            return (-x*x/2).exp()/norm*(part+arb(0,omitted.upper()))
        deficit=a*tail(x1)+b*tail(x2)
        expectation=a-deficit
        phi=lambda z:(-z/arb(2).sqrt()).erfc()/2
        closed=a*phi(x1)-b*phi(-x2)
        if expectation.is_finite() and closed.is_finite() and closed.overlaps(expectation) and expectation.rad()<=a.abs_upper()*arb(2)**(-1200):
            return dict(status='interval',precision=precision,route='split-payoff-deficit-quadrature',closed=closed.str(1400,more=True),integral=expectation.str(1400,more=True))
    return None

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='exchange-deficit-reference 1')
    p.add_argument('--references',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();data=json.loads(args.references.read_text());changed=[]
    for row in data['rows']:
        if row['reference']['status']!='unresolved':continue
        result=reference(row)
        if result is not None:
            row['prior_reference']=row['reference'];row['reference']=result;changed.append(row['id'])
    data['deficit_adjudication']=dict(ids=changed,parent_sha256=hashlib.sha256(args.references.read_bytes()).hexdigest(),script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    args.output.write_text(json.dumps(data,indent=2)+'\n');print(changed)
if __name__=='__main__':main()
