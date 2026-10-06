import subprocess,time,json
from pathlib import Path
root=Path('/tmp/morphiq-american-iv-opt');out=Path(__file__).resolve().parent
names=['american-iv-'+x for x in ['progress','spacing','quote','uncertainty','width','budget','cash-put','volatility','exercise','opening-floor','global-cap','cancel']]
cmd=['opam','exec','--switch=morphiq-risk-ml','--',str(root/'_build/default/scripts/mutation/mutation.exe'),*names]
start=time.monotonic()
with (out/'mutations.log').open('w') as log:p=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=7200)
(out/'mutations.json').write_text(json.dumps(dict(command=cmd,exit=p.returncode,seconds=time.monotonic()-start))+'\n')
raise SystemExit(p.returncode)
