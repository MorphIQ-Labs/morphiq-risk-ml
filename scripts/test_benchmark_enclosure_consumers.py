import unittest
import benchmark_enclosure_consumers as b


class Controls(unittest.TestCase):
    def raw(self):
        return '\n'.join([f'CHECK {c} served:0x1p0:0x1p-52' for c in sorted(b.CASES)] +
                         [f'TIME {key} {n} 100 90 200 1 0' for key, n in sorted(b.SLOTS)])+'\n'

    def test_records(self):
        raw = self.raw(); value = b.decode(raw)
        self.assertEqual(len(value['samples']), 120)
        for data, reason in [('', 'incomplete'), ('broken', 'malformed'),
                             (raw.rsplit('\n', 2)[0], 'incomplete'),
                             (raw+raw.splitlines()[0]+'\n', 'duplicate CHECK'),
                             (raw+raw.splitlines()[-1]+'\n', 'duplicate TIME'),
                             (raw.replace('100 90 200', 'nan 90 200'), 'invalid TIME'),
                             (raw.replace(' 1 0\n', ' -1 0\n'), 'invalid TIME GC')]:
            with self.assertRaisesRegex(ValueError, reason): b.decode(data)
        with self.assertRaisesRegex(ValueError, 'CHECK mismatch'): b.same_checks(value['checks'], {})

    def test_criteria(self):
        data = b.decode(self.raw())
        runs = [dict(variant=v, round=n, sample=data) for v in ('baseline', 'candidate') for n in range(5)]
        summary = b.summarize(runs); b.acceptance(summary)
        with self.assertRaisesRegex(ValueError, 'incomplete or duplicate'): b.summarize(runs[:-1])
        with self.assertRaisesRegex(ValueError, 'incomplete summary'): b.acceptance(summary[:-1])
        row = next(r for r in summary if r['key'].endswith('/price'))
        row['speedup'] = .5
        with self.assertRaisesRegex(ValueError, 'latency regression'): b.acceptance(summary)
        row['speedup'] = 1.; row['candidate']['allocation']['median'] = 1000
        with self.assertRaisesRegex(ValueError, 'allocation regression'): b.acceptance(summary)


if __name__ == '__main__': unittest.main()
