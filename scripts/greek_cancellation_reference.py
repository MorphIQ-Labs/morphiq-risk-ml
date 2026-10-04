#!/usr/bin/env python3
"""Original-word #80 Greek neighbors; optional Arb reference generation, version 1."""
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

GREEKS=('delta','gamma','theta','vega','rho','vanna','volga','charm','veta','color')

def cases():
    from carry_cancellation_reference import cases as prices
    contracts=[]
    for row in prices():
        v={key:word(value) for key,value in row['inputs'].items()}
        if v['sigma'] not in (0.,math.ldexp(1.,-160),0.2): continue
        if not math.ldexp(1.,-402) <= v['k'] <= math.ldexp(1.,402): continue
        contracts.append(row)
    template=contracts[0]
    # Exact ATM controls keep mathematical kinks separate from uncertainty.
    for model in ('bsm','black76','displaced'):
        for side in ('call','put'):
            for sigma in (0.,0.2):
                for scale in (-400,0,400):
                    inputs=dict(s=math.ldexp(1.,scale),k=math.ldexp(1.,scale),t=1.,
                                r=0.125,q=0.125,sigma=sigma,shift=math.ldexp(0.5,scale),quote=0.,limit=0.)
                    contracts.append(dict(template,model=model,side=side,region='exact_atm',
                                          inputs={k:bits(v) for k,v in inputs.items()}))
    # Exact shifted sums retain low words even when rounded high words coincide.
    for side in ('call','put'):
        for scale in (-400,0,400):
            for sigma in (0.,math.ldexp(1.,-106),math.ldexp(1.,-160),0.2):
                inputs=dict(s=math.ldexp(word('3ff0000000000001'),scale),k=math.ldexp(1.,scale),
                            shift=math.ldexp(1.,scale+54),t=1.,r=.125,q=.125,sigma=sigma,quote=0.,limit=0.)
                contracts.append(dict(template,model='displaced',side=side,region='shifted_low_words',
                                      inputs={k:bits(v) for k,v in inputs.items()}))
    # Nonzero real carry whose product underflows in the DD coordinate.
    for side in ('call','put'):
        for sigma in (0.,math.ldexp(1.,-160),0.2):
            for rate in (-math.ldexp(1.,-1074),math.ldexp(1.,-1074)):
                inputs=dict(s=1.,k=1.,t=math.ldexp(1.,-1074),r=rate,q=0.,
                            sigma=sigma,shift=0.,quote=0.,limit=0.)
                contracts.append(dict(template,model='bsm',side=side,region='underflowed_carry',
                                      inputs={k:bits(v) for k,v in inputs.items()}))
    return [dict(row,id=f'g{i:05d}_{name}',quantity=name) for i,row in enumerate(contracts) for name in GREEKS]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='greek-cancellation-reference 1')
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
    names=SOURCE_NAMES+['scripts/carry_cancellation_reference.py','scripts/greek_cancellation_reference.py','scripts/numerical_campaign.py']
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
