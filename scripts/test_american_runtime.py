#!/usr/bin/env python3
"""The runtime scorer must reject missing, corrupt and incorrectly accepted data."""
import copy
import unittest
from check_american_runtime import classify


class Controls(unittest.TestCase):
    def setUp(self):
        self.case = dict(id='witness', epsilon='3f50624dd2f1a9fc')
        self.ref = dict(id='witness', reference=dict(status='resolved', kind='analytic_interval', lower='1', upper='1'))

    def score(self, text, ref=None):
        return classify(text, [self.case], [ref or self.ref], 'primary')[0]

    def test_wrong_price(self):
        self.assertEqual(self.score('witness\testimated\t0x1p+1\tmethod')['comparison']['status'], 'fail')

    def test_unavailable_is_not_pass(self):
        self.assertEqual(self.score('witness\tunavailable\t-\tarithmetic:resolution')['comparison']['status'], 'runtime_unavailable')

    def test_unresolved_is_not_pass(self):
        ref = copy.deepcopy(self.ref)
        ref['reference'] = dict(status='unresolved')
        self.assertEqual(self.score('witness\testimated\t0x1p+0\tmethod', ref)['comparison']['status'], 'unresolved_reference')

    def test_protocol_rejections(self):
        for text, reason in [('', 'missing'),
                             ('other\testimated\t0x1p+0\tmethod', 'identity'),
                             ('witness\testimated\tnan\tmethod', 'nonfinite'),
                             ('witness\tunavailable\t0x1p+0\tarithmetic:x', 'usable price'),
                             ('witness\tpartial\t-\tmethod', 'outcome'),
                             ('witness\testimated\t0x1p+0', 'malformed'),
                             ('witness\tunavailable\t-\twhatever', 'unknown failure')]:
            with self.subTest(reason=reason), self.assertRaisesRegex(ValueError, reason):
                self.score(text)


if __name__ == '__main__':
    unittest.main()
