#!/usr/bin/env python3
from pathlib import Path
import subprocess,datetime,os,hashlib,json,statistics,argparse,platform
parser=argparse.ArgumentParser(description="Manual ABBA standalone Greek phase comparison")
parser.add_argument('--version', action='version', version='greek-phases-abba-v1')
parser.add_argument('--baseline-source',type=Path,required=True)
parser.add_argument('--candidate-source',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
roots={'baseline':args.baseline_source.resolve(),'candidate':args.candidate_source.resolve()}
r={'platform':platform.platform(),'toolchain':subprocess.check_output(['ocamlopt','-config'],text=True),'flags':'Dune release; library -O3; benchmark standard release flags','sources':{},'runs':[],'scope':'standalone scalar M.greek costs; no shared evaluator retained between quantities; allocation/time diagnostics, not multi-output timing'}
for name,root in roots.items():
 binary=root/'_build/default/bench/greek_preparation.exe'
 r['sources'][name]={'revision':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),'library_files':{name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ['lib/model_enclosure.ml','lib/production.ml']},'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'harness_sha256':hashlib.sha256((root/'bench/greek_preparation.ml').read_bytes()).hexdigest()}
assert r['sources']['baseline']['harness_sha256']==r['sources']['candidate']['harness_sha256']
for n in range(2):
 for name in ['baseline','candidate','candidate','baseline']:
  load=os.getloadavg();started=datetime.datetime.now(datetime.timezone.utc).isoformat()
  raw=subprocess.check_output([str(roots[name]/'_build/default/bench/greek_preparation.exe')],text=True)
  rows=[]
  for line in raw.splitlines():
   key,i,ns,allocated=line.split();rows.append({'phase':key,'sample':int(i),'ns':float(ns),'bytes':float(allocated)})
  assert len(rows)==55 and len({(x['phase'],x['sample']) for x in rows})==55
  r['runs'].append({'variant':name,'round':n,'load_before':load,'load_after':os.getloadavg(),'started':started,'raw':raw,'rows':rows})
r['summary']=[]
for key in sorted({x['phase'] for x in r['runs'][0]['rows']}):
 row={'phase':key}
 for name in roots:
  data=[x for run in r['runs'] if run['variant']==name for x in run['rows'] if x['phase']==key]
  row[name]={metric:{'median':statistics.median(x[metric] for x in data),'min':min(x[metric] for x in data),'max':max(x[metric] for x in data)} for metric in ['ns','bytes']}
 r['summary'].append(row)
r['complete']=True
args.output.write_text(json.dumps(r,indent=2)+'\n')
