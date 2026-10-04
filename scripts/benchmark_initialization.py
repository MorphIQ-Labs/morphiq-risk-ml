#!/usr/bin/env python3
"""Compare cold launch plus runtime/library initialization of prepared release builds."""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import time


def main(args):
    roots = {'baseline': args.baseline.resolve(), 'replacement': args.replacement.resolve()}
    report = {'host': platform.platform(), 'method': '50 alternating AB/BA pairs; fresh processes; elapsed launch+initialization includes OS overhead',
              'sources': {}, 'runs': []}
    for label, root in roots.items():
        source = root / 'bench/initialization.ml'
        exe = root / '_build-release/default/bench/initialization.exe'
        report['sources'][label] = {'harness_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                                    'binary_sha256': hashlib.sha256(exe.read_bytes()).hexdigest()}
    assert len({s['harness_sha256'] for s in report['sources'].values()}) == 1
    for pair in range(50):
        labels = list(roots)
        if pair % 2:
            labels.reverse()
        for label in labels:
            exe = roots[label] / '_build-release/default/bench/initialization.exe'
            load = os.getloadavg()
            start = time.perf_counter_ns()
            result = subprocess.run([str(exe)], check=True, capture_output=True, text=True)
            elapsed = time.perf_counter_ns() - start
            rows = list(csv.DictReader(io.StringIO(result.stdout)))
            assert len(rows) == 1
            report['runs'].append({'pair': pair, 'implementation': label, 'elapsed_ns': elapsed,
                                   'load_start': load, 'memory': rows[0]})
    args.output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='benchmark_initialization 1')
    for name in ('baseline', 'replacement', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    main(parser.parse_args())
