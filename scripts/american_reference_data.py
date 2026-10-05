"""Offline schema, raw-output and scoring owners for the #110 research fixtures."""
from fractions import Fraction as F
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import subprocess

FIELDS = ('spot', 'strike', 'rate', 'yield_', 'volatility', 'time', 'opens')
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'docs/evidence/american-references'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))


def decode(word):
    require(isinstance(word, str) and re.fullmatch('[0-9a-f]{16}', word), 'invalid input word')
    value = struct.unpack('>d', bytes.fromhex(word))[0]
    require(math.isfinite(value), 'nonfinite input word')
    return value


def inputs(row):
    return {k: decode(row['inputs'][k]) for k in FIELDS}


def validate_corpus(corpus):
    require(corpus['schema'] == 'american-reference-corpus-v1', 'corpus schema')
    rows = corpus['rows']
    require(0 < len(rows) <= 50, 'corpus row budget')
    require(len({r['id'] for r in rows}) == len(rows), 'duplicate corpus id')
    for row in rows:
        require(re.fullmatch('[A-Za-z0-9_-]+', row['id']) is not None, 'invalid id')
        require(set(row['inputs']) == set(FIELDS), 'input fields')
        require(row['side'] in ('call', 'put'), 'invalid side')
        p = inputs(row)
        require(all(p[k] >= 0 for k in ('spot', 'strike', 'volatility', 'time', 'opens'))
                and p['opens'] <= p['time'], 'invalid model')
        require(F(decode(row['epsilon'])) == max(F(p['spot']), F(p['strike']))/65536,
                'changed epsilon policy')
    return rows


def first_index(row, n):
    p = inputs(row)
    if p['time'] == 0:
        return 0
    index = F(p['opens'])*n/F(p['time'])
    return -(-index.numerator // index.denominator)


def runner_input(rows, levels):
    return ''.join(' '.join([r['id'], r['side'], str(n), str(first_index(r, n)),
                            *[r['inputs'][f] for f in FIELDS]])+'\n'
                   for r in rows for n in levels)


def parse_raw(text, expected):
    rows = {}
    for line in text.splitlines():
        fields = line.split('\t')
        require(len(fields) == 7, 'truncated or extra output fields')
        name, level, status, *rest = fields
        require(level.isdigit(), 'invalid output level')
        key = (name, int(level))
        require(key in expected, 'unexpected output row')
        require(key not in rows, 'duplicate output row')
        require(status in ('finite', 'unavailable', 'exception', 'incompatible'), 'output status')
        values = []
        for token in rest[:3]:
            if token == '-':
                values.append(None)
            else:
                try:
                    value = float.fromhex(token)
                except ValueError as error:
                    raise ValueError('invalid output number') from error
                require(math.isfinite(value), 'nonfinite output number')
                require(re.fullmatch(r'-?0x[0-9a-f]+(?:\.[0-9a-f]+)?p[+-][0-9]+', token),
                        'output number must be hexadecimal')
                values.append(token)
        require((status in ('finite', 'incompatible')) == (values[0] is not None),
                'status/value mismatch')
        require(bool(rest[3]), 'missing outcome detail')
        rows[key] = dict(status=status, american=values[0], european=values[1],
                         bermudan=values[2], detail=rest[3])
    require(rows.keys() == expected, 'missing output row')
    return rows


def capture(command, text, output, timeout):
    """Save raw output even on failure; no failed runner can publish references."""
    path = Path(output)
    try:
        process = subprocess.run(command, input=text, text=True, capture_output=True,
                                 timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raw = error.stdout or b''
        path.write_bytes(raw.encode() if isinstance(raw, str) else raw)
        path.with_suffix(path.suffix+'.stderr').write_text('process timeout\n')
        raise ValueError('runner timeout') from error
    except OSError as error:
        path.write_text('')
        path.with_suffix(path.suffix+'.stderr').write_text(str(error)+'\n')
        raise ValueError('runner startup failure') from error
    path.write_text(process.stdout)
    path.with_suffix(path.suffix+'.stderr').write_text(process.stderr)
    require(process.returncode == 0, 'runner exit failure')
    require(len(process.stdout.encode()) <= 8*1024*1024, 'output budget')
    return process.stdout


def interval(reference):
    require(reference['status'] == 'resolved', 'unresolved reference')
    require(reference['kind'] in ('analytic_interval', 'empirical'), 'reference kind')
    lo, hi = F(reference['lower']), F(reference['upper'])
    require(lo <= hi, 'reversed reference interval')
    return lo, hi


def score_price(reference, value, epsilon):
    if reference['status'] != 'resolved':
        return dict(status='unresolved_reference')
    require(math.isfinite(value), 'nonfinite candidate')
    lo, hi = interval(reference)
    limit = F(epsilon)
    if (hi-lo)/2 > limit/8:
        return dict(status='reference_too_wide')
    error = max(abs(F(value)-lo), abs(F(value)-hi))
    return dict(status='pass' if error <= limit else 'fail', worst_error=str(error),
                scope=reference['kind'])


def validate_fixture(corpus, fixture):
    rows = validate_corpus(corpus)
    require(fixture['schema'] == 'american-references-v1' and fixture['complete'] is True,
            'incomplete fixture')
    require([r['id'] for r in fixture['rows']] == [r['id'] for r in rows],
            'fixture row identity/order')
    for case, row in zip(rows, fixture['rows']):
        require(row['inputs'] == case['inputs'], 'fixture input mismatch')
        ref = row['reference']
        require(ref['status'] in ('resolved', 'unresolved'), 'reference status')
        if ref['status'] == 'resolved':
            lo, hi = interval(ref)
            require((hi-lo)/2 <= F(decode(case['epsilon']))/8, 'reference width exceeds policy')
            require(hi >= 0, 'negative reference')
        else:
            require(bool(ref['reason']), 'missing unresolved reason')
        require([v['level'] for v in row['canonical']] == corpus['policy']['quantlib_levels'],
                'canonical level identity/order')
        for comparison in row['canonical']:
            require(comparison['outcome']['status'] in ('finite', 'exception', 'incompatible'),
                    'canonical status')
            status = comparison['comparison']['status']
            if status == 'pass':
                require(ref['status'] == 'resolved' and comparison['outcome']['status'] == 'finite',
                        'unresolved or excluded comparison passed')
                actual = score_price(ref, float.fromhex(comparison['outcome']['american']),
                                     decode(case['epsilon']))
                require(actual['status'] == 'pass', 'incorrect comparison expectation')
    return fixture['rows']


def verify_manifest(base=BASE, root=ROOT):
    manifest = strict_json((base/'manifest.json').read_text())
    for name, digest in manifest['sha256'].items():
        path = Path(name)
        require(not path.is_absolute() and '..' not in path.parts, 'manifest path')
        require(hashlib.sha256((root/path).read_bytes()).hexdigest() == digest,
                'fixture provenance mismatch: '+name)
    corpus = strict_json((base/'cases-v1.json').read_text())
    fixture = strict_json((base/'references-v1.json').read_text())
    validate_fixture(corpus, fixture)
    return len(fixture['rows'])
