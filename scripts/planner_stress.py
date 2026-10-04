#!/usr/bin/env python3
"""Bound planner stress subprocesses and separately measure fresh-process RSS."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import resource
import subprocess
import sys
import time


def run(command, seconds):
    # OCaml domains are threads of this child: timeout kills and reaps the process.
    result = subprocess.run(command, capture_output=True, text=True, timeout=seconds)
    if result.returncode:
        raise RuntimeError(f'exit {result.returncode}: {result.stderr}\n{result.stdout}')
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='planner-stress 1')
    sub = parser.add_subparsers(dest='command', required=True)
    check = sub.add_parser('check')
    check.add_argument('runner', type=Path)
    check.add_argument('--repeats', type=int, default=1)
    memory = sub.add_parser('memory')
    memory.add_argument('runner', type=Path)
    measure = sub.add_parser('measure')
    measure.add_argument('runner', type=Path)
    measure.add_argument('book', type=int)
    measure.add_argument('scenarios', type=int)
    args = parser.parse_args()
    runner = str(args.runner.resolve())
    if args.command == 'measure':
        started = time.monotonic()
        result = run([runner, '--memory', str(args.book), str(args.scenarios)], 120)
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        # macOS reports bytes, Linux reports KiB. Other platforms are unsupported.
        if sys.platform not in ('darwin', 'linux'):
            raise ValueError('RSS units are not defined on this platform')
        result['peak_rss_bytes'] = usage.ru_maxrss * (1 if sys.platform == 'darwin' else 1024)
        result['elapsed_seconds'] = time.monotonic() - started
        print(json.dumps(result))
        return
    results = []
    if args.command == 'check':
        if not 1 <= args.repeats <= 50:
            raise ValueError('repeats must be in 1..50')
        for _ in range(args.repeats):
            results.append(run([runner], 90))
    else:
        for book, scenarios in ((256, 1), (256, 8), (4096, 1), (4096, 8)):
            results.append(run([sys.executable, str(Path(__file__).resolve()),
                                'measure', runner, str(book), str(scenarios)], 125))
    try:
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        revision = 'unavailable'  # Dune's source sandbox has no Git metadata.
    print(json.dumps(dict(schema=1, command=args.command, complete=True,
                          source_commit=revision, platform=platform.platform(),
                          python=platform.python_version(),
                          runner_sha256=hashlib.sha256(Path(runner).read_bytes()).hexdigest(),
                          results=results), indent=2))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps(dict(complete=False, tool_error=str(error))), file=sys.stderr)
        raise SystemExit(2)
