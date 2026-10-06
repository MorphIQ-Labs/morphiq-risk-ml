import sys
import tempfile
import unittest
from pathlib import Path
from american_iv_campaign import execute, parse

# Minimal well-formed Marshal envelope, testing the collector, not OCaml values.
REPLAY = '8495a6be0000000100000000000000000000000040'
GOOD = f'ROOT a 0x1p-3 0x1p-2 4\nROW a interval {REPLAY}\nTOTAL 1 1 0 0\n'
class Controls(unittest.TestCase):
    def test_complete(self): self.assertEqual(len(parse(GOOD, ['a'], 1)), 1)
    def test_truncation(self):
        with self.assertRaisesRegex(ValueError, 'incomplete total'): parse(GOOD.rsplit('TOTAL',1)[0], ['a'])
    def test_identity(self):
        with self.assertRaisesRegex(ValueError, 'case identity'): parse(GOOD, ['b'])
    def test_impossible(self):
        with self.assertRaisesRegex(ValueError, 'criterion'): parse(GOOD, ['a'], 2)
    def test_malformed(self):
        with self.assertRaisesRegex(ValueError, 'malformed replay'): parse(GOOD.replace(REPLAY,'00'), ['a'])
    def test_duplicate(self):
        with self.assertRaisesRegex(ValueError, 'duplicate'): parse(GOOD+f'ROW a interval {REPLAY}\n', ['a'])
    def test_missing_root(self):
        with self.assertRaisesRegex(ValueError, 'root/outcome'): parse('\n'.join(GOOD.splitlines()[1:]), ['a'])
    def test_startup_and_timeout(self):
        with tempfile.TemporaryDirectory() as d:
            out,err=Path(d)/'out',Path(d)/'err'
            with self.assertRaisesRegex(ValueError, 'failed startup'): execute([str(Path(d)/'missing')],out,err,1)
            with self.assertRaisesRegex(ValueError, 'timeout'): execute([sys.executable,'-c','import time;time.sleep(2)'],out,err,.05)
            with self.assertRaisesRegex(ValueError, 'process failed'): execute([sys.executable,'-c','raise SystemExit(1)'],out,err,1)
    def test_order(self):
        second=GOOD.replace(" a "," b ").replace("TOTAL 1 1 0 0\n", "")
        text=second+GOOD.replace("TOTAL 1 1 0 0", "TOTAL 2 2 0 0")
        with self.assertRaisesRegex(ValueError, "identity/order"): parse(text,["a","b"])
    def test_replay_change(self):
        changed=GOOD.replace(REPLAY, REPLAY[:-2]+'41')
        self.assertNotEqual(parse(GOOD,['a']),parse(changed,['a']))
if __name__ == '__main__': unittest.main()
