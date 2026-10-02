#!/usr/bin/env python3
"""Build the pinned author's C++ and retain exact-quote inverse comparisons.

Optional research tool; not part of default CI. Requires a C++17 compiler
accepting the author's Unicode identifiers (GCC 16 works) and mpmath 1.3.0.
The archive must be acquired separately from www.jaeckel.org/LetsBeRational.7z.
"""
import argparse
import ctypes
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile

import mpmath

ARCHIVE_SHA256 = "da2f6870b213e04ef35b4d309269ee5ce12be5830d9733e5f29542bf7b652470"
SOURCES = ["lets_be_rational.cpp", "normaldistribution.cpp", "rationalcubic.cpp", "erf_cody.cpp"]


def reference(beta, x, dps):
    with mpmath.workdps(dps):
        b, x = mpmath.mpf(beta), mpmath.mpf(x)
        cdf = lambda z: mpmath.erfc(-z / mpmath.sqrt(2)) / 2
        price = lambda s: (mpmath.exp(x / 2) * cdf(x / s + s / 2)
                           - mpmath.exp(-x / 2) * cdf(x / s - s / 2))
        lo, hi = mpmath.mpf(0), mpmath.mpf(32)
        if not price(hi) > b:
            raise RuntimeError("reference not bracketed")
        for _ in range(4 * dps):
            mid = (lo + hi) / 2
            if price(mid) < b:
                lo = mid
            else:
                hi = mid
        if hi - lo > mpmath.mpf(10) ** (-(dps - 10)):
            raise RuntimeError("reference unresolved")
        return float((lo + hi) / 2)


def normal_overflow_reference():
    roots = []
    for precision in (100, 200):
        with mpmath.workdps(precision):
            m = mpmath.mpf(sys.float_info.max)
            distance = 2 * m

            def price(s):
                d = distance / s
                return (s * mpmath.exp(-d * d / 2) / mpmath.sqrt(2 * mpmath.pi)
                        - distance * mpmath.erfc(d / mpmath.sqrt(2)) / 2)

            lo, hi = m / 20, m / 10
            if not price(lo) < 1 < price(hi):
                raise RuntimeError("normal overflow reference not bracketed")
            for _ in range(4 * precision):
                mid = (lo + hi) / 2
                if price(mid) < 1:
                    lo = mid
                else:
                    hi = mid
            roots.append(float((lo + hi) / 2))
    if roots[0] != roots[1] or not math.isfinite(roots[0]):
        raise RuntimeError("normal overflow reference unresolved")
    return dict(model="bachelier", side="put", forward=sys.float_info.max.hex(),
                strike=(-sys.float_info.max).hex(), time="0x1p+0", rate="0x0p+0",
                quote="0x1p+0", root=roots[0].hex(), precision=[100, 200],
                expected_library_outcome="Numerical_failure", reason=
                "Exact F-K overflows binary64 although the real root is finite.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--compiler", default="g++")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    archive = args.archive.resolve()
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
        parser.error("source archive differs from the recorded reference")
    if mpmath.__version__ != "1.3.0":
        parser.error("requires mpmath 1.3.0")
    flags = ["-std=c++17", "-O3", "-ffp-contract=off", "-DNO_XL_API", "-shared", "-fPIC"]
    with tempfile.TemporaryDirectory(prefix="risk-canonical-iv-") as tmp:
        subprocess.run(["bsdtar", "-xf", str(archive), "-C", tmp,
                        "--include=*.h", *[f"--include=LetsBeRational/{s}" for s in SOURCES]], check=True)
        source = Path(tmp) / "LetsBeRational"
        library = Path(tmp) / "reference.so"
        subprocess.run([args.compiler, *flags, *SOURCES, "-o", str(library)], cwd=source, check=True)
        lib = ctypes.CDLL(str(library))
        for name in ["NormalisedBlack", "NormalisedImpliedBlackVolatility"]:
            fn = getattr(lib, name)
            fn.argtypes = [ctypes.c_double] * 3
            fn.restype = ctypes.c_double
        rows = []
        for x in [0., -.01, -1., -10., -100.]:
            for s in [.1, .5, 1., 4., 16.]:
                beta = lib.NormalisedBlack(x, s, 1.)
                if not 0 < beta < math.exp(x / 2):
                    rows.append(dict(x=x.hex(), total=s.hex(), quote=beta.hex(), status="boundary quote"))
                    continue
                got = lib.NormalisedImpliedBlackVolatility(beta, x, 1.)
                low, high = [reference(beta, x, dps) for dps in (100, 200)]
                if low != high or not math.isfinite(got) or got <= 0:
                    raise RuntimeError("unresolved reference or invalid canonical inverse")
                rows.append(dict(x=x.hex(), total=s.hex(), quote=beta.hex(), status="root",
                                 canonical=got.hex(), reference=high.hex(),
                                 error_ulp=abs(got - high) / math.ulp(high)))
        result = dict(archive_sha256=ARCHIVE_SHA256, mpmath=mpmath.__version__,
                      compiler=subprocess.check_output([args.compiler, "--version"], text=True).splitlines()[0],
                      flags=flags, reference_precision=[100, 200], rows=rows,
                      normal_overflow=normal_overflow_reference())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"{len(rows)} cases retained in {args.output}")


if __name__ == "__main__":
    main()
