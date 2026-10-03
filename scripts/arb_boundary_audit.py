#!/usr/bin/env python3
"""Optional independent FLINT/Arb enclosure of boundary-veta reference cells."""
import argparse
from collections import Counter
import gzip
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import struct
from flint import arb, ctx, __FLINT_VERSION__


def word(x):
    return struct.unpack('>d', bytes.fromhex(x.zfill(16)))[0]


def certify(model, inputs, reference):
    for precision in (256, 512, 1024, 2048):
        with ctx.workprec(precision):
            s, t, r, shift = map(arb, inputs)
            w = arb(1) if model == 'bachelier' else s + (shift if model == 'displaced' else 0)
            value = w*(-r*t).exp()*(r*t-arb(.5))/(365*(2*arb.pi()*t).sqrt())
            lower = (arb(math.nextafter(reference, -math.inf))+arb(reference))/2
            upper = (arb(math.nextafter(reference, math.inf))+arb(reference))/2
            if value > lower and value < upper:
                return precision
            if value < lower or value > upper:
                raise ArithmeticError('reference outside exact rounding cell')
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    counts, precisions = Counter(), Counter()
    unresolved = []
    wrong_control = False
    with gzip.open(args.fixture, 'rt') as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip() or line.startswith('#'):
                continue
            model, side, *fields = line.split()
            inputs = list(map(word, fields[:4]))
            reference = word(fields[4])
            bits = certify(model, inputs, reference)
            counts[model] += 1
            if bits is None:
                unresolved.append(dict(line=line_number, input=line.strip()))
            else:
                precisions[bits] += 1
                if not wrong_control:
                    try:
                        certify(model, inputs, math.nextafter(reference, math.inf))
                    except ArithmeticError:
                        wrong_control = True
                    else:
                        raise ArithmeticError('wrong adjacent reference was not rejected')
    report = dict(method='Arb interval evaluation of derived veta and exact rounding-cell comparison',
                  python_flint=importlib.metadata.version('python-flint'), flint=__FLINT_VERSION__,
                  source_sha256={str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in (args.fixture, Path(__file__), Path('oracle/gen_boundary_greeks.py'))},
                  rows=dict(counts), precision_counts=dict(precisions), unresolved=unresolved,
                  adjacent_wrong_reference_rejected=wrong_control,
                  scope='Independent interval arithmetic; derivative identity additionally checked by nested price differentiation. Not human review.')
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(dict(rows=sum(counts.values()), unresolved=len(unresolved), precisions=dict(precisions))))
    if not counts or unresolved or not wrong_control:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
