#!/usr/bin/env python3
"""Sequential paired fast/certified costs for development and release builds.

Prebuild fast_batch, fast_planner and shared_portfolio in _build (development)
and _build_release (--profile release) in both worktrees. Run no task-owned
builds, tests or allocation samplers alongside this timing campaign.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse(raw, bench):
    checks, samples = {}, {}
    for line in raw.splitlines():
        fields = line.split()
        if fields[0] == 'CHECK':
            key = fields[1]
            if key in checks:
                raise ValueError('duplicate coverage')
            checks[key] = fields[2:]
        elif fields[0] == 'TIME':
            if bench == 'shared_portfolio':
                _, key, sample, ns, cpu, allocation = fields
            else:
                _, size, phase, sample, ns, cpu, allocation = fields
                key = size + '/' + phase
            slot = key, int(sample)
            values = dict(ns=float(ns), cpu_ns=float(cpu), bytes=float(allocation))
            if slot in samples or any(not (0 <= v < float('inf')) for v in values.values()):
                raise ValueError('invalid timing sample')
            samples[slot] = dict(phase=key, sample=int(sample), **values)
        else:
            raise ValueError('unexpected benchmark output')
    if bench == 'shared_portfolio':
        expected_checks = {r+'/'+str(n) for r in ('ordinary','boundaries','failure') for n in (1,2,11)}
        phases = ('compile','execution','end-to-end')
    else:
        expected_checks = {'32','256','1024'}
        phases = ('compile','execute','one-shot','scalar-admit-price','scalar-preadmitted',
                  'pack-compile-execute-extract') if bench == 'fast_batch' else (
                  'compile','execute-1','execute-4','pack-compile-execute')
    expected_slots = {(k+'/'+p,n) for k in expected_checks for p in phases for n in range(1,6)}
    if set(checks) != expected_checks or set(samples) != expected_slots:
        raise ValueError('incomplete benchmark coverage')
    return checks, list(samples.values())


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='fast-allocation-abba-v1')
    p.add_argument('--baseline-source',type=Path,required=True)
    p.add_argument('--candidate-source',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--rounds',type=int,default=2)
    args = p.parse_args()
    if args.rounds < 1:
        p.error('rounds must be positive')
    benches = ('fast_batch','fast_planner','shared_portfolio')
    profiles = dict(development='_build',release='_build_release')
    report = dict(protocol='fast-allocation-abba-v1',platform=platform.platform(),
        cpu_count=os.cpu_count(),toolchain=subprocess.check_output(['ocamlopt','-config'],text=True),
        flags='OCaml 5.3 Flambda, library -O3; Dune development (opaque) and release (cross-module optimization), separate build directories',
        scope='Batch means, fixed phase order, shared host. Fast planner four-worker bytes cover coordinator only. Certified and fast assurance are distinct. Harnesses perform numerical checks outside timing.',
        driver_sha256=sha(Path(__file__)),sources={},runs=[])
    if platform.system() == 'Darwin':
        report['hardware']=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
    for name in ('baseline','candidate'):
        root=getattr(args,name+'_source').resolve()
        files=sorted(root.glob('lib/**/*.ml'))+sorted(root.glob('lib/**/*.mli'))+sorted(root.glob('lib/**/*.c'))
        files += [root/f for f in ('lib/dune','bench/dune','dune-project')]
        files += [root/'bench'/f'{b}.ml' for b in benches]
        report['sources'][name]=dict(root=str(root),revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
            files={str(f.relative_to(root)):sha(f) for f in files},binaries={
                profile+'/'+b:dict(path=str(root/d/'default/bench'/f'{b}.exe'),
                  sha256=sha(root/d/'default/bench'/f'{b}.exe')) for profile,d in profiles.items() for b in benches})
    for b in benches:
        if report['sources']['baseline']['files'][f'bench/{b}.ml'] != report['sources']['candidate']['files'][f'bench/{b}.ml']:
            raise ValueError('benchmark sources differ')
    identities={}
    def save():
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(report,indent=2)+'\n')
    for profile in profiles:
        for round_ in range(args.rounds):
            for variant in ('baseline','candidate','candidate','baseline'):
                for bench in benches:
                    before=os.getloadavg()
                    binary=report['sources'][variant]['binaries'][profile+'/'+bench]['path']
                    raw=subprocess.check_output([binary],text=True,timeout=600)
                    checks,samples=parse(raw,bench)
                    if checks != identities.setdefault(bench,checks):
                        raise ValueError('outcomes changed between variants/profiles')
                    report['runs'].append(dict(profile=profile,round=round_,variant=variant,bench=bench,
                        finished=datetime.datetime.now(datetime.timezone.utc).isoformat(),load_before=before,
                        load_after=os.getloadavg(),raw=raw,samples=samples))
                    save()
                print(f'finished {profile} round {round_+1}: {variant}',flush=True)
    report['checks']=identities
    summary=[]
    for profile in profiles:
        for bench in benches:
            phases=sorted({s['phase'] for r in report['runs'] if r['bench']==bench for s in r['samples']})
            for phase in phases:
                row=dict(profile=profile,bench=bench,phase=phase)
                for variant in ('baseline','candidate'):
                    values=[s for r in report['runs'] if (r['profile'],r['bench'],r['variant'])==(profile,bench,variant)
                            for s in r['samples'] if s['phase']==phase]
                    row[variant]={k:dict(median=statistics.median(s[k] for s in values),min=min(s[k] for s in values),
                                       max=max(s[k] for s in values)) for k in ('ns','cpu_ns','bytes')}
                summary.append(row)
    report.update(summary=summary,complete=True)
    save()


if __name__ == '__main__':
    main()
