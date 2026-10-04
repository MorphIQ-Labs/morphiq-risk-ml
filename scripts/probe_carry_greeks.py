#!/usr/bin/env python3
"""Optional independent witness for the Greek sibling of carry cancellation."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from numerical_cases import bits,word,wire
from numerical_campaign import SOURCE_NAMES,parse_results,ulps

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='carry-greek-probe 1')
    p.add_argument('--runner',type=Path,required=True)
    p.add_argument('--runner-source',required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    from numerical_reference import reference
    inputs=dict(s='3ff0000000000001',k=bits(1.),t=bits(1.),r='bcafffffffffffff',
                q=bits(0.),sigma=bits(float.fromhex('0x1p-160')),shift=bits(0.),quote=bits(0.),limit=bits(0.))
    rows=[]
    for q in ('delta','gamma','theta','vega','rho','vanna','volga','charm','veta','color'):
        row=dict(id='g_'+q,region='carry_cancellation',model='bsm',side='call',
                 quantity=q,mode='fast',inputs=inputs)
        row['reference']=reference(row);rows.append(row)
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory)/'requests.txt';path.write_text('\n'.join(map(wire,rows))+'\n')
        process=subprocess.run([str(args.runner.resolve()),str(path)],capture_output=True,text=True,check=True,timeout=60)
    results=parse_results(process.stdout,rows)
    for row in rows:
        actual=results[row['id']];row['actual']=actual
        row['ulps']=ulps(word(actual['value']),word(row['reference']['rounded'])) if actual['status']=='value' and 'rounded' in row['reference'] else None
    names=SOURCE_NAMES+['scripts/probe_carry_greeks.py']
    report=dict(schema=1,runner_source=args.runner_source,
                runner_sha256=hashlib.sha256(args.runner.read_bytes()).hexdigest(),
                source_sha256={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names},rows=rows)
    args.output.write_bytes(gzip.compress((json.dumps(report,indent=2)+'\n').encode(),mtime=0))
    print(json.dumps({r['quantity']:r['ulps'] for r in rows}))

if __name__=='__main__':main()
