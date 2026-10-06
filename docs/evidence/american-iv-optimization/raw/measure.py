import hashlib,json,math,os,platform,statistics,subprocess,time
from fractions import Fraction
from pathlib import Path
from timing_controls import execute,EXPECTED,verify,acceptance
out=Path(__file__).resolve().parent
roots={'baseline':Path('/tmp/morphiq-american-iv-opt-baseline'),'candidate':Path('/tmp/morphiq-american-iv-opt')}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def cmd(args,root):return subprocess.check_output(args,cwd=root,text=True).strip()
def identity(root):
 assert not cmd(['git','status','--porcelain'],root),'dirty source'
 return dict(source=cmd(['git','rev-parse','HEAD'],root),tree=cmd(['git','rev-parse','HEAD^{tree}'],root),binary_sha256=sha(root/'_build/default/bench/american_iv.exe'),driver_sha256=sha(root/'bench/american_iv.ml'))
identities={k:identity(r) for k,r in roots.items()}
assert identities['baseline']['driver_sha256']==identities['candidate']['driver_sha256']
report=dict(identities=identities,platform=platform.platform(),hardware=cmd(['sysctl','-n','machdep.cpu.brand_string'],roots['candidate']),compiler=cmd(['opam','exec','--switch=morphiq-risk-ml','--','ocamlopt','-config'],roots['candidate']),collector_sha256=sha(Path(__file__)),controls_sha256=sha(out/'timing_controls.py'),profile='release; library and benchmark -O3',warmup_per_path=1,rounds_per_process=3,environment={'OCAMLRUNPARAM':'v=0x400'},rss_unit='bytes on Darwin',processes=[])
references={c[0]:(Fraction(c[11]),Fraction(c[12])) for line in (roots['candidate']/'docs/evidence/american-iv/references.tsv').read_text().splitlines() if (c:=line.split())}
def save(): (out/'timing.json').write_text(json.dumps(report,indent=2)+'\n')
checks={}
for pair in range(5):
 for mode in (['baseline','candidate'] if pair%2==0 else ['candidate','baseline']):
  root=roots[mode];assert identity(root)==identities[mode]
  record=dict(pair=pair,mode=mode,load_before=os.getloadavg(),start_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()));report['processes'].append(record);save()
  try:
   actual,samples,usage=execute([str(root/'_build/default/bench/american_iv.exe'),str(root/'docs/evidence/american-iv/references.tsv')],out/f'timing-{pair}-{mode}.log',out/f'timing-{pair}-{mode}.stderr',600)
   verify(actual,references)
   if mode in checks:assert checks[mode]==actual,'changed outcome identity'
   checks[mode]=actual
   gc={key:int(value) for line in (out/f'timing-{pair}-{mode}.stderr').read_text().splitlines() for key,value in [line.split(': ')]}
   assert all(k in gc for k in ['allocated_words','minor_collections','major_collections','top_heap_words'])
   record.update(exit=0,load_after=os.getloadavg(),samples=samples,resources=usage,gc=gc)
   assert identity(root)==identities[mode]
  except BaseException as error:
   record['failure']=str(error);save();raise
  save();print(pair,mode,'complete',flush=True)
report['checks']=checks
report['summary']={mode:{name:{field:dict(median=statistics.median(s[field] for p in report['processes'] if p['mode']==mode for s in p['samples'] if s['name']==name),minimum=min(s[field] for p in report['processes'] if p['mode']==mode for s in p['samples'] if s['name']==name),maximum=max(s[field] for p in report['processes'] if p['mode']==mode for s in p['samples'] if s['name']==name)) for field in ['wall_ns','cpu_ns','allocated_bytes']} for name in sorted(EXPECTED)} for mode in roots}
criteria=[]
for name in sorted(EXPECTED):
 for field in ['wall_ns','allocated_bytes']:
  ratio=report['summary']['candidate'][name][field]['median']/report['summary']['baseline'][name][field]['median']
  pde_inverse=not name.startswith('call-100') and not name.endswith('/price')
  maximum=.75 if pde_inverse else (1.1 if field=='wall_ns' else 1.05)
  criteria.append(dict(path=name,metric=field,ratio=ratio,maximum=maximum,passed=ratio<=maximum))
report['criteria']=criteria;save()
for c in criteria:acceptance(c['ratio'],c['maximum'])
print('All frozen adoption criteria passed',flush=True)
