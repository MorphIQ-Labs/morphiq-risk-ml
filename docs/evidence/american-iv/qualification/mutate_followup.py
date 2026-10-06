import subprocess,time,json
from pathlib import Path
root=Path('/tmp/morphiq-american-iv');out=Path(__file__).resolve().parent
cmd=['opam','exec','--switch=morphiq-risk-ml','--',str(root/'_build/default/scripts/mutation/mutation.exe'),'american-iv-exercise','american-iv-cancel']
start=time.monotonic()
with (out/'mutation-followup.log').open('w') as log:p=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=7200)
(out/'mutation-followup.json').write_text(json.dumps(dict(source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),command=cmd,exit=p.returncode,seconds=time.monotonic()-start))+'\n')
raise SystemExit(p.returncode)
