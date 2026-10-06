"""Manual scalar Greek cost characterization; no deployment performance gate."""
import argparse
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
from american_reference_data import strict_json
from benchmark_american_allocation import require, sample, sha
from benchmark_bermudan_boundary import checked
ROOT=Path(__file__).resolve().parents[1]


def decode(raw,model,quantity):
    try:r=strict_json(raw)
    except (ValueError,TypeError) as e:raise ValueError('malformed Greek benchmark output') from e
    require(isinstance(r,dict),'Greek benchmark record')
    require((r.get('model'),r.get('quantity'),r.get('calls'),r.get('warmup_calls'))==(model,quantity,1,1),'Greek benchmark workload mismatch')
    for k in ('seconds_per_call','allocated_bytes_per_call','price'):
        require(type(r.get(k)) in (int,float) and math.isfinite(r[k]) and (r[k]>=0 if k=='price' else r[k]>0),'Greek benchmark metric '+k)
    for k in ('minor_collections','major_collections','heap_words_after','live_words_after','estimated_greeks','unavailable_greeks','rejected_greeks'):
        require(type(r.get(k)) is int and r[k]>=0,'Greek benchmark count '+k)
    require(sum(r[k] for k in ('estimated_greeks','unavailable_greeks','rejected_greeks'))=={'price':0,'spatial':3,'all':5}[quantity],'missing Greek outcomes')
    require(isinstance(r.get('digest'),str) and len(r['digest'])==32 and all(c in '0123456789abcdef' for c in r['digest']),'Greek outcome digest')
    return r


def summarize(runs):
    out=[]
    for model in ('constant','piecewise','cash'):
        prices=set()
        for quantity in ('price','spatial','all'):
            rs=[r for r in runs if r['sample']['model']==model and r['sample']['quantity']==quantity]
            require(len(rs)==5 and {r['round'] for r in rs}==set(range(5)),'incomplete Greek benchmark samples')
            require(len({r['sample']['digest'] for r in rs})==1,'Greek outcomes changed between processes')
            prices.update(r['sample']['price'] for r in rs)
            out.append(dict(model=model,quantity=quantity,outcomes={k:rs[0]['sample'][k] for k in ('estimated_greeks','unavailable_greeks','rejected_greeks')},metrics={k:dict(median=statistics.median(xs),min=min(xs),max=max(xs)) for k in ('seconds_per_call','allocated_bytes_per_call','minor_collections','major_collections') for xs in [[r['sample'][k] for r in rs]]}))
        require(len(prices)==1,'underlying price differs by requested quantities')
    return out


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='benchmark-american-greeks 1')
    p.add_argument('--build',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();build=strict_json(a.build.read_text())
    def guard():
        checked(build,current=True)
        for path in ('scripts/benchmark_american_greeks.py','scripts/benchmark_american_allocation.py','scripts/benchmark_bermudan_boundary.py','scripts/american_reference_data.py'):
            require(build['source_sha256'][path]==sha(ROOT/path),'Greek collector source changed')
        require(not subprocess.check_output(['git','-C',str(ROOT),'status','--porcelain','--untracked-files=all','--','scripts/benchmark_american_greeks.py']),'dirty Greek collector')
    guard();a.output.mkdir(parents=True,exist_ok=False)
    result=dict(complete=False,build=build,platform=platform.platform(),cpu_count=os.cpu_count(),runs=[])
    if platform.system()=='Darwin':result['hardware']=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
    def save():(a.output/'results.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    try:
        for i in range(5):
            for model in ('constant','piecewise','cash'):
                quantities=('price','spatial','all') if i%2==0 else ('all','spatial','price')
                for quantity in quantities:
                    raw,resources=sample([build['binaries']['greeks']['path'],'--mode',model,quantity],a.output/f'{i}-{model}-{quantity}',timeout=300)
                    result['runs'].append(dict(round=i,load=os.getloadavg(),sample=decode(raw,model,quantity),resources=resources));save()
        result['summary']=summarize(result['runs']);guard();result['complete']=True
    finally:save()
    print(json.dumps(result['summary']))

if __name__=='__main__':main()
