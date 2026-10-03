#!/usr/bin/env python3
"""Optional independent Arb validation of original-input planner outputs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from shadow_campaign import validate


def audit(text):
    seen=set()
    for line in text.splitlines():
        scenario,instrument,model,side,name,*words=line.split()
        key=int(scenario),int(instrument),name
        if key in seen or len(words)!=9:
            raise ValueError('duplicate or malformed result')
        seen.add(key)
        row=dict(model=model,side=side,inputs=words[:7],limit='3ddb7cdfd9d7bdbb')  # exact 1e-10
        result=validate(row,name,['ok',*words[7:]])
        if result['status']!='certified':
            raise ArithmeticError((key,result))
    names=['price','delta','gamma','rho','theta','vega','vanna','volga','charm','veta','color']
    expected={(s,i,q) for s in range(27) for i in range(8) for q in names}
    if seen!=expected:
        raise ValueError('incomplete or extra reference outcomes')
    return len(seen)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='planner-arb-audit-v1')
    p.add_argument('--binary',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    binary=args.binary.resolve()
    runs=[subprocess.check_output([str(binary),'--workers',str(w)],text=True) for w in (1,2,3,4)]
    if any(text!=runs[0] for text in runs):
        raise ArithmeticError('worker replay mismatch')
    count=audit(runs[0])
    bad=runs[0].splitlines()
    fields=bad[0].split(); fields[-2]='7fefffffffffffff';bad[0]=' '.join(fields)
    try: audit('\n'.join(bad))
    except ArithmeticError: pass
    else: raise AssertionError('corrupt certificate was accepted')
    try: audit('\n'.join(runs[0].splitlines()[:-1]))
    except ValueError: pass
    else: raise AssertionError('truncated campaign was accepted')
    import flint, importlib.metadata
    report=dict(method='Original-input Arb price and order-three formal series derivatives; fixed 1e-10 typed scalar limits',
        certificates=count,scenarios=27,instruments=8,workers=[1,2,3,4],identical=True,
        corrupt_certificate_rejected=True,truncated_output_rejected=True,
        binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
        output_sha256=hashlib.sha256(runs[0].encode()).hexdigest(),
        python_flint=importlib.metadata.version('python-flint'),flint=flint.__FLINT_VERSION__)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))


if __name__=='__main__': main()
