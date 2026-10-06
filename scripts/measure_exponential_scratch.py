#!/usr/bin/env python3
"""Frozen paired American/European campaign for call-owned exponential scratch."""
import argparse,datetime,json,os,platform,statistics,subprocess
from pathlib import Path
import check_american_backends as american
import benchmark_enclosure_consumers as european
from measure_american_workloads import source_snapshot,sha,child,require_child,atomic_json
ROOT=Path(__file__).resolve().parents[1]
CASES=('call','flat','cash','bermudan','piecewise','piecewise-cash','greeks','iv','certified','hard')
JOBS=[(c,1) for c in CASES]+[(c,4) for c in ('cash','bermudan','piecewise-cash')]

def statistics_of(xs):
    return dict(median=statistics.median(xs),minimum=min(xs),maximum=max(xs),samples=xs)

def summarize(runs, allocation_targets=None):
    if allocation_targets is None: allocation_targets={c:.9 for c in ('bermudan','piecewise','piecewise-cash')}
    expected={(r,c,n,v) for r in range(5) for c,n in JOBS+[('european',0)] for v in ('baseline','candidate')}
    keys=[(x['round'],x['case'],x['size'],x['variant']) for x in runs]
    if len(keys)!=len(expected) or set(keys)!=expected:raise ValueError('incomplete/duplicate paired campaign')
    summary={};failures=[]
    for case,size in JOBS:
        row={}
        identities=[]
        for variant in ('baseline','candidate'):
            rs=[r for r in runs if (r['case'],r['size'],r['variant'])==(case,size,variant)]
            identities.extend({k:r['result'][k] for k in ('rows','values')} for r in rs)
            methods=rs[0]['result']['times']
            row[variant]=dict(time={m:{k:statistics_of([r['result']['times'][m][k] for r in rs]) for k in ('wall_s','first_s')} for m in methods},
              memory={m:statistics_of([r['result']['memory'][m] for r in rs]) for m in methods},
              compilation={m:statistics_of([r['result']['compilation'][m] for r in rs]) for m in ('batch','planner')},
              rss=statistics_of([r['peak_rss_bytes'] for r in rs]))
        if any(i!=identities[0] for i in identities):raise ValueError('changed American complete replay')
        for method in row['baseline']['time']:
            if method=='admission':continue
            limit=allocation_targets.get(case,1.05) if size==1 and method=='scalar' else 1.05
            if row['candidate']['memory'][method]['median']>limit*row['baseline']['memory'][method]['median']:
                failures.append(f'{case}/{size}/{method}: allocation criterion')
            if row['candidate']['time'][method]['wall_s']['median']>1.1*row['baseline']['time'][method]['wall_s']['median']:
                failures.append(f'{case}/{size}/{method}: latency criterion')
        summary[f'{case}/{size}']=row
    er=[dict(variant=r['variant'],round=r['round'],sample=r['result']) for r in runs if r['case']=='european']
    for r in er:european.same_checks(er[0]['sample']['checks'],r['sample']['checks'])
    es=european.summarize(er)
    for r in es:
        if not r['key'].endswith('/admission'):
            if r['candidate']['ns']['median']>1.1*r['baseline']['ns']['median']:failures.append(r['key']+': European latency criterion')
            if r['candidate']['allocation']['median']>1.05*r['baseline']['allocation']['median']:failures.append(r['key']+': European allocation criterion')
    return dict(american=summary,european=es,criteria_pass=not failures,failures=failures)

def main(*, description=__doc__, version='exponential-scratch-campaign 1', allocation_targets=None):
    p=argparse.ArgumentParser(description=description)
    p.add_argument('--baseline',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--version',action='version',version=version)
    a=p.parse_args();roots={'baseline':a.baseline.resolve(),'candidate':ROOT};out=a.output.resolve()
    if any(out.is_relative_to(r) for r in roots.values()):p.error('output must be outside source trees')
    out.mkdir(parents=True,exist_ok=False)
    sources={k:source_snapshot(r) for k,r in roots.items()}
    binaries={v:{k:r/'_build/default/bench'/name for k,name in [('american','backend_requests.exe'),('european','certified_scalar.exe')]} for v,r in roots.items()}
    hashes={str(p):sha(p) for b in binaries.values() for p in b.values()}
    for name in ('bench/backend_requests.ml','bench/backend_inputs.ml','bench/certified_scalar.ml'):
        if sources['baseline'][name]!=sources['candidate'][name]:raise ValueError('benchmark driver changed')
    def guard():
        if any(source_snapshot(r)!=sources[v] for v,r in roots.items()) or any(sha(Path(p))!=h for p,h in hashes.items()):raise ValueError('source/binary drift')
    manifest=dict(campaign=version,allocation_targets=allocation_targets,sources=sources,binaries=hashes,commits={v:subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip() for v,r in roots.items()},
      platform=platform.platform(),logical_cpus=os.cpu_count(),
      hardware=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip() if platform.system()=='Darwin' else platform.machine(),
      started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
      compiler=subprocess.check_output(['opam','exec','--switch=morphiq-risk-ml','--','ocamlopt','-config'],text=True))
    atomic_json(out/'manifest.json',manifest);runs=[];identities={}
    for i in range(5):
        jobs=JOBS+[('european',0)]
        for case,size in (reversed(jobs) if i%2 else jobs):
            for variant in (('candidate','baseline') if i%2 else ('baseline','candidate')):
                guard();name=f'{i}-{variant}-{case}-{size}'
                command=['env','-u','MORPHIQ_CAPTURE_CELLS','-u','MORPHIQ_POLICY_BACKEND','-u','MORPHIQ_POLICY_TRACE','-u','MORPHIQ_POLICY_ACCOUNT']
                command.append(str(binaries[variant]['european' if case=='european' else 'american']))
                if size:
                    command+=['--case',case,'--size',str(size)]
                    if i%2:command.append('--reverse')
                record=child(command,out/(name+'.log'),out/(name+'.stderr'),600)
                atomic_json(out/(name+'.json'),record);require_child(record)
                raw=(out/(name+'.log')).read_text()
                result=european.decode(raw) if case=='european' else american.requests(raw,case,size)
                identity=result['checks'] if not size else {k:result[k] for k in ('rows','values')}
                key=(case,size)
                if key in identities and identity!=identities[key]:raise ValueError('changed complete request replay')
                identities[key]=identity
                record.update(round=i,variant=variant,case=case,size=size,result=result);runs.append(record)
                atomic_json(out/(name+'.json'),record)
                atomic_json(out/'progress.json',dict(completed=len(runs),expected=140,last=name))
                print(name,'complete',flush=True)
    guard();summary=summarize(runs,allocation_targets)
    atomic_json(out/'summary.json',summary)
    atomic_json(out/'complete.json',dict(complete=True,processes=len(runs),criteria_pass=summary['criteria_pass'],source_unchanged=True))
    if not summary['criteria_pass']:raise ValueError('frozen engineering criteria failed: '+str(summary['failures']))
if __name__=='__main__':main()
