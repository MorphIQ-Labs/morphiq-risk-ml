#!/usr/bin/env python3
"""Manual, source-guarded actual-matrix and complete-request backend campaign."""
import argparse,datetime,hashlib,json,os,platform,subprocess
from pathlib import Path
import check_american_backends as check
from measure_american_workloads import child,require_child,atomic_json,source_snapshot,sha
CASES=('call','flat','cash','bermudan','piecewise-cash','greeks','iv','certified','hard')
MODES=('native','ocaml','lapack')
ROOT=Path(__file__).resolve().parent.parent

def environment(mode,**extra):
    result=['env']
    for key in ('MORPHIQ_POLICY_BACKEND','MORPHIQ_POLICY_TRACE','MORPHIQ_CAPTURE_CELLS','MORPHIQ_POLICY_ACCOUNT'):
        result+=['-u',key]
    result+=['MORPHIQ_POLICY_BACKEND='+mode]
    return result+[k+'='+str(v) for k,v in extra.items()]

def tree_snapshot(root):
    output={}
    for directory,dirs,files in os.walk(root):
        dirs[:]=[d for d in dirs if d not in ('_build','.git','__pycache__')]
        for name in files:
            p=Path(directory)/name
            output[str(p.relative_to(root))]=sha(p)
    return output

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--experiment',type=Path,required=True,help='builder output directory')
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--phase',choices=('qualify','measure'),required=True)
    p.add_argument('--qualification',type=Path)
    p.add_argument('--version',action='version',version='american-backends-campaign 1')
    a=p.parse_args();out=a.output.resolve();exp=a.experiment.resolve();tree=exp/'source'
    if out.is_relative_to(ROOT) or out.is_relative_to(tree):p.error('output must be outside both source trees')
    out.mkdir(parents=True,exist_ok=False)
    binaries={mode:{name:(ROOT if mode=='native' else tree)/'_build/default/bench'/('backend_'+name+'.exe')
                    for name in ('requests','micro','contracts')} for mode in MODES}
    source=source_snapshot(ROOT);experimental=tree_snapshot(tree)
    hashes={str(p):sha(p) for d in binaries.values() for p in d.values()}
    manifest=dict(source_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
      source=source,experimental_source=experimental,binaries=hashes,build_manifest_sha256=sha(exp/'build-manifest.json'),
      platform=platform.platform(),hardware=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip() if platform.system()=='Darwin' else platform.machine(),
      logical_cpus=os.cpu_count(),compiler=subprocess.check_output(['opam','exec','--switch=morphiq-risk-ml','--','ocamlopt','-config'],text=True),
      started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    atomic_json(out/'manifest.json',manifest)
    evidence_hashes={}
    def guard():
        if source_snapshot(ROOT)!=source or tree_snapshot(tree)!=experimental or any(sha(Path(p))!=h for p,h in hashes.items()):
            raise RuntimeError('source or binary changed during campaign')
        if any(sha(Path(p))!=h for p,h in evidence_hashes.items()):
            raise RuntimeError('qualification evidence changed during campaign')
    def execute(name,command):
        record=child(command,out/(name+'.log'),out/(name+'.stderr'),600)
        atomic_json(out/(name+'.json'),record);require_child(record)
        return record,(out/(name+'.log')).read_text()
    if a.phase=='qualify':
        captures={};proofs={};requests={}
        # Native trace adapter preserves the underlying implementation; native
        # timings below use the untouched production owner, not this adapter.
        for case,cells in [(c,64) for c in CASES]+[('flat',256),('cash',256)]:
            name=f'capture-{case}-{cells}';path=out/(name+'.matrices')
            record,text=execute(name,environment('native',MORPHIQ_POLICY_TRACE=path,MORPHIQ_CAPTURE_CELLS=cells)+
              [str(tree/'_build/default/bench/backend_requests.exe'),'--case',case,'--capture'])
            parsed=check.requests(text,case,1,capture=True);ms=check.matrices(path)
            captures[name]=dict(path=path.name,sha256=sha(path),count=len(ms),dimensions=sorted({m['n'] for m in ms}),outcome=parsed)
            for mode in MODES:
                if not ms:continue
                job=name+'-'+mode
                _,text=execute(job,environment(mode)+[str(binaries[mode]['micro']),'--input',str(path),'--repeats','1'])
                result=check.micro(text,ms,repeats=1)
                scored=[check.exact(m,result['solutions'][i]['values']) for i,m in enumerate(ms)]
                proofs[job]=dict(matrices=scored,violations=sum(not r['passes'] for r in scored),
                  changed_words=sum(x.hex()!=row[4].hex() for i,m in enumerate(ms) for x,row in zip(result['solutions'][i]['values'],m['rows'])))
                atomic_json(out/(job+'-proof.json'),proofs[job])
            print(name,'matrices',len(ms),flush=True)
        for mode in MODES:
            _,text=execute('contracts-'+mode,environment(mode)+[str(binaries[mode]['contracts'])])
            requests['contracts-'+mode]=text
            for case in CASES:
                for size in (1,4):
                    name=f'outcomes-{mode}-{case}-{size}'
                    record,text=execute(name,environment(mode,MORPHIQ_POLICY_ACCOUNT=1)+[str(binaries[mode]['requests']),'--case',case,'--size',str(size),'--capture'])
                    requests[name]=check.requests(text,case,size,True)
                    if mode=='lapack':
                        parts=(out/(name+'.stderr')).read_text().strip().split('\t')
                        if len(parts)!=3 or parts[0]!='NATIVE_ALLOC':raise ValueError('native allocation accounting missing')
                        requests[name]['native_scratch_cumulative_bytes']=int(parts[1]);requests[name]['native_owners']=int(parts[2])
        guard();atomic_json(out/'qualification.json',dict(complete=True,captures=captures,proofs=proofs,outcomes=requests,
            all_exact_residuals_pass=all(p['violations']==0 for p in proofs.values())))
        print('qualification complete',flush=True);return
    if a.qualification is None:p.error('measure requires --qualification')
    qualification=a.qualification.resolve();q=json.loads((qualification/'qualification.json').read_text())
    if not q['complete']:raise ValueError('incomplete qualification')
    qmanifest=json.loads((qualification/'manifest.json').read_text())
    if any(qmanifest[k]!=manifest[k] for k in ('source','experimental_source','binaries','build_manifest_sha256')):
        raise ValueError('qualification/source identity differs')
    atomic_json(out/'qualification-identity.json',dict(path=str(qualification),sha256=sha(qualification/'qualification.json')))
    evidence_hashes={str(qualification/name):sha(qualification/name) for name in ('qualification.json','manifest.json')}
    for c in q['captures'].values():
        path=qualification/c['path']
        if sha(path)!=c['sha256']:raise ValueError('captured matrix identity differs')
        evidence_hashes[str(path)]=c['sha256']
    captures=[(name,qualification/c['path']) for name,c in q['captures'].items() if c['count']]
    qualified_micro={}
    for name,path in captures:
        for mode in MODES:
            log=qualification/(name+'-'+mode+'.log')
            qualified_micro[(name,mode)]=check.micro(log.read_text(),check.matrices(path),repeats=1)['solutions']
            evidence_hashes[str(log)]=sha(log)
    jobs=[('request',case,size,None) for case in CASES for size in (1,4)]+[('micro',name,0,path) for name,path in captures]
    replay={};completed=0
    for round_index in range(5):
        for kind,case,size,path in (list(reversed(jobs)) if round_index%2 else jobs):
            for mode in (tuple(reversed(MODES)) if round_index%2 else MODES):
                guard();name=f'{round_index}-{kind}-{mode}-{case}-{size}'
                command=environment(mode)+[str(binaries[mode]['requests' if kind=='request' else 'micro'])]
                command+=['--case',case,'--size',str(size)] if kind=='request' else ['--input',str(path)]
                if round_index%2:command+=['--reverse']
                record,text=execute(name,command)
                parsed=check.requests(text,case,size) if kind=='request' else check.micro(text,check.matrices(path))
                identity={k:parsed[k] for k in ('rows','values')} if kind=='request' else parsed['solutions']
                if kind=='request':
                    qualified=q['outcomes'][f'outcomes-{mode}-{case}-{size}']
                    expected={k:qualified[k] for k in ('rows','values')}
                    # JSON object keys are strings after loading the qualification.
                    if json.loads(json.dumps(identity))!=expected:
                        raise ValueError('request differs from qualified outcomes')
                elif identity!=qualified_micro[(case,mode)]:
                    raise ValueError('matrix solution differs from qualified outcomes')
                key=(kind,case,size,mode)
                if key in replay and replay[key]!=identity:raise ValueError('changed backend replay between processes')
                replay[key]=identity
                record.update(round=round_index,kind=kind,case=case,size=size,mode=mode,result=parsed)
                atomic_json(out/(name+'.json'),record);completed+=1
                atomic_json(out/'progress.json',dict(completed=completed,expected=5*3*len(jobs),last=name))
                print(name,'pass',round(record['wall_s'],3),flush=True)
    guard();atomic_json(out/'complete.json',dict(complete=True,processes=completed,source_unchanged=True))
if __name__=='__main__':main()
