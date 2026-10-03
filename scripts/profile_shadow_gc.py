#!/usr/bin/env python3
"""Separate process GC trace of captured shadow inputs; never used as ordinary latency evidence."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time
from shadow_campaign import wire


def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,default=Path('docs/evidence/shadow-campaign.json.gz'))
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    evidence=json.load(gzip.open(args.input,'rt'));rows=[r['input'] for r in evidence['rows']]
    worker=Path('_build/default/bench/shadow.exe').resolve();reader=Path('_build/default/bench/gc_trace.exe').resolve()
    if sha(worker)!=evidence['worker_sha256']: raise RuntimeError('profile worker differs from captured shadow source')
    load=os.getloadavg()
    with tempfile.TemporaryDirectory(prefix='risk-gc-') as directory:
        marker=Path(directory)/'done'
        env=dict(os.environ,OCAML_RUNTIME_EVENTS_START='1',OCAML_RUNTIME_EVENTS_PRESERVE='1',OCAML_RUNTIME_EVENTS_DIR=directory)
        p=subprocess.Popen([str(worker)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
        trace=None
        try:
            if p.stdout.readline()!='READY\n': raise RuntimeError('profile worker did not start')
            trace=subprocess.Popen([str(reader),directory,str(p.pid),str(marker)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            if trace.stdout.readline()!='READY\n': raise RuntimeError('reader did not start')
            start=time.monotonic();out,err=p.communicate(wire(rows,1),timeout=120)
            elapsed=time.monotonic()-start
            marker.touch();events,errors=trace.communicate(timeout=60)
            if p.returncode or trace.returncode: raise RuntimeError(f'incomplete trace: worker={p.returncode} reader={trace.returncode}\n{err}\n{events}\n{errors}')
        finally:
            for process in [p,trace]:
                if process is not None and process.poll() is None:
                    process.kill();process.communicate()
        values={}
        for line in out.splitlines():
            f=line.split('\t')
            if f[0]=='STATS' or f[1]=='latency': continue
            _,id=f[0].split(':');values.setdefault(id,{})[f[1]]=f[2:]
        if values!={r['input']['id']:r['outputs'] for r in evidence['rows']}: raise RuntimeError('profile numerical replay changed')
        phases={};unions={};integrity=None
        for line in events.splitlines():
            f=line.split('\t')
            if f[0]=='INTEGRITY': integrity=dict(lost_events=int(f[1]),unpaired_spans=int(f[2]))
            elif f[0]=='UNION': unions[f[1]]=int(f[2])
            else: phases[f[0]]=dict(zip(['count','total_ns','p50_ns','p99_ns','max_ns'],map(int,f[1:])))
        if integrity!=dict(lost_events=0,unpaired_spans=0): raise RuntimeError('trace integrity not established')
    report=dict(input_sha256=sha(args.input),source_sha256={str(p):sha(p) for p in [Path(__file__),Path('scripts/shadow_campaign.py'),Path('bench/gc_trace.ml'),Path('bench/dune')]},
                worker_sha256=sha(worker),reader_sha256=sha(reader),rows=len(rows),numerical_replay_identical=True,
                platform=platform.platform(),load_before=load,load_after=os.getloadavg(),instrumented_subprocess_seconds=elapsed,
                phases=phases,gc_phase_union_ns_by_domain=unions,integrity=integrity,
                source_documentation='Installed OCaml 5.3.0 runtime_events.mli; EV_MINOR/EV_MAJOR begin/end timestamps, per-domain union',
                scope='Separate instrumented whole-worker sample including startup/encoding/I/O, not uninstrumented request latency or a service-level claim. Minor and major durations may overlap; only the per-domain union removes overlap. No runtime pricing dependency added.')
    args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))


if __name__=='__main__': main()
