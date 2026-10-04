#!/usr/bin/env python3
"""Exact-rational checks of the majorants in docs/error-analysis.md.

This verifies the inequalities of the written analysis, not a formal
verification of the OCaml implementation. No measurements enter the constants.
Only Python's standard library is required at test build time.
"""
from fractions import Fraction as F
from math import factorial
import sys
import re
from pathlib import Path
import kernel_certificates
import dd_exp_coefficients

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
assert upper/2 + 8*u*746 < z
assert (exp_interval(z)[1]-1)*inflate < F(416,1000)

# Degree-22 expm1 as r + r²*(1/2 + r*(1/3! + ...)). The two leading
# coefficients are exact; add_float costs <=2u², below the conservative add
# allowance charged here. The separately rounded square and tail product
# give each r^k coefficient at most k multiply roundings. Loop unrolling is
# not used; inline annotations preserve the primitive operation order.
# For coefficient k, at most k
# multiplications and k additions affect r^k/k!. Summing absolute weights
# gives sum k*z^(k-1)/k! <= exp(z). Splitting each exact rational coefficient
# incurs at most u² relative error, also bounded by that sum. Divide by
# |expm1(r)/r| >= 1-z, valid on both sides of zero.
coefficients = dd_exp_coefficients.check()
for k, (hi, lo) in enumerate(coefficients, 1):
    exact = F(1, factorial(k))
    assert abs(F(hi)+F(lo)-exact) <= u2*exact
    assert hi+lo == hi
N = len(coefficients)
assert N == 22
rounding = ((add+mul)/u2+1)*exp_interval(z)[1]/(1-z)
tail = z**N/(factorial(N+1)*(1-z/F(N+2))*(1-z))/u2
reduced = (rounding+tail)*inflate
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

assert F(1, factorial(22))/(1-F(1,23)) < F(1,2**69)

# Binary64 Elementary.exp: polynomial arithmetic, rounded coefficients,
# Taylor tail, two fma reductions, and the final sum. Constants are read from
# the implementation; dyadic fractions retain their exact stored values.
root = Path(__file__).resolve().parent.parent
source = (root/'lib/elementary.ml').read_text()
def fp_literal(value):
    return F(float.fromhex(value) if '0x' in value else float(value))
coefficients = source.split('let exp_coefficients =',1)[1].split('[|',1)[1].split('|]',1)[0]
coefficients = [fp_literal(v.strip()) for v in coefficients.split(';') if v.strip()]
assert len(coefficients) == 14
R = F(347,1000)
polynomial_rounding = u*sum((F(k+1)*R**(k+1)/F(factorial(k+1)) for k in range(14)),F(0))
coefficient_error = sum((abs(c-F(1,factorial(k+1)))*R**(k+1) for k,c in enumerate(coefficients)),F(0))
taylor_tail = R**15/(factorial(15)*(1-R/16))
product_rounding = u*sum((R**k/F(factorial(k)) for k in range(1,15)),F(0))
ln_hi = fp_literal(re.search(r'let ln2_hi = (\S+)',source).group(1))
ln_lo = fp_literal(re.search(r'let ln2_lo = (\S+)',source).group(1))
ln_error = max(abs(ln_hi+ln_lo-lower),abs(ln_hi+ln_lo-upper))
reduction = (2*R+F(1,2**20))*u+1077*ln_error
# exp(-R) >= 1-R; 2^-20 bounds |k ln2_lo|. Final ldexp adds an absolute
# half-quantum if subnormal, separately from this relative majorant.
elementary_exp = (u+(polynomial_rounding+coefficient_error+taylor_tail+product_rounding)/(1-R)
                  + reduction/(1-reduction))*inflate
assert elementary_exp < 4*u

approximation, kernel_rounding = kernel_certificates.verify()

# Generated odd series: coefficient, remainder and weighted FMA analysis.
c_lo,c_hi = kernel_certificates.inverse_sqrt_pi()
erf_small = approximation['erf_small_total']
assert erf_small < 26*u

# Split.scaled_exp_neg: |n|<6000, reduced |r|<.7. Two reduction roundings
# plus the two-word ln2 residual; three product/correction roundings.
split_source = (root/'lib/split.ml').read_text()
split_hi = fp_literal(re.search(r'let ln2_hi = (\S+)',split_source).group(1))
split_lo = fp_literal(re.search(r'let ln2_lo = (\S+)',split_source).group(1))
split_ln_error = max(abs(split_hi+split_lo-lower),abs(split_hi+split_lo-upper))
assert F(4096)/split_hi*(1+u) < 6000
split_reduction = F(7,5)*u + 6000*(split_ln_error+u2)
split_factor = (1+4*u)*(1+u)**3/(1-split_reduction)
for lo_squared in [F(0),F(1,10**6)]:
    error = split_factor*(1+lo_squared/(2*(1-F(1,1000))))-1
    assert error < 12*u+lo_squared
