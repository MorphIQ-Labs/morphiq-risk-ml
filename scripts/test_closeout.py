#!/usr/bin/env python3
"""Failure controls for installed provenance and experimental dossier integrity."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from candidate_artifact import (verify_notices, verify_origin, EXCHANGE_FIELDS,
                                exchange_input, verify_exchange_replay)
from check_experimental import check, CATEGORIES, PLATFORMS


class Controls(unittest.TestCase):
    def test_exchange_replay_controls(self):
        rows=[dict(id=name,inputs={k:'0000000000000000' for k in EXCHANGE_FIELDS})
              for name in ['a','b']]
        expected='a served 0x0p+0 0x0p+0\nb numerical_failure\n'
        self.assertEqual(len(exchange_input(rows,expected).splitlines()),2)
        self.assertEqual(verify_exchange_replay(expected,expected),
                         {'served':1,'numerical_failure':1})
        for observed in ['',expected.splitlines()[0],expected+expected,
                         '\n'.join(reversed(expected.splitlines())),
                         expected.replace('served 0x0p+0','served 0x1p+0'),
                         expected.replace('0x0p+0\n','0x1p-52\n'),
                         expected.replace('numerical_failure','accuracy_exceeded')]:
            with self.subTest(observed=observed),self.assertRaisesRegex(RuntimeError,'replay differs'):
                verify_exchange_replay(expected,observed)
        for bad in [[],rows[:1],list(reversed(rows)),[rows[0],rows[0]]]:
            with self.assertRaisesRegex(RuntimeError,'membership/order'):
                exchange_input(bad,expected)
        for key,value in [('id','a b'),('inputs',dict(rows[0]['inputs'],rho='nan'))]:
            bad=copy.deepcopy(rows);bad[0][key]=value
            with self.assertRaisesRegex(RuntimeError,'invalid exchange'):
                exchange_input(bad,expected)
        with self.assertRaisesRegex(RuntimeError,'reference outcome'):
            exchange_input(rows,expected.replace('served 0x0p+0 0x0p+0','unknown'))

    def test_notice_integrity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); source=root/'source'; prefix=root/'install'
            names=['LICENSE','NOTICE','THIRD_PARTY_NOTICES.md','SECURITY.md','LICENSES/upstream.txt']
            for name in names:
                for base in (source, prefix/'doc/morphiq_risk_ml'):
                    p=base/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(name)
            self.assertEqual(len(verify_notices(source,prefix)),5)
            installed=prefix/'doc/morphiq_risk_ml/LICENSES/upstream.txt'
            installed.write_text('changed notice')
            with self.assertRaisesRegex(RuntimeError,'changed installed notice'): verify_notices(source,prefix)
            installed.unlink()
            with self.assertRaisesRegex(RuntimeError,'missing or changed'): verify_notices(source,prefix)

    def test_origin(self):
        verify_origin('/tmp/isolated/lib/morphiq_risk_ml',Path('/tmp/isolated'))
        with self.assertRaisesRegex(RuntimeError,'unintended package'):
            verify_origin('/tmp/ambient/lib/morphiq_risk_ml',Path('/tmp/isolated'))

    def test_dossier(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);commit='a'*40
            record=dict(candidate_commit=commit,package_version='0.3.0',decision='qualified-experimental',assessor='test fixture only',limitations=['finite coverage'],evidence=[])
            for category in sorted(CATEGORIES):
                for platform in (sorted(PLATFORMS) if category=='platform' else ['none']):
                    name=category+'-'+platform+'.json'
                    data=dict(commit=commit,package_version='0.3.0',source_tar_reproduced=True,smoke_native=True,smoke_bytecode=True,installed_notices_sha256={'LICENSE':'test'},consumer_sha256='test')
                    target=root/name;target.write_text(json.dumps(data))
                    record['evidence'].append(dict(category=category,platform=platform,path=name,sha256=hashlib.sha256(target.read_bytes()).hexdigest(),candidate_commit=commit))
            self.assertEqual(check(record,root),[])
            for key,value in [('candidate_commit','b'*40),('decision','pending')]:
                bad=copy.deepcopy(record);bad[key]=value;self.assertTrue(check(bad,root))
            bad=copy.deepcopy(record);bad['evidence'].pop();self.assertTrue(check(bad,root))
            bad=copy.deepcopy(record);bad['evidence'][0]['path']='../outside';self.assertTrue(check(bad,root))
            target=root/record['evidence'][0]['path'];target.write_text('{}');self.assertTrue(check(record,root))
            target.unlink();self.assertTrue(check(record,root))


if __name__=='__main__': unittest.main()
