"""Failure controls for independent reference scoring and complete result rows."""
import copy
from fractions import Fraction as F
import unittest
from numerical_cases import bits, cases, fingerprint
from numerical_campaign import parse_results, score, ulps


class Controls(unittest.TestCase):
    def row(self):
        row=cases('smoke')[0]
        row.update(mode='production',quantity='price',reference=dict(status='interval',lower='1',upper='1'))
        return row

    def value(self,x=1.,radius=0.):
        return dict(status='certificate',value=bits(x),radius=bits(radius))

    def score(self,row,result): return score(row,result,{'black price':1})[0]

    def test_certificate_predicate(self):
        row=self.row()
        self.assertEqual(self.score(row,self.value()),'value_checked')
        self.assertEqual(self.score(row,self.value(2.)),'wrong_value')
        row['reference'].update(lower=str(F(1)-F(1,2**60)),upper=str(F(1)+F(1,2**60)))
        self.assertEqual(self.score(row,self.value()),'reference_unresolved')
        self.assertEqual(self.score(row,self.value(radius=2.**-59)),'value_checked')

    def test_nonfinite_certificate_even_with_unresolved_reference(self):
        row=self.row();row['reference']=dict(status='unresolved')
        self.assertEqual(self.score(row,self.value(radius=float('inf'))),'invalid_success')
        self.assertEqual(self.score(row,self.value(float('nan'))),'invalid_success')
        self.assertEqual(self.score(row,dict(status='value',value=bits(1.),radius='-')),'invalid_success')

    def test_accuracy_limit(self):
        row=self.row();row['inputs']['limit']=bits(2.**-20)
        self.assertEqual(self.score(row,self.value(radius=2.**-19)),'invalid_success')

    def test_root_words(self):
        row=self.row();row.update(quantity='iv',mode='iv',reference=dict(status='root',word=bits(1.)))
        self.assertEqual(self.score(row,dict(status='root',value=bits(1.),radius='-')),'value_checked')
        self.assertEqual(self.score(row,dict(status='root',value=bits(2.),radius='-')),'wrong_value')

    def test_explicit_failure_and_classifications(self):
        row=self.row();failure=dict(status='numerical_failure',value='-',radius='-')
        self.assertEqual(self.score(row,failure),'availability_failure')
        row['region']='greek_zeros'
        self.assertEqual(self.score(row,failure),'availability_regression')
        row['region']='expiry';row['reference']=dict(status='class',expected='unsupported_expiry')
        self.assertEqual(self.score(row,failure),'wrong_class')
        self.assertEqual(self.score(row,dict(status='unsupported_expiry',value='-',radius='-')),'class_checked')

    def test_fast_budget_and_nonfinite_distinctions(self):
        self.assertEqual(ulps(2.,-2.),2**63)
        row=self.row();row['mode']='fast';row['reference']['rounded']=bits(1.)
        self.assertEqual(self.score(row,dict(status='value',value=bits(2.),radius='-')),'quality_excursion')
        self.assertEqual(self.score(row,dict(status='value',value=bits(float('inf')),radius='-')),'nonfinite_fast_price')
        row['quantity']='gamma'
        self.assertEqual(self.score(row,dict(status='value',value=bits(float('inf')),radius='-')),'invalid_success')

    def test_result_completeness_and_identity(self):
        rows=cases('smoke')[:2]
        lines=[f"{r['id']} {fingerprint(r)} value {bits(1.)} -" for r in rows]
        self.assertEqual(len(parse_results('\n'.join(lines),rows)),2)
        for fault in ('',lines[0], '\n'.join([lines[0],lines[0]]),
                      '\n'.join(lines)[:-5], '\n'.join(lines).replace(fingerprint(rows[0]),'0'*64),
                      '\n'.join(lines).replace('value','unknown',1)):
            with self.assertRaises(ValueError): parse_results(fault,rows)

    def test_membership_is_bounded_and_reproducible(self):
        for lane in ('smoke','full'):
            rows=cases(lane)
            self.assertEqual(rows,cases(lane))
            self.assertEqual(len(rows),len({r['id'] for r in rows}))
            self.assertLess(len(rows),50000)


if __name__=='__main__': unittest.main()
