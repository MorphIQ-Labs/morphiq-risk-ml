#!/usr/bin/env python3
"""Verify a retained experimental dossier; never grants institutional approval."""
import argparse
import hashlib
import json
from pathlib import Path
import re

PLATFORMS = {'ubuntu-24.04', 'ubuntu-24.04-arm', 'macos-15'}
CATEGORIES = {'scope', 'provenance', 'numerical', 'planner', 'platform', 'mutations'}


def check(record, root):
    errors = []
    commit = record.get('candidate_commit', '')
    if not re.fullmatch(r'[0-9a-f]{40}', commit): errors.append('invalid candidate commit')
    if record.get('decision') != 'qualified-experimental': errors.append('not qualified')
    if not record.get('assessor') or not record.get('limitations'): errors.append('missing decision scope')
    if record.get('package_version') != '0.3.0': errors.append('unexpected baseline version')
    evidence = record.get('evidence', [])
    if {e.get('category') for e in evidence} != CATEGORIES: errors.append('incomplete evidence categories')
    platforms = set()
    for item in evidence:
        path = item.get('path', '')
        target = (root / path).resolve()
        if not path or not target.is_relative_to(root.resolve()) or not target.is_file():
            errors.append('missing/outside evidence: ' + path)
            continue
        if hashlib.sha256(target.read_bytes()).hexdigest() != item.get('sha256'):
            errors.append('changed evidence: ' + path)
        if item.get('candidate_commit') != commit: errors.append('candidate mismatch: ' + path)
        if item.get('category') == 'platform':
            platform = item.get('platform')
            if platform in platforms: errors.append('duplicate platform')
            platforms.add(platform)
            report = json.loads(target.read_text())
            if report.get('commit') != commit or report.get('package_version') != record.get('package_version'):
                errors.append('artifact identity mismatch: ' + path)
            if not all(report.get(k) for k in ['source_tar_reproduced', 'smoke_native', 'smoke_bytecode', 'installed_notices_sha256', 'consumer_sha256']):
                errors.append('incomplete installed consumer evidence: ' + path)
    if platforms != PLATFORMS: errors.append('incomplete platform coverage')
    return errors


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('record', type=Path)
    p.add_argument('--root', type=Path, default=Path('.'))
    args = p.parse_args()
    try: errors = check(json.loads(args.record.read_text()), args.root)
    except (OSError, ValueError, TypeError, AttributeError, KeyError) as e: errors = ['invalid dossier: ' + str(e)]
    print(json.dumps(dict(qualified=not errors, errors=errors), indent=2))
    raise SystemExit(bool(errors))


if __name__ == '__main__': main()
