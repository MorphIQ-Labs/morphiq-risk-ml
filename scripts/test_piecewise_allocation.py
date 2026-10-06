"""Frozen paired performance criteria; process/decoder controls use shared helpers."""
import copy
import unittest
from benchmark_piecewise_allocation import acceptance
from test_benchmark_american_allocation import Controls as SharedControls

class Criteria(unittest.TestCase):
    def test_criteria(self):
        metrics=lambda a,t:dict(allocated_bytes_per_call=dict(median=a),seconds_per_call=dict(median=t))
        rows=[dict(family=f,mode=m,baseline=metrics(100,1),candidate=metrics(40,.7) if f=='piecewise' else metrics(100,1)) for f in ('american','bermudan','piecewise') for m in ('none','cash')]
        acceptance(rows)
        for index in (0,4):
            for metric,value,reason in [('allocated_bytes_per_call',106 if index==0 else 51,'allocation'),('seconds_per_call',1.11 if index==0 else .81,'latency')]:
                bad=copy.deepcopy(rows);bad[index]['candidate'][metric]['median']=value
                with self.assertRaisesRegex(ValueError,reason):acceptance(bad)
        with self.assertRaisesRegex(ValueError,'incomplete'):acceptance(rows[:-1]+[rows[0]])

if __name__=='__main__':unittest.main()
