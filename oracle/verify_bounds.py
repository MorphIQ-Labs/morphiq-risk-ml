#!/usr/bin/env python3
"""Exact-rational checks of the majorants in docs/error-analysis.md.

This verifies the inequalities of the written analysis, not a formal
verification of the OCaml implementation. No measurements enter the constants.
Only Python's standard library is required at test build time.
"""
from fractions import Fraction as F
from math import factorial
import sys

u = F(1, 2**53)
u2 = u*u
add = 3*u2 + 13*u**3
mul = 5*u2
div = F(49, 5)*u2
# This factor bounds the higher-order products of the fewer than 1000 error
# factors in the paths below. 100000u also covers replacing perturbed magnitudes
# in denominators by their exact values (all denominators are bounded away
# from zero in these reductions).
inflate = 1/(1-100000*u)

# ln(2) from a rational atanh series, with a positive geometric remainder.
lower = 2*sum((F(1, 3)**(2*k+1)/F(2*k+1) for k in range(100)), F(0))
upper = lower + 2*F(1, 3)**201/(201*(1-F(1, 9)))
ln2 = F(float.fromhex('0x1.62e42fefa39efp-1')) + F(float.fromhex('0x1.abc9e3b39803fp-56'))
assert max(abs(ln2-lower), abs(ln2-upper)) < lower*u2/4

# Positive Taylor enclosures prove the transport/weight constants without
# evaluating a platform transcendental function.
def exp_interval(x):
    n = 40
    low = sum((x**k/F(factorial(k)) for k in range(n+1)), F(0))
    return low, low + x**(n+1)/F(factorial(n+1))/(1-x/F(n+2))

z = F(347,1000)
elow, _ = exp_interval(z)
assert z*elow/(elow-1) < F(121,100)
weights = F(0)
for j in range(9):
    _, upper_exp = exp_interval(z/F(2**(9-j)))
    amplitude = upper_exp-1
    weights += amplitude/(2-amplitude)
assert weights*inflate < F(24,100)
assert (exp_interval(z)[1]-1)*inflate < F(416,1000)

# expm1 at |r| < .0007. Seven additions (including the quadratic term),
# powers and generated factorials, and either the stopping rule or degree-8 cap.
r = F(7, 10000)
coeff = ((1+div)**8-1)/u2
series = ((1+add)**7-1)/u2 + 5*r/2 + (40+coeff)*r*r/(6*(1-r))
cap_tail = r**8/(factorial(9)*(1-r/10))/u2
stop_tail = F(1, 2**113)/(5*(1-r/6))/u2
# The sum of |s_j|/(2-|s_j|) in the nine doublings is < .24.
# Their relative error transport is < 1.21 on |512r| <= .347.
reduced = F(121, 100)*(series*F(1001,1000) + max(cap_tail, stop_tail) + 9*add/u2 + F(6, 5))*inflate
assert reduced < 80
# |expm1(z)|/exp(z) < .416 for |z| <= .347; one final DD add,
# plus reduction error <= (2 + 3|x|)u².
exp_base = (F(416, 1000)*80 + 3 + 2)*inflate
assert exp_base < 40

# log_reduced: parameter error, Horner adds/products, generated coefficients,
# the squared parameter, and final multiplication. Power-of-two scaling exact.
v = F(296, 10000)
log_reduced = (F(49,5)/(1-v) + 3/(1-v) + 5*v/(1-v)
    + F(49,5)*v/(3*(1-v)) + 5*v/(3*(1-v)**2) + 5
    + v**23/(47*(1-v))/u2)*inflate
assert log_reduced < 20
# |ln m|/|ln a| <= 1; |e ln 2|/|ln a| <= 2; final addition.
log_total = (20 + 2*F(9,4) + 3)*inflate
assert log_total < 32

# Binary64 log1p tail. d = RN(2+f), q = RN(f/d), hence two input
# roundings affect the tail; the leading term includes the quotient residual.
v = F(295,10000)
tail_ratio = v/(3*(1-v))
argument = 2*v/(1-v)
evaluation = (3 + 2/(1-v))*tail_ratio
truncation = v**11/(23*(1-v))/u
round_tail = tail_ratio
log1p = (argument + evaluation + truncation + round_tail + 32*u)*inflate
assert log1p < F(14,100)

if '--ocaml' in sys.argv:
    print('(* Generated after exact-rational verification; see oracle/verify_bounds.py. *)')
    print('let exp_base = 40.0\nlet exp_slope = 3.0\nlet expm1_reduced = 80.0\nlet log = 32.0\nlet log1p_tail = 0.14')
else:
    for name, value, ceiling in [('expm1 reduced / u²', reduced, 80),
        ('exp base / u²', exp_base, 40), ('log / u²', log_total, 32),
        ('log1p tail / u', log1p, .14)]:
        print(f'{name}: {float(value):.12g} < {ceiling}')
