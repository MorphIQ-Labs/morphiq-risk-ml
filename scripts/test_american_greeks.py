"""Offline Greek evidence integrity and collector failure controls."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import check_american_greeks as runtime
import collect_american_greeks as ref
import generate_american_greeks as generator
from american_reference_data import capture, strict_json


class Controls(unittest.TestCase):
    def test_frozen_inputs(self):
        frozen=strict_json((ref.BASE/'frozen.json').read_text())
        for name,digest in frozen.items():self.assertEqual(hashlib.sha256((ref.BASE.parents[2]/name).read_bytes()).hexdigest(),digest)
        rows=strict_json((ref.BASE/'cases-v1.json').read_text())['rows']
        self.assertEqual(len(rows),46);self.assertEqual(len({r['id'] for r in rows}),46)

    def test_reference_schema_controls(self):
        line='x\t256\tfinite\t0x1p+0\t0x1p+0\n'
        self.assertEqual(ref.parse(line,['x'],256,'prices')['x']['values'],[1.,1.])
        for bad,reason in [('', 'missing/extra'),(line+line,'missing/extra'),(line.replace('x\t','y\t'),'identity/order'),(line.rsplit('\t',1)[0]+'\n','truncated/extra'),(line.replace('0x1p+0\n','nan\n'),'hexadecimal'),(line.replace('0x1p+0\n','0x1p-1\n'),'reversed/negative')]:
            with self.subTest(reason=reason),self.assertRaisesRegex(ValueError,reason):ref.parse(bad,['x'],256,'prices')

    def test_runtime_scoring_controls(self):
        cases=[dict(id='x')]
        refs=[dict(id='x',quantity=q,status='finite',value='0x0p+0',radius='0x0p+0',resolved={'loose':True}) for q in ref.QUANTITIES]
        raw=''.join(f'x\t{q}\testimated\t0x0p+0\tindicator=0\t0x1p+0\n' for q in ref.QUANTITIES)
        self.assertTrue(all(x['comparison']=='pass' for x in runtime.classify(raw,cases,refs,'loose')))
        impossible=raw.replace('estimated\t0x0p+0','estimated\t0x1p+20')
        self.assertTrue(all(x['comparison']=='fail' for x in runtime.classify(impossible,cases,refs,'loose')))
        for bad,reason in [(raw[:-1].rsplit('\n',1)[0],'missing/extra'),(raw.replace('x\tdelta','x\tgamma'),'identity/order'),(raw.replace('estimated\t0x0p+0','unavailable\t0x0p+0'),'failed Greek'),(raw.replace('estimated\t0x0p+0','estimated\tnan'),'hexadecimal')]:
            with self.subTest(reason=reason),self.assertRaisesRegex(ValueError,reason):runtime.classify(bad,cases,refs,'loose')
        unresolved=[dict(r,resolved={'loose':False}) for r in refs]
        self.assertTrue(all(x['comparison']=='unresolved_reference' for x in runtime.classify(raw,cases,unresolved,'loose')))

    def test_capture_controls(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'raw'
            with self.assertRaisesRegex(ValueError,'startup failure'):capture([str(Path(d)/'absent')],'',path,.1)
            self.assertTrue(path.exists())
            with self.assertRaisesRegex(ValueError,'timeout'):capture([sys.executable,'-c','import time;print("partial",flush=True);time.sleep(5)'],'',path,.5)
            self.assertIn('partial',path.read_text())
            with self.assertRaisesRegex(ValueError,'exit failure'):capture([sys.executable,'-c','raise SystemExit(3)'],'',path,1)

    def test_real_family(self):
        row=strict_json((ref.BASE/'cases-v1.json').read_text())['rows'][0]
        shifted=generator.shifted(row,'rho',2**-10)
        from fractions import Fraction
        from american_piecewise_reference import number
        self.assertEqual(Fraction(number(shifted['inputs']['rate'])),Fraction(number(row['inputs']['rate']))+Fraction(2**-10))
        with self.assertRaisesRegex(ValueError,'not representable'):generator.shifted(row,'rho',2**-100)
        with self.assertRaisesRegex(ValueError,'negative volatility'):generator.shifted(row,'vega',-.25)

    def test_generator_drift_controls(self):
        # Exercise the real generator's final guards, substituting only process
        # execution; malformed result publication is separately rejected above.
        for fault in ('source','binary'):
            with tempfile.TemporaryDirectory() as d:
                path=Path(d);exe=path/'binary';exe.write_bytes(b'original')
                args=['generate','--quantlib',str(exe),'--quadrature',str(exe),'--price-quadrature',str(exe),'--mpmath-python',sys.executable,'--output',str(path/'out')]
                def fake_capture(command,data,dest,timeout):
                    Path(dest).write_text('')
                    if fault=='binary':exe.write_bytes(b'changed')
                    return ''
                maps=[{'source':'before'},{'source':'after' if fault=='source' else 'before'}]
                with mock.patch.object(sys,'argv',args),mock.patch.object(generator,'sources',side_effect=maps),mock.patch.object(generator,'capture',side_effect=fake_capture),contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaisesRegex(ValueError, 'source drift' if fault=='source' else 'binary drift'):generator.main()
                self.assertFalse(strict_json((path/'out/manifest.json').read_text())['complete'])

    def test_committed_references(self):
        path=ref.BASE/'references-v1.json'
        data=strict_json(path.read_text());canonical=strict_json((ref.BASE/'canonical-v1.json').read_text())
        cases=strict_json((ref.BASE/'cases-v1.json').read_text())['rows']
        expected=[(r['id'],q) for r in cases for q in ref.QUANTITIES]
        for corpus in (data,canonical):
            self.assertEqual([(r['id'],r['quantity']) for r in corpus['rows']],expected)
            for r in corpus['rows']:
                if r['status']=='finite':
                    ref.finite(r['value']);radius=ref.finite(r['radius']);self.assertGreaterEqual(radius,0)
                    self.assertEqual(r['resolved'],{m:radius<=ts[r['quantity']]/8 for m,ts in ref.TARGETS.items()})
        manifest=strict_json((ref.BASE/'reference-provenance.json').read_text())
        for name,digest in manifest['artifacts'].items():self.assertEqual(hashlib.sha256((ref.BASE/name).read_bytes()).hexdigest(),digest)


if __name__=='__main__':unittest.main()
