#!/usr/bin/env python3
"""Rational certificates for the rounded coefficient sets used by the kernels.

Bernstein coefficients enclose a polynomial on an entire interval. Differential
residuals then enclose the approximation error; no sampled function values enter
these bounds. This checks the mathematical inequalities, not a formal translation
of the OCaml evaluator. See docs/error-analysis.md for the floating-point paths.
"""
from fractions import Fraction as F
from math import comb, factorial, isqrt
from pathlib import Path
import re

U = F(1, 2**53)
H = 1/(1-100000*U)
ROOT = Path(__file__).resolve().parent.parent


def trim(p):
    while len(p) > 1 and p[-1] == 0:
        p.pop()
    return p


def add(p, q):
    return trim([(p[i] if i < len(p) else 0) + (q[i] if i < len(q) else 0)
                 for i in range(max(len(p), len(q)))])


def sub(p, q):
    return add(p, [-v for v in q])


def mul(p, q):
    result = [F(0)]*(len(p)+len(q)-1)
    for i, a in enumerate(p):
        for j, b in enumerate(q):
            result[i+j] += a*b
    return trim(result)


def scale(p, a):
    return [a*c for c in p]


def deriv(p):
    return [i*p[i] for i in range(1, len(p))] or [F(0)]


def val(p, x):
    result = F(0)
    for c in reversed(p):
        result = result*x+c
    return result


def bernstein(p, a, b):
    """Exact power-basis translation to [0,1], then Bernstein conversion."""
    q, width = [p[-1]], b-a
    for c in reversed(p[:-1]):
        q = ([a*q[0]+c]
             + [a*q[i]+width*q[i-1] for i in range(1, len(q))]
             + [width*q[-1]])
    n = len(q)-1
    result = [sum((q[k]*F(comb(j, k), comb(n, k)) for k in range(j+1)), F(0))
              for j in range(n+1)]
    assert result[0] == val(p, a) and result[-1] == val(p, b)
    return result


def rational_bound(p, q, a, b, pieces=128):
    """Upper bound for |p/q|; nonnegative q coefficients make q monotone."""
    assert a >= 0 and b >= a and all(c >= 0 for c in q) and val(q, a) > 0
    result = F(0)
    for i in range(pieces):
        lo, hi = a+(b-a)*F(i, pieces), a+(b-a)*F(i+1, pieces)
        result = max(result, max(map(abs, bernstein(p, lo, hi)))/val(q, lo))
    return result


def atan_bounds(x, n):
    total = sum(((-1)**k*x**(2*k+1)/F(2*k+1) for k in range(n)), F(0))
    remainder = (-1)**n*x**(2*n+1)/F(2*n+1)
    return min(total, total+remainder), max(total, total+remainder)


def inverse_sqrt_pi():
    # Machin's identity and alternating remainders, followed by integer sqrt.
    a, b = atan_bounds(F(1, 5), 100)
    c, d = atan_bounds(F(1, 239), 30)
    pi_lo, pi_hi = 16*a-4*d, 16*b-4*c
    bits = 192
    lo = F(isqrt((2**(2*bits)*pi_hi.denominator)//pi_hi.numerator), 2**bits)
    hi = F(isqrt((2**(2*bits)*pi_lo.denominator)//pi_lo.numerator)+1, 2**bits)
    assert lo*lo*pi_hi <= 1 <= hi*hi*pi_lo
    return lo, hi


def approximation_bounds():
    lo, hi = inverse_sqrt_pi()
    c = (lo+hi)/2
    import erf_certificates
    error_functions = erf_certificates.verify()
    w = [F(0), F(1)]

    source = (ROOT/'lib/normalised_black.ml').read_text()
    y = source.split('let y_prime h =', 1)[1].split('(* Region II:', 1)[0]
    pattern = r'(?<![A-Za-z_0-9])[-+]?[0-9]+\.[0-9]*(?:[eE][-+]?[0-9]+)?'
    expression = y.split('let g =', 1)[1].split('    in', 1)[0]
    numbers = [F(float(v)) for v in re.findall(pattern, expression)]
    assert len(numbers) == 13
    a, b = [-abs(v) for v in numbers[:6]], numbers[6:]
    assert b[0] == 1
    cp, b2 = add(b, mul(w, a)), mul(b, b)
    # G(a)=Y'(-a), a G'-(1+a²)G+1=0. In the tail G=w C(w)/B(w).
    numerator = sub(sub(b2, mul([1, 3], mul(cp, b))),
                    scale(mul([0, 0, 1], sub(mul(deriv(cp), b), mul(cp, deriv(b)))), 2))
    yp_tail = rational_bound(numerator, b2, F(0), F(1, 16))
    y_tail_at_4 = F(1, 16)*val(cp, F(1, 16))/val(b, F(1, 16))
    g = rational_bound(mul(w, [-v for v in a]), b, F(0), F(1, 16))
    assert g/(1-g) < F(1, 4)

    expression = y.split('else if h <= -0.46875 then', 1)[1].split('  else', 1)[0]
    numbers = [F(float(v)) for v in re.findall(pattern, expression)]
    assert len(numbers) == 16
    p, q = numbers[:8], numbers[8:]
    p[-1] = -p[-1]
    assert q[0] == 1
    q2 = mul(q, q)
    numerator = add(sub(mul(w, sub(mul(deriv(p), q), mul(p, deriv(q)))),
                        mul([1, 0, 1], mul(p, q))), q2)
    yp_middle = rational_bound(numerator, q2, F(15, 32), F(4))
    jump = abs(val(p, F(4))/val(q, F(4))-y_tail_at_4)*(1+yp_tail)/y_tail_at_4
    yp_middle = max(yp_middle, yp_tail+jump)
    # Only the highest numerator coefficient is negative. Its absolute
    # coefficient condition is below 1.001 on this interval. The standard
    # absolute Horner bound handles cancellation in its inner stages.
    assert 2*abs(p[-1])*4**7/p[0] < F(1, 1000)
    return {**error_functions, 'yprime_tail': yp_tail, 'yprime_middle': yp_middle}


def rounding_bounds(approximation):
    # Generated error functions carry their own rational/FMA certificates.
    error_functions = max(approximation[k] for k in
        ('erfcx_local_total','erfcx_tail_total','erfcx_asymptote_total'))
    assert error_functions < 40*U

    yp_middle = (approximation['yprime_middle']
                 + F(1001, 1000)*((1+U)**15/(1-U)**14-1))*H
    yp_tail = (approximation['yprime_tail']
               + ((1+U)**4*(1+((1+U)**30/(1-U)**24-1)/4)-1))*H
    # On [0,.46875], G=1-a Mills(a); a*Mills/(1-a*Mills)<1.5.
    # Forty u from erfcx, two u from its argument, three u for constants
    # and products, then subtraction. Deliberately bound these products too.
    yp_small = (F(3, 2)*((1+40*U)*(1+U)**5-1)+U)*H
    assert F(1254,1000)*F(15,32)/(1-F(1254,1000)*F(15,32)) < F(3,2)
    yprime = max(yp_middle, yp_tail, yp_small)
    assert yprime < 96*U
    return {'erfcx_nonnegative': error_functions, 'yprime': yprime}


def verify():
    approximation = approximation_bounds()
    return approximation, rounding_bounds(approximation)


if __name__ == '__main__':
    approximation, rounded = verify()
    for name, bound in {**approximation, **rounded}.items():
        print(f'{name}: {float(bound/U):.12g} u')
