#!/usr/bin/env python3
"""Refine all traced inverse references independently through mpmath erfinv.

Run with the pinned oracle environment. The generator uses log-tail root
solving; this check uses the inverse error function with enough guard digits
to preserve 2p-1 even at the smallest subnormal probability.
"""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import mpmath as mp


def value(word):
    return struct.unpack('>d', bytes.fromhex(word))[0]


def bits(x):
    return struct.pack('>d', x).hex()


def main(args):
    before=args.before.read_text().splitlines(); after=args.after.read_text().splitlines()
    assert len(before)==len(after)
    records=[]; points=[[],[]]; regions={}; other_changes=0
    for old,new in zip(before,after):
        f,p,r,b=old.split(); nf,np,nr,a=new.split()
        assert (f,p,r)==(nf,np,nr)
        if f!='inv':
            other_changes+=a!=b
            continue
        probability=value(p); tail=min(probability,1-probability)
        precision=math.ceil(-math.log10(tail))
        refs=[]; errors=[]
        for digits in (160+precision,320+precision):
            with mp.workdps(digits):
                exact=mp.mpf(probability)
                reference=mp.sqrt(2)*mp.erfinv(2*exact-1)
                refs.append(bits(float(reference)))
                spacing=mp.mpf(math.ulp(float(reference)))
                errors.append([float((mp.mpf(value(x))-reference)/spacing) for x in (b,a)])
        assert refs==[r,r], (p,r,refs)
        assert max(abs(x-y) for x,y in zip(*errors))<1e-12, p
        region='central' if abs(probability-.5)<=.425 else 'tail'
        stats=regions.setdefault(region,dict(rows=0,changed=0,worst_before_fractional_ulp=0,worst_after_fractional_ulp=0))
        stats['rows']+=1;stats['changed']+=a!=b
        for key,e in zip(('worst_before_fractional_ulp','worst_after_fractional_ulp'),errors[-1]): stats[key]=max(stats[key],abs(e))
        for xs,x in zip(points,(b,a)):xs.append((probability,value(x)))
        records.append(dict(p=p,reference=r,before=b,after=a,signed_ulp=errors[-1],digits=[160+precision,320+precision]))
        if len(records)%1000==0: print(f'{len(records)} inverse references refined',file=sys.stderr,flush=True)
    violations=[]
    for xs in points:
        xs.sort();violations.append(sum(y[1]<x[1] for x,y in zip(xs,xs[1:])))
    assert violations[1]==0, violations
    assert other_changes==0,other_changes
    result=dict(method='independent erfinv at 160/320 plus tail decimal digits',mpmath=mp.__version__,regions=regions,
                monotonicity_violations=dict(before=violations[0],after=violations[1]),non_inverse_changes=other_changes,
                trace_sha256=[hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.before,args.after)],records=records)
    args.output.write_bytes(gzip.compress((json.dumps(result,sort_keys=True,indent=2)+'\n').encode(),mtime=0))
    print(json.dumps({k:v for k,v in result.items() if k!='records'},indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='qualify_inverse_normal 1')
    for name in ('before','after','output'):parser.add_argument('--'+name,type=Path,required=True)
    main(parser.parse_args())
