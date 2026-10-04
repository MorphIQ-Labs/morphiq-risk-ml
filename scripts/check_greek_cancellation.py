#!/usr/bin/env python3
"""Score every #80 request; refusals and reference uncertainty are not accuracy passes."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from numerical_cases import wire
from numerical_campaign import SOURCE_NAMES,parse_results,score
from greek_cancellation_reference import cases

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='greek-cancellation-check 1')
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
    sources=SOURCE_NAMES+['scripts/carry_cancellation_reference.py','scripts/greek_cancellation_reference.py','scripts/numerical_campaign.py']
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
    if len(budgets)!=22:raise ValueError('incomplete budgets')
    outcomes=[];counts=Counter();failures=[]
    for row in rows:
        outcome,detail=score(row,results[row['id']],budgets)
        if row['region']=='exact_atm' and outcome not in ('value_checked','class_checked'):outcome='atm_control_failure'
        if outcome not in ('value_checked','class_checked','availability_failure','reference_unresolved'):failures.append(row['id'])
        outcomes.append(dict(id=row['id'],outcome=outcome,result=results[row['id']],detail=detail))
        counts[outcome]+=1
    summary=dict(counts=dict(counts),failures=len(failures))
    full=dict(summary,runner_source=args.runner_source,runner_sha256=hashlib.sha256(args.runner.read_bytes()).hexdigest(),
              reference_sha256=manifest['sha256'],scorer_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),outcomes=outcomes)
    args.output.write_text(json.dumps(full,indent=2)+'\n');print(json.dumps(summary))
    if failures and not args.record_only:raise SystemExit(1)

if __name__=='__main__':main()