# The inequality is affine in lo², so endpoint checks cover |lo|<=.001.
# Positive erfc rounds to zero at 28; the replay includes input error.
assert F(55,2)**2 > 1075*upper
assert c_hi/F(55,2) < 1
# Negative erfcx overflows at -27, by 2 exp(x²)-erfcx(-x).
assert F(27)**2 > 1025*upper
assert F(99,100)*4096 > (1025+2048+1075)*upper
# Derivative bounds across a small interval straddling zero.
assert F(2,100)+2*c_hi < 2
mills_negative = (F(1254,1000)+F(1,200))/(1-F(1,80000))
assert (1+F(1,40000))*mills_negative+F(1,200) < 2

# Normal_dd's constant 1/sqrt(2*pi), enclosed with Machin's identity and
# sqrt(2) by integer/rational inequalities.
c_lo,c_hi = kernel_certificates.inverse_sqrt_pi()
sqrt2_lo = F(1414213562373095048801688724209698078569671875376948073176679,10**60)
sqrt2_hi = sqrt2_lo + F(1,10**60)
assert sqrt2_lo**2 < 2 < sqrt2_hi**2
normal_source = (root/'lib/normal_dd.ml').read_text()
constant = re.search(r'let inv_sqrt_2pi = \{ Dd.hi = ([^;]+); lo = ([^ }]+)',normal_source)
normal_constant = fp_literal(constant.group(1))+fp_literal(constant.group(2))
normal_lo,normal_hi = c_lo/sqrt2_hi,c_hi/sqrt2_lo
assert max(abs(normal_constant-normal_lo),abs(normal_constant-normal_hi)) < normal_lo*u2
# On |d.hi|<=6 (including a normalized low word), d²<37. At term 128,
# q_128/q_0 <= 37^128/257!! < 2^-120, so the 400-iteration cap is unreachable.
odd_factorial = 1
for k in range(1,129): odd_factorial *= 2*k+1
assert F(37)**128/odd_factorial < F(1,2**120)
# The terms share a sign and sum n*q_n / sum q_n <= d²/2. This bounds
# accumulated term errors without charging the maximum n to every term.
series_error = (F(99,5)*F(37,2) + 3*129 + 1)*inflate
pdf_error = (40+3*F(37,2)+5*F(37,2)+6)*inflate
assert pdf_error < 200
cdf_error = (F(1,2)*(series_error+200+5)+4)*inflate
assert cdf_error < 512

# Finite-exponent noise in the DD elementary/normal compositions. Primitive
# allowances are checked exactly on execution (test/exact_dyadic.ml). Fewer
# than 2^14 primitive calls each contribute <=32 quanta; the written absolute
# transport bound is 2^60, including series sensitivity and Horner evaluation.
assert 1/(1-z) < 2 # reduced Horner perturbation transport
assert exp_interval(F(19))[1] < 2**28
transport = F(1)
for k in range(1, 402):
    transport *= max(F(1), F(37, 2*k+1))
assert transport < 2**28
assert 7*2**28 < 2**31
assert 401*7*2**28 < 2**40
assert (2**40 + 2**31)*(2 + 1)*16 < 2**60
finite_noise = F(2**80, 2**1074)
assert 2**14 * 32 * 2**60 < 2**80
# Minimum nonzero magnitude needing a relative small-expm1 certificate is
# >2^-106; log and the unscaled exp/pdf paths have larger minima. Use the
# explicit spare margin below each ceiling, not a second use of inflate.
assert finite_noise < u2/F(2**106)
for value, ceiling in [(reduced,80),(exp_base,40),(log_total,32),(pdf_error,200),(cdf_error,512)]:
    assert ceiling-value > 1

if '--ocaml' in sys.argv:
    print('(* Generated after exact-rational verification; see oracle/verify_bounds.py. *)')
    print('let exp_base = 40.0\nlet exp_slope = 3.0\nlet expm1_reduced = 80.0\nlet log = 32.0\nlet log1p_tail = 0.14\nlet elementary_exp = 4.0\nlet erfcx = 40.0\nlet y_prime = 96.0\nlet normal_pdf = 200.0\nlet normal_cdf = 512.0')
else:
    for name, value, ceiling in [('expm1 reduced / u²', reduced, 80),
        ('exp base / u²', exp_base, 40), ('log / u²', log_total, 32),
        ('log1p tail / u', log1p, .14), ('elementary exp / u',elementary_exp/u,4), ('Normal DD pdf / u²',pdf_error,200), ('Normal DD cdf absolute / u²',cdf_error,512)]:
        print(f'{name}: {float(value):.12g} < {ceiling}')
