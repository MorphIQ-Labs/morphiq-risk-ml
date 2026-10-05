#!/usr/bin/env python3
"""Cash campaign protocol, scoring, corpus and provenance controls (stdlib)."""
import hashlib, json, pathlib, unittest
from check_bermudan import BASE, classify
from freeze_bermudan import corpus

class Controls(unittest.TestCase):
    def setUp(self):
        self.case={'id':'witness','epsilon':'3f50624dd2f1a9fc'}
        self.ref={'id':'witness','value':1.,'radius':0.,'reference_kind':'empirical-quadrature'}
    def score(self,text,ref=None):return classify(text,[self.case],[ref or self.ref],'primary')[0]['comparison']['status']
    def test_wrong_value(self):self.assertEqual(self.score('witness\testimated\t0x1p+1\tmethod'),'fail')
    def test_absent_reference(self):self.assertEqual(self.score('witness\testimated\t0x1p+0\tmethod',{'id':'witness'}),'unresolved_reference')
    def test_wide_reference(self):self.assertEqual(self.score('witness\testimated\t0x1p+0\tmethod',{**self.ref,'radius':1.}),'reference_too_wide')
    def test_unavailable(self):self.assertEqual(self.score('witness\tunavailable\t-\tarithmetic:resolution'),'runtime_unavailable')
    def test_bad_protocol(self):
        for text,reason in [('', 'missing'),('witness\testimated\t0x1p+0','malformed'),('other\testimated\t0x1p+0\tmethod','identity'),('witness\testimated\tnan\tmethod','invalid cash price'),('witness\tunavailable\t0x1p+0\tarithmetic:x','invalid cash failure'),('witness\tpartial\t-\tx','outcome')]:
            with self.subTest(text=text),self.assertRaisesRegex(ValueError,reason):self.score(text)
    def test_frozen_corpus(self):self.assertEqual(corpus(),json.loads((BASE/'cases-v1.json').read_text()))
    def test_provenance(self):
        root=BASE.parents[2]
        manifest=json.loads((BASE/'manifest.json').read_text())
        for name,digest in manifest['sha256'].items():
            self.assertFalse(pathlib.Path(name).is_absolute());self.assertNotIn('..',pathlib.Path(name).parts)
            self.assertEqual(hashlib.sha256((root/name).read_bytes()).hexdigest(),digest,name)
    def test_runner_failure_reasons(self):
        records=json.loads((BASE/'runner-controls.json').read_text())
        expected={'truncated':'missing exercise separator','missing-right':'truncated exercise side','unknown-flag':'unrecognized arguments'}
        for name in ('quadrature','quantlib'):
            for kind,reason in expected.items():
                row=next(r for r in records if r['runner']==name and r['control']==kind)
                self.assertEqual(row['returncode'],2);self.assertIn(reason,row['stderr']);self.assertEqual(row['stdout'],'')
    def test_reference_rows(self):
        cases=json.loads((BASE/'cases-v1.json').read_text())['rows'];refs=json.loads((BASE/'references.json').read_text())['rows']
        self.assertEqual([r['id'] for r in cases],[r['id'] for r in refs]);self.assertEqual(len(refs),32)
        for ref in refs:
            self.assertEqual([int(r[1]) for r in ref['quadrature']],[256,512,1024]);self.assertEqual([int(r[1]) for r in ref['quantlib']],[128,256,512])
if __name__=='__main__':unittest.main()
