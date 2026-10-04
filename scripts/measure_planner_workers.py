#!/usr/bin/env python3
"""Retain a serial, alternating-order worker/tile sweep of a built benchmark."""
import argparse
import datetime
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess


def command(args):
    return subprocess.check_output(args, text=True).strip()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', action='version', version='planner-workers-sweep-v1')
    args = parser.parse_args()
    binary = args.binary.resolve()
    # Refuse to replace a prior campaign, including an interrupted one.
    if args.output.exists():
        parser.error('output already exists')
    configurations = [('fast', 32, t) for t in (8, 32)]
    configurations += [('fast', 1024, t) for t in (32, 256, 1024)]
    configurations += [('fast', 16384, t) for t in (32, 256, 1024, 4096)]
    configurations += [('certified', 16, t) for t in (1, 4, 16)]
    configurations += [('certified', 128, t) for t in (1, 8, 32, 128)]
    data = {
        'schema': 'planner-workers-sweep-v1',
        'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'platform': platform.platform(),
        'hardware': command(['sysctl', '-n', 'machdep.cpu.brand_string']) if platform.system() == 'Darwin' else platform.machine(),
        'logical_cpus': os.cpu_count(),
        'source_commit': command(['git', 'rev-parse', 'HEAD']),
        'library_tree': command(['git', 'rev-parse', 'HEAD:lib']),
        'diff': command(['git', 'diff', '--', 'lib']),
        'harness_sha256': sha('bench/planner_workers.ml'),
        'driver_sha256': sha(__file__),
        'binary_sha256': sha(binary),
        'compiler_config': command(['opam', 'exec', '--switch=morphiq-risk-ml', '--', 'ocamlopt', '-config']),
        'profile': 'release (caller must build the supplied binary in this profile)',
        'complete': False,
        'runs': [],
    }
    if data['diff']:
        raise RuntimeError('campaign expects an unchanged library')
    digests = {}
    try:
        # Reversal reduces order bias; it does not isolate the host or remove GC noise.
        for repetition in range(4):
            ordered = configurations if repetition in (0, 3) else list(reversed(configurations))
            for mode, size, tile in ordered:
                iterations = max(1, 4096 // size) if mode == 'fast' else 1
                argv = [str(binary), '--mode', mode, '--size', str(size),
                        '--tile-rows', str(tile), '--samples', '5', '--warmups', '3',
                        '--iterations', str(iterations)]
                run = {'repetition': repetition, 'argv': argv,
                       'start_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                       'load_before': os.getloadavg()}
                data['runs'].append(run)
                result = subprocess.run(argv, text=True, capture_output=True, timeout=180)
                run.update(stdout=result.stdout, stderr=result.stderr,
                           returncode=result.returncode, load_after=os.getloadavg())
                if result.returncode:
                    raise RuntimeError(f'benchmark failed: {argv}: {result.stderr}')
                records = [json.loads(line) for line in result.stdout.splitlines()]
                config = records[0]
                if len(records) != 31 or config['kind'] != 'config':
                    raise RuntimeError('incomplete benchmark records')
                key = mode, size
                if digests.setdefault(key, config['digest']) != config['digest']:
                    raise RuntimeError('tile/repetition output replay differs')
                print(repetition, mode, size, tile, 'checked', flush=True)
        data['complete'] = True
    finally:
        data['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        args.output.parent.mkdir(parents=True, exist_ok=True)
        # Exclusive creation also protects against a concurrent campaign.
        with args.output.open('xb') as stream:
            with gzip.GzipFile(fileobj=stream, mode='wb', mtime=0, filename='') as compressed:
                compressed.write((json.dumps(data, indent=2) + '\n').encode())


if __name__ == '__main__':
    main()
