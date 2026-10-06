import copy,json,unittest
from check_american_iv import BASE,load,validate
class Controls(unittest.TestCase):
 def setUp(self):self.d=json.loads((BASE/'references.json').read_text())
 def test_complete(self):self.assertEqual(len(load()),30)
 def test_truncated(self):
  self.d['rows'].pop()
  with self.assertRaisesRegex(ValueError,'incomplete corpus'):validate(self.d)
 def test_duplicate(self):
  self.d['rows'][1]['id']=self.d['rows'][0]['id']
  with self.assertRaisesRegex(ValueError,'duplicate case'):validate(self.d)
 def test_reversed(self):
  self.d['rows'][0]['lower']='1'
  with self.assertRaisesRegex(ValueError,'reversed interval'):validate(self.d)
 def test_unresolved(self):
  self.d['rows'][0]['resolved']=False
  with self.assertRaisesRegex(ValueError,'unresolved reference'):validate(self.d)
 def test_missing_attempt(self):
  self.d['rows'][0]['attempts'].pop()
  with self.assertRaisesRegex(ValueError,'missing independent'):validate(self.d)
 def test_counterexample(self):
  self.d['cash_put_counterexample'][1]['upper']='11'
  with self.assertRaisesRegex(ValueError,'counterexample lost'):validate(self.d)
if __name__=='__main__':unittest.main()
