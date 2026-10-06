import subprocess,json,hashlib
from pathlib import Path
root=Path('/tmp/morphiq-american-iv-opt');out=Path(__file__).resolve().parent
records=[]
for name,width,expansions in [('initial','.05','2'),('refined','.05','3'),('tight','.005','3')]:
 command=[str(out/'baseline/check'),str(root/'docs/evidence/american-iv/references.tsv'),'all',width,expansions]
 with (out/('baseline-'+name+'.log')).open('w') as f:
  p=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT,timeout=600)
 records.append(dict(name=name,command=command,exit=p.returncode))
 (out/'baseline-checks.json').write_text(json.dumps(records,indent=2)+'\n')
 assert p.returncode==0
 print(name, (out/('baseline-'+name+'.log')).read_text().splitlines()[-1],flush=True)
