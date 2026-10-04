#!/usr/bin/env python3
"""Manual sequential ABBA comparison of certified multi-output portfolios."""
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
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version', action='version', version='shared-portfolio-abba-v1')
    p.add_argument('--baseline-source', type=Path, required=True)
    p.add_argument('--candidate-source', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--rounds', type=int, default=2)
    args = p.parse_args()
    if args.rounds < 1:
        p.error('rounds must be positive')
    report = dict(protocol='shared-portfolio-abba-v1', platform=platform.platform(),
                  cpu_count=os.cpu_count(), toolchain=subprocess.check_output(['ocamlopt', '-config'], text=True),
                  flags='Dune release; library -O3; benchmark standard release flags',
                  warmup='two calls per phase per fresh process; full major GC before each sample outside timing',
                  measured='five two-call samples per phase; ns and bytes per 24-row portfolio invocation; execution workers=1',
                  driver_sha256=sha(Path(__file__)), sources={}, runs=[])
    if platform.system() == 'Darwin':
        report['hardware'] = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
    for name in ('baseline', 'candidate'):
        root = getattr(args, name + '_source').resolve()
        binary = root / '_build/default/bench/shared_portfolio.exe'
        files = sorted(root.glob('lib/**/*.ml')) + sorted(root.glob('lib/**/*.mli'))
        files += [root / f for f in ('bench/shared_portfolio.ml', 'bench/dune', 'lib/dune', 'dune-project')]
        report['sources'][name] = dict(root=str(root), binary=str(binary), binary_sha256=sha(binary),
            revision=subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
            diff_sha256=hashlib.sha256(subprocess.check_output(['git', '-C', str(root), 'diff', 'HEAD'])).hexdigest(),
            files={str(f.relative_to(root)): sha(f) for f in files})
    if report['sources']['baseline']['files']['bench/shared_portfolio.ml'] != report['sources']['candidate']['files']['bench/shared_portfolio.ml']:
        raise ValueError('different benchmark sources')
    identities = {}
    expected_checks = {f'{r}/{n}' for r in ('ordinary', 'boundaries', 'failure') for n in (1, 2, 11)}
    expected_samples = {(f'{k}/{phase}', n) for k in expected_checks for phase in ('compile', 'execution', 'end-to-end') for n in range(1, 6)}
    def save():
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    for round_ in range(args.rounds):
        for name in ('baseline', 'candidate', 'candidate', 'baseline'):
            started = datetime.datetime.now(datetime.timezone.utc).isoformat()
            before = os.getloadavg()
            raw = subprocess.check_output([report['sources'][name]['binary']], text=True)
            checks, samples, seen = {}, [], set()
            for line in raw.splitlines():
                fields = line.split()
                if fields[0] == 'CHECK':
                    _, key, digest, served, failed = fields
                    value = (digest, int(served), int(failed))
                    if key in checks or int(served) + int(failed) != 24 * int(key.split('/')[1]):
                        raise ValueError('invalid/duplicate coverage')
                    if value != identities.setdefault(key, value):
                        raise ValueError('baseline/candidate/worker ordered outcome mismatch')
                    checks[key] = value
                elif fields[0] == 'TIME':
                    _, key, n, elapsed, cpu, allocation = fields
                    slot = key, int(n)
                    if slot in seen or min(float(elapsed), float(cpu), float(allocation)) < 0:
                        raise ValueError('invalid/duplicate timing')
                    seen.add(slot)
                    samples.append(dict(phase=key, sample=int(n), ns=float(elapsed), cpu_ns=float(cpu), bytes=float(allocation)))
                else:
                    raise ValueError('unexpected benchmark output')
            if set(checks) != expected_checks or seen != expected_samples:
                raise ValueError('incomplete campaign')
            report['runs'].append(dict(variant=name, round=round_, started=started,
                                      load_before=before, load_after=os.getloadavg(), raw=raw, samples=samples))
            save()
            print(f'finished round {round_ + 1}: {name}', flush=True)
    report['checks'] = identities
    report['summary'] = []
    for phase in sorted({k for k, _ in expected_samples}):
        row = dict(phase=phase)
        for name in ('baseline', 'candidate'):
            values = [s for r in report['runs'] if r['variant'] == name for s in r['samples'] if s['phase'] == phase]
            row[name] = {key: dict(median=statistics.median(v[key] for v in values),
                                  min=min(v[key] for v in values), max=max(v[key] for v in values))
                         for key in ('ns', 'cpu_ns', 'bytes')}
        row['speedup'] = row['baseline']['ns']['median'] / row['candidate']['ns']['median']
        report['summary'].append(row)
    report['complete'] = True
    save()


if __name__ == '__main__':
    main()
