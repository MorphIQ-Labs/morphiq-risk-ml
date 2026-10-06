"""Exercise the cash pass's frozen targets without running timings in CI."""
import unittest
from measure_cash_interpolation import TARGETS
from measure_exponential_scratch import summarize
from test_exponential_scratch_campaign import records
class Controls(unittest.TestCase):
    def test_targets(self):
        self.assertTrue(summarize(records(),TARGETS)['criteria_pass'])
        for case,amount in (('cash',91),('bermudan',96),('piecewise-cash',96)):
            rows=records()
            for r in rows:
                if (r['case'],r['size'],r['variant'])==(case,1,'candidate'):
                    r['result']['memory']['scalar']=amount
            s=summarize(rows,TARGETS)
            self.assertIn(case+'/1/scalar: allocation criterion',s['failures'])
    def test_latency(self):
        rows=records()
        for r in rows:
            if (r['case'],r['size'],r['variant'])==('cash',1,'candidate'):
                r['result']['times']['scalar']['wall_s']=1.11
        self.assertIn('cash/1/scalar: latency criterion',summarize(rows,TARGETS)['failures'])
if __name__=='__main__':unittest.main()
