#!/usr/bin/env python3
"""Lift the kernel's polynomial arithmetic into the outward-error algebra.

Only the straight-line A0..A16 and B0..B6 formulas are lifted. Their exact
coefficients are checked against the Gaussian moment recurrences below; the
region selection and truncation bounds are independently written in OCaml.
"""
from fractions import Fraction as F
from math import comb, factorial, prod, ulp
from pathlib import Path
import re
import ast

ROOT = Path(__file__).resolve().parent.parent
NUMBER = r'(?<![\w.])(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?'

class P:
    def __init__(self, coefficients): self.c = list(coefficients)
    def __add__(self, other):
        n = max(len(self.c), len(other.c))
        return P([(self.c[i] if i<len(self.c) else 0)+(other.c[i] if i<len(other.c) else 0) for i in range(n)])
    def __neg__(self): return P([-v for v in self.c])
    def __sub__(self, other): return self+-other
    def __mul__(self, other):
        result = [F(0)]*(len(self.c)+len(other.c)-1)
        for i,a in enumerate(self.c):
            for j,b in enumerate(other.c): result[i+j] += a*b
        return P(result)
    def __truediv__(self, other):
        assert len(other.c)==1
        return P([v/other.c[0] for v in self.c])

def polynomial(expression, variables):
    expression = expression.replace('+.', '+').replace('-.', '-').replace('*.', '*').replace('/.', '/')
    # Keep literals exact; interpreting Python float nodes would lose their
    # rational value before we can verify the rounded binary64 coefficients.
    expression = re.sub(NUMBER, lambda m: 'literal("'+m[0]+'")', expression)
    def visit(node):
        if isinstance(node, ast.Name): return variables[node.id]
        if isinstance(node, ast.Call):
            assert isinstance(node.func,ast.Name) and node.func.id=='literal'
            return P([F(float(node.args[0].value))])
        if isinstance(node, ast.UnaryOp) and isinstance(node.op,ast.USub): return -visit(node.operand)
        if isinstance(node, ast.BinOp):
            a,b=visit(node.left),visit(node.right)
            return {ast.Add:P.__add__,ast.Sub:P.__sub__,ast.Mult:P.__mul__,ast.Div:P.__truediv__}[type(node.op)](a,b)
        raise ValueError(ast.dump(node))
    return visit(ast.parse(' '.join(expression.split()),mode='eval').body)

source = (ROOT/'lib/normalised_black.ml').read_text()
source = re.sub(r'\(\*.*?\*\)', '', source, flags=re.S)
asymptotic = source.split('module Asymptotic = struct',1)[1].split('let high_terms',1)[0]
definitions = list(re.finditer(r'let a(\d+) (?:e|_) =\s*(.*?)(?=\s*let a\d+|\Z)',asymptotic,re.S))
assert len(definitions)==17
for definition in definitions:
    n = int(definition[1])
    p = polynomial(definition[2],{'e':P([0,1])})
    expected = [2*(-1)**n*prod(range(1,2*n,2))*comb(2*n+1,2*j+1) for j in range(n+1)]
    assert len(p.c)==len(expected)
    for actual,exact in zip(p.c,expected):
        assert abs(actual-exact) <= F(ulp(float(actual)))/2, (n,actual,exact)

small = source.split('let small_t_scaled h t =',1)[1].split('let vega_exponent',1)[0]
definitions = list(re.finditer(r'let b([0-6]) =\s*(.*?)\bin\b',small,re.S))
assert len(definitions)==7
for a in [0,1]:
    moments = [P([a]), P([3*a-1,a])]
    for n in range(2,7):
        moments.append(P([4*n-1,1])*moments[-1]-P([(2*n-1)*(2*n-2)])*moments[-2])
    for definition, moment in zip(definitions,moments):
        n = int(definition[1])
        actual = polynomial(definition[2],{'a':P([a]),'h2':P([0,1])})
        expected = moment/P([F(factorial(2*n+1),2)])
        assert actual.c==expected.c, (n,a,actual.c,expected.c)

def lift(expression):
    def literal(m):
        value=F(m[0])
        # Exact integer constants and powers of two need no coefficient error.
        constructor='c' if F(float(value))==value else 'constant'
        # Large A coefficients are rounded versions of the integer recurrence.
        # Even an exactly representable decimal can differ from that integer.
        if abs(value)>2**53: constructor='constant'
        return '('+constructor+' '+m[0]+')'
    return re.sub(r'(?<![\w.])-(?=\(c |\(constant )', '-.', re.sub(NUMBER,literal,expression))

print('(* Generated from checked moment polynomials by oracle/lift_polynomials.py.\n'
      + (ROOT/'LICENSES/LetsBeRational.txt').read_text() + '*)')
print('''module Make (B : sig
  type t
  val c : float -> t
  val constant : float -> t
  val add : t -> t -> t
  val sub : t -> t -> t
  val mul : t -> t -> t
  val div : t -> t -> t
  val neg : t -> t
  val y_prime : t -> t
end) = struct
open B
let ( +. ) = add
let ( -. ) = sub
let ( *. ) = mul
let ( /. ) = div
let ( ~-. ) = neg
''')
print(lift(asymptotic))
print('let coefficients = [|'+ ';'.join('a'+str(n) for n in range(17))+'|]')
print('let small_t_scaled h t ='+lift(small))
print('end')
