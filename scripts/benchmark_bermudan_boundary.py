#!/usr/bin/env python3
"""Manual paired qualification of request-owned boundary reuse (#119)."""
import argparse, json, os, pathlib, platform, statistics, subprocess
from benchmark_american_allocation import decode, guard, require, sample, sha
ROOT=pathlib.Path(__file__).resolve().parents[1]
PATHS=['lib','bench','test','scripts/benchmark_bermudan_boundary.py','dune','dune-project','morphiq_risk_ml.opam.locked']

def checked(build, current=False):
    guard(build,current=current)
    for binary in build['binaries'].values():
        require(sha(binary['path'])==binary['sha256'],'changed binary')
    if current:
        require(not subprocess.check_output(['git','-C',str(ROOT),'status','--porcelain','--untracked-files=all','--',*PATHS]),'dirty measured sources')

def acceptance(rows):
    expected={(f,m,p) for f in ('american','bermudan') for m in ('none','cash') for p in (('admission','price','diagnostics') if f=='american' else ('price',))}
    require(len(rows)==8 and {(r['family'],r['mode'],r['phase']) for r in rows}==expected,'incomplete workloads')
    for r in rows:
        base=r['baseline']; candidate=r['candidate']
        allocation=candidate['allocated_bytes_per_call']['median']/base['allocated_bytes_per_call']['median']
        latency=candidate['seconds_per_call']['median']/base['seconds_per_call']['median']
        if r['family']=='bermudan':
            require(allocation<=0.4,'Bermudan allocation criterion failed')
            require(latency<=0.8,'Bermudan latency criterion failed')
        elif r['phase']=='price':
            require(allocation<=1.05,'American allocation regression')
            require(latency<=1.1,'American latency regression')

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--version',action='version',version='bermudan-boundary 1')
    for name in ('baseline','candidate','output'):ap.add_argument('--'+name,type=pathlib.Path,required=True)
    a=ap.parse_args();builds={k:json.loads(getattr(a,k).read_text()) for k in ('baseline','candidate')}
    for k,b in builds.items():checked(b,current=k=='candidate')
    require(builds['baseline']['compiler']==builds['candidate']['compiler'],'compiler mismatch')
    require(builds['baseline']['source_sha256']['bench/american_allocation.ml']==builds['candidate']['source_sha256']['bench/american_allocation.ml'],'American driver mismatch')
    drivers=[subprocess.check_output(['git','-C',str(ROOT),'show',builds[k]['revision']+':test/bermudan.ml'],text=True).split('let bench mode =',1)[1].split('let () =',1)[0] for k in ('baseline','candidate')]
    require(drivers[0]==drivers[1],'Bermudan timed driver mismatch')
    a.output.mkdir(parents=True,exist_ok=False)
    result=dict(complete=False,builds=builds,collector_sha256=sha(__file__),platform=platform.platform(),cpu_count=os.cpu_count(),runs=[])
    if platform.system()=='Darwin':result['hardware']=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
    workloads=[(f,m,p) for f in ('american','bermudan') for m in ('none','cash') for p in (('admission','price','diagnostics') if f=='american' else ('price',))]
    def save():(a.output/'results.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    try:
        for round_ in range(5):
            for family,mode,phase in workloads:
                for variant in (('baseline','candidate') if round_%2==0 else ('candidate','baseline')):
                    b=builds[variant]
                    command=([b['binaries']['bermudan']['path'],'--bench',mode] if family=='bermudan' else [b['binaries']['bench']['path'],'--measure','--mode',mode,'--phase',phase,'--calls','3'])
                    load=os.getloadavg();raw,resources=sample(command,a.output/f'{round_}-{variant}-{family}-{mode}-{phase}')
                    result['runs'].append(dict(round=round_,variant=variant,family=family,load=load,sample=decode(raw,mode,phase,3),resources=resources));save()
        result['summary']=[]
        for family,mode,phase in workloads:
            row=dict(family=family,mode=mode,phase=phase)
            for variant in ('baseline','candidate'):
                rs=[r for r in result['runs'] if (r['family'],r['sample']['mode'],r['sample']['phase'],r['variant'])==(family,mode,phase,variant)]
                require(len(rs)==5 and {r['round'] for r in rs}==set(range(5)),'incomplete samples')
                row[variant]={key:dict(median=statistics.median(xs),min=min(xs),max=max(xs)) for key in ('seconds_per_call','allocated_bytes_per_call','minor_collections','major_collections') for xs in [[r['sample'][key] for r in rs]]}
            result['summary'].append(row)
        for k,b in builds.items():checked(b,current=k=='candidate')
        acceptance(result['summary']);result['complete']=True
    finally:save()
    print(json.dumps(result['summary']))
if __name__=='__main__':main()
