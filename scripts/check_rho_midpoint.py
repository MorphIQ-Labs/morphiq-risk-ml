#!/usr/bin/env python3
"""Score every #77 request; refusals and reference uncertainty are not accuracy passes."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
from numerical_cases import wire,word
from numerical_campaign import SOURCE_NAMES,parse_results,score
from rho_midpoint_reference import cases

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='rho-midpoint-check 1')
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--runner',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--runner-source',required=True)
    p.add_argument('--record-only',action='store_true')
    args=p.parse_args()
    data=args.reference.read_bytes();manifest=json.loads(Path(str(args.reference)+'.manifest.json').read_text())
    if hashlib.sha256(data).hexdigest()!=manifest['sha256']:raise ValueError('fixture hash')
    report=json.loads(gzip.decompress(data));rows=report['rows']
    if len(rows)!=manifest['rows'] or [{k:v for k,v in r.items() if k!='reference'} for r in rows]!=cases():raise ValueError('fixture membership')
    sources=SOURCE_NAMES+['scripts/rho_midpoint_reference.py','scripts/numerical_campaign.py']
    if set(sources)!=set(report['source_sha256']):raise ValueError('incomplete reference provenance')
    for name,digest in report['source_sha256'].items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:raise ValueError('stale reference: '+name)
    if any(r['reference']['status'] not in ('interval','class','unresolved') for r in rows):raise ValueError('reference generation failed')
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory)/'requests.txt';path.write_text('\n'.join(map(wire,rows))+'\n')
        result=subprocess.run([str(args.runner.resolve()),str(path)],capture_output=True,text=True,check=True,timeout=120)
    results=parse_results(result.stdout,rows)
    budget_process=subprocess.run([str(args.runner.resolve()),'--budgets'],check=True,capture_output=True,text=True,timeout=10)
    budgets={}
    for line in budget_process.stdout.splitlines():
        family,quantity,value=line.split();budgets[family+' '+quantity]=float(value)
    if len(budgets)!=22 or not all(math.isfinite(v) and v>=0 for v in budgets.values()):raise ValueError('invalid budgets')
    outcomes=[];counts=Counter();failures=[]
    for row in rows:
        outcome,detail=score(row,results[row['id']],budgets)
        # A returned subnormal refinement claims a complete rounding cell.
        if row['model']=='bsm' and outcome=='value_checked' and abs(word(results[row['id']]['value']))<=float.fromhex('0x1p-1022') and detail.get('ulps')!=0:
            outcome='rounding_cell_difference'
        inp=row['inputs']
        required=(row['model']=='bsm' and inp['s']==inp['k']=='3ff0000000000000'
                  and inp['t']=='0000000000000001' and inp['r']==inp['q']=='0000000000000000'
                  and inp['sigma']=='3fd0000000000000')
        if required and (outcome!='value_checked' or detail.get('ulps')!=0):outcome='original_witness_failure'
        if row['region']=='ordinary_control' and outcome!='value_checked':outcome='ordinary_control_failure' 
        if outcome not in ('value_checked','class_checked','availability_failure','reference_unresolved'):failures.append(row['id'])
        outcomes.append(dict(id=row['id'],outcome=outcome,result=results[row['id']],detail=detail))
        counts[outcome]+=1
    summary=dict(counts=dict(counts),failures=len(failures))
    full=dict(summary,runner_source=args.runner_source,runner_sha256=hashlib.sha256(args.runner.read_bytes()).hexdigest(),
              reference_sha256=manifest['sha256'],scorer_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),outcomes=outcomes)
    args.output.write_text(json.dumps(full,indent=2)+'\n');print(json.dumps(summary))
    if failures and not args.record_only:raise SystemExit(1)

if __name__=='__main__':main()
