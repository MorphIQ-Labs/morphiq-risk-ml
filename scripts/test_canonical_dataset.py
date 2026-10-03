#!/usr/bin/env python3
"""Captured workload coverage and rejection controls; no optional dependencies."""
import copy
from collections import Counter
from pathlib import Path
import unittest

from canonical_dataset import digest_rows, load_dataset, validate_dataset

ROOT = Path(__file__).resolve().parent.parent


class DatasetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data, cls.rows = load_dataset(ROOT / 'docs/evidence/canonical-portfolio.json.gz')

    def test_coverage(self):
        self.assertEqual(len(self.rows), 720)
        self.assertEqual(Counter((r['model'], r['side']) for r in self.rows),
                         {(m, s): 90 for m in ('bsm', 'black76', 'displaced', 'bachelier')
                          for s in ('call', 'put')})
        for model in ('bsm', 'black76', 'displaced', 'bachelier'):
            cells = Counter((r['scenario'], r['design']['moneyness'],
                             r['design']['total_deviation'], r['side'])
                            for r in self.rows if r['model'] == model)
            self.assertEqual(set(cells), {(f'maturity-{t}', m, v, s) for t in range(6)
                                         for m in (-4, -1, 0, 1, 4) for v in (.1, .5, 1)
                                         for s in ('call', 'put')})
            self.assertTrue(all(n == 1 for n in cells.values()))

    def test_invalid_inputs_rejected_even_with_updated_hash(self):
        mutations = [lambda r: r.update(id='bad\trow'),
                     lambda r: r.update(id=self.rows[1]['id']),
                     lambda r: r.update(model='other'),
                     lambda r: r.update(side='CALL'),
                     lambda r: r.update(quote='7ff0000000000000'),
                     lambda r: r.update(quote='bff0000000000000'),
                     lambda r: r.update(limit='3ff0000000000000'),
                     lambda r: r.update(inputs=r['inputs'][:6]),
                     lambda r: r['inputs'].__setitem__(0, '7ff8000000000000'),
                     lambda r: r.update(quantity=True),
                     lambda r: r.update(quantity=100001),
                     lambda r: r.update(currency='EUR'),
                     lambda r: r.update(category='stress')]
        for change in mutations:
            data = copy.deepcopy(self.data)
            change(data['rows'][0])
            data['rows_sha256'] = digest_rows(data['rows'])
            with self.assertRaises(ValueError):
                validate_dataset(data)

    def test_tamper_and_truncation_rejected(self):
        data = copy.deepcopy(self.data)
        data['rows'][0]['quote'] = '0000000000000000'
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            validate_dataset(data)
        data = copy.deepcopy(self.data)
        data['rows'].pop()
        with self.assertRaises(ValueError):
            validate_dataset(data)


if __name__ == '__main__':
    unittest.main()
