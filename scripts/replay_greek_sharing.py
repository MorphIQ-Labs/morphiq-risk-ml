#!/usr/bin/env python3
"""Manual exact replay of scalar and grouped output paths on retained corpora."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess


def canonical_rows(text):
    lines = text.splitlines()
    if lines.count('READY') != 1 or sum(x.startswith('STATS\t') for x in lines) != 1:
        raise ValueError('incomplete worker envelope')
    return [x for x in lines if x != 'READY' and not x.startswith('STATS\t') and '\tlatency\t' not in x]


def verify(expected, observed):
    if observed != expected:
        raise ValueError('changed, missing, reordered or extra output')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version', action='version', version='greek-sharing-replay-v1')
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    root = Path(__file__).resolve().parents[1]
    report = dict(protocol='greek-sharing-replay-v1', binaries={}, corpora=[])
    for name in ('baseline', 'candidate'):
        binary = getattr(args, name).resolve()
        report['binaries'][name] = dict(path=str(binary), sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
    for corpus in ('shadow-campaign', 'canonical-shadow'):
        path = root / 'docs/evidence' / (corpus + '.json.gz')
        rows = json.loads(gzip.decompress(path.read_bytes()))['rows']
        wire, expected = [], []
        for row in rows:
            i = row['input']
            wire.append('\t'.join([i['id'], i['model'], i['side'], *i['inputs'], i['quote'], i['limit']]))
            for name, fields in row['outputs'].items():
                expected.append('\t'.join([i['id'], name, *fields]))
        runs = []
        for name in ('baseline', 'candidate'):
            for mode in ('scalar', 'many'):
                binary = report['binaries'][name]['path']
                raw = subprocess.check_output([binary] + (['--many'] if mode == 'many' else []),
                                              input='\n'.join(wire) + '\n', text=True)
                observed = canonical_rows(raw)
                verify(expected, observed)
                runs.append(dict(variant=name, mode=mode, sha256=hashlib.sha256(('\n'.join(observed)+'\n').encode()).hexdigest()))
        for bad in (expected[:-1], ['corrupt certificate'] + expected[1:], list(reversed(expected))):
            try:
                verify(expected, bad)
            except ValueError:
                pass
            else:
                raise AssertionError('replay failure control was accepted')
        report['corpora'].append(dict(name=corpus, corpus_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
            inputs=len(rows), outputs=len(expected), runs=runs,
            truncated_corrupted_reordered_rejected=True))
        print(f'{corpus}: {len(rows)} inputs, {len(expected)} identical outputs on all four paths', flush=True)
    report['scope'] = 'Exact retained certificate/outcome compatibility; independent reference results are separate.'
    args.output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
