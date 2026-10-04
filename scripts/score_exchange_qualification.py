#!/usr/bin/env python3
"""Exact-rational certificate scoring; unresolved references never count as passes."""
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
from pathlib import Path
from flint import arb, ctx
from exchange_reference import value

def endpoints(text):
    x=arb(text)
    return [x.lower(),x.upper()]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='exchange-score 1')
    p.add_argument('--references',type=Path,required=True);p.add_argument('--runtime',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();ctx.prec=4096
    references=json.loads(args.references.read_text())['rows']
    runtime=[line.split() for line in args.runtime.read_text().splitlines()]
    if [r['id'] for r in references] != [r[0] for r in runtime]:raise SystemExit('membership/order mismatch')
    rows=[]
    for row,observed in zip(references,runtime):
        id,status,*words=observed;ref=row['reference'];rs=ref['status']
        verdict='explicit_failure';reason=None
        if status=='served':
            centre,radius=map(lambda x:Fraction(float.fromhex(x)),words)
            limit=Fraction(value(row['inputs']['limit']))
            if centre<0 or radius<0 or radius>limit:
                verdict='failure';reason='invalid certificate'
            elif rs=='interval':
                bounds=endpoints(ref['closed'])+endpoints(ref['integral'])
                # Certificate endpoints are exact dyadics of at most 2099 bits.
                # Keep reference exponents in Arb: far-tail exponents can be
                # too large to materialize as an integer rational denominator.
                def exact(q):
                    result=arb(q.numerator)/arb(q.denominator)
                    if not result.is_exact():raise ValueError('certificate endpoint not exact')
                    return result
                low,high=exact(centre-radius),exact(centre+radius)
                if all(low<=x and x<=high for x in bounds):verdict='contained'
                else:verdict='failure';reason='reference outside certificate'
            elif rs=='unresolved':
                verdict='failure' if row['required'] else 'unadjudicated'
                reason='mandatory reference unresolved' if row['required'] else None
            else:verdict='failure';reason='served invalid/reference error'
        elif status in ('invalid_input','invalid_accuracy'):
            verdict='invalid_control' if rs==status else 'failure'
        elif status not in ('numerical_failure','accuracy_exceeded'):
            verdict='failure';reason='unknown runtime result'
        elif row['required'] or rs not in ('interval','unresolved'):
            verdict='failure';reason='mandatory/unexpected refusal'
        rows.append(dict(id=id,runtime_status=status,reference_status=rs,verdict=verdict,reason=reason,words=words))
    result=dict(schema=1,rows=rows,counts=dict(Counter(r['verdict'] for r in rows)),runtime_counts=dict(Counter(r['runtime_status'] for r in rows)),
                references_sha256=hashlib.sha256(args.references.read_bytes()).hexdigest(),runtime_sha256=hashlib.sha256(args.runtime.read_bytes()).hexdigest())
    args.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result['counts']))
    if any(r['verdict']=='failure' for r in rows):raise SystemExit(1)
if __name__=='__main__':main()
