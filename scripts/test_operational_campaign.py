#!/usr/bin/env python3
"""Operational evidence controls: corrupt output, missing targets, child cleanup."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from operational_campaign import decode, record, run_case, summarize, validate

RUNNER = Path(sys.argv.pop(1)).resolve()
CONFIG = json.loads(Path(sys.argv.pop(1)).read_text())


def small(mode='fast'):
    config = copy.deepcopy(CONFIG)
    config.update(repetitions=1, warmups=0, requests=1, timeout_seconds=15)
    case = config['cases'][0]
    case.update(positions=4, days=[0,7], mode=mode, workers=2, tile_rows=2,
                buffer_slots=8, concurrency=2)
    config['cases'] = [case]
    return config, case


class Controls(unittest.TestCase):
    def test_specification_rejects_ambiguous_or_invalid_targets(self):
        for raw in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}'):
            with self.assertRaises(ValueError):
                decode(raw)
        config, _ = small()
        validate(config)
        for field, value in [('requests', 0), ('warmups', True), ('timeout_seconds', float('inf'))]:
            bad = copy.deepcopy(config)
            bad[field] = value
            with self.assertRaises(ValueError):
                validate(bad)
        for field, value in [('name','../escape'), ('positions',True), ('workers',0), ('cancel_after_ms',-1)]:
            bad = copy.deepcopy(config)
            bad['cases'][0][field] = value
            with self.assertRaises(ValueError):
                validate(bad)
        bad = copy.deepcopy(config)
        bad['cases'][0]['requirements']['warm_p95_ms'] = -1
        with self.assertRaises(ValueError):
            validate(bad)

    def real(self, config, case):
        with tempfile.TemporaryDirectory() as tmp:
            return run_case(RUNNER, case, config, Path(tmp)/'run')

    def test_fast_reuse_and_recompile_replay(self):
        config, case = small()
        case['sink'] = 'digest'
        a = self.real(config, case)
        case['policy'] = 'recompile'
        b = self.real(config, case)
        self.assertTrue(a['complete'] and b['complete'])
        self.assertEqual(a['checks'][0]['result']['digest'], b['checks'][0]['result']['digest'])
        for run in (a,b):
            for wave in run['waves']:
                for response in wave['responses']:
                    self.assertEqual(response['result']['served'], 8)
                    self.assertEqual(response['result']['errors'], {})
            self.assertTrue(all(x['returncode']==0 and x['peak_rss_bytes']>0 for x in run['children']))
        summary = summarize(case, [b])
        self.assertEqual(summary['criteria']['warm_p95_ms']['status'], 'pending')
        case['requirements']['warm_p95_ms'] = 0
        self.assertEqual(summarize(case, [b])['criteria']['warm_p95_ms']['status'], 'fail')
        # Missing and nonfinite metrics, wrong counts and fabricated success fail.
        original = b['waves'][0]['responses'][0]['result']
        for key, value in [('served',0), ('rows',0), ('request_ms',float('nan')), ('stop','complete-but-partial')]:
            bad = dict(original, **{key:value})
            with self.assertRaises(ValueError):
                record(bad, 'request', case)
        bad = dict(original)
        del bad['cancel_issued_ms']
        with self.assertRaises(ValueError):
            record(bad, 'request', case)

    def test_certified_boundaries_remain_failures(self):
        config, case = small('certified')
        case.update(days=[365,366], outputs='all', buffer_slots=88, sink='digest')
        result = self.real(config, case)['waves'][1]['responses'][0]['result']
        self.assertEqual(result['rows'], 8)
        self.assertEqual(result['calculations'], 88)
        self.assertEqual(result['served'], 4)
        self.assertEqual(result['errors'], {'post_expiry':44, 'unsupported':40})

    def test_cancellation_and_unobserved_cancel_are_not_success_evidence(self):
        config, case = small()
        case.update(positions=2048, cancel_after_ms=0, tile_rows=256, buffer_slots=512)
        result = self.real(config, case)
        summary = summarize(case, [result])
        self.assertEqual(summary['cancelled'], 2)
        self.assertEqual(summary['requests_per_second'], 0)
        self.assertGreater(summary['uncommitted_calculations'], 0)
        self.assertGreaterEqual(summary['max_cancel_observation_ms'], 0)
        config, case = small()
        result = self.real(config, case)
        case['requirements']['max_cancel_observation_ms'] = 1
        self.assertEqual(summarize(case, [result])['criteria']['max_cancel_observation_ms']['status'], 'pending')

    def test_eof_truncation_timeout_and_failed_spawn_preserve_partial_run(self):
        config, case = small()
        case['concurrency'] = 1
        config['timeout_seconds'] = .15
        for name, body in [('eof', 'pass'), ('truncated', 'print("{",flush=True)'),
                           ('timeout','import time\ntime.sleep(30)')]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                fake = root/'child'
                fake.write_text('#!/usr/bin/env python3\n'+body+'\n')
                fake.chmod(0o700)
                with self.assertRaises(ValueError):
                    run_case(fake, case, config, root/'run')
                record = json.loads((root/'run/run.json').read_text())
                self.assertFalse(record['complete'])
                self.assertEqual(len(record['children']), 1)
                self.assertTrue((root/'run/client-0.jsonl').exists())
                if name == 'timeout':
                    self.assertEqual(record['children'][0]['returncode'], -9)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            with self.assertRaises(FileNotFoundError):
                run_case(root/'missing', case, config, root/'run')
            self.assertFalse(json.loads((root/'run/run.json').read_text())['complete'])

    def test_existing_destination_and_cli(self):
        config, case = small()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'sentinel').write_text('keep')
            with self.assertRaises(FileExistsError):
                run_case(RUNNER, case, config, root)
            self.assertEqual((root/'sentinel').read_text(), 'keep')
        for args, expected in [(['--help'],0), (['--version'],0), (['--size','0'],2),
                               (['--mode','bad'],2), (['--','unexpected'],2)]:
            child = subprocess.run([str(RUNNER),*args],capture_output=True,timeout=15)
            self.assertEqual(child.returncode, expected)


if __name__ == '__main__':
    unittest.main()
