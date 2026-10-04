#!/usr/bin/env python3
"""Bounded, independently adjudicated minimization of a false precision agreement.

Manual lane: python-flint==0.9.0 and mpmath==1.3.0. The intentionally challenged
reference is common.agreed(Contract.price), without the existing rational repair.
No production output or committed fixture is modified or used as ground truth.
"""
import argparse
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ('s', 'k', 't', 'r', 'q', 'sigma', 'shift')
STATUSES = ('failure', 'no_failure', 'unresolved', 'invalid', 'tool_error')


def bits(x):
    return struct.pack('>d', x).hex()


def exact(words):
    if len(words) != 7 or any(len(w) != 16 for w in words):
        raise ValueError('seven binary64 words required')
    return [struct.unpack('>d', bytes.fromhex(w))[0] for w in words]


def valid(values):
    s, k, t, r, q, sigma, shift = values
    return (all(map(math.isfinite, values)) and s > 0 and k > 0 and t > 0
            and sigma > 0 and r == q == shift == 0)


def run_checked(command, timeout):
    """A crashed, absent, timed-out or malformed reference never proves failure."""
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        if result.returncode:
            return dict(status='tool_error', reason=f'exit {result.returncode}', stderr=result.stderr)
        value = json.loads(result.stdout)
        if not isinstance(value, dict) or value.get('status') not in STATUSES:
            raise ValueError('missing reference status')
        # The worker supplies the rigorous predicate. A status without its
        # certificate is incomplete output, not an independently resolved fault.
        if value['status'] == 'failure' and not all(key in value for key in
                ('inputs', 'observed', 'expected', 'rational_bracket', 'arb')):
            raise ValueError('missing failure certificate')
        return value
    except (OSError, subprocess.TimeoutExpired, ValueError) as error:
        return dict(status='tool_error', reason=str(error))


def evaluate(words):
    values = exact(words)
    if not valid(values):
        return dict(status='invalid', inputs=words, reason='outside smooth zero-carry BSM call scope')
    sys.path.insert(0, str(ROOT / 'oracle'))
    from common import Contract, agreed
    from price_rounding import positive_tail_bound, tiny_time_value_rounding
    from arb_reference_campaign import audit, price, positive_tail
    s, k, t, r, q, sigma, shift = values
    c = Contract('bsm', True, s, k, t, r, q, shift)
    observed = agreed(lambda: c.price(sigma))
    expected = tiny_time_value_rounding(c, sigma)
    record = dict(inputs=words, observed=None if observed is None else bits(observed),
                  expected=None if expected is None else bits(expected))
    if observed is None or expected is None:
        return dict(record, status='unresolved', reason='agreement or rational tail proof unavailable')
    intrinsic, bound = positive_tail_bound(c, sigma)
    record['rational_bracket'] = dict(lower_exclusive=str(intrinsic),
                                     upper_exclusive=str(intrinsic + bound))
    assess = lambda reference: audit(lambda: price('bsm', 'call', values), reference,
                                    lambda: positive_tail('bsm', 'call', values))
    observed_check, expected_check = assess(observed), assess(expected)
    record['arb'] = dict(observed=observed_check, expected=expected_check)
    if expected_check[0] != 'certified' or observed_check[0] == 'unresolved':
        return dict(record, status='unresolved', reason='independent enclosure did not resolve both cells')
    if bits(observed) != bits(expected) and observed_check[0] == 'wrong':
        return dict(record, status='failure')
    return dict(record, status='no_failure')


def candidates(words):
    """One finite normalization pass; no claim of global/minimal-bit optimality."""
    values = exact(words)
    # Failed and unresolved proposals are deliberately retained, not filtered out.
    for field, replacement in [('t', 0.), ('t', 1.), ('k', 0.), ('s', 1.),
                               ('sigma', 1.), ('sigma', 2.**-14)]:
        proposed = values.copy()
        proposed[FIELDS.index(field)] = replacement
        yield field + '=' + replacement.hex(), list(map(bits, proposed))
    # Remove a common monetary power-of-two scale while preserving original
    # binary64 inputs exactly. The predicate must still resolve after rescaling.
    s, k, *_ = values
    scale = math.frexp(s)[1] - 1
    proposed = values.copy()
    proposed[0], proposed[1] = math.ldexp(s, -scale), math.ldexp(k, -scale)
    yield 'normalize monetary scale', list(map(bits, proposed))


