#!/usr/bin/env python3
"""Bind exact terminal references to their generator and runtime transcription."""
import copy
import hashlib
import json
from fractions import Fraction as F
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / 'docs/evidence/american-forward-optimization/reference-v1'


def check(data, text, generator):
    assert data['generator_sha256'] == hashlib.sha256(generator).hexdigest(), 'generator identity'
    assert data['bits'] == [256, 512], 'precision levels'
    rows = data['rows']
    assert len(rows) == 40 and len({p['id'] for p in rows}) == 40, 'case inventory'
    lines = []
    for p in rows:
        intervals = [[F(v) for v in pair] for pair in p['precision_intervals']]
        assert len(intervals) == 2 and all(lo <= hi for lo, hi in intervals), 'interval order'
        assert max(lo for lo, hi in intervals) <= min(hi for lo, hi in intervals), 'precision overlap'
        assert F(p['lower']) == min(lo for lo, hi in intervals), 'lower hull'
        assert F(p['upper']) == max(hi for lo, hi in intervals), 'upper hull'
        for key in ['rates', 'yields', 'vols']:
            expected = [(1., p[key][0][1])]
            if p['piecewise']:
                split, second = {'rates': (.5, -.02), 'yields': (.25, .04), 'vols': (.75, .35)}[key]
                expected = [(split, p[key][0][1]), (1. - split, second)]
            assert p[key] == [list(x) for x in expected], 'curve transcription'
        values = [p['id'], p['phase'], 'piecewise' if p['piecewise'] else 'constant',
                  *[float(p[k]).hex() for k in ['s', 'k']],
                  *[float(p[k][0][1]).hex() for k in ['rates', 'yields', 'vols']],
                  ','.join(x.hex() for x in p['cash']), p['lower'], p['upper']]
        lines.append(' '.join(values))
    assert text == '\n'.join(lines) + '\n', 'runtime transcription'


def main():
    data = json.loads((REF / 'references.json').read_text())
    text = (REF / 'references.tsv').read_text()
    generator = (ROOT / 'scripts/generate_terminal_cash.py').read_bytes()
    check(data, text, generator)
    controls = []
    controls.append((data, text, generator + b'\n', 'generator identity'))
    controls.append((data, text[:-1], generator, 'runtime transcription'))
    changed = copy.deepcopy(data)
    changed['rows'][0]['lower'] = '-1'
    controls.append((changed, text, generator, 'lower hull'))
    changed = copy.deepcopy(data)
    changed['rows'][0]['precision_intervals'][1] = ['-2', '-1']
    controls.append((changed, text, generator, 'precision overlap'))
    changed = copy.deepcopy(data)
    changed['rows'][0]['rates'][0][0] = .5
    controls.append((changed, text, generator, 'curve transcription'))
    for args in controls:
        try:
            check(*args[:3])
        except AssertionError as error:
            assert str(error) == args[3], (str(error), args[3])
        else:
            raise AssertionError('accepted invalid fixture: ' + args[3])
    print('40 exact-input references bound to generator and TSV; five rejection controls pass')


if __name__ == '__main__':
    main()
