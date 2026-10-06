import hashlib,json,math,os,platform,statistics,subprocess,time
from pathlib import Path
from timing_controls import execute
root=Path('/tmp/morphiq-american-iv');out=Path(__file__).resolve().parent
source='c3f5f5e5a3b7801466fa8ddfefe1fc843ca04a9b';exe=root/'_build/default/bench/american_iv.exe'
def cmd(args):return subprocess.check_output(args,cwd=root,text=True).strip()
assert not cmd(['git','status','--porcelain'])
head=cmd(['git','rev-parse','HEAD']);assert head.startswith(source)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=dict(source=head,tree=cmd(['git','rev-parse','HEAD^{tree}']),binary_sha256=sha(exe),platform=platform.platform(),hardware=cmd(['sysctl','-n','machdep.cpu.brand_string']),compiler=cmd(['opam','exec','--switch=morphiq-risk-ml','--','ocamlopt','-config']),collector_sha256=sha(Path(__file__)),controls_sha256=sha(out/'timing_controls.py'),profile='release, library -O3, bench -O3',warmup_per_sample=1,rounds_per_process=3,processes=[])
expected={f'{a}/{b}' for a in ['call-100-0.05-american','american-put','cash-terminal-american'] for b in ['price','solve','end-to-end']}
checks=None
for i in range(5):
 record=dict(index=i,load_before=os.getloadavg(),start_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()));report['processes'].append(record)
 (out/'timing.json').write_text(json.dumps(report,indent=2)+'\n')
 try:
  actual_checks,samples=execute([str(exe),str(root/'docs/evidence/american-iv/references.tsv')],out/f'timing-{i}.log',out/f'timing-{i}.stderr',1800)
 except BaseException as error:
  record['failure']=str(error)
  (out/'timing.json').write_text(json.dumps(report,indent=2)+'\n')
  raise
 record.update(exit=0,load_after=os.getloadavg())
 if checks is None:checks=actual_checks
 assert checks==actual_checks
 record['samples']=samples
 assert not cmd(['git','status','--porcelain']) and cmd(['git','rev-parse','HEAD'])==head and sha(exe)==report['binary_sha256']
 (out/'timing.json').write_text(json.dumps(report,indent=2)+'\n')
report['checks']=checks
report['summary']={name:{field:dict(median=statistics.median(s[field] for p in report['processes'] for s in p['samples'] if s['name']==name),minimum=min(s[field] for p in report['processes'] for s in p['samples'] if s['name']==name),maximum=max(s[field] for p in report['processes'] for s in p['samples'] if s['name']==name)) for field in ['wall_ns','allocated_bytes']} for name in sorted(expected)}
(out/'timing.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['summary'],indent=2))
