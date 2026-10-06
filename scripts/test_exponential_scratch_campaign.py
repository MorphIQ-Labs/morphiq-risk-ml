"""Negative controls for frozen completeness, replay and improvement criteria."""
import unittest
import measure_exponential_scratch as m

def records():
    result=[]
    for i in range(5):
        for case,size in m.JOBS+[('european',0)]:
            for variant in ('baseline','candidate'):
                amount=100 if variant=='baseline' else 80
                if size:
                    data=dict(rows={'0':'same complete outcome'},values={'0':[1.]},
                      times={k:dict(wall_s=1.,first_s=0.) for k in ('scalar','batch','planner1')},
                      memory={k:amount for k in ('scalar','batch','planner1')},compilation={'batch':1.,'planner':1.})
                else:
                    data=dict(checks={k:'unchanged' for k in m.european.CASES},samples=[dict(key=k,index=n,ns=1.,allocation=amount) for k,n in m.european.SLOTS])
                result.append(dict(round=i,case=case,size=size,variant=variant,result=data,peak_rss_bytes=1))
    return result

class Controls(unittest.TestCase):
    def test_complete_and_failed_criteria(self):
        rows=records();self.assertTrue(m.summarize(rows)['criteria_pass'])
        for r in rows:
            if (r['case'],r['size'],r['variant'])==('bermudan',1,'candidate'):r['result']['memory']['scalar']=91
        summary=m.summarize(rows)
        self.assertFalse(summary['criteria_pass']);self.assertIn('bermudan/1/scalar: allocation criterion',summary['failures'])
    def test_missing_and_duplicate(self):
        rows=records()
        for bad in (rows[:-1],rows[:-1]+[rows[0]]):
            with self.assertRaisesRegex(ValueError,'incomplete/duplicate'):m.summarize(bad)
    def test_changed_replay(self):
        rows=records();rows[1]['result']['rows']['0']='altered'
        with self.assertRaisesRegex(ValueError,'changed American complete replay'):m.summarize(rows)
    def test_european_regression(self):
        rows=records()
        for r in rows:
            if r['case']=='european' and r['variant']=='candidate':
                for s in r['result']['samples']:s['allocation']=106
        self.assertTrue(any('European allocation criterion' in x for x in m.summarize(rows)['failures']))
if __name__=='__main__':unittest.main()
