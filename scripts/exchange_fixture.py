#!/usr/bin/env python3
"""Export/check exact rational endpoints for dependency-free exchange tests."""
import argparse
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'docs/evidence/exchange-implementation'
FIXTURE = ROOT/'test/exchange_reference.tsv'
MANIFEST = BASE/'fixture-manifest.json'
SOURCES = ['scripts/exchange_fixture.py', 'scripts/exchange_reference.py',
           'docs/evidence/exchange-implementation/cases-v1.json',
           'docs/evidence/exchange-implementation/references-v2.json', 'test/exchange_reference.tsv']

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--check', action='store_true')
    p.add_argument('--version', action='version', version='exchange-fixture 1')
    args=p.parse_args()
    if not args.check:
        from flint import arb, ctx
        ctx.prec=512
        data=json.loads((BASE/'references-v2.json').read_text())
        lines=[]
        for row in data['rows']:
            ref=row['reference']; status=ref['status']
            bounds=[]
            if status=='interval':
                for name in ('closed','integral'):
                    interval=arb(ref[name])
                    bounds.extend(str(x.fmpq()) for x in (interval.lower(),interval.upper()))
            lines.append(' '.join([row['id'], str(int(row['required'])), status, *row['inputs'].values(), *bounds]))
        FIXTURE.write_text('\n'.join(lines)+'\n')
        MANIFEST.write_text(json.dumps({n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in SOURCES},indent=2)+'\n')
    for name, digest in json.loads(MANIFEST.read_text()).items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:
            raise SystemExit('exchange fixture provenance mismatch: '+name)
    data=json.loads((BASE/'references-v2.json').read_text())
    if data['generator_sha256'] != hashlib.sha256((ROOT/'scripts/exchange_reference.py').read_bytes()).hexdigest():
        raise SystemExit('reference generator mismatch')
    if data['corpus_sha256'] != hashlib.sha256((BASE/'cases-v1.json').read_bytes()).hexdigest():
        raise SystemExit('reference corpus mismatch')
    print('exchange fixture provenance: OK')
if __name__=='__main__': main()
