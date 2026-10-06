import csv,json
from fractions import Fraction as Q
from pathlib import Path
out=Path(__file__).resolve().parent
root=Path('/tmp/morphiq-american-iv-opt')
refs={c[0]:(Q(c[11]),Q(c[12]),c[13]) for line in (root/'docs/evidence/american-iv/references.tsv').read_text().splitlines() if (c:=line.split())}
def load(path):
 rows={};roots={}
 for line in path.read_text().splitlines():
  c=line.split()
  if c and c[0]=='ROW':rows[c[1]]=(c[2],c[3])
  elif c and c[0]=='ROOT':roots[c[1]]=c[2:]
 assert set(rows)==set(refs)
 return rows,roots
summary=[];records=[]
for config,width in [('initial',.05),('refined',.05),('tight',.005)]:
 old,oldroots=load(out/f'baseline-{config}.log');new,newroots=load(out/f'candidate-{config}.log')
 counts=dict(configuration=config,cases=30,accepted=0,refused=0,changed_accepted_payloads=0,changed_failure_payloads=0)
 for name,(status,payload) in old.items():
  assert new[name][0]==status,(config,name,status,new[name][0])
  row=dict(configuration=config,case=name,status=status,reference=refs[name][2])
  if status=='interval':
   counts['accepted']+=1;counts['changed_accepted_payloads']+=new[name][1]!=payload
   for mode,roots in [('baseline',oldroots),('candidate',newroots)]:
    lo,hi,n=roots[name];l,h=Q(float.fromhex(lo)),Q(float.fromhex(hi));rl,rh,_=refs[name]
    assert l<=rl<=rh<=h and h-l<=Q(width)
    row.update({mode+'_lower':lo,mode+'_upper':hi,mode+'_calls':n,mode+'_lower_reference_gap':str(rl-l),mode+'_upper_reference_gap':str(h-rh)})
  else:
   counts['refused']+=1;counts['changed_failure_payloads']+=new[name][1]!=payload
  records.append(row)
 summary.append(counts)
with (out/'compatibility.csv').open('w') as f:
 fields=list(dict.fromkeys(key for r in records for key in r));w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(records)
(out/'compatibility.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
