#!/usr/bin/env python3
"""Failure controls for the optional qualification scorer (requires pinned Arb)."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from exchange_reference import bits
SCRIPT=Path(__file__).with_name('score_exchange_qualification.py')
class Controls(unittest.TestCase):
    def score(self,result,reference=None,required=True):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            ref=reference or dict(status='interval',closed='1',integral='1')
            row=dict(id='control',required=required,inputs=dict(limit=bits(.25)),reference=ref)
            (root/'refs.json').write_text(json.dumps(dict(rows=[row])))
            (root/'runtime.txt').write_text('control '+result+'\n')
            run=subprocess.run([sys.executable,str(SCRIPT),'--references',str(root/'refs.json'),'--runtime',str(root/'runtime.txt'),'--output',str(root/'score.json')],capture_output=True,text=True,timeout=10)
            return run.returncode,json.loads((root/'score.json').read_text())
    def test_exact_pass(self):
        code,score=self.score('served 0x1p0 0x0p0');self.assertEqual(code,0);self.assertEqual(score['counts'],{'contained':1})
    def test_wrong_price_rejected(self):
        code,score=self.score('served 0x0p0 0x0p0');self.assertEqual(code,1);self.assertEqual(score['counts'],{'failure':1})
    def test_limit_enforced(self):
        code,_=self.score('served 0x1p0 0x1p0');self.assertEqual(code,1)
    def test_entire_interval_required(self):
        code,_=self.score('served 0x1p0 0x0p0',dict(status='interval',closed='1',integral='[1 +/- 0.01]'));self.assertEqual(code,1)
    def test_unresolved_not_accuracy_pass(self):
        code,score=self.score('served 0x1p0 0x0p0',dict(status='unresolved'),False);self.assertEqual(code,0);self.assertEqual(score['counts'],{'unadjudicated':1})
    def test_remote_tail_exponent_without_rational_materialization(self):
        ref=dict(status='interval',closed='[+/- 1e-1000000000000000000]',integral='[+/- 1e-1000000000000000000]')
        code,score=self.score('served 0x0p0 0x0.0000000000001p-1022',ref)
        self.assertEqual(code,0);self.assertEqual(score['counts'],{'contained':1})
    def test_mandatory_refusal_rejected(self):
        code,_=self.score('numerical_failure');self.assertEqual(code,1)
    def test_invalid_not_success(self):
        code,_=self.score('served 0x1p0 0x0p0',dict(status='invalid_input'));self.assertEqual(code,1)
if __name__=='__main__':unittest.main()
