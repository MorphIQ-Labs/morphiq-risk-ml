#!/usr/bin/env python3
"""Audit BSM/displaced/Bachelier replay words in test/determinism.ml order.

The 30,240 records are fixed by that test; admitted records contain price, IV,
and ten Greeks. Changed IVs here use each implementation's served price, so
these are not fixed-quote comparisons. This script assesses compatibility, not
reference accuracy. Generate dumps using the optional second test argument.
"""
from pathlib import Path
import gzip,hashlib,json,math,struct
import argparse
p=argparse.ArgumentParser(description='Compare the fixed public determinism corpus, retaining changed words.')
p.add_argument('--version',action='version',version='compare_error_function_replay 1')
p.add_argument('before',type=Path);p.add_argument('after',type=Path);p.add_argument('output_prefix')
args=p.parse_args()
paths=dict(baseline=args.before,final=args.after)

def floating(w):return struct.unpack('>d',bytes.fromhex(w))[0]
def ordered(w):
 n=int(w,16);return -(n&((1<<63)-1)) if n>>63 else n
def kind(w):
 if len(w)!=16:return w
 v=floating(w)
 return 'nan' if math.isnan(v) else 'infinite' if math.isinf(v) else 'zero' if v==0 else 'finite'
data=[paths[label].read_text().splitlines() for label in ['baseline','final']]
assert len(data[0])==len(data[1])
fields=['price','iv','delta','gamma','theta','vega','rho','vanna','volga','charm','veta','color']
models=['bsm','displaced','bachelier'];changes=[];stats={};index=0
for record in range(8*7*6*3*2*5*3):
 old,new=data[0][index],data[1][index]
 if old=='refused':
  assert new==old;index+=1;continue
 model=models[record%3]
 for field in fields:
  old,new=data[0][index],data[1][index];index+=1
  st=stats.setdefault(model+' '+field,dict(rows=0,changed=0,class_changes=0,sign_changes=0,max_ulp_movement=0))
  st['rows']+=1
  if old!=new:
   row=dict(record=record,model=model,field=field,before=old,after=new)
   changes.append(row);st['changed']+=1
   st['class_changes']+=kind(old)!=kind(new)
   if len(old)==len(new)==16:st['sign_changes']+=(int(old,16)>>63)!=(int(new,16)>>63)
   if kind(old)==kind(new)=='finite':
    st['max_ulp_movement']=max(st['max_ulp_movement'],abs(ordered(old)-ordered(new)))
assert index==len(data[0])
report=dict(fields=stats,records=30240,changed=len(changes),bytes=[paths[label].stat().st_size for label in ['baseline','final']],sha256={label:hashlib.sha256(paths[label].read_bytes()).hexdigest() for label in ['baseline','final']})
Path(args.output_prefix+'.json').write_text(json.dumps(report,indent=2)+'\n')
Path(args.output_prefix+'-changes.json.gz').write_bytes(gzip.compress((json.dumps(changes)+'\n').encode(),mtime=0))
print(json.dumps(report,indent=2))
