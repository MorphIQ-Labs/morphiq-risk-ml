#!/usr/bin/env python3
"""Generate the pre-specified canonical portfolio; no library outputs are used."""
import argparse
import gzip
import importlib.metadata
import json
import math
from pathlib import Path
import platform

import QuantLib as ql
from flint import __FLINT_VERSION__
from canonical_dataset import SCHEMA, digest_rows, validate_dataset
from shadow_campaign import mapped, word, rounded_quote, sha


def generate():
    if (ql.__version__, importlib.metadata.version('python-flint'), __FLINT_VERSION__) != ('1.43', '0.9.0', '3.6.0'):
        raise RuntimeError('canonical environment versions differ from specification')
    rows = []
    for model in ('bsm', 'black76', 'displaced', 'bachelier'):
        j = 0
        for t in (1 / 365, 1 / 12, .5, 1., 5., 10.):
            for m in (-4., -1., 0., 1., 4.):
                for total in (.1, .5, 1.):
                    scale = (.01, 100., 10000.)[j % 3]
                    r = (-.05, 0., .025, .1)[(j // 3) % 4]
                    q = (-.02, 0., .03)[(j // 12) % 3] if model == 'bsm' else r
                    shift = 1.25 * scale if model == 'displaced' else 0.
                    if model == 'bachelier':
                        k = (-scale, 0., scale)[(j // 3) % 3]
                        s = k + m * scale * total
                        sigma = scale * total / math.sqrt(t)
                    else:
                        k = scale - shift
                        forward = scale * math.exp(m * total)
                        s = forward * math.exp(-(r - q) * t) if model == 'bsm' else forward - shift
                        sigma = total / math.sqrt(t)
                    inputs = [s, k, t, r, q, sigma, shift]
                    for side in ('call', 'put'):
                        row = dict(id=f'canonical-{len(rows):04d}', model=model, side=side,
                                   inputs=list(map(word, inputs)), limit=word(1e-10),
                                   scenario=f'maturity-{j // 15}', category='interior',
                                   quantity=(-10000, 25000, -50000, 100000)[len(rows) % 4],
                                   currency='USD', factor=model + '-synthetic')
                        f, strike, d, stddev = mapped(row)
                        fn = ql.bachelierBlackFormula if model == 'bachelier' else ql.blackFormula
                        quote = fn(ql.Option.Call if side == 'call' else ql.Option.Put, strike, f, stddev, d)
                        row.update(quote=word(quote), canonical_mapped=list(map(word, (f, strike, d, stddev))),
                                   independent_price=word(rounded_quote(model, side, inputs)),
                                   design=dict(combination=j, moneyness=m, total_deviation=total, scale=scale))
                        rows.append(row)
                    j += 1
    sources = ['scripts/generate_canonical_dataset.py', 'scripts/canonical_dataset.py',
               'scripts/shadow_campaign.py', 'scripts/arb_reference_campaign.py',
               'docs/canonical-dataset.md']
    data = dict(schema=SCHEMA, row_count=len(rows), rows_sha256=digest_rows(rows),
                specification='docs/canonical-dataset.md', source_sha256={p: sha(p) for p in sources},
                versions=dict(quantlib=ql.__version__, python_flint=importlib.metadata.version('python-flint'),
                              flint=__FLINT_VERSION__, python=platform.python_version()),
                platform=platform.platform(),
                canonical_source='https://github.com/lballabio/QuantLib/tree/6b57206e04598f092efee66e3b367efc84771995',
                quantlib_binary_sha256={p.name:sha(p) for p in Path(ql.__file__).parent.glob('_QuantLib*') if p.is_file()},
                scope='Generated scalar model grid; no claim of observed institutional portfolio coverage.', rows=rows)
    validate_dataset(data)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version=SCHEMA)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = generate()
    raw = (json.dumps(data, indent=2, allow_nan=False) + '\n').encode()
    if args.output.suffix == '.gz':
        with args.output.open('wb') as stream:
            with gzip.GzipFile(fileobj=stream, mode='wb', mtime=0, filename='') as z:
                z.write(raw)
    else:
        args.output.write_bytes(raw)
    print(json.dumps(dict(rows=data['row_count'], rows_sha256=data['rows_sha256'])))


if __name__ == '__main__':
    main()
