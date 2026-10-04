#!/usr/bin/env python3
"""Original-word #76 neighbors; optional Arb reference generation, version 1."""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import platform
import importlib.metadata
from numerical_cases import bits, word

ROOT = Path(__file__).resolve().parents[1]

def cases():
    rows = []
    def add(model, s, k, t, r, q, sigma, shift, side, region):
        rows.append(dict(id=f'c{len(rows):05d}', region=region, model=model,
                         side=side, quantity='price', mode='fast',
                         inputs={name:bits(value) for name,value in zip(
                             ('s','k','t','r','q','sigma','shift','quote','limit'),
                             (s,k,t,r,q,sigma,shift,0.,0.))}))
    rate = word('bcafffffffffffff')
    for scale in (-900, -400, 0, 400, 900):
        for maturity in (0.0625, 1., 16.):
            for spot in (1., word('3ff0000000000001'), word('3ff0000000000002')):
                for r in (math.nextafter(rate,-math.inf), rate, math.nextafter(rate,math.inf)):
                    for swap in (False, True):
                        s,k=(1.,spot) if swap else (spot,1.)
                        rr= -r if swap else r
                        for sigma in (0., word('0000000000000001'), math.ldexp(1.,-200), math.ldexp(1.,-160), 0.2):
                            for side in ('call','put'):
                                add('bsm',math.ldexp(s,scale),math.ldexp(k,scale),maturity,
                                    rr/maturity,0.,sigma,0.,side,'carry_scale_time')
    for q in (-0.125, 0.125):
        for r in (q+math.nextafter(rate,-math.inf), q+rate, q+math.nextafter(rate,math.inf)):
            for side in ('call','put'):
                for sigma in (0.,0.2):
                    add('bsm',word('3ff0000000000001'),1.,1.,r,q,sigma,0.,side,'common_discount')
    for model in ('black76','displaced'):
        for scale in (-900,0,900):
            for side in ('call','put'):
                for sigma in (0.,0.2):
                    shift=math.ldexp(0.5,scale) if model=='displaced' else 0.
                    add(model,math.ldexp(word('3ff0000000000001'),scale)-shift,
                        math.ldexp(1.,scale)-shift,1.,rate,rate,sigma,shift,side,'tied_shift_control')
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='carry-cancellation-reference 1')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    from numerical_reference import reference
    from numerical_campaign import SOURCE_NAMES
    from flint import __FLINT_VERSION__
    rows=cases()
    for row in rows:
        row['reference']=reference(row)
        if row['reference']['status'] not in ('interval','class','root','unresolved'):
            raise ValueError('reference error')
    names=SOURCE_NAMES+['scripts/carry_cancellation_reference.py']
    result=dict(schema=1,rows=rows,source_sha256={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names},
                tools=dict(python=platform.python_version(),flint=__FLINT_VERSION__,
                  python_flint=importlib.metadata.version('python-flint'),mpmath=importlib.metadata.version('mpmath')),
                precision_bits=[256,512,1024,2048,4096])
    data=gzip.compress((json.dumps(result,separators=(',',':'))+'\n').encode(),mtime=0)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(data)
    Path(str(args.output)+'.manifest.json').write_text(json.dumps(dict(rows=len(rows),sha256=hashlib.sha256(data).hexdigest()),indent=2)+'\n')
    print(f'{len(rows)} original-word references')

if __name__=='__main__': main()
