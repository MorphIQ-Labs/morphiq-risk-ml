#!/usr/bin/env python3
"""Adjudicate retained extreme-tail rows with a direct payoff inequality."""
import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
from flint import arb,ctx
from exchange_reference import value

def bound(row):
    p={k:Fraction(value(x)) for k,x in row['inputs'].items()}
    v=p['time']*((p['sigma1']-p['sigma2'])**2+2*p['sigma1']*p['sigma2']*(1-p['rho']))
    if v<6400 or p['s1']<=0 or p['s2']<=0:return None
    ctx.prec=4096
    ball=lambda q:arb(q.numerator)/arb(q.denominator)
    a=ball(p['s1'])*(-ball(p['q1'])*ball(p['time'])).exp()
    b=ball(p['s2'])*(-ball(p['q2'])*ball(p['time'])).exp()
    s=ball(v).sqrt()
    ratio=(ball(p['s1'])/ball(p['s2'])).log()+(ball(p['q2'])-ball(p['q1']))*ball(p['time'])
    d1=ratio/s+s/2;d2=d1-s
    phi=lambda z:(-z/arb(2).sqrt()).erfc()/2
    closed=a*phi(d1)-b*phi(d2)
    deficit=(a+b)*arb(-800).exp()/(40*(2*arb.pi()).sqrt())
    interval=a+arb(0,deficit.upper())
    if not (closed.is_finite() and interval.is_finite() and closed.overlaps(interval)):
        raise ValueError('tail bound/reference disagreement or nonfinite result')
    return dict(status='interval',precision=4096,route='direct-payoff-deficit-proof',
                resolution_goal_met=False,closed=closed.str(1400,more=True),integral=interval.str(1400,more=True),
                note='finite analytical bound judged by full certificate containment; not a quadrature precision pass')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='exchange-tail-adjudication 1')
    p.add_argument('--references',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();data=json.loads(args.references.read_text());changed=[]
    for row in data['rows']:
        if row['reference']['status']!='unresolved':continue
        result=bound(row)
        if result is not None:
            row['prior_reference']=row['reference'];row['reference']=result;changed.append(row['id'])
    data['tail_adjudication']=dict(ids=changed,parent_sha256=hashlib.sha256(args.references.read_bytes()).hexdigest(),script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    args.output.write_text(json.dumps(data,indent=2)+'\n');print(changed)
if __name__=='__main__':main()
