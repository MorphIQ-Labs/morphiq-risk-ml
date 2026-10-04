#!/usr/bin/env python3
"""Paired error-function and end-to-end measurements for two prepared worktrees.

Build bench/error_functions.exe and bench/assurance.exe in _build-release
(--profile release --build-dir _build-release), and the primitive harness in
_build (development profile), before running. Harness sources must match.
Runs sequentially; stop other task-owned tests/builds before timing.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(args):
    roots = dict(baseline=args.baseline.resolve(), replacement=args.replacement.resolve())
    harnesses = ['bench/error_functions.ml', 'bench/assurance.ml', 'bench/assurance_clock.c']
    hashes = {name: {f: digest(root/f) for f in harnesses} for name, root in roots.items()}
    assert len({json.dumps(v, sort_keys=True) for v in hashes.values()}) == 1, 'harness sources differ'
    cpu = (subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip()
           if platform.system() == 'Darwin' else platform.processor())
    report = {'host': platform.platform(), 'cpu': cpu, 'hardware_threads':os.cpu_count(),
              'compiler':'OCaml 5.3.0 Flambda; library and benchmark -O3',
              'method':'three alternating AB/BA/AB orders; sequential processes; busy shared host; timings provisional',
              'harness_sha256':next(iter(hashes.values())), 'sources':{}, 'runs':[]}
    for label,root in roots.items():
        report['sources'][label]={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
                                 'source_sha256':{f:digest(root/f) for f in ['lib/cody.ml','lib/dd.ml','lib/split.ml','lib/normal.ml','lib/normalised_black.ml','lib/erf_coefficients.ml'] if (root/f).exists()}}
    names = list(roots)
    for profile, directory, benches in [('dev','_build',['error_functions']),
                                         ('release','_build-release',['error_functions','assurance'])]:
        for pair in range(3):
            order = names if pair % 2 == 0 else names[::-1]
            for label in order:
                for bench in benches:
                    exe = roots[label]/directory/'default/bench'/f'{bench}.exe'
                    cmd = [str(exe)] + (['--count','64','--runs','7'] if bench=='assurance' else [])
                    load = os.getloadavg()
                    start = time.monotonic()
                    result = subprocess.run(cmd, text=True, capture_output=True, check=True)
                    rows = list(csv.DictReader(io.StringIO(result.stdout)))
                    assert len(rows) == (61 if bench=='assurance' else 7), 'incomplete benchmark output'
                    report['runs'].append({'profile':profile,'pair':pair,'implementation':label,
                        'benchmark':bench,'load_start':load,'load_end':os.getloadavg(),
                        'elapsed_seconds':time.monotonic()-start,'rows':rows,'outcomes':result.stderr})
                    print(f'{profile} {pair} {label} {bench}: complete', flush=True)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w',dir=args.output.parent,prefix='.erf-bench-',delete=False) as f:
        json.dump(report,f,indent=2);f.write('\n');temporary=Path(f.name)
    os.replace(temporary,args.output)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='benchmark_error_functions 1')
    for name in ('baseline','replacement','output'):p.add_argument('--'+name,type=Path,required=True)
    main(p.parse_args())
