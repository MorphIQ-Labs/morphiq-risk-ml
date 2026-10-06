"""Manual paired scalar Greek optimization campaign (#119)."""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
from benchmark_american_allocation import require, sample, sha
from benchmark_american_greeks import decode
from benchmark_bermudan_boundary import checked
ROOT=Path(__file__).resolve().parents[1]
MODELS=('constant','piecewise','cash')
QUANTITIES=('price','spatial','all')


def summarize(runs):
    require(len(runs)==90,'incomplete campaign')
    out=[]
    for model in MODELS:
        prices=set()
        for quantity in QUANTITIES:
            row=dict(model=model,quantity=quantity)
            digests=set()
            for variant in ('baseline','candidate'):
                rs=[r for r in runs if (r['variant'],r['sample']['model'],r['sample']['quantity'])==(variant,model,quantity)]
                require(len(rs)==5 and {r['round'] for r in rs}==set(range(5)),'incomplete paired samples')
                digests.update(r['sample']['digest'] for r in rs)
                prices.update(r['sample']['price'] for r in rs)
                outcomes=[tuple(r['sample'][k] for k in ('estimated_greeks','unavailable_greeks','rejected_greeks')) for r in rs]
                require(len(set(outcomes))==1,'changing outcomes')
                row[variant]=dict(outcomes=outcomes[0],metrics={k:dict(median=statistics.median(xs),min=min(xs),max=max(xs)) for k in ('seconds_per_call','allocated_bytes_per_call','minor_collections','major_collections') for xs in [[r['sample'][k] for r in rs]]})
            require(len(digests)==1 and row['baseline']['outcomes']==row['candidate']['outcomes'],'baseline/candidate full outcomes differ')
            out.append(row)
        require(len(prices)==1,'price depends on Greek selection')
    return out


def acceptance(rows):
    require(len(rows)==9 and {(r['model'],r['quantity']) for r in rows}=={(m,q) for m in MODELS for q in QUANTITIES},'incomplete workload summary')
    for r in rows:
        improved=r['model'] in ('piecewise','cash') and r['quantity']=='all'
        for key,limit in [('allocated_bytes_per_call',.8 if improved else 1.05),('seconds_per_call',.9 if improved else 1.1)]:
            ratio=r['candidate']['metrics'][key]['median']/r['baseline']['metrics'][key]['median']
            require(ratio<=limit,f"{r['model']}/{r['quantity']} {key} ratio {ratio} exceeds {limit}")


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='american-greek-optimization 1')
    for k in ('baseline','candidate','output'):p.add_argument('--'+k,type=Path,required=True)
    a=p.parse_args();builds={k:json.loads(getattr(a,k).read_text()) for k in ('baseline','candidate')}
    paths=['scripts/benchmark_american_greek_optimization.py','scripts/benchmark_american_greeks.py','scripts/benchmark_american_allocation.py','scripts/benchmark_bermudan_boundary.py','scripts/american_reference_data.py']
    source={s:sha(ROOT/s) for s in paths}
    def guard():
        for variant,b in builds.items():checked(b,current=variant=='candidate')
        require(source=={s:sha(ROOT/s) for s in paths},'collector source drift')
        require(not subprocess.check_output(['git','-C',str(ROOT),'status','--porcelain','--untracked-files=all','--',*paths]),'dirty collector')
        for s in paths:require(builds['candidate']['source_sha256'][s]==source[s],'collector/build source mismatch')
    guard();require(builds['baseline']['compiler']==builds['candidate']['compiler'],'compiler mismatch')
    driver='bench/american_greeks.ml'
    require(builds['baseline']['source_sha256'][driver]==builds['candidate']['source_sha256'][driver],'benchmark driver mismatch')
    a.output.mkdir(parents=True,exist_ok=False)
    result=dict(complete=False,builds=builds,collector_sources=source,platform=platform.platform(),cpu_count=os.cpu_count(),runs=[])
    if platform.system()=='Darwin':result['hardware']=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
    def save():(a.output/'results.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    try:
        for i in range(5):
            for model in MODELS:
                for quantity in QUANTITIES:
                    for variant in (('baseline','candidate') if i%2==0 else ('candidate','baseline')):
                        raw,resources=sample([builds[variant]['binaries']['greeks']['path'],'--mode',model,quantity],a.output/f'{i}-{model}-{quantity}-{variant}',timeout=300)
                        result['runs'].append(dict(round=i,variant=variant,load=os.getloadavg(),sample=decode(raw,model,quantity),resources=resources));save()
        result['summary']=summarize(result['runs']);guard();acceptance(result['summary']);result['complete']=True
    finally:save()
    print(json.dumps(result['summary']))

if __name__=='__main__':main()
