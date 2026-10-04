#!/usr/bin/env python3
"""Original-word #77 rho midpoint neighbors; optional Arb reference generation, version 1."""
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
    rows=[]
    def add(model,side,s,k,t,r,q,sigma,shift,region):
        rows.append(dict(id=f'r{len(rows):05d}',region=region,model=model,side=side,quantity='rho',mode='fast',
            inputs={name:bits(value) for name,value in dict(s=s,k=k,t=t,r=r,q=q,sigma=sigma,shift=shift,quote=0.,limit=0.).items()}))
    times=[word(f'{i:016x}') for i in (1,2,3,5,7,15,1001,2**52-1,2**52,2**52+1)]
    strikes=[0.5,math.nextafter(1.,0.),1.,math.nextafter(1.,math.inf),1.5,3.,5.]
    for t in times:
        for scale in (-400,0,400):
            for k in strikes:
                k=math.ldexp(k,scale)
                for ratio in (0.5,1.,2.):
                    for sigma in (0.,math.ldexp(1.,-200),0.25):
                        for rate in (-0.125,0.,0.125):
                            for side in ('call','put'):
                                add('bsm',side,k*ratio,k,t,rate,rate,sigma,0.,'rho_product')
    for model in ('black76','displaced'):
        for t in (times[0],times[2],times[-2]):
            for k in (0.5,1.,1.5,3.):
                for ratio in (0.5,1.,2.):
                    for sigma in (0.,0.25):
                        for side in ('call','put'):
                            add(model,side,k*ratio,k,t,0.,0.,sigma,0.25 if model=='displaced' else 0.,'tied_product_control')
    # Two normal-range cases keep the unaffected path explicit.
    for side in ('call','put'):
        add('bsm',side,100.,95.,1.,0.02,0.,0.2,0.,'ordinary_control')
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='rho-midpoint-reference 1')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    from numerical_reference import reference
    from numerical_campaign import SOURCE_NAMES
    from flint import __FLINT_VERSION__
    rows=cases()
    import subprocess,sys,tempfile
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory)/'requests.json'
        for start in range(0,len(rows),64):
            group=rows[start:start+64];path.write_text(json.dumps(group))
            process=subprocess.run([sys.executable,str(ROOT/'scripts/numerical_campaign.py'),'worker',str(path)],capture_output=True,text=True,check=True,timeout=60)
            resolved=json.loads(process.stdout)
            if [r['id'] for r in resolved]!=[r['id'] for r in group]: raise ValueError('reference membership')
            if any(r['reference']['status'] not in ('interval','class','root','unresolved') for r in resolved): raise ValueError('reference error')
            rows[start:start+len(group)]=resolved
            print(f'{start+len(group)}/{len(rows)}',flush=True)
    names=SOURCE_NAMES+['scripts/rho_midpoint_reference.py','scripts/numerical_campaign.py']
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
