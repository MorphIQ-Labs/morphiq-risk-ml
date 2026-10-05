#!/usr/bin/env python3
"""Controls for the frozen boundary-reuse performance criteria."""
import copy, unittest
from benchmark_bermudan_boundary import acceptance

class Controls(unittest.TestCase):
    def test_cost_criteria(self):
        rows=[]
        for family in ('american','bermudan'):
            for mode in ('none','cash'):
                for phase in (('admission','price','diagnostics') if family=='american' else ('price',)):
                    metrics=lambda a,t: {'allocated_bytes_per_call':{'median':a},'seconds_per_call':{'median':t}}
                    rows.append(dict(family=family,mode=mode,phase=phase,baseline=metrics(100,1),candidate=metrics(30,0.5) if family=='bermudan' else metrics(100,1)))
        acceptance(rows)
        for key,value,reason in [('allocated_bytes_per_call',41,'allocation'),('seconds_per_call',0.81,'latency')]:
            bad=copy.deepcopy(rows);bad[-1]['candidate'][key]['median']=value
            with self.assertRaisesRegex(ValueError,reason):acceptance(bad)
        with self.assertRaisesRegex(ValueError,'incomplete'):acceptance(rows[:-1]+[rows[0]])
if __name__=='__main__':unittest.main()
