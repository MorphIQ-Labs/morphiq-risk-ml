#!/usr/bin/env python3
"""Independently enclose both rounding-cell residuals of every IV reference root.

Uses FLINT/Arb's arbitrary-precision balls and erfc, not the OCaml runtime
expansions, Taylor/continued-fraction evaluator or mpmath refinement. Optional
assurance tooling: python-flint==0.9.0, no production dependency.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import platform
import struct

from flint import arb, ctx, __FLINT_VERSION__


def word(text):
    return struct.unpack(">d", bytes.fromhex(text.zfill(16)))[0]


def price(model, side, inputs, sigma):
    s, k, t, r, q, _seed, shift, _quote = map(arb, inputs)
    theta = 1 if side == "call" else -1
    root_time = t.sqrt()
    total = sigma * root_time
    sqrt2 = arb(2).sqrt()

    def cdf(x):
        return (-x / sqrt2).erfc() / 2

    dr = (-r*t).exp()
    if model == "bachelier":
        d = (s-k)/total
        density = (-d*d/2).exp() / (2*arb.pi()).sqrt()
        return dr * (theta*(s-k)*cdf(theta*d) + total*density)
    if model == "displaced":
        s, k = s+shift, k+shift
    if model != "bsm":
        q = r
    d1 = ((s/k).log() + (r-q)*t)/total + total/2
    d2 = d1-total
    return theta*(s*(-q*t).exp()*cdf(theta*d1) - k*dr*cdf(theta*d2))


def certify(model, side, inputs, root):
    for precision in [256, 512, 1024, 2048, 4096]:
        with ctx.workprec(precision):
            centre = arb(root)
            lower = (arb(math.nextafter(root, 0.0)) + centre)/2
            successor = math.nextafter(root, math.inf)
            upper = ((centre + arb(successor))/2 if math.isfinite(successor)
                     else centre+(centre-arb(math.nextafter(root, 0.0)))/2)
            left = price(model, side, inputs, lower)-arb(inputs[-1])
            right = price(model, side, inputs, upper)-arb(inputs[-1])
            if left < 0 and right > 0:
                return precision
            if left > 0 or right < 0:
                raise RuntimeError(f"reference root outside its exact rounding cell: {model} {side} {root.hex()}")
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    counts, precisions = Counter(), Counter()
    unresolved = []
    shifted_root_rejected = False
    with gzip.open(args.fixture, "rt") as stream:
        for index, line in enumerate(stream, 1):
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.split()
            if fields[2] != "root":
                continue
            model, side = fields[:2]
            inputs = [word(x) for x in fields[4:12]]
            root = word(fields[14])
            precision = certify(model, side, inputs, root)
            counts[model] += 1
            if precision is None:
                unresolved.append(dict(line=index, input=line.strip()))
            else:
                precisions[precision] += 1
                if not shifted_root_rejected and math.isfinite(math.nextafter(root, math.inf)):
                    try:
                        certify(model, side, inputs, math.nextafter(root, math.inf))
                    except RuntimeError:
                        shifted_root_rejected = True
                    else:
                        raise RuntimeError("interval audit failed to reject an adjacent wrong reference root")
    report = dict(
        method="Strict opposite residual signs at exact adjacent-float midpoints, enclosed by FLINT/Arb erfc-based real-model evaluation",
        python_flint=importlib.metadata.version("python-flint"),
        flint=__FLINT_VERSION__,
        platform=platform.platform(),
        fixture_sha256=hashlib.sha256(args.fixture.read_bytes()).hexdigest(),
        script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        root_rows=dict(counts), working_precision_counts=dict(precisions),
        unresolved=unresolved,
        adjacent_wrong_root_control=shifted_root_rejected,
        scope="Independent interval audit of reference rounding cells, not an independent human review or a proof of all OCaml executions.")
    args.output.write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(dict(roots=sum(counts.values()), precisions=dict(precisions), unresolved=len(unresolved))))
    if not counts or unresolved:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
