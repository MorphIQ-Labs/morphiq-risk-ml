#!/usr/bin/env python3
"""Refine changed CALERF-replacement outputs, refining only changed Greek quantities.

No production coefficient is imported. Model values use the existing independent
oracle definitions; Greeks also use price differentiation. Scalar references use
mpmath Gaussian functions/Tricomi U. 220/440-digit expansions must agree.
"""
import argparse
from functools import lru_cache
import gzip
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'oracle'))
import mpmath
from mpmath import mp
from common import Contract,word,bits,round_binary64
from gen_greeks import closed_form
from gen_greek_bits import expansion
import gen_normal


@lru_cache(maxsize=4096)
def greek_values(model,side,inputs,precision,quantity):
    s,k,t,r,q,sigma,shift=map(word,inputs)
    c=Contract(model,side=='call',s,k,t,r,q,shift)
    with mp.workdps(precision+c.digits(sigma)):
        exact=closed_form(c,sigma)[quantity]
        if quantity=='rho':
            independent=mp.diff(lambda rate:c.price(sigma,r=rate),mp.mpf(c.r))
        else:
            orders=dict(delta=(1,0,0),gamma=(2,0,0),theta=(0,0,1),
                        vega=(0,1,0),vanna=(1,1,0),volga=(0,2,0),
                        charm=(1,0,1),veta=(0,1,1),color=(2,0,1))
            independent=mp.diff(lambda spot,vol,time:c.price(vol,s=spot,t=time),
                                (mp.mpf(c.s),mp.mpf(sigma),mp.mpf(c.t)),orders[quantity])
            if quantity in ('theta','charm','veta','color'):independent=-independent/365
        return exact,independent


def main(args):
    assert mpmath.__version__=='1.3.0'
    rows=json.loads(gzip.decompress(args.changes.read_bytes()))
    results=[]
    scalar=dict(erf=gen_normal.erf,erfc=gen_normal.erfc,erfcx=gen_normal.erfcx,
                cdf=gen_normal.cdf,logcdf=gen_normal.logcdf,pdf=gen_normal.phi,inv=gen_normal.inv)
    for row in rows:
        if row['fixture']=='dd':continue
        fields=row['input_reference'].split()
        normal=row['fixture']=='normal'
        greek=row['fixture'] in ('greeks','greek_bits')
        extra=0
        if not normal:
            model,side,quantity=fields[:3]
            start=4 if row['fixture']=='greeks' else 3
            if row['fixture']=='greeks':assert fields[3] in ('resolved','single_route')
            inputs=tuple(fields[start:start+7])
            s,k,t,r,q,sigma,shift=map(word,inputs)
            c=Contract(model,side=='call',s,k,t,r,q,shift)
            extra=c.digits(sigma)
        expansions=[]
        for precision in (220,440):
            with mp.workdps(precision+extra):
                if normal:value=scalar[fields[0]](mp.mpf(word(fields[1])))
                elif greek:
                    exact,independent=greek_values(model,side,inputs,precision,quantity)
                    value=exact
                    assert value==independent or abs(value-independent)<mp.mpf('1e-150')*abs(value)
                else:value=c.price(sigma)
                expansions.append(expansion(value))
                reference=gen_normal.to_double(value) if normal else round_binary64(value)
                if row['fixture']=='greek_bits':assert expansion(value)==(int(fields[10]),*fields[11:])
                else:assert bits(reference)==fields[-1],row
                errors={name:mp.nstr((mp.mpf(word(row[name]))-value)/math.ulp(reference),30)
                        for name in ('before','after')}
        assert expansions[0]==expansions[1],row
        results.append({**row,'refined_reference':expansions[-1],
                        'signed_ulp_error':errors,'precision_digits':[220+extra,440+extra],
                        'differentiation_checked':greek})
        if len(results)%250==0:print(len(results),'changed rows refined',flush=True)
    sources=[Path(__file__),ROOT/'oracle/common.py',ROOT/'oracle/gen_greeks.py',
             ROOT/'oracle/gen_greek_bits.py',ROOT/'oracle/gen_normal.py']
    result={'mpmath':mpmath.__version__,'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
            'changed_served_rows':results}
    data=(json.dumps(result,indent=2)+'\n').encode()
    if args.output.suffix=='.gz':data=gzip.compress(data,mtime=0)
    args.output.write_bytes(data)
    print(len(results),'changed rows refined; all committed references confirmed')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='audit_error_function_changes 1')
    p.add_argument('--changes',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    main(p.parse_args())
