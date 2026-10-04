#!/usr/bin/env python3
"""Retain fast batch compilation, execution and request-cost measurements."""
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
    parser.add_argument('--version', action='version', version='fast-batch-campaign-v1')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=5)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error('runs must be positive')
    root = Path(__file__).resolve().parents[1]
    binary = root / '_build/default/bench/fast_batch.exe'
    sources = sorted(root.glob('lib/**/*.ml')) + sorted(root.glob('lib/**/*.mli')) + sorted(root.glob('lib/**/*.c'))
    sources += [root / p for p in ('bench/fast_batch.ml', 'bench/dune', 'lib/dune', 'dune-project', 'scripts/benchmark_fast_batch.py')]
    report = dict(protocol='fast-batch-campaign-v1', revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
                  sources_sha256={str(p.relative_to(root)): sha(p) for p in sources}, binary_sha256=sha(binary),
                  platform=platform.platform(), cpu_count=os.cpu_count(),
                  toolchain=subprocess.check_output(['ocamlopt', '-config'], text=True),
                  flags='Dune default profile; library -O3; benchmark standard flags',
                  measurements='ns, CPU ns and bytes per whole batch; five samples after three warmups per phase; max(1,8192/n) iterations per sample; full major GC outside timing',
                  limits='Shared host; repeated phase order, not randomized; no individual tail-latency or production SLA claim. Finite results checked outside timing.', runs=[])
    if platform.system() == 'Darwin':
        report['hardware'] = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
    phases = {'scalar-admit-price', 'scalar-preadmitted', 'compile', 'execute', 'one-shot', 'pack-compile-execute-extract'}
    slots = {(n, phase, sample) for n in (32, 256, 1024) for phase in phases for sample in range(1, 6)}
    identities = {}
    def save():
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    for i in range(args.runs):
        before = os.getloadavg()
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        raw = subprocess.check_output([str(binary)], text=True)
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
        if seen != slots or checks != {32, 256, 1024}:
            raise ValueError('incomplete coverage')
        report['runs'].append(dict(run=i, started=started, load_before=before, load_after=os.getloadavg(), raw=raw, samples=samples))
        save()
        print(f'completed process {i + 1}', flush=True)
    report['checks'] = identities
    report['summary'] = []
    for n in (32, 256, 1024):
        for phase in sorted(phases):
            values = [s for r in report['runs'] for s in r['samples'] if s['size'] == n and s['phase'] == phase]
            report['summary'].append(dict(size=n, phase=phase, **{
                key: dict(median=statistics.median(s[key] for s in values), min=min(s[key] for s in values), max=max(s[key] for s in values))
                for key in ('ns', 'cpu_ns', 'bytes')}))
    report['complete'] = True
    save()


if __name__ == '__main__':
    main()
