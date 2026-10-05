"""Paired piecewise allocation optimization campaign (#119)."""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
from benchmark_american_allocation import decode, require, sample, sha
from benchmark_bermudan_boundary import checked
ROOT=Path(__file__).resolve().parents[1]


def acceptance(summary):
    expected={(f,m) for f in ('american','bermudan','piecewise') for m in ('none','cash')}
    require(len(summary)==6 and {(r['family'],r['mode']) for r in summary}==expected,'incomplete workloads')
    for r in summary:
        allocation, latency = (0.50,0.80) if r['family']=='piecewise' else (1.05,1.10)
        require(r['candidate']['allocated_bytes_per_call']['median']<=allocation*r['baseline']['allocated_bytes_per_call']['median'],'allocation criterion')
        require(r['candidate']['seconds_per_call']['median']<=latency*r['baseline']['seconds_per_call']['median'],'latency criterion')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='piecewise-benchmark 1')
    for k in ('baseline','candidate','output'):p.add_argument('--'+k,type=Path,required=True)
    a=p.parse_args();builds={k:json.loads(getattr(a,k).read_text()) for k in ('baseline','candidate')}
    def check():
        for k,b in builds.items():checked(b,current=k=='candidate')
        require(not subprocess.check_output(['git','-C',str(ROOT),'status','--porcelain','--untracked-files=all','--','scripts/benchmark_piecewise_allocation.py']),'dirty collector')
        require(builds['candidate']['source_sha256']['scripts/benchmark_piecewise_allocation.py']==sha(__file__),'collector source changed')
    check();require(builds['baseline']['compiler']==builds['candidate']['compiler'],'compiler mismatch')
    for path in ('bench/american_allocation.ml','test/bermudan.ml'):
        require(builds['baseline']['source_sha256'][path]==builds['candidate']['source_sha256'][path],'constant benchmark driver mismatch')
    old=subprocess.check_output(['git','-C',str(ROOT),'show',builds['baseline']['revision']+':test/american_piecewise.ml'],text=True)
    new=(ROOT/'test/american_piecewise.ml').read_text()
    body=lambda s:s.split('let bench mode =',1)[1].split('let () =',1)[0]
    require(body(old)==body(new),'piecewise benchmark driver mismatch')
    a.output.mkdir(parents=True,exist_ok=False)
    result=dict(complete=False,builds=builds,collector_sha256=sha(__file__),platform=platform.platform(),cpu_count=os.cpu_count(),runs=[])
    if platform.system()=='Darwin':result['hardware']=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
    def save():(a.output/'results.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    try:
        for round_ in range(5):
            for family in ('american','bermudan','piecewise'):
                for mode in ('none','cash'):
                    variants=('baseline','candidate') if round_%2==0 else ('candidate','baseline')
                    for variant in variants:
                        b=builds[variant]
                        key='bench' if family=='american' else family
                        command=[b['binaries'][key]['path']]
                        command+=['--measure','--mode',mode,'--phase','price','--calls','3'] if family=='american' else ['--bench',mode]
                        raw,resources=sample(command,a.output/f'{round_}-{family}-{mode}-{variant}')
                        result['runs'].append(dict(round=round_,family=family,mode=mode,variant=variant,load=os.getloadavg(),sample=decode(raw,mode,'price',3),resources=resources));save()
        summary=[]
        for family in ('american','bermudan','piecewise'):
            for mode in ('none','cash'):
                row=dict(family=family,mode=mode)
                for variant in ('baseline','candidate'):
                    rs=[r for r in result['runs'] if (r['family'],r['mode'],r['variant'])==(family,mode,variant)]
                    require(len(rs)==5 and {r['round'] for r in rs}==set(range(5)),'incomplete samples')
                    row[variant]={k:dict(median=statistics.median(xs),min=min(xs),max=max(xs)) for k in ('seconds_per_call','allocated_bytes_per_call','minor_collections','major_collections') for xs in [[r['sample'][k] for r in rs]]}
                summary.append(row)
        result['summary']=summary;check();acceptance(summary);result['complete']=True
    finally:save()
    print(json.dumps(summary))

if __name__=='__main__':main()
