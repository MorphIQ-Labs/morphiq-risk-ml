#!/usr/bin/env python3
"""Pair two committed experiment builds; run after all builds/tests/profiles end."""
import argparse
import collections
import contextlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess

import campaign

@contextlib.contextmanager
def at(root):
    previous = Path.cwd()
    os.chdir(root)
    try:
        yield
    finally:
        os.chdir(previous)

def snapshot(root, binary):
    with at(root):
        result = campaign.metadata(binary)
    assert result['source_status'] == '', 'commit all source before timing'
    return result

def collect(roots, binaries, destination):
    out = Path(destination)
    out.mkdir(exist_ok=False)
    before = [snapshot(root, binary) for root, binary in zip(roots, binaries)]
    campaign.write(out / 'before.json', before)
    inputs = [subprocess.check_output([str(binary), '--dump-inputs'], timeout=campaign.RUN_TIMEOUT_SECONDS) for binary in binaries]
    assert inputs[0] == inputs[1], 'different benchmark requests'
    (out / 'timed-inputs.txt').write_bytes(inputs[0])
    rows = []
    expected = {(family,n,backend,phase,sample)
                for family in ['eligible','fallback-heavy','mixed']
                for n in [1,32,256,4096] for backend in campaign.NAMES
                for phase in ['compile','execute','one-shot'] for sample in range(1,6)}
    # Four fresh processes per revision; each revision sees both backend orders.
    for index, revision in enumerate([0,1,1,0,1,0,0,1]):
        start = snapshot(roots[revision], binaries[revision])
        command = [str(binaries[revision]), '--bench']
        if index % 4 in [1,2]: command.append('--reverse')
        with (out / f'run-{index}.jsonl').open('w') as stdout, (out / f'run-{index}.stderr').open('w') as stderr:
            subprocess.run(command, stdout=stdout, stderr=stderr, timeout=campaign.RUN_TIMEOUT_SECONDS, check=True)
        run = [json.loads(line) for line in (out / f'run-{index}.jsonl').read_text().splitlines()]
        seen = set()
        for row in run:
            key = tuple(row[k] for k in ['family','n','backend','phase','sample'])
            assert row['kind'] == 'timing' and key in expected and key not in seen
            assert all(math.isfinite(row[k]) and row[k] >= 0 for k in ['ns','cpu_ns','bytes'])
            assert 0 <= row['eligible'] <= row['n'] and row['iterations'] >= 1
            seen.add(key)
            row.update(revision=revision, process=index)
        assert seen == expected, 'incomplete benchmark'
        campaign.write(out / f'run-{index}-host.json', {'revision':revision,'start':start,'end':snapshot(roots[revision], binaries[revision])})
        rows += run
    after = [snapshot(root, binary) for root, binary in zip(roots, binaries)]
    campaign.write(out / 'after.json', after)
    for a,b in zip(before,after):
        assert all(a[k] == b[k] for k in ['source','library_tree','source_status','binary_sha256','experiment_files'])
    grouped = collections.defaultdict(lambda: collections.defaultdict(list))
    for row in rows:
        key = tuple(row[k] for k in ['revision','family','n','backend','phase'])
        grouped[key][row['process']].append(row)
    result = []
    for key, processes in grouped.items():
        medians = [statistics.median(row['ns'] for row in process) for process in processes.values()]
        assert len(medians) == 4
        result.append(dict(zip(['revision','family','n','backend','phase'],key)) | {
            'median_process_median_ns':statistics.median(medians),
            'process_medians_ns':medians,
            'bytes':statistics.median(row['bytes'] for process in processes.values() for row in process),
            'eligible':next(iter(processes.values()))[0]['eligible']})
    campaign.write(out / 'summary.json', {'samples':len(rows),'complete':True,'summary':result})
    print('Paired samples:', len(rows))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='fast-simd-compare-1')
    parser.add_argument('baseline_root', type=Path)
    parser.add_argument('baseline_binary', type=Path)
    parser.add_argument('candidate_root', type=Path)
    parser.add_argument('candidate_binary', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    collect([args.baseline_root.resolve(),args.candidate_root.resolve()],
            [args.baseline_binary.resolve(),args.candidate_binary.resolve()],args.output.resolve())
