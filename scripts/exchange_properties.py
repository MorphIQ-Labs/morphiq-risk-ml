#!/usr/bin/env python3
"""Independent exact-rational parity and currency-scaling campaign checks."""
import argparse
from fractions import Fraction
import json
from pathlib import Path
from flint import arb,ctx
from exchange_reference import value

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='exchange-properties 1')
    p.add_argument('--cases',type=Path,required=True);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();ctx.prec=4096
    cases={r['id']:r for r in json.loads(args.cases.read_text())['rows']}
    outputs={words[0]:words[1:] for words in (line.split() for line in args.runtime.read_text().splitlines())}
    def cert(id):
        result=outputs[id]
        return tuple(Fraction(float.fromhex(x)) for x in result[1:]) if result[0]=='served' else None
    def exact(x):
        n,d=x.as_integer_ratio();return arb(n)/arb(d)
    rows=[]
    for id,row in cases.items():
        if not id.endswith('-reverse'):continue
        forward=id.removesuffix('-reverse');c1,c2=cert(forward),cert(id)
        if c1 is None or c2 is None:
            rows.append(dict(id=forward,property='parity',status='unavailable'));continue
        x={k:value(v) for k,v in cases[forward]['inputs'].items()}
        target=exact(x['s1'])*(-exact(x['q1'])*exact(x['time'])).exp()-exact(x['s2'])*(-exact(x['q2'])*exact(x['time'])).exp()
        bounds=[Fraction(str(z.fmpq())) for z in (target.lower(),target.upper())]
        centre=c1[0]-c2[0];radius=c1[1]+c2[1]
        rows.append(dict(id=forward,property='parity',status='pass' if all(abs(centre-z)<=radius for z in bounds) else 'failure'))
    for id in cases:
        if not id.startswith('scale-'):continue
        suffix=id[len('scale-'):];exponent,rho=suffix.split('-',1) if not suffix.startswith('-') else ('-'+suffix[1:].split('-',1)[0],suffix[1:].split('-',1)[1])
        exponent=int(exponent)
        other='scale-0-'+rho;c1,c2=cert(id),cert(other)
        if c1 is None or c2 is None:
            rows.append(dict(id=id,property='currency-scaling',status='unavailable'));continue
        factor=Fraction(2)**exponent
        # Intervals must overlap after exact dyadic scaling. This is a
        # consistency property, separate from full independent containment.
        ok=abs(c1[0]-factor*c2[0])<=c1[1]+factor*c2[1]
        rows.append(dict(id=id,property='currency-scaling',status='pass' if ok else 'failure'))
    from collections import Counter
    counts=dict(Counter(r['property']+'/'+r['status'] for r in rows))
    args.output.write_text(json.dumps(dict(rows=rows,counts=counts),indent=2)+'\n');print(counts)
    if any(r['status']=='failure' for r in rows):raise SystemExit(1)
if __name__=='__main__':main()
