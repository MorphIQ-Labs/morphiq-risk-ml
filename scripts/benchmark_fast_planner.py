#!/usr/bin/env python3
"""Retain fast planner compilation and bounded streaming measurements."""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='fast-planner-campaign-v1')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--tile-rows', type=int, default=32)
    parser.add_argument('--size', type=int)
    args = parser.parse_args()
    sizes = (args.size,) if args.size is not None else (32, 256, 1024)
    if args.tile_rows < 1 or args.tile_rows > 1000000 or any(n < 1 or n > 1000000 for n in sizes):
        parser.error('size and tile rows must be in 1..1000000')
    if args.runs < 1:
        parser.error('runs must be positive')
    root = Path(__file__).resolve().parents[1]
    binary = root / '_build/default/bench/fast_planner.exe'
    sources = sorted(root.glob('lib/**/*.ml')) + sorted(root.glob('lib/**/*.mli')) + sorted(root.glob('lib/**/*.c'))
    sources += [root / p for p in ('bench/fast_planner.ml', 'bench/dune', 'lib/dune', 'dune-project', 'scripts/benchmark_fast_planner.py')]
    report = dict(protocol='fast-planner-campaign-v1', revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                  sources_sha256={str(p.relative_to(root)): sha(p) for p in sources}, binary_sha256=sha(binary),
                  platform=platform.platform(), cpu_count=os.cpu_count(),
                  workload=dict(sizes=sizes, scenarios=4, tile_rows=args.tile_rows, workers=[1,4]),
                  toolchain=subprocess.check_output(['ocamlopt', '-config'], text=True),
                  flags='Dune default profile; library -O3; benchmark standard flags',
                  measurements='ns, CPU ns and coordinator-domain bytes per whole four-scenario job; five samples after three warmups per phase; max(1,4096/n) iterations per sample; full major GC outside timing',
                  limits='Shared host; repeated phase order, not randomized; no individual tail-latency or production SLA claim. Finite results checked outside timing. Worker-domain allocation is excluded; execute-4 bytes are not total job allocation.', runs=[])
    if platform.system() == 'Darwin':
        report['hardware'] = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
    phases = {'compile', 'execute-1', 'execute-4', 'pack-compile-execute'}
    slots = {(n, phase, sample) for n in sizes for phase in phases for sample in range(1, 6)}
    identities = {}
    def save():
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    for i in range(args.runs):
        before = os.getloadavg()
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        command = [str(binary), '--tile-rows', str(args.tile_rows)]
        if args.size is not None:
            command += ['--size', str(args.size)]
        raw = subprocess.check_output(command, text=True)
        seen, checks, samples = set(), set(), []
        for line in raw.splitlines():
            fields = line.split()
            if fields[0] == 'CHECK':
                _, n, digest = fields
                n = int(n)
                if n in checks or digest != identities.setdefault(n, digest):
                    raise ValueError('duplicate or inconsistent outcome digest')
                checks.add(n)
            elif fields[0] == 'TIME':
                _, n, phase, sample, ns, cpu_ns, allocation = fields
                slot = int(n), phase, int(sample)
                if slot in seen or min(float(ns), float(cpu_ns), float(allocation)) < 0:
                    raise ValueError('invalid/duplicate sample')
                seen.add(slot)
                samples.append(dict(size=int(n), phase=phase, sample=int(sample), ns=float(ns), cpu_ns=float(cpu_ns), bytes=float(allocation)))
            else:
                raise ValueError('unexpected output')
        if seen != slots or checks != set(sizes):
            raise ValueError('incomplete coverage')
        report['runs'].append(dict(run=i, started=started, load_before=before, load_after=os.getloadavg(), raw=raw, samples=samples))
        save()
        print(f'completed process {i + 1}', flush=True)
    report['checks'] = identities
    report['summary'] = []
    for n in sizes:
        for phase in sorted(phases):
            values = [s for r in report['runs'] for s in r['samples'] if s['size'] == n and s['phase'] == phase]
            report['summary'].append(dict(size=n, phase=phase, **{
                key: dict(median=statistics.median(s[key] for s in values), min=min(s[key] for s in values), max=max(s[key] for s in values))
                for key in ('ns', 'cpu_ns', 'bytes')}))
    report['complete'] = True
    save()


if __name__ == '__main__':
    main()
