"""Check lane admission without running expensive mutation campaigns."""

import subprocess
import sys
import unittest
from pathlib import Path

EXE = str(Path(sys.argv.pop(1)).resolve())


def invoke(*args):
    return subprocess.run([EXE, *args], capture_output=True, text=True, timeout=10)


class SelectionTests(unittest.TestCase):
    def test_guard_failure_controls(self):
        result = invoke("--self-test")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mutation guard controls pass", result.stdout)

    def listing(self, *args):
        result = invoke(*args, "--list")
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = [line.split()[0] for line in result.stdout.splitlines()]
        self.assertEqual(len(ids), len(set(ids)))
        return set(ids)

    def test_core_is_a_strict_reviewed_subset(self):
        full = self.listing()
        core = self.listing("--core")
        self.assertEqual(len(full), 176)
        self.assertEqual(core, {
            "split-root-nonoverlap", "dd-scale-nonoverlap",
            "reference-expansion", "scaled-exp-prefactor", "certified-rounding-cell",
            "greeks-theta-dd", "bachelier-theta-dd",
        })
        self.assertLess(core, full)

    def test_surviving_probe_is_separate(self):
        self.assertEqual(self.listing("--probe"), {"intrinsic-terms", "iv-maximum-error",
            "bachelier-iv-quantum", "iv-rounded-bound", "iv-beta-bar", "iv-ln-beta"})
        self.assertNotIn("intrinsic-terms", self.listing())

    def test_invalid_selection_fails_before_baseline(self):
        for args in [
            ["--cor"], ["--core", "quotient-remainder"],
            ["--core", "--probe"], ["--probe", "--core"],
            ["intrinsic-terms"], ["--core", "nonexistent"],
        ]:
            with self.subTest(args=args):
                result = invoke(*args)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("unknown mutants:", result.stderr)
                self.assertNotIn("baseline", result.stdout)


if __name__ == "__main__":
    unittest.main()
