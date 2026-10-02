#!/usr/bin/env python3
"""Flatten FerroRisk's #440 European pricing oracle into scoring rows.

The source is 50,094 contracts with mpmath values. Each value is refined until
two successive precisions agree to 1e-45. Regions follow
score_european_formulations.region(). The reference is the exact value
correctly rounded to binary64.

Output lines:
  <model> <call|put> <region> <s> <k> <t> <r> <q> <sigma> <shift> <reference>
where every number is a binary64 hex word; shift is 0 when absent.
"""
import gzip
import json
import math
import struct
import sys

import mpmath
from mpmath import mp, mpf


def word(h):
    return struct.unpack(">d", bytes.fromhex(h))[0]


def round_binary64(value):
    """Nearest binary64, ties to even, subnormals exact (FerroRisk's rounding)."""
    if value == 0:
        return 0.0
    sign, man, exp, bc = value._mpf_
    top = exp + bc - 1
    if top >= 1024:
        return -math.inf if sign else math.inf
    quantum = max(top - 52, -1074)
    shift = quantum - exp
    if shift <= 0:
        n = int(man) << (-shift)
    else:
        n, remainder = int(man) >> shift, int(man) & ((1 << shift) - 1)
        half = 1 << (shift - 1)
        if remainder > half or (remainder == half and n & 1):
            n += 1
    result = math.ldexp(float(n), quantum)
    return -result if sign else result


def bits(x):
    return struct.pack(">d", x).hex()


def region(row, oracle):
    if word(row["sigma"]) == 0:
        return "zero_variance"
    scale = word(row["k"])
    if row["model"] in ("bsm", "black76") and not 1e-100 <= scale <= 1e100:
        return "extreme_scale"
    side = 1 if row["type"] == "call" else -1
    intrinsic = side * mpf(oracle["intrinsic"])
    with mp.workdps(40):
        t, r = mpf(word(row["t"])), mpf(word(row["r"]))
        discount = mpmath.exp(-r * t)
        if row["model"] == "displaced":
            strike_leg = mpf(word(row["k"]) + word(row["shift"])) * discount
        else:
            strike_leg = mpf(word(row["k"])) * discount
        std_dev = mpf(word(row["sigma"])) * mpmath.sqrt(t)
        if row["model"] == "bachelier":
            x = mpf(oracle["intrinsic"]) / strike_leg
            std_dev = std_dev * discount / strike_leg
        else:
            x = mpf(oracle["x"])
        if abs(x) <= mpf("1e-2") and std_dev <= mpf("1e-4"):
            return "near_atm_tiny_variance"
    if intrinsic > 0:
        value = mpf(oracle["value"]) if oracle["status"] == "value" else mpf(0)
        return "deep_itm" if intrinsic >= value / 2 else "itm"
    return "otm"


def main(candidates, oracle, out):
    mp.dps = 60
    with gzip.open(oracle, "rt") as f:
        header = json.loads(f.readline())
        assert header["schema"] == "ferro-risk.440-european-oracle.v1", header
        values = {o["cell"]: o for o in map(json.loads, f)}
    with gzip.open(candidates, "rt") as f, open(out, "w") as w:
        w.write(f"# ferro-risk #440 oracle, mpmath {header['mpmath_version']}, agreement {header['agreement']}\n")
        for line in f:
            row = json.loads(line)
            o = values[row["cell"]]
            if o["status"] == "value":
                ref = round_binary64(mpf(o["value"]))
            elif o["status"] == "bound":
                ref = 0.0  # upper bound below 2^-1100 rounds to zero
            else:
                continue
            shift = row["shift"] or bits(0.0)
            fields = [row["model"], row["type"], region(row, o)] + [
                row[k] for k in ("s", "k", "t", "r", "q", "sigma")] + [shift, bits(ref)]
            w.write(" ".join(fields) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
