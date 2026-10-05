#!/usr/bin/env python3
"""Offline reference/scorer failure controls; no optional numerical packages."""
import copy
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest

from american_reference_data import (BASE, capture, decode, first_index, inputs,
    parse_raw, score_price, strict_json, validate_corpus, validate_fixture, verify_manifest)
from freeze_american_cases import corpus as frozen_corpus
from generate_american_references import exact_extension


class Protocol(unittest.TestCase):
    def setUp(self):
        self.expected = {('case', 512)}
        self.raw = 'case\t512\tfinite\t0x1p+0\t0x1p+0\t0x1p+0\tcrr\n'
        self.ref = dict(status='resolved', kind='analytic_interval', lower='1', upper='1')

    def test_complete_raw(self):
        self.assertEqual(parse_raw(self.raw, self.expected)[('case',512)]['american'], '0x1p+0')

    def test_missing_duplicate_and_unexpected(self):
        for raw, error in [('', 'missing output row'), (self.raw*2, 'duplicate output row'),
                           (self.raw.replace('case','other'),'unexpected output row')]:
            with self.subTest(error=error), self.assertRaisesRegex(ValueError,error):
                parse_raw(raw,self.expected)

    def test_truncation_and_nonfinite(self):
        for raw,error in [(self.raw.rsplit('\t',1)[0], 'truncated'),
                          (self.raw.replace('0x1p+0','nan',1),'nonfinite output'),
                          (self.raw.replace('finite','unavailable'), 'status/value mismatch')]:
            with self.subTest(error=error), self.assertRaisesRegex(ValueError,error):
                parse_raw(raw,self.expected)

    def test_nonfinite_and_duplicate_json(self):
        for value,error in [('{"x":NaN}','nonfinite JSON'),
                            ('{"x":1,"x":2}','duplicate JSON key')]:
            with self.assertRaisesRegex(ValueError,error): strict_json(value)

    def test_incorrect_price_cannot_pass(self):
        self.assertEqual(score_price(self.ref,1.,F(1,100))['status'],'pass')
        self.assertEqual(score_price(self.ref,2.,F(1,100))['status'],'fail')
        with self.assertRaisesRegex(ValueError,'nonfinite candidate'):
            score_price(self.ref,float('inf'),F(1,100))

    def test_unresolved_and_wide_cannot_pass(self):
        self.assertEqual(score_price(dict(status='unresolved'),1.,F(1,100))['status'],
                         'unresolved_reference')
        self.ref['upper']='2'
        self.assertEqual(score_price(self.ref,1.,F(1,100))['status'],'reference_too_wide')

    def test_delayed_opening_uses_exact_ceil(self):
        row=next(r for r in frozen_corpus()['rows'] if r['id']=='put-delayed')
        self.assertEqual(first_index(row,513),257)
        self.assertEqual(first_index(row,512),256)

    def test_invalid_input_and_changed_tolerance(self):
        data=frozen_corpus()
        data['rows'][0]['inputs']['spot']='7ff0000000000000'
        with self.assertRaisesRegex(ValueError,'nonfinite input word'): validate_corpus(data)
        data=frozen_corpus();data['rows'][0]['epsilon']='3ff0000000000000'
        with self.assertRaisesRegex(ValueError,'changed epsilon policy'): validate_corpus(data)

    def test_incorrect_extension_expectation(self):
        case=copy.deepcopy(frozen_corpus()['extension_cases'][0])
        self.assertEqual(exact_extension(case)['value'],'10')
        case['exact']='11'
        with self.assertRaisesRegex(ValueError,'incorrect extension expectation'): exact_extension(case)

    def test_process_exit_retains_partial_output(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'raw'
            with self.assertRaisesRegex(ValueError,'runner exit failure'):
                capture([sys.executable,'-c','print("partial"); raise SystemExit(7)'], '',path,5)
            self.assertEqual(path.read_text(),'partial\n')

    def test_startup_and_timeout_are_not_passes(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'raw'
            with self.assertRaisesRegex(ValueError,'runner startup failure'):
                capture([str(Path(temp)/'absent')], '',path,1)
            with self.assertRaisesRegex(ValueError,'runner timeout'):
                capture([sys.executable,'-c','import time; time.sleep(5)'], '',path,.1)

    def test_successful_but_truncated_process_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            raw=capture([sys.executable,'-c','print("case\\t512")'],'',Path(temp)/'raw',5)
            with self.assertRaisesRegex(ValueError,'truncated'): parse_raw(raw,self.expected)

    def test_existing_campaign_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'failure.json'
            path.write_text('prior evidence')
            generator = Path(__file__).with_name('generate_american_references.py')
            result = subprocess.run([sys.executable,str(generator),'--lattice','absent',
                '--quantlib','absent','--output',temp],capture_output=True,text=True)
            self.assertEqual(result.returncode,2)
            self.assertIn('output directory already exists',result.stderr)
            self.assertEqual(path.read_text(),'prior evidence')
            self.assertEqual(list(Path(temp).iterdir()),[path])

    def test_source_or_fixture_corruption_fails_provenance(self):
        for name in ('scripts/generator.py','docs/fixture.json'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                root=Path(temp);base=root/'evidence';base.mkdir()
                target=root/name;target.parent.mkdir(parents=True);target.write_text('original')
                manifest=dict(sha256={name:hashlib.sha256(target.read_bytes()).hexdigest()})
                (base/'manifest.json').write_text(json.dumps(manifest))
                target.write_text('corrupt')
                with self.assertRaisesRegex(ValueError,'fixture provenance mismatch'):
                    verify_manifest(base,root)


class Fixture(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.corpus=strict_json((BASE/'cases-v1.json').read_text())
        cls.fixture=strict_json((BASE/'references-v1.json').read_text())

    def test_frozen_corpus_reproduces(self):
        self.assertEqual(self.corpus,frozen_corpus())

    def test_provenance_and_complete_schema(self):
        self.assertEqual(verify_manifest(),len(self.corpus['rows']))

    def test_missing_duplicate_rows(self):
        for rows in (self.fixture['rows'][:-1], self.fixture['rows']+[self.fixture['rows'][0]]):
            bad=copy.deepcopy(self.fixture);bad['rows']=rows
            with self.assertRaisesRegex(ValueError,'fixture row identity'):
                validate_fixture(self.corpus,bad)

    def test_wrong_comparison_expectation(self):
        bad=copy.deepcopy(self.fixture)
        row=next(r for r in bad['rows'] if r['reference']['status']=='resolved')
        row['canonical'][0]['outcome'].update(status='finite',american=float(1e12).hex())
        row['canonical'][0]['comparison']['status']='pass'
        with self.assertRaisesRegex(ValueError,'incorrect comparison expectation'):
            validate_fixture(self.corpus,bad)

    def test_wrong_reference_width(self):
        bad=copy.deepcopy(self.fixture)
        row=next(r for r in bad['rows'] if r['reference']['status']=='resolved')
        row['reference'].update(lower='0',upper='1000000000')
        with self.assertRaisesRegex(ValueError,'reference width exceeds policy'):
            validate_fixture(self.corpus,bad)

    def test_all_cash_expectations_replay(self):
        expected = {x['id']: x for x in self.fixture['extensions']}
        self.assertEqual(set(expected), {x['id'] for x in self.corpus['extension_cases']})
        for case in self.corpus['extension_cases']:
            if case['kind'] == 'zero-carry-cash':
                self.assertEqual(exact_extension(case), expected[case['id']])

    def test_tighter_comparisons_are_recomputed(self):
        for case, row in zip(self.corpus['rows'], self.fixture['rows']):
            for comparison in row['canonical']:
                if comparison['outcome']['status'] == 'finite':
                    actual = score_price(row['reference'],
                        float.fromhex(comparison['outcome']['american']), decode(case['epsilon'])/4)
                    self.assertEqual(actual, comparison['epsilon_quarter_comparison'])
                else:
                    self.assertEqual(comparison['epsilon_quarter_comparison']['status'], 'excluded')

    def test_missing_canonical_level(self):
        bad=copy.deepcopy(self.fixture);bad['rows'][0]['canonical'].pop()
        with self.assertRaisesRegex(ValueError,'canonical level identity'):
            validate_fixture(self.corpus,bad)


if __name__=='__main__':
    unittest.main()
