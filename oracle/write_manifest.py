#!/usr/bin/env python3
"""Record only explicitly rebuilt fixtures; reject stale unrebuilt records.

oracle/build.sh passes the names it actually regenerated. Without arguments
this validates the manifest. Extra fields pin transitive local Python imports.
Hashes are BLAKE2b-256, matching OCaml Digest.BLAKE256.
"""
import ast
import gzip
import hashlib
import platform
from pathlib import Path
import sys

ORACLE = Path(__file__).resolve().parent
FIXTURES = ("elementary", "normal", "european", "displaced", "iv", "greeks", "dd", "regressions", "greek_bits")
HEADER = "# name generator generator_blake2b256 common_blake2b256 mpmath python rows fixture_blake2b256 [dependency:blake2b256 ...]"


def blake(path):
    return hashlib.blake2b(path.read_bytes(), digest_size=32).hexdigest()


def rows(path):
    with gzip.open(path, "rt") as f:
        return sum(1 for line in f if line.strip() and not line.startswith("#"))


def dependencies(root, generator):
    """Transitively follow static local imports, including imports in functions."""
    seen = set()
    def visit(name):
        if name in seen:
            return
        seen.add(name)
        for node in ast.walk(ast.parse((root / name).read_text())):
            modules = ([n.name for n in node.names] if isinstance(node, ast.Import)
                       else [node.module] if isinstance(node, ast.ImportFrom) and node.module else [])
            for module in modules:
                local = module.split('.')[0] + '.py'
                if (root / local).is_file():
                    visit(local)
    visit(generator)
    return sorted(seen - {generator, 'common.py'})


def read_records(root):
    records = {}
    path = root / 'MANIFEST'
    if not path.exists():
        return records
    for line in path.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split()
        if len(fields) < 8 or fields[0] not in FIXTURES or fields[0] in records:
            raise ValueError('malformed, unknown or duplicate manifest record: ' + line)
        records[fields[0]] = fields
    return records


def update(root, rebuilt, versions=None):
    rebuilt = set(rebuilt)
    if not rebuilt <= set(FIXTURES):
        raise ValueError('unknown fixture names: ' + ', '.join(sorted(rebuilt - set(FIXTURES))))
    records = read_records(root)
    # Check every unselected record BEFORE constructing or writing new records.
    # A partial rebuild must not bless changed code for other fixtures.
    for name in FIXTURES:
        if name in rebuilt:
            continue
        if name not in records:
            raise ValueError(f'{name}: missing provenance; run oracle/build.sh {name}')
        fields = records[name]
        generator = f'gen_{name}.py'
        expected = [generator, blake(root / generator), blake(root / 'common.py')]
        extras = [dep + ':' + blake(root / dep) for dep in dependencies(root, generator)]
        fixture = root / 'fixtures' / f'{name}.txt.gz'
        if (fields[1:4] != expected or fields[7] != blake(fixture)
                or fields[6] != str(rows(fixture)) or fields[8:] != extras):
            raise ValueError(f'{name}: stale provenance; run oracle/build.sh {name}')
    if not rebuilt:
        return
    if versions is None:
        import mpmath
        versions = (mpmath.__version__, platform.python_version())
    for name in rebuilt:
        generator = f'gen_{name}.py'
        fixture = root / 'fixtures' / f'{name}.txt.gz'
        records[name] = [name, generator, blake(root / generator), blake(root / 'common.py'),
                         *versions, str(rows(fixture)), blake(fixture)]
        records[name] += [dep + ':' + blake(root / dep) for dep in dependencies(root, generator)]
    content = '\n'.join([HEADER] + [' '.join(records[name]) for name in FIXTURES]) + '\n'
    temporary = root / 'MANIFEST.tmp'
    temporary.write_text(content)
    temporary.replace(root / 'MANIFEST')


if __name__ == '__main__':
    try:
        update(ORACLE, sys.argv[1:])
    except ValueError as error:
        sys.exit(str(error))