def minimize(original, assess):
    current = original
    first = assess(current)
    if first['status'] != 'failure':
        return dict(original=first, minimized=first, attempts=[], complete=False)
    attempts = []
    # Rebuild the finite proposal list after each accepted reduction, preserving
    # earlier simplifications. Exactly seven proposals, no unbounded search.
    for index in range(7):
        label, proposal = list(candidates(current))[index]
        result = assess(proposal)
        accepted = result['status'] == 'failure' and proposal != current
        attempts.append(dict(reduction=label, accepted=accepted, result=result))
        if accepted:
            current = proposal
    final = assess(current)  # independent final recheck, not cached acceptance
    return dict(original=first, minimized=final, attempts=attempts,
                complete=final['status'] == 'failure' and
                all(a['result']['status'] != 'tool_error' for a in attempts))


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', dir=path.parent, delete=False) as stream:
        name = stream.name
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write('\n')
    try:
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)



def conversion_controls():
    """Challenge the actual mpmath-to-binary64 boundary with exact dyadics."""
    sys.path.insert(0, str(ROOT / 'oracle'))
    from common import round_binary64
    from mpmath import mp
    from fractions import Fraction as F
    from arb_reference_campaign import classify
    from flint import arb, ctx
    midpoint = F(1) + F(1, 2**53)
    half_subnormal = F(1, 2**1075)
    cases = [(midpoint, 1.), (midpoint + F(1, 2**110), math.nextafter(1., math.inf)),
             (midpoint - F(1, 2**110), 1.), (half_subnormal, 0.),
             (half_subnormal + F(1, 2**1200), 2.**-1074),
             (half_subnormal - F(1, 2**1200), 0.)]
    records = []
    with mp.workprec(2048), ctx.workprec(2048):
        for value, expected in cases:
            exact_mp = mp.mpf(value.numerator) / value.denominator
            observed = round_binary64(exact_mp)
            interval = arb(value.numerator) / arb(value.denominator)
            if bits(observed) != bits(expected) or classify(interval, expected) != 'certified':
                raise ArithmeticError('exact binary64 conversion control failed')
            records.append(dict(exact=str(value), rounded=bits(observed)))
        cancelled = (mp.mpf(1) + mp.mpf(2)**-80) - 1
        if round_binary64(cancelled) != 2.**-80:
            raise ArithmeticError('cancellation control failed')
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='oracle-challenge 1')
    parser.add_argument('--worker', nargs=7, metavar='HEXWORD')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.worker:
        print(json.dumps(evaluate(args.worker), allow_nan=False))
        return
    if not args.output: parser.error('--output required')
    from arb_reference_campaign import controls, audit
    from flint import arb, __FLINT_VERSION__
    import flint.types.arb as arb_module
    import mpmath
    controls()
    conversions = conversion_controls()
    wide = audit(lambda: arb(1, 2.**-40), 1.)
    if wide[0] != 'unresolved' or wide[1] != 4096:
        raise ArithmeticError('insufficient uncertainty falsely accepted')
    original = list(map(bits, [math.nextafter(128., math.inf), 2.**-46, 4., 0., 0., 1e-4, 0.]))
    command = [sys.executable, str(Path(__file__).resolve()), '--worker']
    def assess(words):
        result = run_checked(command + words, timeout=60)
        if result.get('inputs') != words:
            return dict(status='tool_error', inputs=words, reason='missing/mismatched input identity', output=result)
        return result
    result = minimize(original, assess)
    sources = ['scripts/oracle_challenge.py', 'scripts/arb_reference_campaign.py',
               'scripts/arb_iv_audit.py', 'scripts/arb_greek_audit.py',
               'oracle/common.py', 'oracle/price_rounding.py', 'scripts/fixture_catalog.py']
    result.update(schema=1, model='bsm', side='call', quantity='price', fields=FIELDS,
                  violated_contract='correct binary64 rounding of the exact original-input price',
                  challenged_reference='common.agreed(Contract.price), bypassing existing rational repair',
                  uncertainty_control=wide, exact_midpoint_controls=True,
                  exact_conversion_controls=conversions, cancellation_control=True,
                  termination='7 proposals plus original/final checks; 60s per worker; Arb 256..4096 bits; common.agreed at most 6 precisions',
                  scope='Known false-agreement regression; finite normalization, not global minimality or a new production defect',
                  tool_sha256={name: hashlib.sha256(p.read_bytes()).hexdigest() for name, p in
                               [('python', Path(sys.executable).resolve()),
                                ('arb_extension', Path(arb_module.__file__)),
                                ('mpmath_init', Path(mpmath.__file__))]},
                  python=platform.python_version(), mpmath=importlib.metadata.version('mpmath'),
                  python_flint=importlib.metadata.version('python-flint'), flint=__FLINT_VERSION__,
                  source_sha256={name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sources},
                  reproduce='python scripts/oracle_challenge.py --output /tmp/oracle-challenge.json')
    atomic_json(args.output, result)
    print(json.dumps(dict(complete=result['complete'], attempts=len(result['attempts']),
                         minimized=result['minimized'].get('inputs'))))
    if not result['complete']: raise SystemExit(1)


if __name__ == '__main__': main()
