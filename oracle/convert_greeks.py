#!/usr/bin/env python3
"""Flatten FerroRisk's Greek derivative reference (greek_derivative_reference.json).

Each Greek of each contract is an mpmath value: from two independent routes
(explicit closed form and differentiated price) where both exist, at two
precisions. Conventions: time Greeks are -d/dT / 365, and forward models'
rho is -T V.

Output lines:
  <model> <side> <greek> <status> <s> <k> <t> <r> <q> <sigma> <shift> <reference>
Numbers are binary64 hex words; the reference is nan where there is none.
"""
import json
import struct
import sys

MODELS = ("bsm", "black76", "displaced", "bachelier")
NAN = struct.pack(">d", float("nan")).hex()


def main(src, out):
    doc = json.load(open(src))
    with open(out, "w") as w:
        w.write(f"# ferro-risk greek derivative reference, mpmath {doc['mpmath_version']}\n")
        for row in doc["rows"]:
            if row["model"] not in MODELS:
                continue
            for greek, g in row["greeks"].items():
                ref = g.get("reference_bits") or NAN
                fields = [row["model"], row["side"], greek, g["status"]] + row["input_bits"] + [row["shift_bits"], ref]
                w.write(" ".join(fields) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:3])
