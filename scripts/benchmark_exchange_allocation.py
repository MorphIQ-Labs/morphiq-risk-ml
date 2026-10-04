#!/usr/bin/env python3
"""Retain an A/B/B/A run of the fixed exchange qualification benchmark."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='exchange-allocation 1')
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--baseline-revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    expected = {(f'{regime}/{phase}', r)
                for regime in ('ordinary', 'singular', 'tail', 'failure')
                for phase in ('admission', 'evaluation', 'end-to-end')
                for r in range(1, 8)}
    report = dict(schema=1, baseline_revision=args.baseline_revision,
                  candidate_parent=subprocess.check_output(
                      ['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
                  platform=platform.platform(), order='ABBA',
                  source_sha256={p: sha(root / p) for p in (
                      'lib/enclosure.ml', 'bench/exchange_qualification_bench.ml',
                      'bench/dune', 'scripts/benchmark_exchange_allocation.py')},
                  limits=['Shared workstation; no deployment SLA.',
                          'No task-owned test, build or profiler runs during timing.',
                          '100 calls per evaluation batch, 7 batches, 20 warm-up pairs.',
                          'Allocation is cumulative bytes per call, not resident memory.',
                          'Correctness and complete-corpus compatibility checked separately.'],
                  runs=[])
    for label, binary in [('A1', args.baseline), ('B1', args.candidate),
                          ('B2', args.candidate), ('A2', args.baseline)]:
        load = os.getloadavg()
        start = time.monotonic()
        proc = subprocess.run([str(binary.resolve())], capture_output=True,
                              text=True, check=True)
        rows, seen = [], set()
        for line in proc.stdout.splitlines():
            phase, round_, ns, allocation = line.split()
            key = phase, int(round_)
            ns, allocation = float(ns), float(allocation)
            if (key in seen or key not in expected or not math.isfinite(ns)
                    or not math.isfinite(allocation) or ns <= 0 or allocation < 0):
                raise ValueError(f'invalid benchmark row: {line}')
            seen.add(key)
            rows.append(dict(phase=phase, round=key[1], ns=ns, bytes=allocation))
        if seen != expected or proc.stderr:
            raise ValueError('incomplete benchmark or unexpected stderr')
        report['runs'].append(dict(label=label, binary_sha256=sha(binary),
                                  elapsed_seconds=time.monotonic() - start,
                                  load_before=load, load_after=os.getloadavg(), rows=rows))
        print(label, 'complete', flush=True)
    report['summary'] = {}
    for phase in sorted({p for p, _ in expected}):
        summary = {}
        for version in 'AB':
            rows = [r for run in report['runs'] if run['label'].startswith(version)
                    for r in run['rows'] if r['phase'] == phase]
            summary[version] = {field: dict(median=statistics.median(r[field] for r in rows),
                                           min=min(r[field] for r in rows),
                                           max=max(r[field] for r in rows))
                                for field in ('ns', 'bytes')}
        summary['time_reduction_percent'] = 100 * (1 - summary['B']['ns']['median'] /
                                                   summary['A']['ns']['median'])
        summary['allocation_reduction_percent'] = 100 * (1 - summary['B']['bytes']['median'] /
                                                         summary['A']['bytes']['median'])
        report['summary'][phase] = summary
    args.output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
