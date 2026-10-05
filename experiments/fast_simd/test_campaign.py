#!/usr/bin/env python3
"""Protocol/decision controls using synthetic evidence, not pricing references."""
import contextlib
import copy
import io
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import campaign
import compare

class ScorerControls(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / 'input.txt'
        self.trace = self.root / 'trace.jsonl'
        self.report = self.root / 'report.json'
        self.source.write_text(' '.join(['bachelier','call','otm','control'] + [campaign.word(x) for x in (-1.,0.,1.,0.,0.,1.,0.,1.)])+'\n')
        self.row = {'row':0,'eligible':True,'outcomes':[campaign.word(1.)]*5}

    def score(self, rows):
        self.trace.write_text(''.join(json.dumps(row)+'\n' for row in rows))
        with contextlib.redirect_stdout(io.StringIO()):
            campaign.score(self.source,self.trace,self.report)
        return json.loads(self.report.read_text())

    def test_complete(self):
        r=self.score([self.row])
        self.assertTrue(r['operation_preserving_pass'])
        self.assertTrue(r['sleef_quality_pass'])
        self.assertFalse(r['universal_bound'])

    def test_missing_duplicate_and_reordered(self):
        for rows in [[],[self.row,self.row],[self.row|{'row':1}]]:
            with self.assertRaises(AssertionError): self.score(rows)

    def test_nonfinite_and_malformed(self):
        for replacement in [campaign.word(math.nan),campaign.word(math.inf),'not-an-outcome']:
            row=copy.deepcopy(self.row);row['outcomes'][3]=replacement
            with self.assertRaises(AssertionError): self.score([row])
        with self.assertRaises(AssertionError): self.score([self.row|{'outcomes':['0']*4}])

    def test_changed_operation_preserving_and_fallback(self):
        row=copy.deepcopy(self.row);row['outcomes'][3]=campaign.word(math.nextafter(1.,2.))
        with self.assertRaisesRegex(AssertionError,'operation-preserving mismatch'): self.score([row])
        row['eligible']=False
        with self.assertRaisesRegex(AssertionError,'fallback mismatch'): self.score([row])

    def test_sleef_failure_is_a_recorded_no_go(self):
        row=copy.deepcopy(self.row);row['outcomes'][4]=campaign.word(1.01)
        report=self.score([row])
        self.assertFalse(report['sleef_quality_pass'])
        self.assertFalse(report['sleef_no_regional_regression'])
        self.assertEqual(report['backends']['sleef-simd']['gate_failures'],1)
        self.assertEqual(len(report['changed_rows']),1)

class CollectorControls(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root=Path(self.directory.name)
        self.binary=self.root/'fake-runner'
        self.destination=self.root/'evidence'
        self.state={'binary_sha256':'control','source':'control','source_status':'','experiment_files':{},'library_tree':'control'}
        patch=mock.patch.object(campaign,'metadata',return_value=self.state)
        patch.start();self.addCleanup(patch.stop)

    def program(self, text):
        self.binary.write_text('#!/usr/bin/env python3\n'+text+'\n')
        self.binary.chmod(0o700)

    def collect(self):
        with contextlib.redirect_stdout(io.StringIO()):
            campaign.collect(self.binary,self.destination)

    def test_startup_failure(self):
        with self.assertRaises(FileNotFoundError): self.collect()
        self.assertTrue((self.destination/'before.json').exists())
        self.assertFalse((self.destination/'summary.json').exists())

    def test_failed_process_and_partial_evidence(self):
        self.program('print("partial",flush=True)\nraise SystemExit(7)')
        with self.assertRaises(subprocess.CalledProcessError) as error: self.collect()
        self.assertEqual(error.exception.returncode,7)
        self.assertEqual((self.destination/'run-0.jsonl').read_text(),'partial\n')

    def test_timeout_reaps_child_and_retains_output(self):
        self.program('import os,time\nprint(os.getpid(),flush=True)\ntime.sleep(30)')
        with mock.patch.object(campaign,'RUN_TIMEOUT_SECONDS',2.0):
            with self.assertRaises(subprocess.TimeoutExpired): self.collect()
        pid=int((self.destination/'run-0.jsonl').read_text())
        with self.assertRaises(ProcessLookupError): os.kill(pid,0)
        self.assertFalse((self.destination/'summary.json').exists())

    def test_truncated_and_malformed(self):
        self.program('pass')
        with self.assertRaises(AssertionError): self.collect()
        self.destination=self.root/'malformed'
        self.program('print("not json")')
        with self.assertRaises(json.JSONDecodeError): self.collect()

    def valid_output(self):
        self.program('''import json
for family in ['eligible','fallback-heavy','mixed']:
 for n in [1,32,256,4096]:
  for backend in ['batch-fast','prepared-ocaml','native-scalar','native-simd','sleef-simd']:
   for phase in ['compile','execute','one-shot']:
    for sample in range(1,6):
     print(json.dumps(dict(kind='timing',family=family,n=n,backend=backend,phase=phase,sample=sample,ns=1.,cpu_ns=1.,bytes=1.,eligible=0,iterations=1)))''')

    def test_complete(self):
        self.valid_output();self.collect()
        report=json.loads((self.destination/'summary.json').read_text())
        self.assertTrue(report['complete'])
        self.assertEqual(report['samples'],3600)

    def test_changed_source_rejected(self):
        self.valid_output()
        with mock.patch.object(campaign,'metadata',side_effect=[self.state]*9+[self.state|{'source_status':'changed'}]):
            with self.assertRaises(AssertionError): self.collect()
        self.assertTrue((self.destination/'after.json').exists())
        self.assertFalse((self.destination/'summary.json').exists())

class PairedCollectorControls(CollectorControls):
    def test_different_inputs_rejected(self):
        self.valid_output()
        with mock.patch.object(compare,'snapshot',return_value=self.state):
            with mock.patch.object(compare.subprocess,'check_output',side_effect=[b'first',b'second']):
                with self.assertRaisesRegex(AssertionError,'different benchmark requests'):
                    self.collect()
        self.assertFalse((self.destination/'run-0.jsonl').exists())

    def collect(self):
        with mock.patch.object(compare,'snapshot',side_effect=lambda *_: campaign.metadata(self.binary)):
            with contextlib.redirect_stdout(io.StringIO()):
                compare.collect([self.root,self.root],[self.binary,self.binary],self.destination)

    def test_complete(self):
        self.valid_output();self.collect()
        report=json.loads((self.destination/'summary.json').read_text())
        self.assertTrue(report['complete'])
        self.assertEqual(report['samples'],7200)
        self.assertTrue(all(len(r['process_medians_ns'])==4 for r in report['summary']))

    def test_failed_process_and_partial_evidence(self):
        self.program('import sys\nif "--dump-inputs" in sys.argv: print("same")\nelse:\n print("partial",flush=True)\n raise SystemExit(7)')
        with self.assertRaises(subprocess.CalledProcessError) as error: self.collect()
        self.assertEqual(error.exception.returncode,7)
        self.assertEqual((self.destination/'run-0.jsonl').read_text(),'partial\n')

    def test_timeout_reaps_child_and_retains_output(self):
        self.program('import sys,os,time\nif "--dump-inputs" in sys.argv: print("same")\nelse:\n print(os.getpid(),flush=True)\n time.sleep(30)')
        with mock.patch.object(campaign,'RUN_TIMEOUT_SECONDS',2.):
            with self.assertRaises(subprocess.TimeoutExpired): self.collect()
        pid=int((self.destination/'run-0.jsonl').read_text())
        with self.assertRaises(ProcessLookupError): os.kill(pid,0)
        self.assertFalse((self.destination/'summary.json').exists())

    def test_changed_source_rejected(self):
        self.valid_output()
        # Two initial snapshots, two per process, two final snapshots.
        with mock.patch.object(campaign,'metadata',side_effect=[self.state]*19+[self.state|{'source':'changed'}]):
            with self.assertRaises(AssertionError): self.collect()
        self.assertTrue((self.destination/'after.json').exists())
        self.assertFalse((self.destination/'summary.json').exists())

if __name__=='__main__': unittest.main()
