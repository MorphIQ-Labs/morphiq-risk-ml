"""Exact midpoint/time-value reference controls; no mpmath dependency."""
import math
from types import SimpleNamespace
import unittest
from price_rounding import tiny_time_value_rounding,positive_tail_bound,price_reference


def contract(model='bsm',**kwargs):
    data=dict(model=model,call=True,s=math.nextafter(1.,math.inf),k=2.**-53,
              t=1.,r=0.,q=0.,shift=0.)
    data.update(kwargs)
    return SimpleNamespace(**data)


class Rounding(unittest.TestCase):
    def test_positive_increment_above_even_lower_midpoint(self):
        for model in ('bsm','black76','displaced','bachelier'):
            c=contract(model,shift=2.**-54 if model=='displaced' else 0.)
            for sigma in (1e-300,1e-12,1e-4,.01):
                self.assertEqual(tiny_time_value_rounding(c,sigma),math.nextafter(1.,math.inf))
                put=contract(model,s=c.k,k=c.s,call=False,shift=c.shift)
                self.assertEqual(tiny_time_value_rounding(put,sigma),math.nextafter(1.,math.inf))

    def test_proof_overrides_the_false_agreed_midpoint(self):
        self.assertEqual(price_reference(contract(),1e-4,lambda:1.),math.nextafter(1.,math.inf))
        self.assertEqual(price_reference(contract(),1.,lambda:7.),7.)

    def test_existing_even_upper_midpoint(self):
        c=contract(s=.01,k=.001)
        self.assertEqual(tiny_time_value_rounding(c,1e-4),.009000000000000001)

    def test_unsupported_premises(self):
        for c,sigma in [(contract(r=.01),1e-4),(contract(q=.01),1e-4),
                        (contract(t=0.),1e-4),(contract(),0.),
                        (contract(s=-1.),1e-4),(contract(s=math.inf),1e-4),
                        (contract(),1.),(contract(t=math.nan),1e-4)]:
            self.assertIsNone(tiny_time_value_rounding(c,sigma))

    def test_otm_is_positive_but_rounds_to_zero(self):
        c=contract(call=False)
        self.assertGreater(positive_tail_bound(c,1e-4)[1],0)
        self.assertEqual(tiny_time_value_rounding(c,1e-4),0.)


if __name__=='__main__': unittest.main()
