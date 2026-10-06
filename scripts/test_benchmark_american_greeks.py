import copy
import json
import unittest
from benchmark_american_greeks import decode,summarize

class Controls(unittest.TestCase):
    def row(self,model='constant',quantity='all'):
        return dict(model=model,quantity=quantity,calls=1,warmup_calls=1,seconds_per_call=.1,allocated_bytes_per_call=100,price=10.,minor_collections=0,major_collections=0,heap_words_after=100,live_words_after=50,estimated_greeks={'price':0,'spatial':3,'all':5}[quantity],unavailable_greeks=0,rejected_greeks=0,digest='0'*32)
    def test_decode(self):
        r=self.row();self.assertEqual(decode(json.dumps(r),'constant','all'),r)
        for change,reason in [({'calls':2},'workload'),({'seconds_per_call':float('nan')},'malformed'),({'allocated_bytes_per_call':0},'metric'),({'estimated_greeks':4},'missing Greek'),({'digest':'missing'},'digest')]:
            with self.assertRaisesRegex(ValueError,reason):decode(json.dumps(dict(r,**change)),'constant','all')
        with self.assertRaisesRegex(ValueError,'malformed'):decode('{','constant','all')
    def test_summarize(self):
        rs=[dict(round=i,sample=self.row(m,q)) for i in range(5) for m in ('constant','piecewise','cash') for q in ('price','spatial','all')]
        self.assertEqual(len(summarize(rs)),9)
        with self.assertRaisesRegex(ValueError,'incomplete'):summarize(rs[:-1])
        bad=copy.deepcopy(rs);bad[-1]['sample']['digest']='1'*32
        with self.assertRaisesRegex(ValueError,'outcomes changed'):summarize(bad)
        bad=copy.deepcopy(rs);bad[-1]['sample']['price']=11
        with self.assertRaisesRegex(ValueError,'underlying price differs'):summarize(bad)

if __name__=='__main__':unittest.main()
