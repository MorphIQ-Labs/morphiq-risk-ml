#!/usr/bin/env python3
"""Build a test-only fixture identity catalog from verified committed archives."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path


def blake(data):
    return hashlib.blake2b(data, digest_size=32).hexdigest()


def manifest(root):
    records = {}
    for line in (root / 'MANIFEST').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split()
        if (len(fields) < 8 or fields[0] in records
                or not fields[0].replace('_', '').isalnum()):
            raise ValueError('malformed or duplicate manifest record')
        records[fields[0]] = (int(fields[6]), fields[7])
    if not records:
        raise ValueError('empty fixture manifest')
    return records


def verified_text(path, names=None):
    """Validate a single immutable archive snapshot against its sibling manifest."""
    name = path.name.removesuffix('.txt.gz')
    if path.name != name + '.txt.gz' or (names is not None and name not in names):
        raise ValueError('unexpected fixture name: ' + path.name)
    records = manifest(path.parent.parent)
    if name not in records:
        raise ValueError('fixture absent from manifest: ' + name)
    expected_rows, digest = records[name]
    archive = path.read_bytes()
    if blake(archive) != digest:
        raise ValueError('compressed fixture hash mismatch: ' + name)
    raw = gzip.decompress(archive)
    text = raw.decode()
    rows = sum(bool(s.strip()) and not s.startswith('#') for s in text.splitlines())
    if rows != expected_rows or rows == 0:
        raise ValueError('fixture row count mismatch: ' + name)
    return text


def catalog(root):
    result = {}
    for name, (rows, _) in manifest(root).items():
        raw = verified_text(root / 'fixtures' / (name + '.txt.gz')).encode()
        result[name] = (rows, blake(raw))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='fixture-catalog 1')
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    print('let records = [')
    for name, (rows, digest) in sorted(catalog(args.root).items()):
        print(f'  ({json.dumps(name)}, ({rows}, {json.dumps(digest)}));')
    print(']')


if __name__ == '__main__': main()
