#!/usr/bin/env python3
"""Compare exact fixture-aligned traces emitted by the ordinary scorers.

Usage: compare_exponential_traces.py BASE_PREFIX CANDIDATE_PREFIX OUTPUT_PREFIX
Prefixes end before -dd.tsv, -european.tsv, etc. Writes a JSON summary and
reproducibly compressed per-row changes. Trace collection must complete first.
No changed digest or baseline agreement is treated as an accuracy witness.
"""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

FIXTURES = ('dd', 'european', 'displaced', 'greeks', 'greek_bits')


def floating(word):
    return struct.unpack('>d', bytes.fromhex(word))[0]


def ordered(word):
    n = int(word, 16)
    return -(n & ((1 << 63)-1)) if n >> 63 else n


def main(before, after, output):
    summary = {'fixtures': {}, 'regions': {}, 'trace_sha256': {}}
    changes = []
    for fixture in FIXTURES:
        paths = [Path(f'{prefix}-{fixture}.tsv') for prefix in (before, after)]
        data = [p.read_text().splitlines() for p in paths]
        assert len(data[0]) == len(data[1]) and data[0], (fixture, 'row mismatch')
        count = classes = signs = max_delta = 0
        for row_number, (old, new) in enumerate(zip(*data), 1):
            row, old = old.split('\t')
            new_row, new = new.split('\t')
            assert row == new_row, (fixture, row_number, 'different inputs')
            fields = row.split()
            if fixture == 'dd':
                region = 'dd '+fields[0]
            elif fixture in ('european', 'displaced'):
                region = ('bachelier' if fields[0] == 'bachelier' else 'black')+' price '+fields[2]
            else:
                region = ('bachelier' if fields[0] == 'bachelier' else 'black')+' '+fields[2]
            stats = summary['regions'].setdefault(region, {'rows': 0, 'changed': 0})
            stats['rows'] += 1
            if old != new:
                count += 1
                stats['changed'] += 1
                changes.append({'fixture': fixture, 'row_number': row_number,
                                'input_reference': row, 'before': old, 'after': new})
            if fixture != 'dd':
                def classify(s):
                    if len(s) != 16: return s
                    v = floating(s)
                    return 'nan' if math.isnan(v) else 'infinite' if math.isinf(v) else 'zero' if v == 0 else 'finite'
                classes += classify(old) != classify(new)
                if classify(old) == classify(new) == 'finite':
                    delta = abs(ordered(old)-ordered(new))
                    max_delta = max(max_delta, delta)
                    signs += (ordered(old) < 0) != (ordered(new) < 0)
                    stats['max_ulp_movement'] = max(stats.get('max_ulp_movement', 0), delta)
                # Scalar fixtures carry the correctly-rounded reference. The
                # extra-bit Greek fixture is scored separately by its existing
                # expansion-error certificate, never by its first mantissa word.
                if fixture != 'greek_bits' and (fixture != 'greeks' or fields[3] in ('resolved','single_route')):
                    ref = fields[-1]
                    if classify(ref) in ('finite','zero'):
                        for label, value in [('before', old), ('after', new)]:
                            if classify(value) in ('finite','zero'):
                                key = 'worst_'+label+'_ulp'
                                stats[key] = max(stats.get(key, 0), abs(ordered(value)-ordered(ref)))
        summary['fixtures'][fixture] = {'rows': len(data[0]), 'changed': count}
        if fixture != 'dd':
            summary['fixtures'][fixture].update(class_changes=classes, sign_changes=signs, max_ulp_movement=max_delta)
        for label, path in zip(('before', 'after'), paths):
            summary['trace_sha256'][f'{label}-{fixture}'] = hashlib.sha256(path.read_bytes()).hexdigest()
    Path(output+'.json').write_text(json.dumps(summary, indent=2, sort_keys=True)+'\n')
    with open(output+'-changes.json.gz', 'wb') as raw:
        with gzip.GzipFile(fileobj=raw, mode='wb', mtime=0, filename='') as compressed:
            compressed.write((json.dumps(changes, separators=(',',':'))+'\n').encode())
    print(json.dumps(summary['fixtures'], indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='compare_exponential_traces 1')
    parser.add_argument('baseline_prefix')
    parser.add_argument('candidate_prefix')
    parser.add_argument('output_prefix')
    args = parser.parse_args()
    main(args.baseline_prefix, args.candidate_prefix, args.output_prefix)
