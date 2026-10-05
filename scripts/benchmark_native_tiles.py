#!/usr/bin/env python3
"""Prepare common public-API drivers, then separately measure paired tile jobs."""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess

CONFIGURATIONS = [(32,32),(256,32),(256,256),(4096,256),(4096,1024)]
FAMILIES = ['eligible','mixed','fallback-heavy']
WORKERS = [1,2,4]
PHASES = ['execute','compile-execute']
TIMEOUT = 180
DUMP_SIZE = 4096
DUMP_SCENARIOS = 4
OPAM = ['opam','exec','--switch=morphiq-risk-ml','--']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path,value):
    Path(path).write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')


def command(args,**kwargs):
    return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT,**kwargs).strip()


def source(root):
    status=command(['git','status','--porcelain=v1','--untracked-files=all'],cwd=root)
    if status:
        raise ValueError('source is not clean: '+str(root))
    return dict(root=str(root),revision=command(['git','rev-parse','HEAD'],cwd=root),
                library_tree=command(['git','rev-parse','HEAD:lib'],cwd=root))


def prepare(baseline,candidate,out):
    out.mkdir(parents=True,exist_ok=False)
    roots=[baseline.resolve(),candidate.resolve()]
    before=[source(r) for r in roots]
    common={name:(roots[1]/path).read_bytes() for name,path in
            [('driver.ml','bench/native_fast_planner.ml'),('clock.c','bench/assurance_clock.c')]}
    executables=[]
    for i,root in enumerate(roots):
        build=out/str(i);build.mkdir();prefix=build/'installed'
        logs=[]
        for cmd in [OPAM+['dune','build','--profile','release','--build-dir','_build_release','@install'],
                    OPAM+['dune','install','--build-dir','_build_release','--prefix',str(prefix)]]:
            logs.append(command(cmd,cwd=root))
        for name,data in common.items(): (build/name).write_bytes(data)
        env=['env','OCAMLPATH='+str(prefix/'lib'),'CAML_LD_LIBRARY_PATH='+str(prefix/'lib/stublibs')]
        logs.append(command(OPAM+env+['ocamlfind','ocamlopt','-O3','-package','morphiq_risk_ml,unix',
                            '-linkpkg','-o','runner','clock.c','driver.ml'],cwd=build))
        (build/'build.log').write_text('\n'.join(logs)+'\n')
        executable=build/'runner'
        executables.append(dict(path=str(executable),sha256=sha(executable)))
    after=[source(r) for r in roots]
    if before!=after: raise ValueError('source changed during build')
    manifest=dict(sources=before,binaries=executables,
        driver_sha256={name:hashlib.sha256(data).hexdigest() for name,data in common.items()},
        compiler=command(OPAM+['ocamlopt','-config']),clang=command(['clang','--version']),
        platform=platform.platform(),cpu_count=os.cpu_count(),
        build='release library -O3; identical external public consumer ocamlopt -O3; benchmark-only monotonic clock',
        scope='Local engineering comparison; no deployment or release qualification')
    if platform.system()=='Darwin':manifest['hardware']=command(['sysctl','-n','machdep.cpu.brand_string'])
    write(out/'prepared.json',manifest)


def snapshot(prepared):
    sources=[source(Path(s['root'])) for s in prepared['sources']]
    binaries=[dict(path=b['path'],sha256=sha(b['path'])) for b in prepared['binaries']]
    if sources!=prepared['sources'] or binaries!=prepared['binaries']:
        raise ValueError('prepared source or binary changed')
    return dict(sources=sources,binaries=binaries)


def parse(raw):
    checks={};samples={}
    for line in raw.splitlines():
        fields=line.split()
        if len(fields)==6 and fields[0]=='CHECK':
            _,family,n,tile,workers,digest=fields
            key=(family,int(n),int(tile),int(workers))
            if key in checks:raise ValueError('duplicate check')
            checks[key]=digest
        elif len(fields)==11 and fields[0]=='TIME':
            _,family,n,tile,workers,phase,number,*values=fields
            key=(family,int(n),int(tile),int(workers),phase,int(number))
            floats=list(map(float,values))
            if key in samples or any(not math.isfinite(x) or x<0 for x in floats):
                raise ValueError('invalid timing sample')
            samples[key]=dict(zip(['ns','cpu_ns','coordinator_bytes','first_output_ns'],floats))
        else:raise ValueError('unexpected benchmark output')
    required={(f,n,t,w) for f in FAMILIES for n,t in CONFIGURATIONS for w in WORKERS}
    slots={(*key,p,s) for key in required for p in PHASES for s in range(1,6)}
    if set(checks)!=required or set(samples)!=slots:raise ValueError('incomplete benchmark coverage')
    return checks,samples


