#!/usr/bin/env python3
"""Refine every changed served value against the existing model definitions.

Run with mpmath 1.3.0. Reads the trace comparator's changed rows, evaluates at
220/440 digits plus input-dependent cancellation precision, and records signed
fractional-ULP errors. The changed near-zero Greek also uses differentiation.
"""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT/'oracle'))
from mpmath import mp
import mpmath
from common import Contract, word, bits
from gen_greeks import closed_form, differentiated
from gen_greek_bits import expansion


def main(source, destination):
    assert mpmath.__version__ == '1.3.0'
    rows = json.loads(gzip.decompress(source.read_bytes()))
    results = []
    for row in rows:
        if row['fixture'] == 'dd': continue
        fields = row['input_reference'].split()
        model, side, quantity = fields[:3]
        greek = row['fixture'] in ('greeks','greek_bits')
        start = 4 if row['fixture']=='greeks' else 3
        if row['fixture']=='greeks': assert fields[3] in ('resolved','single_route')
        s,k,t,r,q,sigma,shift = map(word, fields[start:start+7])
        contract = Contract(model, side=='call', s,k,t,r,q,shift)
        refined = []
        for precision in (220,440):
            with mp.workdps(precision+contract.digits(sigma)):
                value = (closed_form(contract,sigma)[quantity]
                         if greek else contract.price(sigma))
                refined.append(expansion(value))
                if greek:
                    independent = differentiated(contract,sigma)[quantity]
                    assert abs(value-independent) < mp.mpf('1e-150')*abs(value)
                reference = float(value)
                if row['fixture']!='greek_bits': assert bits(reference)==fields[-1]
                else: assert expansion(value)==(int(fields[10]),*fields[11:])
                signed_errors = {name:mp.nstr((mp.mpf(word(row[name]))-value)/math.ulp(reference),30)
                                 for name in ('before','after')}
        assert refined[0] == refined[1]
        results.append({**row,'refined_reference':refined[-1],
                        'signed_ulp_error':signed_errors,
                        'precision_digits':[220+contract.digits(sigma),440+contract.digits(sigma)],
                        'differentiation_checked':greek})
    provenance={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                for p in [Path(__file__),ROOT/'oracle/common.py',ROOT/'oracle/gen_greeks.py',ROOT/'oracle/gen_greek_bits.py']}
    output={'mpmath':mpmath.__version__,'source_sha256':provenance,'changed_served_rows':results}
    destination.write_text(json.dumps(output,indent=2)+'\n')
    print(f'{len(results)} changed served rows refined; all committed references confirmed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='audit_exponential_changes 1')
    parser.add_argument('--changes', type=Path, default=ROOT/'docs/evidence/dd-exponential-compatibility-changes.json.gz')
    parser.add_argument('--output', type=Path, default=ROOT/'docs/evidence/dd-exponential-refined-changes.json')
    args = parser.parse_args()
    main(args.changes, args.output)
