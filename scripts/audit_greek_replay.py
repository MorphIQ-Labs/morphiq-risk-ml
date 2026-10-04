#!/usr/bin/env python3
"""Independently audit every changed #80 public replay word from original inputs."""
import argparse
import gzip
import hashlib
import itertools
import json
from pathlib import Path
import subprocess
from numerical_cases import bits,word
from numerical_campaign import SOURCE_NAMES,score

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='greek-replay-audit 1')
    for name in ('before','after','harness','output'):p.add_argument('--'+name,type=Path,required=True)
    args=p.parse_args()
    from numerical_reference import reference
    before=args.before.read_text().splitlines();after=args.after.read_text().splitlines()
    if len(before)!=362880 or len(after)!=len(before):raise ValueError('unexpected replay length')
    factors=subprocess.run([str(args.harness.resolve()),'--replay-factors'],capture_output=True,text=True,check=True,timeout=10).stdout.splitlines()
    if len(factors)!=7:raise ValueError('factor count')
    grid=list(itertools.product([1e-150,0.0123,0.9,1.,1.05,37.5,1e5,1e150],map(word,factors),
        [0.,1e-6,1./365.,0.25,2.,30.],[(-0.01,0.02),(0.03,0.01),(0.05,0.05)],
        ['call','put'],[0.,1e-6,0.05,0.3,2.],['bsm','displaced','bachelier']))
    rows=[]
    for index,(old,new) in enumerate(zip(before,after)):
        if old==new:continue
        s,factor,t,(r,q),side,sigma,model=grid[index//12]
        if index%12!=4 or sigma!=0. or model=='bachelier':raise ValueError('unexpected changed quantity')
        k=s*factor;shift=0.
        if model=='displaced':s-=0.01;shift=0.03
        row=dict(id=f'replay{index}',region='zero_variance_theta',model=model,side=side,mode='fast',quantity='theta',
            inputs={key:bits(value) for key,value in dict(s=s,k=k,t=t,r=r,q=q,sigma=sigma,shift=shift,quote=0.,limit=0.).items()})
        row['reference']=reference(row)
        row['before']=old;row['after']=new
        for label,value in [('before',old),('after',new)]:
            outcome,detail=score(row,dict(status='value',value=value,radius='-'),{'black theta':8.})
            row[label+'_outcome']=outcome;row[label+'_detail']=detail
            if label=='after' and outcome!='value_checked':raise ValueError('unresolved/incorrect changed output: '+str(row))
        rows.append(row)
    names=SOURCE_NAMES+['scripts/audit_greek_replay.py','scripts/numerical_campaign.py','bench/greek_cancellation.ml','test/determinism.ml']
    report=dict(rows=rows,changed=len(rows),before_sha256=hashlib.sha256(args.before.read_bytes()).hexdigest(),
        after_sha256=hashlib.sha256(args.after.read_bytes()).hexdigest(),factors=factors,
        source_sha256={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in names})
    args.output.write_bytes(gzip.compress((json.dumps(report,indent=2)+'\n').encode(),mtime=0))
    print(json.dumps(dict(changed=len(rows),before_worst=max(r['before_detail'].get('ulps',0) for r in rows),
        after_worst=max(r['after_detail']['ulps'] for r in rows))))

if __name__=='__main__':main()
