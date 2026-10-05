#!/usr/bin/env python3
"""Manual source-bound American regression and Bermudan cost characterization."""
import argparse, json, os, pathlib, platform, statistics, subprocess
from benchmark_american_allocation import decode, guard, require, sample, sha
ROOT=pathlib.Path(__file__).resolve().parents[1]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--version',action='version',version='bermudan-cost 1')
    ap.add_argument('--baseline',type=pathlib.Path,required=True)
    ap.add_argument('--candidate',type=pathlib.Path,required=True)
    ap.add_argument('--output',type=pathlib.Path,required=True)
    a=ap.parse_args();builds={k:json.loads(getattr(a,k).read_text()) for k in ('baseline','candidate')}
    for k,b in builds.items():guard(b,current=k=='candidate')
    candidate=builds['candidate']
    require(not subprocess.check_output(['git','-C',str(ROOT),'status','--porcelain','--untracked-files=all','--','lib','bench','test','scripts/benchmark_bermudan.py','dune','dune-project']), 'dirty measured source')
    for name,h in candidate['source_sha256'].items():require(sha(ROOT/name)==h,'changed source: '+name)
    require(builds['baseline']['compiler']==candidate['compiler'],'compiler mismatch')
    require(builds['baseline']['source_sha256']['bench/american_allocation.ml']==candidate['source_sha256']['bench/american_allocation.ml'],'American driver mismatch')
    require(sha(candidate['binaries']['bermudan']['path'])==candidate['binaries']['bermudan']['sha256'],'Bermudan binary changed')
    a.output.mkdir(parents=True,exist_ok=False)
    result=dict(complete=False,builds=builds,collector_sha256=sha(__file__),platform=platform.platform(),cpu_count=os.cpu_count(),runs=[])
    if platform.system()=='Darwin':result['hardware']=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
    def save():(a.output/'results.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    try:
        for round_ in range(5):
            order=('baseline','candidate','bermudan') if round_%2==0 else ('bermudan','candidate','baseline')
            for mode in ('none','cash'):
                for variant in order:
                    command=([candidate['binaries']['bermudan']['path'],'--bench',mode] if variant=='bermudan' else [builds[variant]['binaries']['bench']['path'],'--measure','--mode',mode,'--phase','price','--calls','3'])
                    load=os.getloadavg();raw,resources=sample(command,a.output/f'{round_}-{variant}-{mode}')
                    value=decode(raw,mode,'price',3)
                    result['runs'].append(dict(round=round_,variant=variant,load=load,sample=value,resources=resources));save()
        result['summary']=[dict(variant=v,mode=m,metrics={key:dict(median=statistics.median(xs),min=min(xs),max=max(xs)) for key in ('seconds_per_call','allocated_bytes_per_call') for xs in [[r['sample'][key] for r in result['runs'] if r['variant']==v and r['sample']['mode']==m]]}) for v in ('baseline','candidate','bermudan') for m in ('none','cash')]
        guard(candidate,current=True)
        require(not subprocess.check_output(['git','-C',str(ROOT),'status','--porcelain','--untracked-files=all','--','lib','bench','test','scripts/benchmark_bermudan.py','dune','dune-project']), 'measured source changed during campaign')
        for name,h in candidate['source_sha256'].items():require(sha(ROOT/name)==h,'source changed during campaign: '+name)
        require(sha(candidate['binaries']['bermudan']['path'])==candidate['binaries']['bermudan']['sha256'],'Bermudan binary changed during campaign')
        result['complete']=True
    finally:save()
    print(json.dumps(result['summary']))
if __name__=='__main__':main()
