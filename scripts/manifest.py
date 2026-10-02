#!/usr/bin/env python3
"""Provenance for the committed oracle fixtures (oracle/fixtures/*.txt.gz).

`write` records each fixture's provenance in oracle/MANIFEST.json:
- its generator's SHA-256, and the shared common.py's;
- the mpmath and Python versions;
- the row count;
- the fixture's own SHA-256.

`check` verifies the repository against the manifest. It fails if a
fixture's bytes changed, if a generator or common.py changed without the
fixture being regenerated, or if a fixture is missing. CI runs `check`.
"""
import gzip
import hashlib
import json
import platform
import sys
from pathlib import Path

ORACLE = Path(__file__).resolve().parents[1] / "oracle"
MANIFEST = ORACLE / "MANIFEST.json"
GENERATORS = {
    "elementary": "gen_elementary.py",
    "normal": "gen_normal.py",
    "european": "gen_european.py",
    "displaced": "gen_displaced.py",
    "iv": "gen_iv.py",
    "greeks": "gen_greeks.py",
}
SHARED = ("common.py",)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows(path):
    with gzip.open(path, "rt") as f:
        return sum(1 for line in f if line and not line.startswith("#"))


def entry(name):
    fixture = ORACLE / "fixtures" / f"{name}.txt.gz"
    import mpmath
    return {
        "generator": GENERATORS[name],
        "generator_sha256": sha(ORACLE / GENERATORS[name]),
        "shared_sha256": {s: sha(ORACLE / s) for s in SHARED},
        "mpmath": mpmath.__version__,
        "python": platform.python_version(),
        "rows": rows(fixture),
        "fixture_sha256": sha(fixture),
    }


def write():
    current = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    for name in GENERATORS:
        if (ORACLE / "fixtures" / f"{name}.txt.gz").exists():
            current[name] = entry(name)
    MANIFEST.write_text(json.dumps(current, indent=2, sort_keys=True) + "\n")


def check():
    manifest = json.loads(MANIFEST.read_text())
    problems = []
    for name, gen in GENERATORS.items():
        fixture = ORACLE / "fixtures" / f"{name}.txt.gz"
        record = manifest.get(name)
        if record is None or not fixture.exists():
            problems.append(f"{name}: no fixture or manifest entry")
            continue
        if sha(fixture) != record["fixture_sha256"]:
            problems.append(f"{name}: fixture bytes differ from the manifest")
        if sha(ORACLE / gen) != record["generator_sha256"]:
            problems.append(f"{name}: {gen} changed since the fixture was generated; run oracle/build.sh {name}")
        for s, h in record["shared_sha256"].items():
            if sha(ORACLE / s) != h:
                problems.append(f"{name}: {s} changed since the fixture was generated; run oracle/build.sh {name}")
    for p in problems:
        print(p)
    print(f"{len(GENERATORS) - len({p.split(':')[0] for p in problems})} of {len(GENERATORS)} fixtures match their manifest")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(write() or 0 if sys.argv[1:] == ["write"] else check())
