#!/usr/bin/env python3
"""Failure controls for the bounded planner campaign launcher and source wrapper."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from planner_stress import run


class Controls(unittest.TestCase):
    def test_success_and_rejections(self):
        self.assertEqual(run([sys.executable, '-c', 'print("{\\\"ok\\\": true}")'], 5), {'ok': True})
        with self.assertRaises(RuntimeError):
            run([sys.executable, '-c', 'raise SystemExit(1)'], 5)
        with self.assertRaises(ValueError):
            run([sys.executable, '-c', 'print("truncated{")'], 5)
        with self.assertRaises(OSError):
            run(['/nonexistent/morphiq-planner-worker'], 5)

    def test_deadline_reaps_child(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            run([sys.executable, '-c', 'import time; time.sleep(30)'], 0.05)

    def test_source_wrapper_refuses_missing_or_ambiguous_site(self):
        generator = Path(__file__).with_name('instrument_planner.py')
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'planner.ml'
            hint = 'Bachelier.Fast_middle.may_prepare'
            execute = 'let execute t ~workers ~cancellation ~sink ='
            for text, site in [('', hint), (hint + '\n' + hint, hint),
                               (hint, execute), (hint + '\n' + (execute + '\n') * 2, execute)]:
                source.write_text(text)
                result = subprocess.run([sys.executable, str(generator), str(source)],
                                        capture_output=True, text=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
                self.assertIn('planner instrumentation site missing/ambiguous: ' + site, result.stderr)


if __name__ == '__main__':
    unittest.main()
