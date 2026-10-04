#!/usr/bin/env python3
"""Record bounded-slot, sampled live-heap and pricing-domain allocation probes.

This is an instrumented memory campaign, never a timing benchmark. It neither
measures process RSS nor includes domain runtime initialization in worker-body
allocation counters.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='fast-memory-v1')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    binary = root / '_build/default/test/fast_planner_metrics.exe'
    files = [root / p for p in ('lib/planner.ml', 'test/fast_planner_metrics.ml',
             'test/planner_probe.ml', 'scripts/instrument_planner.py',
             'scripts/measure_fast_planner_memory.py')]
    sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    report = dict(protocol='fast-memory-v1', revision=subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        platform=platform.platform(), toolchain=subprocess.check_output(['ocamlopt','-config'],text=True),
        sources_sha256={str(p.relative_to(root)):sha(p) for p in files},
        binary_sha256=sha(binary),
        scope='Test-only source instrumentation. all_domain_bytes sums coordinator GC allocation and worker-body GC allocation, including probe overhead; domain runtime initialization/stacks are excluded. Live words are post-major-GC samples, not peak RSS. Fixed eight-position book, compact linear scenario axis, non-retaining sink.',
        runs=[])
    for count in (8, 800, 8000):
        for workers in (1, 4):
            before=os.getloadavg()
            raw=subprocess.check_output([str(binary),'--scenarios',str(count),
                                         '--workers',str(workers)],text=True,timeout=300)
            value=json.loads(raw)
            if (value['scenarios'] != count or value['workers'] != workers
                    or value['rows'] != count*8 or value['injected_failure']
                    or value['peak_slots'] != workers*4 or value['bound'] != 16
                    or value['source_sha256'] != sha(root/'lib/planner.ml')
                    or value['all_domain_bytes'] <= 0):
                raise ValueError('incomplete or inconsistent memory probe')
            report['runs'].append(dict(measured=value, load_before=before,
                load_after=os.getloadavg(), finished=datetime.datetime.now(datetime.timezone.utc).isoformat()))
            args.output.parent.mkdir(parents=True,exist_ok=True)
            args.output.write_text(json.dumps(report,indent=2)+'\n')
            print(f'completed scenarios={count}, workers={workers}',flush=True)
    report['complete']=True
    args.output.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
