#!/usr/bin/env python3
"""Replay captured certified portfolio outputs without optional oracle packages.

This checks output identity against independently audited evidence; it does not
replace the original interval audit or make a universal accuracy claim.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess


def wire(records):
    return ''.join('\t'.join(['0:' + r['input']['id'], r['input']['model'],
                             r['input']['side'], *r['input']['inputs'],
                             r['input']['quote'], r['input']['limit']]) + '\n'
                   for r in records)


def verify(records, output):
    expected = {r['input']['id']: r['outputs'] for r in records}
    if not expected or len(expected) != len(records):
        raise ValueError('empty or duplicate reference rows')
    lines = output.splitlines()
    if not lines or lines.pop(0) != 'READY':
        raise ValueError('worker did not initialize')
    observed = {}
    latencies = set()
    stats = 0
    for line in lines:
        fields = line.split('\t')
        if fields[0] == 'STATS':
            if len(fields) != 7:
                raise ValueError('malformed worker statistics')
            stats += 1
            continue
        if len(fields) < 3 or not fields[0].startswith('0:'):
            raise ValueError('malformed worker record')
        row_id, quantity = fields[0][2:], fields[1]
        if row_id not in expected:
            raise ValueError('unexpected worker row')
        if quantity == 'latency':
            if row_id in latencies or len(fields) != 3:
                raise ValueError('duplicate or malformed latency')
            latencies.add(row_id)
        else:
            row = observed.setdefault(row_id, {})
            if quantity in row:
                raise ValueError('duplicate worker quantity')
            row[quantity] = fields[2:]
    if stats != 1 or latencies != set(expected):
        raise ValueError('incomplete worker run')
    if observed != expected:
        raise ValueError('numerical outcomes differ from certified reference run')
    return sum(len(r) - 1 for r in expected.values())  # Exclude admission.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='canonical replay schema 1')
    parser.add_argument('--campaign', type=Path, required=True)
    parser.add_argument('--worker', type=Path, default=Path('_build/default/bench/shadow.exe'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(gzip.decompress(args.campaign.read_bytes()))
    result = subprocess.run([str(args.worker.resolve())], input=wire(report['rows']),
                            text=True, capture_output=True, check=True, timeout=1800)
    checked = verify(report['rows'], result.stdout)
    def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
    evidence = dict(candidate_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                    campaign_sha256=sha(args.campaign), worker_sha256=sha(args.worker),
                    replay_tool_sha256=sha(Path(__file__)), rows=len(report['rows']),
                    matched_price_greek_iv_outcomes=checked,
                    scope='Exact numerical replay of the independently audited captured campaign; timing is not scored.')
    args.output.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence))


if __name__ == '__main__':
    main()
