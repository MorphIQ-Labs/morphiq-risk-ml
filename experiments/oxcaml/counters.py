#!/usr/bin/env python3
"""Manual macOS process-counter probe of the pinned layout benchmark binaries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='planner-counters-v1')
    parser.add_argument('--comparison', type=Path, required=True,
                        help='Prior compiler comparison with expected binary hashes')
    parser.add_argument('--variant', action='append', required=True,
                        help='NAME=path/to/batch_layout.exe')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('This protocol requires macOS /usr/bin/time -l')
    variants = {name: Path(path).resolve() for name, path in
                (entry.split('=', 1) for entry in args.variant)}
    if len(variants) != len(args.variant):
        parser.error('duplicate variant')
    prior = json.loads(args.comparison.read_text())
    report = dict(protocol='planner-counters-v1', host=platform.platform(),
                  scope='Whole process: startup, packing, scalar, batch and packed layout; not isolated kernel counters',
                  comparison_sha256=hashlib.sha256(args.comparison.read_bytes()).hexdigest(),
                  binaries={}, runs=[], complete=False)
    for name, path in variants.items():
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != prior['binaries'][name]['batch_layout.exe']:
            raise ValueError(f'{name}: binary differs from pinned comparison')
        report['binaries'][name] = digest
    for repeat in range(3):
        order = list(variants)
        if repeat % 2:
            order.reverse()
        for name in order:
            command = ['/usr/bin/time', '-l', str(variants[name]), '--count', '256']
            load = os.getloadavg()
            result = subprocess.run(command, text=True, capture_output=True, check=True)
            counters = {}
            for key, label in (('instructions_retired', 'instructions retired'),
                               ('cycles_elapsed', 'cycles elapsed'),
                               ('peak_rss_bytes', 'maximum resident set size'),
                               ('involuntary_context_switches', 'involuntary context switches')):
                match = re.search(r'(\d+)\s+' + label, result.stderr)
                if match is None:
                    raise ValueError(f'{name}: missing {label}')
                counters[key] = int(match[1])
            measured = json.loads(result.stdout)
            if measured.get('identical') is not True:
                raise ArithmeticError(f'{name}: layout outcomes differ')
            report['runs'].append(dict(variant=name, repeat=repeat, command=command,
                                      host_load=load, counters=counters,
                                      result=measured, time_l_stderr=result.stderr))
            args.output.write_text(json.dumps(report, indent=2) + '\n')
    report['complete'] = True
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('15 counter probes complete; pinned binaries and layout equivalence verified')


if __name__ == '__main__':
    main()
