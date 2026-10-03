#!/usr/bin/env python3
"""Regression checks for provenance preservation during partial rebuilds."""
import gzip
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import write_manifest as manifest


class Provenance(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'fixtures').mkdir()
        (self.root / 'common.py').write_text('')
        for name in manifest.FIXTURES:
            (self.root / f'gen_{name}.py').write_text('import common\n')
            (self.root / 'fixtures' / f'{name}.txt.gz').write_bytes(gzip.compress(b'one row\n', mtime=0))
        (self.root / 'gen_greek_bits.py').write_text('import gen_greeks\n')
        manifest.update(self.root, manifest.FIXTURES, ('test-mp', 'test-python'))

    def test_transitive_change_cannot_be_blessed(self):
        before = (self.root / 'MANIFEST').read_bytes()
        (self.root / 'gen_greeks.py').write_text('import common\n# changed formula\n')
        with self.assertRaisesRegex(ValueError, 'greek_bits: stale'):
            manifest.update(self.root, ['greeks'], ('new-mp', 'new-python'))
        self.assertEqual(before, (self.root / 'MANIFEST').read_bytes())

    def test_partial_rebuild_preserves_unselected_records(self):
        before = manifest.read_records(self.root)
        manifest.update(self.root, ['normal'], ('new-mp', 'new-python'))
        after = manifest.read_records(self.root)
        self.assertEqual(after['normal'][4:6], ['new-mp', 'new-python'])
        for name in set(manifest.FIXTURES) - {'normal'}:
            self.assertEqual(before[name], after[name])

    def test_missing_dependency_rejected(self):
        path = self.root / 'MANIFEST'
        lines = path.read_text().splitlines()
        path.write_text('\n'.join(' '.join(line.split()[:8]) if line.startswith('greek_bits ') else line for line in lines))
        with self.assertRaisesRegex(ValueError, 'greek_bits: stale'):
            manifest.update(self.root, [])

    def test_missing_and_duplicate_records_rejected(self):
        path = self.root / 'MANIFEST'
        original = path.read_text()
        path.write_text('\n'.join(line for line in original.splitlines() if not line.startswith('normal ')))
        with self.assertRaisesRegex(ValueError, 'normal: missing'):
            manifest.update(self.root, [])
        path.write_text(original + next(line for line in original.splitlines() if line.startswith('normal ')) + '\n')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            manifest.update(self.root, [])


if __name__ == '__main__':
    unittest.main()
