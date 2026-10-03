"""Temporary fictional approval records exercise the integrity gate, not real authorization."""
import copy
import hashlib
from pathlib import Path
import tempfile
import unittest
from check_acceptance import check,EVIDENCE,ROLES


class Gate(unittest.TestCase):
    def test_acceptance_integrity_and_negative_controls(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);p=root/'fictional-evidence';p.write_text('test-only; no real approval\n')
            sha='a'*40
            item=dict(path=p.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),candidate_commit=sha)
            record=dict(candidate_commit=sha,status='accepted',intended_use='fictional unit-test scope',package_version='0.1.0',blockers=[],
                        evidence={k:dict(item) for k in EVIDENCE},artifacts=[dict(item)],
                        decisions={k:dict(item,name='Fictional test actor',date='2020-01-01',decision='accept') for k in ROLES})
            self.assertEqual(check(record,root,root),[])
            for edit in [lambda r:r.update(status='pending'),lambda r:r.update(blockers=['unresolved']),
                         lambda r:r['decisions'].pop('model_validation'),
                         lambda r:r['evidence']['shadow'].update(candidate_commit='b'*40),
                         lambda r:r['decisions']['engineering_release'].update(date='2999-01-01'),
                         lambda r:r['artifacts'][0].update(path='../outside'),
                         lambda r:r['evidence']['full_mutations'].update(sha256='0'*64)]:
                broken=copy.deepcopy(record);edit(broken)
                self.assertTrue(check(broken,root,root))
            p.write_text('changed after acceptance\n')
            self.assertTrue(check(record,root,root))

    def test_pending_is_never_accepted(self):
        self.assertTrue(check(dict(status='pending'),Path('.'),Path('.')))


if __name__=='__main__': unittest.main()
