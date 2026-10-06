#!/usr/bin/env python3
"""Small collector rejection controls; the timing campaign remains manual."""
import copy
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import measure_american_workloads as campaign

BINARY = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else None
DIGEST = 'a' * 64


def fixture(phase='check', case='call', size=1):
    rows = 1 if size == 1 else 8
    lines = [f'ROW\t{i}\t{DIGEST}\testimated' for i in range(rows)]
    lines += [f'CHECK\t{case}\t{size}\t{rows}\t{rows}\t0\t0\t{DIGEST}']
    if phase in ('time', 'memory'):
        for method, tile, workers in sorted(campaign.methods(size)):
            sample = '0.1\t0.1\t0.01' if phase == 'time' else '1000\t100\t1\t2'
            lines.append(f'{phase.upper()}\t{method}\t{tile}\t{workers}\t{sample}')
    if phase == 'time':
        lines += [f'COMPILE\t{method}\t{tile}\t0.001' for method, tile in
                  [('batch', 0)] + [('planner', t) for t in ((1,) if size == 1 else (1, 2, 4))]]
    if phase == 'cancel':
        lines += [f'CANCEL\t{t}\t{w}\tcancelled\t0.006\t0.001\t0\t0'
                  for t, w in campaign.configurations(size)]
    return '\n'.join(lines) + '\n'


class Controls(unittest.TestCase):
    def test_complete_matrices(self):
        for size in (1, 4):
            for phase in ('check', 'time', 'memory'):
                campaign.parse(fixture(phase, size=size), 'call', size, phase)
        campaign.parse(fixture('cancel', 'flat', 4), 'flat', 4, 'cancel')

    def test_parser_rejections(self):
        base = fixture('time')
        trials = [
            (base + 'garbage\n', 'malformed/unknown record'),
            (base.replace('ROW\t0', 'ROW\t2'), 'invalid/duplicate row'),
            (base + base.splitlines()[0] + '\n', 'invalid/duplicate row'),
            (base.replace('\testimated', '\tunknown'), 'invalid status classification'),
            (base.replace('\t1\t0\t0\t' + DIGEST, '\t0\t1\t0\t' + DIGEST), 'classification totals differ'),
            ('\n'.join(base.splitlines()[1:]), 'incomplete replay evidence'),
            ('\n'.join(x for x in base.splitlines() if not x.startswith('TIME\tbatch')), 'incomplete measurement matrix'),
            ('\n'.join(x for x in base.splitlines() if not x.startswith('COMPILE\tbatch')), 'incomplete compilation matrix'),
            (base + next(x for x in base.splitlines() if x.startswith('TIME')) + '\n', 'invalid/duplicate method'),
        ]
        for value in ('nan', 'inf', '-1'):
            trials.append((base.replace('\t0.1\t0.1', '\t' + value + '\t0.1'), 'invalid numeric measurement'))
        campaign.parse(base.replace('\t0.1\t0.1', '\t0\t0.1'), 'call', 1, 'time')
        for text, reason in trials:
            with self.subTest(reason=reason, text=text), self.assertRaisesRegex(ValueError, reason):
                campaign.parse(text, 'call', 1, 'time')
        with self.assertRaisesRegex(ValueError, 'inconsistent allocation scope'):
            campaign.parse(fixture('memory').replace('1000\t100', '10\t100'), 'call', 1, 'memory')

    def test_refusals_are_not_successes(self):
        text = fixture().replace('estimated', 'accuracy-not-demonstrated').replace(
            '\t1\t0\t0\t' + DIGEST, '\t0\t1\t0\t' + DIGEST)
        parsed = campaign.parse(text, 'call', 1, 'check')
        self.assertEqual(parsed['check']['accepted'], 0)
        self.assertEqual(parsed['check']['failed'], 1)

    def test_changed_replay(self):
        before = campaign.parse(fixture(), 'call', 1, 'check')
        after = copy.deepcopy(before)
        after['rows'][0]['digest'] = 'b' * 64
        with self.assertRaisesRegex(ValueError, 'changed complete replay or status'):
            campaign.same_replay(before, after)

    def test_cancellation(self):
        text = fixture('cancel', 'flat', 4)
        completed = text.replace('cancelled\t0.006\t0.001\t0\t0', 'complete\t0.006\t-0.001\t8\t8')
        campaign.parse(completed, 'flat', 4, 'cancel')
        with self.assertRaisesRegex(ValueError, 'cancelled before issuance'):
            campaign.parse(text.replace('\t0.001\t0\t0', '\t-0.001\t0\t0'), 'flat', 4, 'cancel')
        with self.assertRaisesRegex(ValueError, 'invalid cancellation prefix'):
            campaign.parse(text.replace('\t0\t0\n', '\t1\t0\n'), 'flat', 4, 'cancel')

    def test_child_failures_and_reaping(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def run(code, timeout=5):
                return campaign.child([sys.executable, '-c', code], root/'out', root/'err', timeout)
            with self.assertRaises(FileNotFoundError):
                campaign.child([str(root/'missing')], root/'out', root/'err', 5)
            failed = run('raise SystemExit(7)')
            self.assertEqual(failed['exit'], 7)
            with self.assertRaisesRegex(RuntimeError, 'child exited unsuccessfully'):
                campaign.require_child(failed)
            timed = run('import time; time.sleep(60)', .05)
            with self.assertRaisesRegex(RuntimeError, 'child timed out and was reaped'):
                campaign.require_child(timed)
            with self.assertRaises(ChildProcessError):
                campaign.os.waitpid(timed['pid'], campaign.os.WNOHANG)
            campaign.require_child(run('print("ok")'))

    @unittest.skipIf(BINARY is None, 'pass a benchmark binary to qualify live scope')
    def test_live_scope_and_replay(self):
        scope = subprocess.check_output([str(BINARY), '--scope-check'], text=True, timeout=30)
        seen = set()
        for line in scope.splitlines():
            tag, workers, total, local, coordinator, required = line.split('\t')
            self.assertEqual(tag, 'SCOPE'); seen.add(int(workers))
            total, local, coordinator, required = map(float, (total, local, coordinator, required))
            self.assertGreaterEqual(total, required)
            self.assertGreaterEqual(total, local)
            self.assertLess(coordinator, required)  # coordinator-only substitute fails
        self.assertEqual(seen, {1, 2, 4})
        text = subprocess.check_output([str(BINARY), '--case', 'call', '--size', '1', '--phase', 'check'], text=True, timeout=30)
        campaign.parse(text, 'call', 1, 'check')
        order = []
        for flags in ([], ['--reverse']):
            text = subprocess.check_output([str(BINARY), '--case', 'call', '--size', '1',
                                            '--phase', 'time'] + flags, text=True, timeout=30)
            campaign.parse(text, 'call', 1, 'time')
            order.append([line.split('\t')[1:4] for line in text.splitlines() if line.startswith('TIME\t')])
        self.assertEqual(order[0], list(reversed(order[1])))
        text = subprocess.check_output([str(BINARY), '--case', 'call', '--size', '1',
                                        '--phase', 'memory'], text=True, timeout=30)
        campaign.parse(text, 'call', 1, 'memory')


if __name__ == '__main__':
    unittest.main()
