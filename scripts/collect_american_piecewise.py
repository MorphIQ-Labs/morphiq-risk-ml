"""Validate and assemble retained piecewise reference observations (no runtime scorer)."""
import argparse
from decimal import Decimal, localcontext
import hashlib
import json
from pathlib import Path
from american_piecewise_reference import number


def assemble(root, cases):
    ids=[r['id'] for r in cases]
    def jsonrows(name):
        rows=[json.loads(s) for s in (root/name).read_text().splitlines()]
        if [r['id'] for r in rows]!=ids:raise ValueError('reference row identity/order')
        return {r['id']:r for r in rows}
    analytic=[jsonrows(f'analytic-{p}.jsonl') for p in (80,160)]
    discrete=[jsonrows(f'discrete-{p}.jsonl') for p in (80,160)]
    def tsv(name,n):
        rows=[s.split('\t') for s in (root/f'{name}-{n}.tsv').read_text().splitlines()]
        if [r[0] for r in rows]!=ids or any(r[1]!=str(n) for r in rows):raise ValueError('reference row identity/order')
        if any(len(r)!=(7 if name=='quantlib' else 5) for r in rows):raise ValueError('reference column count')
        return {r[0]:r for r in rows}
    quad={n:tsv('quadrature',n) for n in (8,256,512,1024)}
    ql={n:tsv('quantlib',n) for n in (128,256,512)}
    out=[]
    for case in cases:
        id=case['id']; scale=max(number(case['inputs'][k]) for k in ('spot','strike'))
        a,b=(x[id]['value'] for x in analytic)
        d,e=(x[id]['value'] for x in discrete)
        with localcontext() as ctx:
            ctx.prec=180
            if (a is None)!=(b is None) or (d is None)!=(e is None):raise ValueError('precision availability changed')
            if a is not None and abs(Decimal(a)-Decimal(b))>Decimal('1e-70')*max(Decimal(1),abs(Decimal(b))):raise ValueError('analytical precision unresolved')
            if d is not None:
                if abs(Decimal(d)-Decimal(e))>Decimal('1e-70')*max(Decimal(1),abs(Decimal(e))):raise ValueError('discrete precision unresolved')
                cpp=quad[8][id]
                if cpp[2]!='finite' or abs(float(e)-float.fromhex(cpp[3]))>2**-40*scale:raise ValueError('discrete binary64 arithmetic mismatch: '+id)
        refinements=[]
        for n in (256,512,1024):
            v=quad[n][id]
            if v[2]=='finite':
                lo,hi=map(float.fromhex,v[3:5])
                if not 0<=lo<=hi<float('inf'):raise ValueError('invalid quadrature pair')
                refinements.append(dict(n=n,lower=lo.hex(),upper=hi.hex()))
            elif v[2]!='unavailable':raise ValueError('invalid quadrature status')
        if b is not None:
            value=float(b);radius=2**-50*max(1,abs(value));method=analytic[1][id]['method']
        elif len(refinements)==3:
            mids=[(float.fromhex(r['lower'])+float.fromhex(r['upper']))/2 for r in refinements]
            value=mids[-1]
            radius=4*max(abs(mids[1]-mids[0]),abs(mids[2]-mids[1]))+(float.fromhex(refinements[-1]['upper'])-float.fromhex(refinements[-1]['lower']))/2+256*2**-53*1024*scale
            method='positive quadrature empirical refinement'
        else:raise ValueError('missing reference path: '+id)
        out.append(dict(id=id,value=value.hex(),radius=radius.hex(),method=method,primary_resolved=radius<=scale*2**-19,loose_resolved=radius<=scale/800,quadrature=refinements,quantlib=[ql[n][id] for n in (128,256,512)],analytical_digits=b,discrete_digits=e))
    return dict(schema=1,rows=out,sources={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.iterdir()) if p.is_file() and p.suffix in ('.tsv','.jsonl','.stderr')})


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='piecewise-collector 1')
    p.add_argument('--raw',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    cases=json.loads(Path('docs/evidence/american-piecewise/cases-v1.json').read_text())['rows']
    data=assemble(a.raw,cases)
    a.output.write_text(json.dumps(data,indent=2)+'\n')
    print('references',len(data['rows']),'primary resolved',sum(r['primary_resolved'] for r in data['rows']),'loose resolved',sum(r['loose_resolved'] for r in data['rows']))

if __name__=='__main__':main()
