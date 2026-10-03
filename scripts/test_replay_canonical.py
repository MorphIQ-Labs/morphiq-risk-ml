#!/usr/bin/env python3
"""Negative controls for the portable captured-output gate."""
import unittest
from replay_canonical import verify


class ReplayTests(unittest.TestCase):
    def test_complete_and_corrupted_runs(self):
        rows = [dict(input=dict(id='one'), outputs=dict(admission=['ok'], price=['ok', 'value', 'bound']))]
        output = ('READY\n0:one\tadmission\tok\n0:one\tprice\tok\tvalue\tbound\n'
                  '0:one\tlatency\t0.01\nSTATS\t1\t1\t1\t1\t1\t1\n')
        self.assertEqual(verify(rows, output), 1)
        for corrupted in [output.replace('value', 'changed'),
                          output.replace('0:one\tprice\tok\tvalue\tbound\n', ''),
                          output + '0:one\tprice\tok\tvalue\tbound\n',
                          output.replace('0:one', '0:other'),
                          output.replace('READY\n', ''),
                          output.replace('STATS\t1\t1\t1\t1\t1\t1\n', ''),
                          output.replace('0:one\tlatency\t0.01\n', '')]:
            with self.assertRaises(ValueError):
                verify(rows, corrupted)


if __name__ == '__main__':
    unittest.main()
