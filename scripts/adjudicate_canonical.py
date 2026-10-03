#!/usr/bin/env python3
"""Reproduce and independently decompose material canonical rho discrepancies.

The retained initial campaign is never edited and no scoring limit is changed.
The BSM operation sequence is specific to the recorded ARM64 QuantLib wheel;
its disassembly, source and binary identity are retained with the evidence.
"""
import argparse
from fractions import Fraction as F
import gzip
import json
import math
from pathlib import Path

import QuantLib as ql
from flint import arb, ctx
from shadow_campaign import number, word, sha, validate, mapped_model, price, derivative


def arb_fraction(value):
    return arb(value.numerator) / arb(value.denominator)


def adjudicate(record):
    row = record['input']
    comp = record['comparator']
    if row['side'] != 'call' or row['model'] not in ('bsm', 'black76', 'displaced'):
        raise ValueError('outside the reviewed rho operation path')
    if validate(row, 'rho', record['outputs']['rho'])['status'] != 'certified':
        raise ValueError('production rho failed independent certification')
    f, k, d, v = map(number, comp['mapped'])
    t = number(row['inputs'][2])
    observed = number(comp['values']['rho'])
    if min(f, k, d, v, t) <= 0:
        raise ValueError('outside smooth positive-forward formula preconditions')
    if row['model'] == 'bsm':
        cdf = ql.CumulativeNormalDistribution()
        d1 = math.log(f / k) / v + .5 * v
        d2 = d1 - v
        alpha, beta = cdf(d1), -cdf(d2)
        n1, n2 = cdf.derivative(d1), cdf.derivative(d2)
        # ARM64 disassembly: two fdiv, fmul/fmadd/fmadd for temp,
        # fmul/fmadd/fmul for -value, fmadd and final maturity fmul.
        temp = math.fma(-n2 / v, k, math.fma(n1 / v, f, alpha * f))
        negative_value = -d * math.fma(f, alpha, k * beta)
        reproduced = t * math.fma(d, temp, negative_value)
        exact_expression = F(t) * F(d) * ((F(n1) * F(f) - F(n2) * F(k)) / F(v) - F(k) * F(beta))
        method = 'QuantLib BlackCalculator ARM64 rho cancellation; exact source/binary operation replay'
        intermediates = {key: word(value) for key, value in dict(d1=d1, d2=d2, alpha=alpha,
                        beta=beta, n1=n1, n2=n2, temp=temp, negative_value=negative_value).items()}
    else:
        quote = number(comp['values']['price'])
        reproduced = -t * quote
        exact_expression = -F(t) * F(quote)
        method = 'Forward rho=-T*price; canonical price error plus final binary64 multiplication'
        intermediates = dict(canonical_price=word(quote))
    if word(reproduced) != comp['values']['rho']:
        raise ValueError('canonical operation replay differs from captured result')
    with ctx.workprec(512):
        model, inputs = mapped_model(row, [f, k, d, v])
        mapped_rho = derivative(model, row['side'], inputs, 'rho')
        original_rho = derivative(row['model'], row['side'], list(map(number, row['inputs'])), 'rho')
        rounding = F(observed) - exact_expression
        return dict(id=row['id'], name='rho', disposition='canonical_rho_floating_point_error',
                    method=method, reproduced_word=word(reproduced), intermediates=intermediates,
                    exact_arithmetic_rounding_error=str(rounding),
                    input_conversion=str(mapped_rho - original_rho),
                    canonical_primitive_or_price_error=str(arb_fraction(exact_expression) - mapped_rho),
                    canonical_total_error=str(arb(observed) - mapped_rho),
                    original_model_error=str(arb(observed) - original_rho),
                    production_certificate_independently_validated=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--campaign', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(gzip.decompress(args.campaign.read_bytes()))
    if data['versions']['quantlib'] != ql.__version__ or ql.__version__ != '1.43':
        raise RuntimeError('canonical version mismatch')
    binary = {p.name: sha(p) for p in Path(ql.__file__).parent.glob('_QuantLib*') if p.is_file()}
    if binary != data['input_provenance']['quantlib_binary_sha256']:
        raise RuntimeError('canonical wheel differs from captured campaign')
    remaining = [f for f in data['findings'] if f['disposition'] == 'requires_review']
    records = {r['input']['id']: r for r in data['rows']}
    decisions = []
    for finding in remaining:
        if finding['name'] != 'rho':
            raise RuntimeError('unreviewed material quantity')
        decisions.append(adjudicate(records[finding['id']]))
    if not decisions:
        raise RuntimeError('no findings to adjudicate')
    if data['failed_audits'] != [dict(unresolved_material_comparator_findings=True)]:
        raise RuntimeError('initial campaign contains other failures')
    # A completed changed-value rejection exercises replay, not a missing tool.
    control = json.loads(json.dumps(records[decisions[0]['id']]))
    w = control['comparator']['values']['rho']
    control['comparator']['values']['rho'] = word(math.nextafter(number(w), math.inf))
    try:
        adjudicate(control)
    except ValueError as error:
        if str(error) != 'canonical operation replay differs from captured result':
            raise
    else:
        raise RuntimeError('changed comparator value escaped replay')
    paths = ['scripts/adjudicate_canonical.py', 'scripts/shadow_campaign.py',
             'scripts/arb_greek_audit.py', 'scripts/arb_reference_campaign.py',
             'docs/evidence/quantlib-rho-arm64-disassembly.txt']
    report = dict(campaign_sha256=sha(args.campaign), source_sha256={p: sha(p) for p in paths},
                  decisions=decisions, unresolved_material_findings=0,
                  changed_comparator_rejected=True, qualification='passed_after_explicit_adjudication',
                  scope='Generated scalar workload only; original findings and initial failure are retained unchanged. No tolerance change or canonical-output repair.')
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(adjudicated=len(decisions), qualification=report['qualification'])))


if __name__ == '__main__':
    main()
