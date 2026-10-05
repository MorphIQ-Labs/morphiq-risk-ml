#!/usr/bin/env python3
"""Execute and score American estimates; unavailable is never an accuracy pass."""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
import struct
import tempfile
from american_reference_data import FIELDS, decode, score_price, strict_json, require, capture

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'docs/evidence/american-references'


def request_rows(cases, mode):
    result = []
    for case in cases:
        epsilon = decode(case['epsilon'])
        if mode == 'quarter':
            epsilon /= 4
        elif mode == 'loose':
            epsilon = max(decode(case['inputs']['spot']), decode(case['inputs']['strike'])) / 100
        # Configuration requires a positive tolerance; zero-scale scoring remains exact.
        limit = epsilon if epsilon else 2**-16
        result.append(' '.join([case['id'], case['side'],
                                *[case['inputs'][k] for k in FIELDS],
                                struct.pack('>d', limit).hex()]))
    return '\n'.join(result)+'\n'


def classify(raw, cases, references, mode):
    lines = raw.splitlines()
    require(len(lines) == len(cases), 'missing or extra runtime rows')
    result = []
    for line, case, ref in zip(lines, cases, references):
        fields = line.split('\t')
        require(len(fields) == 4, 'malformed runtime row')
        name, status, value, detail = fields
        require(name == case['id'] == ref['id'], 'runtime row identity/order')
        require(status in ('estimated', 'unavailable'), 'runtime outcome')
        require(bool(detail), 'missing runtime method/failure detail')
        entry = dict(id=name, outcome=status, detail=detail,
                     reference_status=ref['reference']['status'])
        if status == 'unavailable':
            require(value == '-', 'failure exposes usable price')
            require(detail.startswith(('resource:', 'arithmetic:', 'accuracy:', 'nonconvergence:',
                                       'cancelled', 'unrepresentable')), 'unknown failure')
            entry['comparison'] = {'status': 'runtime_unavailable'}
        else:
            number = float.fromhex(value)
            require(math.isfinite(number) and number >= 0, 'nonfinite or negative runtime price')
            epsilon = decode(case['epsilon'])
            entry['value'] = value
            entry['primary_comparison'] = score_price(ref['reference'], number, epsilon)
            if mode == 'quarter':
                epsilon /= 4
            elif mode == 'loose':
                epsilon = max(decode(case['inputs']['spot']), decode(case['inputs']['strike']))/100
            entry['comparison'] = score_price(ref['reference'], number, epsilon)
        result.append(entry)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='american-runtime-campaign-v1')
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--mode', choices=('primary', 'quarter', 'loose'), default='primary')
    parser.add_argument('--refined', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.output:
        args.output.mkdir(exist_ok=False, parents=True)
    cases = strict_json((BASE/'cases-v1.json').read_text())['rows']
    references = strict_json((BASE/'references-v1.json').read_text())['rows']
    payload = request_rows(cases, args.mode)
    with tempfile.TemporaryDirectory(prefix='american-runtime-') as temp:
        path = Path(temp)/'input.txt'
        path.write_text(payload)
        cmd = [str(args.executable.resolve()), '--refined-corpus' if args.refined else '--corpus', str(path)]
        destination = args.output if args.output else Path(temp)
        (destination/'input.txt').write_text(payload)
        raw = capture(cmd, '', destination/'stdout.tsv', timeout=1200)
    rows = classify(raw, cases, references, args.mode)
    counts = Counter(r['comparison']['status'] for r in rows)
    # Analytical boundaries are an actual delivered capability, not optional
    # coverage. An all-fail/no-work implementation must not pass this gate.
    for case, row, reference in zip(cases, rows, references):
        if reference['reference'].get('kind') == 'analytic_interval':
            require(row['comparison']['status'] == 'pass', 'analytical capability unavailable: '+case['id'])
    require(counts['fail'] == 0, 'independent American accuracy failure')
    report = dict(schema='american-runtime-campaign-v1', complete=True,
                  mode=args.mode, configuration='refined' if args.refined else 'initial',
                  counts=dict(counts), rows=rows)
    if args.output:
        (args.output/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k != 'rows'}, sort_keys=True))


if __name__ == '__main__':
    main()
