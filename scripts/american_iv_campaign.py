#!/usr/bin/env python3
"""Validate complete manual inverse outcomes; refuses missing or altered rows."""
import argparse
import json
import subprocess
from pathlib import Path
from check_american_iv import load, require


def parse(text, ids, minimum=0):
    rows, roots, total = {}, set(), None
    for line in text.splitlines():
        parts = line.split()
        if not parts:
            continue
        if line == 'American inverse controls passed':
            require(not rows and total is None, 'misplaced controls')
            continue
        if parts[0] == 'ROOT':
            require(len(parts) == 5 and parts[1] not in roots, 'malformed root')
            lo, hi = map(float.fromhex, parts[2:4])
            require(0 <= lo < hi and 2 <= int(parts[4]) <= 64, 'malformed root')
            roots.add(parts[1])
        elif parts[0] == 'ROW':
            require(len(parts) == 4 and parts[1] not in rows, 'duplicate or malformed row')
            require(parts[2] in {'interval', 'price-accuracy', 'price-resource',
                                'price-failure', 'uncertainty-or-plateau',
                                'evaluation-limit', 'unrepresentable-progress',
                                'inconsistent-prices', 'below-range', 'above-range'},
                    'unexpected outcome')
            try:
                replay = bytes.fromhex(parts[3])
            except ValueError:
                raise ValueError('malformed replay') from None
            require(len(replay) >= 20 and replay[:4] == bytes.fromhex('8495a6be')
                    and int.from_bytes(replay[4:8], 'big') == len(replay) - 20,
                    'malformed replay')
            rows[parts[1]] = parts[2:]
        elif parts[0] == 'TOTAL':
            require(total is None and len(parts) == 5, 'malformed total')
            total = list(map(int, parts[1:]))
        else:
            raise ValueError('unexpected output')
    require(list(rows) == list(ids), 'incomplete or changed case identity/order')
    accepted = {k for k, v in rows.items() if v[0] == 'interval'}
    require(roots == accepted, 'root/outcome mismatch')
    require(total == [len(ids), len(accepted), len(ids)-len(accepted), 0], 'incomplete total')
    require(len(accepted) >= minimum, 'acceptance criterion not met')
    return rows


def execute(command, stdout, stderr, timeout):
    with Path(stdout).open('w') as out, Path(stderr).open('w') as err:
        try:
            p = subprocess.run(command, stdout=out, stderr=err, timeout=timeout)
        except FileNotFoundError as e:
            raise ValueError('failed startup') from e
        except subprocess.TimeoutExpired as e:
            raise ValueError('timeout') from e
    require(p.returncode == 0, 'process failed')
    return Path(stdout).read_text()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('logs', nargs='+', type=Path)
    p.add_argument('--minimum', type=int, default=0)
    p.add_argument('--same', action='store_true')
    p.add_argument('--version', action='version', version='american-iv-campaign 1')
    a = p.parse_args()
    ids = [r['id'] for r in load()]
    rows = [parse(f.read_text(), ids, a.minimum) for f in a.logs]
    if a.same:
        require(all(r == rows[0] for r in rows), 'changed replay')
    print(json.dumps([{'log':str(f), 'accepted':sum(v[0]=='interval' for v in r.values()),
                       'refused':sum(v[0]!='interval' for v in r.values())}
                      for f,r in zip(a.logs,rows)], indent=2))

if __name__ == '__main__':
    main()
