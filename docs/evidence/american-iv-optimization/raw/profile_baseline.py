import subprocess,json,time,hashlib
from pathlib import Path
root=Path('/tmp/morphiq-american-iv-opt');out=Path(__file__).resolve().parent
cmd=[str(out/'profile'),str(root/'docs/evidence/american-iv/references.tsv')]
records=dict(source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),binary=hashlib.sha256((out/'profile').read_bytes()).hexdigest(),driver=hashlib.sha256((out/'profile.ml').read_bytes()).hexdigest(),runs=[])
for case in ['american-put','cash-terminal-american']:
 with (out/(case+'-allocation.log')).open('w') as log:
  result=subprocess.run(cmd+[case,'allocation'],stdout=log,stderr=subprocess.STDOUT,timeout=180)
 assert result.returncode==0
 with (out/(case+'-cpu-driver.log')).open('w') as log:
  child=subprocess.Popen(cmd+[case,'cpu'],stdout=log,stderr=subprocess.STDOUT)
  for _ in range(60):
   if 'READY' in (out/(case+'-cpu-driver.log')).read_text():break
   assert child.poll() is None
   time.sleep(.25)
  else:raise RuntimeError('CPU driver failed startup')
  sample=subprocess.run(['sample',str(child.pid),'5','10','-file',str(out/(case+'-cpu.txt'))],capture_output=True,text=True,timeout=30)
  (out/(case+'-sample.log')).write_text(sample.stdout+sample.stderr)
  code=child.wait(timeout=120)
  assert code==0 and sample.returncode==0
 records['runs'].append(dict(case=case,allocation_exit=result.returncode,cpu_exit=code,sample_exit=sample.returncode))
 (out/'profiles.json').write_text(json.dumps(records,indent=2)+'\n')
 print(case,'profiled',flush=True)
