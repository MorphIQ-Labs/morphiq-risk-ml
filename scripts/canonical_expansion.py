#!/usr/bin/env python3
"""Execute the unchanged author's grow_expansion_zeroelim against exact sums.

The source is obtained separately from the recorded CMU URL. This campaign is
reference evidence, not a replacement for the OCaml exact-rational witnesses.
"""
import argparse
import ctypes
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import platform
import random
import subprocess
import tempfile

SHA256 = 'f8662c3f407d1c1c5dcd4dd49ea8b8ddd801a71827d65734206ddc3741792029'
SOURCE_URL = 'https://www.cs.cmu.edu/afs/cs/project/quake/public/code/predicates.c'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--compiler', default='cc')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if hashlib.sha256(args.source.read_bytes()).hexdigest() != SHA256:
        raise SystemExit('canonical source hash mismatch')
    flags = ['-std=gnu99', '-O2', '-ffp-contract=off', '-shared', '-fPIC']
    rng = random.Random(2714)
    sequences = [[1., math.ldexp(1., -53), -1.],
                 [1., math.ldexp(1., -1074), -1.],
                 [math.ldexp(1., 500), 1., -math.ldexp(1., 500)]]
    for _ in range(2000):
        sequences.append([math.ldexp(rng.uniform(-1., 1.), rng.randint(-1000, 1000)) for _ in range(16)])
    with tempfile.TemporaryDirectory(prefix='risk-canonical-expansion-') as work:
        library = Path(work) / 'predicates.so'
        build = subprocess.run([args.compiler, *flags, str(args.source.resolve()), '-o', str(library)],
                               capture_output=True, text=True)
        if build.returncode:
            raise SystemExit(build.stderr)
        dll = ctypes.CDLL(str(library))
        dll.exactinit()
        grow = dll.grow_expansion_zeroelim
        grow.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_double), ctypes.c_double, ctypes.POINTER(ctypes.c_double)]
        grow.restype = ctypes.c_int
        operations = 0
        witnesses = []
        for i, terms in enumerate(sequences):
            words = [0.]
            exact = Fraction(0)
            for value in terms:
                source = (ctypes.c_double * len(words))(*words)
                dest = (ctypes.c_double * (len(words) + 1))()
                count = grow(len(words), source, value, dest)
                words = list(dest[:count])
                exact += Fraction(value)
                if sum(map(Fraction, words), Fraction(0)) != exact:
                    raise ArithmeticError(f'canonical grow failed exact sum: {terms}')
                operations += 1
            if i < 3:
                witnesses.append({'inputs': list(map(float.hex, terms)), 'output': list(map(float.hex, words))})
    report = {'source_url': SOURCE_URL, 'source_sha256': SHA256,
              'compiler': subprocess.check_output([args.compiler, '--version'], text=True).splitlines()[0],
              'flags': flags, 'platform': platform.platform(),
              'sequences': len(sequences), 'exact_rational_checks': operations,
              'failures': 0, 'witnesses': witnesses,
              'scope': 'Unchanged canonical grow_expansion_zeroelim; no financial pricing or performance claim.'}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'{operations} exact-rational canonical expansion checks passed')


if __name__ == '__main__':
    main()
