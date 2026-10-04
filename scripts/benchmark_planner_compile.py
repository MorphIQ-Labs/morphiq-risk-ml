#!/usr/bin/env python3
"""Manual sequential ABBA planner compilation comparison; no scalar execution."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='planner-compile-abba-v1')
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--baseline-source', type=Path, required=True)
    parser.add_argument('--candidate-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--sizes', type=int, nargs='+', default=[5000, 10000, 20000, 40000])
    args = parser.parse_args()
    if args.rounds < 1 or any(n < 1 for n in args.sizes):
        parser.error('positive sizes and rounds required')
    report = dict(protocol='planner-compile-abba-v1', platform=platform.platform(),
                  machine=platform.machine(), cpu_count=os.cpu_count(),
                  toolchain=subprocess.check_output(['ocamlopt', '-config'], text=True),
                  flags='Dune release; library and benchmark -O3',
                  warmup='one full compile per fresh process, then full major GC outside timing',
                  measured='one Planner.compile; excludes input creation, warmup, GC reset and JSON output',
                  sources={}, runs=[])
    if platform.system() == 'Darwin':
        report['hardware'] = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
    for name in ('baseline', 'candidate'):
        root = getattr(args, name + '_source').resolve()
        report['sources'][name] = dict(
            root=str(root), revision=subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
            diff_sha256=hashlib.sha256(subprocess.check_output(['git', '-C', str(root), 'diff', 'HEAD'])).hexdigest(),
            files={f: digest(root / f) for f in ('lib/planner.ml', 'bench/planner_compile.ml', 'bench/dune', 'dune-project', 'lib/dune')},
            binary=str(getattr(args, name).resolve()), binary_sha256=digest(getattr(args, name)))
    if report['sources']['baseline']['files']['bench/planner_compile.ml'] != report['sources']['candidate']['files']['bench/planner_compile.ml']:
        raise ValueError('benchmark sources differ')
    report['driver_sha256'] = digest(Path(__file__))
    identities = {}
    def save():
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    for n in args.sizes:
        for groups in sorted({1, max(1, n // 10), n}):
            for repeat in range(args.rounds):
                for name in ('baseline', 'candidate', 'candidate', 'baseline'):
                    load = os.getloadavg()
                    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    result = json.loads(subprocess.check_output([
                        str(getattr(args, name).resolve()), '--instruments', str(n), '--groups', str(groups)], text=True))
                    if result['instruments'] != n or result['groups'] != groups or result['planning_s'] <= 0:
                        raise ValueError('invalid benchmark output')
                    key = n, groups
                    if result['plan_id'] != identities.setdefault(key, result['plan_id']):
                        raise ValueError('baseline/candidate plan identity mismatch')
                    report['runs'].append(dict(variant=name, round=repeat, started=started,
                                               host_load=load, result=result))
                    save()
            print(f'finished instruments={n}, groups={groups}', flush=True)
    report['summary'] = []
    for n, groups in identities:
        row = dict(instruments=n, groups=groups)
        for name in ('baseline', 'candidate'):
            values = [r['result'] for r in report['runs'] if r['variant'] == name
                      and r['result']['instruments'] == n and r['result']['groups'] == groups]
            times = [r['planning_s'] for r in values]
            row[name] = dict(median_s=statistics.median(times), min_s=min(times), max_s=max(times),
                             median_allocated_words=statistics.median(r['allocated_words'] for r in values))
        row['speedup'] = row['baseline']['median_s'] / row['candidate']['median_s']
        report['summary'].append(row)
    report['complete'] = True
    save()


if __name__ == '__main__':
    main()
