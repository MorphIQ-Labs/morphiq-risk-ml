#!/usr/bin/env python3
"""Collector failure controls; no timing thresholds run in ordinary CI."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import benchmark_american_allocation as b


class Controls(unittest.TestCase):
    def valid(self):
        return dict(mode='cash', phase='price', calls=3, seconds_per_call=.2,
                    allocated_bytes_per_call=100, minor_collections=1,
                    major_collections=0, heap_words_after=100, live_words_after=10)

    def test_record(self):
        value = self.valid()
        self.assertEqual(b.decode(json.dumps(value), 'cash', 'price', 3), value)
        for raw in ('{', '{}\n{}', '[]', ''):
            with self.assertRaisesRegex(ValueError, 'malformed|must be an object'):
                b.decode(raw, 'cash', 'price', 3)
        for key, bad, reason in [('mode', 'none', 'workload mismatch'),
                                 ('calls', 1, 'workload mismatch'),
                                 ('seconds_per_call', float('nan'), 'invalid benchmark metric'),
                                 ('allocated_bytes_per_call', -1, 'invalid benchmark metric'),
                                 ('minor_collections', -1, 'invalid GC metric')]:
            value = self.valid(); value[key] = bad
            with self.assertRaisesRegex(ValueError, reason):
                b.decode(json.dumps(value), 'cash', 'price', 3)
        value = self.valid(); del value['live_words_after']
        with self.assertRaisesRegex(ValueError, 'invalid GC metric'):
            b.decode(json.dumps(value), 'cash', 'price', 3)

    def test_process_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)/'sample'
            with self.assertRaisesRegex(ValueError, 'failed to start'):
                b.sample([str(Path(directory)/'missing')], out)
            with self.assertRaisesRegex(ValueError, 'child failed'):
                b.sample([sys.executable, '-c', 'print("partial");raise SystemExit(3)'], out)
            self.assertEqual(out.with_suffix('.stdout').read_text(), 'partial\n')
            with self.assertRaisesRegex(ValueError, 'benchmark timeout'):
                b.sample([sys.executable, '-c', 'import time;time.sleep(10)'], out, timeout=.05)
            self.assertTrue(json.loads(out.with_suffix('.resources.json').read_text())['timed_out'])
            raw, usage = b.sample([sys.executable, '-c', 'print("ok")'], out)
            self.assertEqual(raw, 'ok\n')
            self.assertGreater(usage['peak_rss_bytes'], 0)
            self.assertEqual(usage['returncode'], 0)

    def test_coverage_and_criteria(self):
        runs = []
        for mode in b.MODES:
            for phase in b.PHASES:
                for variant in ('baseline', 'candidate'):
                    for round_ in range(5):
                        value = self.valid(); value.update(mode=mode, phase=phase)
                        value['allocated_bytes_per_call'] = 100 if variant == 'baseline' else 5
                        runs.append(dict(variant=variant, round=round_, sample=value))
        summary = b.summarize(runs); b.acceptance(summary)
        with self.assertRaisesRegex(ValueError, 'incomplete or duplicate'):
            b.summarize(runs[:-1])
        with self.assertRaisesRegex(ValueError, 'incomplete or duplicate'):
            b.summarize(runs[:-1]+[runs[-2]])
        with self.assertRaisesRegex(ValueError, 'incomplete acceptance'):
            b.acceptance([])
        summary[1]['allocation_reduction'] = .89
        with self.assertRaisesRegex(ValueError, 'allocation criterion'):
            b.acceptance(summary)
        summary[1]['allocation_reduction'] = .95; summary[1]['speedup'] = .5
        with self.assertRaisesRegex(ValueError, 'latency criterion'):
            b.acceptance(summary)

    def test_source_guards(self):
        with self.assertRaisesRegex(ValueError, 'dirty build source'):
            b.guard(dict(status=' M lib/early_exercise.ml'))
        build = dict(status='', source_sha256={}, binaries={'bench': {'path': 'x', 'sha256': 'a'}})
        for status in ('M  lib/new.ml', ' M lib/a.ml', '?? lib/new.ml'):
            with patch.object(b.subprocess, 'check_output', return_value=status):
                with self.assertRaisesRegex(ValueError, 'staged, unstaged or untracked'):
                    b.guard(build, current=True)
        with patch.object(b, 'sha', return_value='changed'):
            with self.assertRaisesRegex(ValueError, 'binary changed'):
                b.guard(build)


if __name__ == '__main__':
    unittest.main()
