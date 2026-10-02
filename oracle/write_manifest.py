#!/usr/bin/env python3
"""Write oracle/MANIFEST: the provenance of each committed fixture.

  oracle/.venv/bin/python oracle/write_manifest.py   (oracle/build.sh runs it)

One line per fixture:

  <name> <generator> <generator hash> <common.py hash> <mpmath> <python> <rows> <fixture hash>

Hashes are BLAKE2b-256, the same function as OCaml's Digest.BLAKE256, so the
check is a dune test (test/manifest.ml) and needs no Python. It fails if a
fixture's bytes changed, or if its generator or common.py changed without
the fixture being regenerated.
"""
import gzip
import hashlib
import platform
from pathlib import Path

import mpmath

ORACLE = Path(__file__).resolve().parent
FIXTURES = ("elementary", "normal", "european", "displaced", "iv", "greeks")


def blake(path):
    return hashlib.blake2b(path.read_bytes(), digest_size=32).hexdigest()


def rows(path):
    with gzip.open(path, "rt") as f:
        return sum(1 for line in f if line and not line.startswith("#"))


def main():
    lines = ["# name generator generator_blake2b256 common_blake2b256 mpmath python rows fixture_blake2b256"]
    for name in FIXTURES:
        fixture = ORACLE / "fixtures" / f"{name}.txt.gz"
        generator = f"gen_{name}.py"
        lines.append(" ".join([
            name, generator, blake(ORACLE / generator), blake(ORACLE / "common.py"),
            mpmath.__version__, platform.python_version(), str(rows(fixture)), blake(fixture),
        ]))
    (ORACLE / "MANIFEST").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
