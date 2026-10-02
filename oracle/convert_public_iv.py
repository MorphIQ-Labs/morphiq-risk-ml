#!/usr/bin/env python3
"""Flatten FerroRisk's public IV reference (testing/data/public_iv_reference.json).

The reference holds exact-input inverses for the European family at two
mpmath precisions. For each root it records the rounding cell: the
volatilities whose exact price rounds to the binary64 quote.

FerroRisk's observed envelope (public_iv_observed_envelope.json) supplies,
per root row, the largest absolute σ error FerroRisk itself has shown.

Output lines:
  <model> <side> <status> <param> <s> <k> <t> <r> <q> <sigma> <shift> <target> <cell_lo> <cell_hi> <root> <ferro_error>
Numbers are binary64 hex words. An absent bound is written as nan, an
unbounded one as inf. <param> names the invalid parameter, or '-'.
"""
import json
import struct
import sys

MODELS = ("bsm", "black76", "displaced", "bachelier")
NAN = struct.pack(">d", float("nan")).hex()
INF = struct.pack(">d", float("inf")).hex()


def bound(cell, side):
    for b in cell or []:
        if b["side"] != side:
            continue
        if b.get("status") in ("unbounded", "unbounded_binary64_cell"):
            return INF if side == "upper" else NAN
        if b.get("root_bits"):
            return b["root_bits"]
    return NAN


def main(src, envelope, out):
    doc = json.load(open(src))
    observed = {r["id"]: r for r in json.load(open(envelope))["rows"]}
    with open(out, "w") as w:
        w.write(f"# ferro-risk public IV reference, mpmath {doc['mpmath_version']}\n")
        for row in doc["rows"]:
            if row["model"] not in MODELS:
                continue
            high = row["profiles"][-1] if row["profiles"] else {}
            fields = [row["model"], row["side"], row["status"], row.get("invalid_parameter", "-")]
            fields += row["input_bits"] + [row["shift_bits"], row.get("target_bits") or NAN]
            fields += [bound(high.get("rounding_cell"), "lower"), bound(high.get("rounding_cell"), "upper"),
                       high.get("root_bits") or NAN]
            e = observed.get(row["id"], {}).get("largest_observed_error")
            fields.append(struct.pack(">d", float(e)).hex() if e is not None else NAN)
            w.write(" ".join(fields) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:4])
