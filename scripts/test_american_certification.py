import copy
import unittest
from check_american_certification import load, validate, feasibility

class Controls(unittest.TestCase):
    def setUp(self):
        self.c,self.lines,self.m,_=load()
    def test_complete(self):
        self.assertEqual(len(validate(self.c,self.lines,self.m)),354)
        self.assertTrue(feasibility()['supersolution']['contradicted_by_positive_continuum_lower_bound'])
    def test_truncated(self):
        with self.assertRaisesRegex(ValueError,'incomplete reference rows'):
            validate(self.c,self.lines[:-1],self.m)
    def test_duplicate(self):
        c=copy.deepcopy(self.c);c['rows'][1]['id']=c['rows'][0]['id']
        with self.assertRaisesRegex(ValueError,'duplicate case ID'):validate(c,self.lines,self.m)
    def test_identity(self):
        lines=self.lines.copy();cells=lines[0].split();cells[3]='0x1p+0';lines[0]=' '.join(cells)
        with self.assertRaisesRegex(ValueError,'identity mismatch'):validate(self.c,lines,self.m)
    def test_reversed(self):
        lines=self.lines.copy();cells=lines[0].split();cells[-2:] = ['1','0'];lines[0]=' '.join(cells)
        with self.assertRaisesRegex(ValueError,'reversed reference'):validate(self.c,lines,self.m)
    def test_unsupported_is_not_pass(self):
        lines=self.lines.copy();cells=lines[-1].split();cells[-2:]=['0','0'];lines[-1]=' '.join(cells)
        with self.assertRaisesRegex(ValueError,'unsupported row'):validate(self.c,lines,self.m)
if __name__=='__main__':unittest.main()
