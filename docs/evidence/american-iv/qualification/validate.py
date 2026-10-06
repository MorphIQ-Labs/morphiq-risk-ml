import json,subprocess,time
from pathlib import Path
root=Path('/tmp/morphiq-american-iv');out=Path(__file__).resolve().parent
source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
commands=[('development',['dune','test']),('release-build',['dune','build','--profile','release','@install','@fmt','bench/american_iv.exe','test/american_iv.exe','test/american_iv.bc']),('release',['dune','test','--profile','release'])]
for name,args in commands:
 start=time.monotonic()
 with (out/(name+'.log')).open('w') as log:
  p=subprocess.run(['opam','exec','--switch=morphiq-risk-ml','--',*args],cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=3600)
 (out/(name+'.json')).write_text(json.dumps(dict(source=source,command=args,exit=p.returncode,seconds=time.monotonic()-start))+'\n')
 print(name,p.returncode,flush=True)
 if p.returncode:raise SystemExit(p.returncode)
