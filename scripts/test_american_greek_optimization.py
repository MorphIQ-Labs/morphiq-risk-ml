"""Failure controls for the paired Greek optimization collector."""
import copy
import unittest
from benchmark_american_greek_optimization import MODELS, QUANTITIES, acceptance, summarize

class Controls(unittest.TestCase):
    def runs(self):
        return [dict(round=i,variant=v,sample=dict(model=m,quantity=q,price=1.,digest='a'*32,
          estimated_greeks={'price':0,'spatial':3,'all':5}[q],unavailable_greeks=0,rejected_greeks=0,
          seconds_per_call=.7 if v=='candidate' else 1.,allocated_bytes_per_call=70 if v=='candidate' else 100,
          minor_collections=0,major_collections=0))
          for i in range(5) for m in MODELS for q in QUANTITIES for v in ('baseline','candidate')]
    def test_criteria(self):
        rows=summarize(self.runs());acceptance(rows)
        for key,value in [('seconds_per_call',.91),('allocated_bytes_per_call',81)]:
            bad=copy.deepcopy(rows);next(r for r in bad if r['model']=='cash' and r['quantity']=='all')['candidate']['metrics'][key]['median']=value
            with self.assertRaisesRegex(ValueError,'cash/all'):acceptance(bad)
        bad=copy.deepcopy(rows);bad[0]['candidate']['metrics']['seconds_per_call']['median']=1.11
        with self.assertRaisesRegex(ValueError,'constant/price'):acceptance(bad)
        with self.assertRaisesRegex(ValueError,'incomplete workload'):acceptance(rows[:-1])
    def test_identity(self):
        for field,value,reason in [('digest','b'*32,'outcomes differ'),('price',2.,'price depends'),('round',1,'incomplete paired')]:
            runs=self.runs()
            if field=='round':runs[0][field]=value
            else:runs[0]['sample'][field]=value
            with self.assertRaisesRegex(ValueError,reason):summarize(runs)
        with self.assertRaisesRegex(ValueError,'incomplete campaign'):summarize(self.runs()[:-1])
if __name__=='__main__':unittest.main()
