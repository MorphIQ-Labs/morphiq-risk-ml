import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import benchmark_native_tiles as bench


class Controls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.binary=self.root/'runner'
        self.payload='CHECK eligible 1 1 1 digest\n'+''.join(
            f'TIME eligible 1 1 1 {p} {s} 100 90 64 20\n'
            for p in bench.PHASES for s in range(1,6))
        self.program(self.payload)
        self.manifest=self.root/'prepared.json'
        self.manifest.write_text(json.dumps({'sources':[], 'binaries':[{'path':str(self.binary)}]*2}))
        for name,value in [('CONFIGURATIONS',[(1,1)]),('FAMILIES',['eligible']),('WORKERS',[1]),('DUMP_SIZE',1),('DUMP_SCENARIOS',1),('snapshot',mock.Mock(return_value={}))]:
            patch=mock.patch.object(bench,name,value);patch.start();self.addCleanup(patch.stop)

    def program(self,payload,extra=''):
        self.binary.write_text('#!/usr/bin/env python3\nimport sys,time,os\n'
            'if "--dump-inputs" in sys.argv: print("bachelier call benchmark timed-tiles-eligible "+" ".join(["0000000000000000"]*8));sys.exit(0)\n'
            'if "--trace" in sys.argv: print("eligible 1 0 0 0000000000000000");sys.exit(0)\n'
            +f'print({payload!r},end="",flush=True)\n'+extra)
        self.binary.chmod(0o755)

    def collect(self):bench.collect(self.manifest,self.root/'results')

    def test_complete(self):
        self.collect();report=json.loads((self.root/'results/summary.json').read_text())
        self.assertTrue(report['complete']);self.assertEqual(report['samples'],80)

    def test_truncated(self):
        self.program(self.payload.rsplit('TIME',1)[0])
        with self.assertRaisesRegex(ValueError,'incomplete benchmark coverage'):self.collect()
        self.assertTrue((self.root/'results/run-0.txt').exists())

    def test_malformed(self):
        self.program('garbage\n')
        with self.assertRaisesRegex(ValueError,'unexpected benchmark output'):self.collect()

    def test_nonfinite(self):
        self.program(self.payload.replace('100 90','nan 90'))
        with self.assertRaisesRegex(ValueError,'invalid timing sample'):self.collect()

    def test_child_failure(self):
        self.program(self.payload,'sys.exit(7)\n')
        with self.assertRaises(subprocess.CalledProcessError) as error:self.collect()
        self.assertEqual(error.exception.returncode,7)
        self.assertEqual((self.root/'results/run-0.txt').read_text(),self.payload)

    def test_failed_start(self):
        self.binary.unlink()
        with self.assertRaises(FileNotFoundError):self.collect()

    def test_timeout_reaped(self):
        self.program('',f'open({str(self.root/"pid")!r},"w").write(str(os.getpid()))\ntime.sleep(20)\n')
        with mock.patch.object(bench,'TIMEOUT',2):
            with self.assertRaises(subprocess.TimeoutExpired):self.collect()
        pid=int((self.root/'pid').read_text())
        with self.assertRaises(ProcessLookupError):os.kill(pid,0)

    def test_changed_source(self):
        bench.snapshot.side_effect=[{},ValueError('prepared source or binary changed')]
        with self.assertRaisesRegex(ValueError,'prepared source or binary changed'):self.collect()
        self.assertTrue((self.root/'results/run-0.txt').exists())

    def test_different_inputs(self):
        other=self.root/'other';other.write_text(self.binary.read_text().replace('print("bachelier call benchmark timed-tiles-eligible "+" ".join(["0000000000000000"]*8))','print("different")'));other.chmod(0o755)
        self.manifest.write_text(json.dumps({'sources':[],'binaries':[{'path':str(self.binary)},{'path':str(other)}]}))
        with self.assertRaisesRegex(ValueError,'different timed inputs'):self.collect()

    def test_changed_trace(self):
        other=self.root/'other';other.write_text(self.binary.read_text().replace('print("eligible 1 0 0 0000000000000000")','print("different")'));other.chmod(0o755)
        self.manifest.write_text(json.dumps({'sources':[],'binaries':[{'path':str(self.binary)},{'path':str(other)}]}))
        with self.assertRaisesRegex(ValueError,'different complete output trace'):self.collect()

    def test_empty_inputs_and_trace(self):
        with self.assertRaisesRegex(ValueError,'incomplete original-input coverage'):bench.validate_inputs('')
        with self.assertRaisesRegex(ValueError,'incomplete output trace'):bench.validate_trace('')

    def test_duplicate_trace(self):
        row='eligible 1 0 0 0000000000000000\n'
        with self.assertRaisesRegex(ValueError,'duplicate or invalid output index'):bench.validate_trace(row+row)

    def test_git_staged_unstaged_untracked(self):
        root=self.root/'repo';root.mkdir()
        def git(*args):subprocess.run(['git',*args],cwd=root,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        git('init','-q');git('config','user.name','Test');git('config','user.email','test@example.invalid')
        (root/'lib').mkdir();p=root/'lib/x';p.write_text('original');git('add','.');git('commit','-qm','fixture')
        bench.source(root)
        p.write_text('changed')
        with self.assertRaisesRegex(ValueError,'source is not clean'):bench.source(root)
        git('add','lib/x')
        with self.assertRaisesRegex(ValueError,'source is not clean'):bench.source(root)
        git('commit','-qm','changed');(root/'untracked').write_text('new')
        with self.assertRaisesRegex(ValueError,'source is not clean'):bench.source(root)


if __name__=='__main__':unittest.main()
