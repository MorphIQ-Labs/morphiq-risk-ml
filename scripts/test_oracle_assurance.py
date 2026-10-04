"""Ordinary dependency/input failure controls; no optional numerical packages."""
import gzip
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from fixture_catalog import blake, catalog
from oracle_challenge import bits, minimize, run_checked

EXE = str(Path(sys.argv.pop(1)).resolve())
FIXTURE = Path(sys.argv.pop(1)).resolve()


class Assurance(unittest.TestCase):
    def test_real_scorer_input_gate(self):
        data = FIXTURE.read_text()
        rows = data.splitlines(keepends=True)
        first = next(i for i, row in enumerate(rows) if not row.startswith('#'))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'input.txt'
            # Establish that the exact executable accepts its unmodified input.
            result = subprocess.run([EXE, str(FIXTURE)], capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            faults = [data[:-20], ''.join(rows[:first] + rows[first+1:]),
                      data + rows[first], data.replace(rows[first], 'broken\n', 1), '',
                      ''.join(rows[:first] + [rows[first+1], rows[first]] + rows[first+2:])]
            for fault in faults:
                path.write_text(fault)
                result = subprocess.run([EXE, str(path)], capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 3, result.stderr)
                self.assertIn(b'REFERENCE INPUT ERROR', result.stderr)
            path.unlink()
            result = subprocess.run([EXE, str(path)], capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 3)

    def test_catalog(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'fixtures').mkdir()
            raw = b'a 0000\nb 0001\n'
            archive = gzip.compress(raw)
            path = root/'fixtures'/'sample.txt.gz'
            path.write_bytes(archive)
            manifest = f'sample gen.py hash hash 1.3.0 3.14 2 {blake(archive)}\n'
            (root/'MANIFEST').write_text(manifest)
            self.assertEqual(catalog(root), {'sample': (2, blake(raw))})
            for fault in ['', manifest*2, manifest.replace(' 2 ', ' 3 '), manifest.replace(blake(archive), '0'*64)]:
                (root/'MANIFEST').write_text(fault)
                with self.assertRaises(ValueError): catalog(root)
            (root/'MANIFEST').write_text(manifest)
            path.write_bytes(archive[:-5])
            with self.assertRaises(ValueError): catalog(root)

    def test_reference_execution_failures(self):
        for command, timeout in [
                (['/missing/oracle/worker'], 1),
                ([sys.executable, '-c', 'raise SystemExit(1)'], 1),
                ([sys.executable, '-c', 'print("truncated {")'], 1),
                ([sys.executable, '-c', 'print(\'{"status":"failure"}\')'], 1),
                ([sys.executable, '-c', 'import time; time.sleep(10)'], .05)]:
            self.assertEqual(run_checked(command, timeout)['status'], 'tool_error')
        value = {'status': 'unresolved', 'reason': 'wide interval'}
        result = run_checked([sys.executable, '-c', f'print({json.dumps(value)!r})'], 1)
        self.assertEqual(result, value)

    def test_minimizer_does_not_accept_uncertainty(self):
        original = list(map(bits, [128., 2.**-46, 4., 0., 0., 1e-4, 0.]))
        calls = []
        def assess(words):
            calls.append(words)
            return dict(status='failure' if words == original else 'unresolved', inputs=words)
        report = minimize(original, assess)
        self.assertEqual(len(calls), 9)
        self.assertEqual(report['minimized']['inputs'], original)
        self.assertTrue(all(not a['accepted'] for a in report['attempts']))
        self.assertTrue(all(a['result']['status'] == 'unresolved' for a in report['attempts']))
        report = minimize(original, lambda words: dict(status='tool_error', inputs=words))
        self.assertFalse(report['complete'])


if __name__ == '__main__': unittest.main()