def validate_inputs(raw):
    counts={f:0 for f in FAMILIES}
    for line in raw.splitlines():
        fields=line.split()
        if len(fields)!=12 or fields[0] not in ['bachelier','bsm','black76','displaced'] or fields[1] not in ['call','put']:
            raise ValueError('invalid original-input row')
        family=fields[3].removeprefix('timed-tiles-')
        if family not in counts or any(not re.fullmatch('[0-9a-f]{16}',w) for w in fields[4:]):
            raise ValueError('invalid original-input words')
        counts[family]+=1
    if any(n!=DUMP_SIZE*DUMP_SCENARIOS for n in counts.values()):
        raise ValueError('incomplete original-input coverage')


def validate_trace(raw):
    expected={(f,DUMP_SIZE,s,i) for f in FAMILIES for s in range(DUMP_SCENARIOS) for i in range(DUMP_SIZE)}
    seen=set()
    for line in raw.splitlines():
        fields=line.split()
        if len(fields)!=5 or not re.fullmatch('[0-9a-f]{16}',fields[4]):
            raise ValueError('invalid complete output row')
        key=(fields[0],*map(int,fields[1:4]))
        if key not in expected or key in seen:raise ValueError('duplicate or invalid output index')
        seen.add(key)
    if seen!=expected:raise ValueError('incomplete output trace')


def host():
    return dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),load=os.getloadavg())


def capture(binary,args,out):
    # subprocess.run kills and reaps a timed-out child; partial stdout survives.
    with out.open('w') as stdout,out.with_suffix(out.suffix+'.stderr').open('w') as stderr:
        subprocess.run([binary,*args],stdout=stdout,stderr=stderr,timeout=TIMEOUT,check=True)
    return out.read_text()


def collect(manifest,out):
    prepared=json.loads(manifest.read_text());out.mkdir(parents=True,exist_ok=False)
    write(out/'prepared.json',prepared);write(out/'before.json',snapshot(prepared))
    binaries=[b['path'] for b in prepared['binaries']]
    inputs=[capture(b,['--dump-inputs'],out/f'inputs-{i}.txt') for i,b in enumerate(binaries)]
    if inputs[0]!=inputs[1]:raise ValueError('different timed inputs')
    validate_inputs(inputs[0])
    traces=[capture(b,['--trace'],out/f'trace-{i}.txt') for i,b in enumerate(binaries)]
    if traces[0]!=traces[1]:raise ValueError('different complete output trace')
    validate_trace(traces[0])
    reference=None;groups={};count=0
    for run,revision in enumerate([0,1,1,0,1,0,0,1]):
        args=['--reverse'] if run%4 in [1,2] else []
        observation=dict(revision=revision,start=host());write(out/f'run-{run}-host.json',observation)
        raw=capture(binaries[revision],args,out/f'run-{run}.txt')
        observation['end']=host();write(out/f'run-{run}-host.json',observation)
        checks,samples=parse(raw)
        if reference is None:reference=checks
        if checks!=reference:raise ValueError('changed numerical replay')
        count+=len(samples)
        for key in {k[:-1] for k in samples}:
            group=groups.setdefault((revision,*key),{k:[] for k in next(iter(samples.values()))})
            for metric in group:
                group[metric].append(statistics.median(samples[(*key,s)][metric] for s in range(1,6)))
        snapshot(prepared)
    write(out/'after.json',snapshot(prepared))
    summaries=[]
    for key,metrics in sorted(groups.items()):
        row=dict(zip(['revision','family','n','tile','workers','phase'],key))
        row.update({k:dict(median=statistics.median(v),process_medians=v) for k,v in metrics.items()})
        summaries.append(row)
    write(out/'summary.json',dict(complete=True,samples=count,summary=summaries,
        scope='Whole four-scenario jobs. Coordinator allocation excludes worker allocations. First output is a sample mean, not a tail guarantee. Shared host.'))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='native-tiles-1')
    sub=p.add_subparsers(dest='action',required=True)
    b=sub.add_parser('prepare');b.add_argument('baseline',type=Path);b.add_argument('candidate',type=Path);b.add_argument('output',type=Path)
    m=sub.add_parser('measure');m.add_argument('manifest',type=Path);m.add_argument('output',type=Path)
    a=p.parse_args()
    if a.action=='prepare':prepare(a.baseline,a.candidate,a.output.resolve())
    else:collect(a.manifest.resolve(),a.output.resolve())


if __name__=='__main__':main()
