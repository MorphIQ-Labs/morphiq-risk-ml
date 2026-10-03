#!/usr/bin/env python3
"""Project-generated DD Taylor coefficients: exact 1/n!, no upstream tables.

Python Fraction -> float rounds to nearest-even; the second rounding acts on
its exact rational residual. The ln(2) split is certified by enclosing
2*atanh(1/3), requiring BOTH endpoints to round to the same two words.
Run without arguments to emit OCaml, or --check to validate stored words.
"""
from fractions import Fraction as F
from math import factorial
from pathlib import Path
import re
import sys

DEGREE = 22


def split(value):
    hi = float(value)
    return hi, float(value - F(hi))


def ln2_split():
    lower = 2 * sum((F(1, 3)**(2*k+1)/(2*k+1) for k in range(100)), F(0))
    upper = lower + 2*F(1, 3)**201/(201*(1-F(1, 9)))
    assert split(lower) == split(upper)
    return split(lower)


def coefficients():
    return [split(F(1, factorial(n))) for n in range(1, DEGREE+1)]


def check():
    source = (Path(__file__).resolve().parent.parent / 'lib/dd.ml').read_text()
    block = source.split('let exp_coefficients =', 1)[1].split('|]', 1)[0]
    pairs = re.findall(r'hi = ([^;]+); lo = ([^ }]+)', block)
    actual = [(float.fromhex(h.strip()), float.fromhex(l.strip())) for h, l in pairs]
    assert actual == coefficients(), 'DD exponential coefficients differ from exact factorials'
    match = re.search(r'let ln2 = \{ hi = ([^;]+); lo = ([^ }]+)', source)
    assert tuple(float.fromhex(x.strip()) for x in match.groups()) == ln2_split()
    return actual


if __name__ == '__main__':
    if sys.argv[1:] == ['--check']:
        check()
        print('22 DD factorial splits and ln(2) verified from rational definitions')
    elif not sys.argv[1:]:
        print('let exp_coefficients =\n  [|')
        for hi, lo in coefficients():
            print(f'    {{ hi = {hi.hex()}; lo = {lo.hex()} }};')
        print('  |]')
    else:
        raise SystemExit('usage: dd_exp_coefficients.py [--check]')
