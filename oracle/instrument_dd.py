#!/usr/bin/env python3
"""Replay the production DD source, inserting exact primitive postconditions.

No arithmetic expression is rewritten. Each wrapper checks a fixed allowance;
the observed error is never fed back into a certificate's radius.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
if sys.argv[1:] == ['normal']:
    print('module Dd = Checked_dd')
    print((root / 'lib/normal_dd.ml').read_text())
else:
    source = (root / 'lib/dd.ml').read_text()
    source = source.replace('type t = { hi : float; lo : float }',
                            'type t = Morphiq_risk.Internal.Dd.t = { hi : float; lo : float }')
    checks = {
        'add': ('a b', 'Exact_dyadic.binary "add" Q.add Exact_dyadic.add_eps a b z'),
        'add_float': ('a y', 'Exact_dyadic.binary "add_float" Q.add Exact_dyadic.float_eps a (of_float y) z'),
        'mul': ('a b', 'Exact_dyadic.binary "mul" Q.mul Exact_dyadic.mul_eps a b z'),
        'mul_float': ('a y', 'Exact_dyadic.binary "mul_float" Q.mul Exact_dyadic.float_eps a (of_float y) z'),
        'div': ('a b', 'Exact_dyadic.binary "div" Q.div Exact_dyadic.div_eps a b z'),
        'sqrt': ('a', 'Exact_dyadic.sqrt a z'),
        'two_prod': ('a b', 'Exact_dyadic.product a b z'),
    }
    # Top-level bindings begin in column zero. Insert the wrapper immediately
    # after the binding, so subsequent production definitions call it as well.
    parts = re.split(r'(?=^let )', source, flags=re.M)
    found = set()
    for i, part in enumerate(parts):
        match = re.match(r'let (\w+) ', part)
        if match and match[1] in checks:
            name = match[1]
            args, check = checks[name]
            found.add(name)
            parts[i] = part.replace('let '+name+' ', 'let '+name+'_impl ', 1)
            parts[i] += f'\nlet {name} {args} =\n  let z = {name}_impl {args} in\n  {check};\n  z\n\n'
    assert found == set(checks), found
    print('module Split = Morphiq_risk.Internal.Split')
    print(''.join(parts))
