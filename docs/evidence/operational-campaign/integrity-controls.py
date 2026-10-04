import json,subprocess,tempfile,os,sys
from pathlib import Path
sys.path.insert(0,str(Path('scripts').resolve()))
import operational_campaign as op
root=op.ROOT
binary=Path('_build_release/default/bench/planner_load.exe').resolve()
results=[]
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);repo=p/'repo';repo.mkdir();(repo/'lib').mkdir();f=repo/'lib/model.ml';f.write_text('let x = 0\n')
 subprocess.run(['git','init','-q',str(repo)],check=True)
 subprocess.run(['git','-C',str(repo),'add','lib'],check=True)
 subprocess.run(['git','-C',str(repo),'-c','user.name=Probe','-c','user.email=probe@example.invalid','-c','commit.gpgsign=false','commit','-qm','fixture'],check=True)
 op.ROOT=repo
 for name in ('bench/planner_load.ml','bench/assurance_clock.c','scripts/operational_campaign.py'):
  dest=repo/name;dest.parent.mkdir(exist_ok=True,parents=True);dest.write_bytes((root/name).read_bytes())
 config=json.loads((root/'bench/operational-local.json').read_text());config.update(repetitions=1,requests=1,warmups=0)
 c=config['cases'][0];c.update(positions=4,days=[0],workers=1,tile_rows=4,buffer_slots=4);config['cases']=[c]
 spec=p/'spec.json';spec.write_text(json.dumps(config))
 for kind in ('staged','unstaged','untracked'):
  subprocess.run(['git','-C',str(repo),'restore','--staged','--worktree','lib/model.ml'],check=True)
  if kind=='untracked': (repo/'lib/extra.ml').write_text('let y = 1\n')
  else:
   f.write_text('let x = 1\n')
   if kind=='staged':subprocess.run(['git','-C',str(repo),'add','lib'],check=True)
  try:op.collect(spec,binary,p/kind)
  except ValueError as e:assert 'library differs' in str(e)
  else:raise AssertionError(kind)
  r=json.loads((p/kind/'report.json').read_text());assert not r['complete'] and not r['cases']
  results.append({'control':kind+' library change','rejected_before_pricing':True})
 op.ROOT=root
 config['cases'][0]['requirements']['warm_p95_ms']=0
 spec.write_text(json.dumps(config))
 child=subprocess.run([sys.executable,'scripts/operational_campaign.py','--config',str(spec),'--binary',str(binary),'--output',str(p/'failed-criterion')],capture_output=True,text=True)
 assert child.returncode==1,child.stderr
 r=json.loads((p/'failed-criterion/report.json').read_text());assert r['complete'] and not r['deployment_accepted'] and r['cases'][c['name']]['summary']['criteria']['warm_p95_ms']['status']=='fail'
 results.append({'control':'impossible latency criterion','exit_code':1,'measurement_complete':True,'deployment_accepted':False})
print(json.dumps(results,indent=2))
