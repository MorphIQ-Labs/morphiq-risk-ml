"""Lightweight integrity and rejection controls; optional research tools stay outside CI."""
import copy
import hashlib
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from check_american_piecewise import BASE, classify, request
from collect_american_piecewise import assemble
from benchmark_american_piecewise import acceptance


class Controls(unittest.TestCase):
    def setUp(self):
        self.cases=json.loads((BASE/'cases-v1.json').read_text())['rows']
        self.refs=json.loads((BASE/'references-v1.json').read_text())['rows']

    def test_request_and_identity(self):
        for row in self.cases:
            self.assertEqual(len(request(row,'primary').split('|')),5)
        self.assertEqual([r['id'] for r in self.cases],[r['id'] for r in self.refs])
        self.assertEqual(len(self.cases),40)

    def test_rejections(self):
        raw='\n'.join(r['id']+'\testimated\t'+v['value']+'\treference-control' for r,v in zip(self.cases,self.refs))
        self.assertNotIn('fail',[r['comparison']['status'] for r in classify(raw,self.cases,self.refs,'loose')])
        for bad,reason in [(raw.split('\n',1)[1],'missing or extra'),(raw.replace('\testimated\t','\twrong\t',1),'outcome/detail'),(raw.replace(self.cases[0]['id'],'wrong',1),'identity/order'),(raw.replace(self.refs[0]['value'],'nan',1),'invalid piecewise price')]:
            with self.assertRaisesRegex(ValueError,reason):classify(bad,self.cases,self.refs,'loose')
        failed=raw.replace(self.refs[0]['value'],'0x1p+20',1)
        self.assertEqual(classify(failed,self.cases,self.refs,'loose')[0]['comparison']['status'],'fail')
        unavailable='\n'.join(r['id']+'\tunavailable\t-\tresource:control' for r in self.cases)
        self.assertTrue(all(r['comparison']['status']=='runtime_unavailable' for r in classify(unavailable,self.cases,self.refs,'loose')))
        refs=copy.deepcopy(self.refs);refs[0]['radius']='0x1p+20'
        self.assertEqual(classify(raw,self.cases,refs,'loose')[0]['comparison']['status'],'reference_too_wide')

    def test_performance_criteria(self):
        summary=[dict(family=f,mode=m,baseline={k:{'median':1.} for k in ('seconds_per_call','allocated_bytes_per_call')},candidate={k:{'median':1.} for k in ('seconds_per_call','allocated_bytes_per_call')}) for f in ('american','bermudan','piecewise') for m in ('none','cash')]
        acceptance(summary)
        with self.assertRaisesRegex(ValueError,'incomplete workloads'):acceptance(summary[:-1])
        for key,reason in [('seconds_per_call','latency'),('allocated_bytes_per_call','allocation')]:
            bad=copy.deepcopy(summary);bad[0]['candidate'][key]['median']=2.
            with self.assertRaisesRegex(ValueError,reason):acceptance(bad)

    def test_retained_reference_arithmetic(self):
        archive=BASE/'reference-raw.tar.gz'
        provenance=json.loads((BASE/'reference-provenance.json').read_text())
        self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(),provenance['raw_sha256'])
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            with tarfile.open(archive) as arc:
                for member in arc:
                    self.assertTrue(member.isfile() and Path(member.name).name==member.name)
                    (root/member.name).write_bytes(arc.extractfile(member).read())
            self.assertEqual(assemble(root,self.cases)['rows'],self.refs)
            p=root/'quadrature-1024.tsv';p.write_text(p.read_text().split('\n',1)[1])
            with self.assertRaisesRegex(ValueError,'identity/order'):assemble(root,self.cases)

if __name__=='__main__':unittest.main()
