#!/usr/bin/env python3
"""Small exact-residual/parser controls, independent of optional Fortran builds."""
from pathlib import Path
import subprocess,sys,tempfile,unittest
import check_american_backends as check
from build_american_backends import replace_once
BINARY=Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 else None
MATRIX='MATRIX\t2\t1\t0x1p-23\nDATA\t0x0p0\t0x1p1\t-0x1p0\t0x0p0\t0x1p0\t0\nDATA\t-0x1p0\t0x1p1\t0x0p0\t0x1.8p1\t0x1p1\t0\n'
class Controls(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
  self.path=Path(self.temp.name)/'matrix.txt';self.path.write_text(MATRIX)
  self.ms=check.matrices(self.path)
 def test_exact_bound(self):
  result=check.exact(self.ms[0],[1.,2.]);self.assertTrue(result['passes']);self.assertEqual(result['error_bound_exact'],'0')
  wrong=check.exact(self.ms[0],[2.,2.]);self.assertFalse(wrong['passes']);self.assertEqual(wrong['error_bound_exact'],'2')
  with self.assertRaisesRegex(ValueError,'solution shape/nonfinite'):check.exact(self.ms[0],[float('nan'),2.])
 def test_capture_controls(self):
  for text,reason in [(MATRIX.rsplit('\n',2)[0]+'\n','truncated matrix'),(MATRIX+MATRIX,'matrix identity/allowance'),(MATRIX.replace('0x1p1','nan',1),'nonfinite matrix/result')]:
   self.path.write_text(text)
   with self.assertRaisesRegex(ValueError,reason):check.matrices(self.path)
 def test_micro_controls(self):
  text='SOLUTION\t0\t2\t0x0p0\t0x1p0\t0x1p1\n'+''.join(f'MICRO\t2\t{b}\t32\t0.001\t0.002\n' for b in (1,8,64))+'COMPLETE\t1\n'
  check.micro(text,self.ms)
  for altered,reason in [(text.replace('0.002','nan'),'invalid numeric measurement'),(text.replace('COMPLETE\t1\n',''),'incomplete micro evidence'),(text+'SOLUTION\t0\t2\t0x0p0\t0x1p0\t0x1p1\n','solution identity/shape')]:
   with self.assertRaisesRegex(ValueError,reason):check.micro(altered,self.ms)
 def test_request_controls(self):
  text='ROW\t0\t'+'a'*64+'\testimated\nVALUES\t0\t0x1p0\n'
  check.requests(text,'flat',1,capture=True)
  with self.assertRaisesRegex(ValueError,'incomplete request matrix'):check.requests(text,'flat',1)
  with self.assertRaisesRegex(ValueError,'request quantity count'):check.requests(text,'greeks',1,True)
  with self.assertRaisesRegex(ValueError,'duplicate/invalid values'):check.requests(text+'VALUES\t0\t0x1p0\n','flat',1,True)
 def test_patch_drift(self):
  with self.assertRaisesRegex(ValueError,'unexpected source anchor'):replace_once(self.path,'missing','replacement')
  self.assertEqual(self.path.read_text(),MATRIX)
 @unittest.skipIf(BINARY is None,'native matrix harness not supplied')
 def test_native_live(self):
  output=subprocess.check_output([str(BINARY),'--input',str(self.path)],text=True,timeout=30)
  parsed=check.micro(output,self.ms)
  self.assertTrue(check.exact(self.ms[0],parsed['solutions'][0]['values'])['passes'])
if __name__=='__main__':unittest.main()
