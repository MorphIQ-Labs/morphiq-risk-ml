import subprocess,time,json,shutil
from pathlib import Path
out=Path(__file__).resolve().parent;root=Path('/tmp/morphiq-american-iv')
started=time.monotonic()
def wait_record(name,success=True):
 while not (out/name).exists():
  if time.monotonic()-started>14400:raise RuntimeError('validation wait limit')
  time.sleep(5)
 record=json.loads((out/name).read_text())
 if success:assert record['exit']==0,(name,record)
 return record
for name in ['development.json','release-build.json','release.json']:wait_record(name)
print('Ordinary suites passed; validating final extra control',flush=True)
commands=[['dune','build','@test/runtest-american_iv','@test/types/runtest'],['dune','build','--profile','release','@fmt','@install','@test/runtest-american_iv','bench/american_iv.exe']]
records=[]
with (out/'final-focused.log').open('w') as log:
 for command in commands:
  start=time.monotonic();p=subprocess.run(['opam','exec','--switch=morphiq-risk-ml','--',*command],cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=1800)
  records.append(dict(command=command,exit=p.returncode,seconds=time.monotonic()-start))
  (out/'final-focused.json').write_text(json.dumps(dict(source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),commands=records),indent=2)+'\n')
  assert p.returncode==0,'final focused checks'
print('Installing external consumers',flush=True)
with (out/'installed-summary.log').open('w') as log:
 p=subprocess.run(['python3',str(out/'qualify_installed.py')],stdout=log,stderr=subprocess.STDOUT,timeout=7200)
assert p.returncode==0,'installed consumer failure'
initial=wait_record('mutations.json',False);followup=wait_record('mutation-followup.json')
text=(out/'mutations.log').read_text();second=(out/'mutation-followup.log').read_text()
assert 'killed    american-iv-exercise by american_iv' in second
assert 'killed    american-iv-cancel by american_iv' in second
names=['american-iv-'+x for x in ['quote','uncertainty','width','budget','cash-put','volatility','opening-floor','global-cap']]+['american-certified-accuracy']
assert all('killed    '+n+' by ' in text for n in names),text
assert initial['exit'] in [0,1]
for suffix in ['json','log']:shutil.copyfile(out/('mutations.'+suffix),out/('mutation-initial.'+suffix))
(out/'mutations.json').write_text(json.dumps(dict(exit=0,qualified=names+['american-iv-exercise','american-iv-cancel'],initial=initial,followup=followup),indent=2)+'\n')
(out/'mutations.log').write_text('Initial controls:\n'+text+'\nFinite-rights control follow-up:\n'+second)
assert (out/'tight-bytecode.log').read_text().endswith('TOTAL 30 30 0 0\n')
print('All validation finished; starting five cost processes',flush=True)
with (out/'timing-summary.log').open('w') as log:
 p=subprocess.run(['python3',str(out/'measure.py')],stdout=log,stderr=subprocess.STDOUT,timeout=10800)
(out/'finish.json').write_text(json.dumps(dict(exit=p.returncode,seconds=time.monotonic()-started))+'\n')
raise SystemExit(p.returncode)
