"""Standard-library schema and provenance checks for captured shadow inputs."""
import gzip
import hashlib
import json
import math
from pathlib import Path
import re
import struct

SCHEMA = 'morphiq-canonical-portfolio-v1'
MODELS = {'bsm', 'black76', 'displaced', 'bachelier'}
FIELDS = {'id', 'model', 'side', 'inputs', 'quote', 'limit', 'scenario',
          'category', 'quantity', 'currency', 'factor'}


def decode_word(value):
    if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{16}', value):
        raise ValueError('expected a lowercase binary64 word')
    result = struct.unpack('>d', bytes.fromhex(value))[0]
    if not math.isfinite(result):
        raise ValueError('nonfinite input word')
    return result


def digest_rows(rows):
    return hashlib.sha256(json.dumps(rows, sort_keys=True, separators=(',', ':'),
                                     allow_nan=False).encode()).hexdigest()


def validate_dataset(data):
    if not isinstance(data, dict) or data.get('schema') != SCHEMA:
        raise ValueError('unsupported portfolio schema')
    rows = data.get('rows')
    if not isinstance(rows, list) or not rows:
        raise ValueError('nonempty portfolio required')
    ids = set()
    for row in rows:
        if not isinstance(row, dict) or not FIELDS <= row.keys():
            raise ValueError('missing row fields')
        for key in ('id', 'scenario', 'factor'):
            if not isinstance(row[key], str) or not re.fullmatch('[A-Za-z0-9_.-]+', row[key]):
                raise ValueError('invalid identifier')
        if row['id'] in ids:
            raise ValueError('duplicate row identifier')
        ids.add(row['id'])
        if row['model'] not in MODELS or row['side'] not in ('call', 'put'):
            raise ValueError('invalid model/side')
        if row['category'] != 'interior' or row['currency'] != 'USD':
            raise ValueError('unsupported qualification category/currency')
        if type(row['quantity']) is not int or not 0 < abs(row['quantity']) <= 100000:
            raise ValueError('invalid position quantity')
        if not isinstance(row['inputs'], list) or len(row['inputs']) != 7:
            raise ValueError('seven original input words required')
        for value in row['inputs']:
            decode_word(value)
        if decode_word(row['quote']) < 0 or decode_word(row['limit']) != 1e-10:
            raise ValueError('invalid quote or changed request limit')
    if data.get('row_count') != len(rows) or data.get('rows_sha256') != digest_rows(rows):
        raise ValueError('row count/hash mismatch')
    return rows


def load_dataset(path):
    path = Path(path)
    raw = gzip.decompress(path.read_bytes()) if path.suffix == '.gz' else path.read_bytes()
    data = json.loads(raw)
    return data, validate_dataset(data)
