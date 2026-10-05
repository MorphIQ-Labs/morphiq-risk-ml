#!/usr/bin/env python3
"""Paired European certified scalar checks for shared enclosure changes."""
import argparse
import json
import math
from pathlib import Path
import statistics
import time
import os
import platform
import subprocess
from benchmark_american_allocation import guard, require, sample, sha

CASES = {'bsm-'+x for x in ('ordinary', 'tail', 'short', 'expiry', 'accuracy-failure')} | {'black76', 'displaced', 'normal'}
PHASES = ('admission', 'price', 'end-to-end')
SLOTS = {(c+'/'+p, n) for c in CASES for p in PHASES for n in range(1, 6)}


def decode(raw):
    checks, values = {}, {}
    for line in raw.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[0] == 'CHECK':
            _, key, value = fields
            require(key in CASES and key not in checks, 'invalid or duplicate CHECK')
            parts = value.split(':')
            if parts[0] == 'served':
                require(len(parts) == 3, 'malformed served CHECK')
                numbers = [float.fromhex(x) for x in parts[1:]]
                require(all(math.isfinite(x) and x >= 0 for x in numbers), 'invalid served CHECK')
            else:
                require(value in ('invalid-input', 'invalid-accuracy', 'unsupported', 'numerical-failure', 'accuracy-exceeded'), 'invalid failure CHECK')
            checks[key] = value
        elif len(fields) == 8 and fields[0] == 'TIME':
            _, key, index, ns, cpu_ns, allocation, minor, major = fields
            slot = key, int(index)
            require(slot in SLOTS and slot not in values, 'invalid or duplicate TIME')
            numbers = [float(ns), float(cpu_ns), float(allocation)]
            require(all(math.isfinite(x) and x >= 0 for x in numbers) and numbers[0] > 0, 'invalid TIME metric')
            require(int(minor) >= 0 and int(major) >= 0, 'invalid TIME GC count')
            values[slot] = dict(key=key, index=int(index), ns=numbers[0], cpu_ns=numbers[1],
                                allocation=numbers[2], minor=int(minor), major=int(major))
        else:
            raise ValueError('malformed benchmark output')
    require(set(checks) == CASES and set(values) == SLOTS, 'incomplete benchmark output')
    return dict(checks=checks, samples=list(values.values()))


def same_checks(expected, actual):
    require(expected == actual, 'complete CHECK mismatch')


def summarize(runs):
    result = []
    for key in sorted({key for key, _ in SLOTS}):
        row = dict(key=key)
        for variant in ('baseline', 'candidate'):
            chosen = [r for r in runs if r['variant'] == variant]
            require(len(chosen) == 5 and {r['round'] for r in chosen} == set(range(5)), 'incomplete or duplicate campaign')
            means = [dict(ns=statistics.mean(s['ns'] for s in r['sample']['samples'] if s['key'] == key),
                          allocation=statistics.mean(s['allocation'] for s in r['sample']['samples'] if s['key'] == key)) for r in chosen]
            row[variant] = {metric: dict(median=statistics.median(m[metric] for m in means),
                                       min=min(m[metric] for m in means), max=max(m[metric] for m in means)) for metric in ('ns', 'allocation')}
        row['speedup'] = row['baseline']['ns']['median'] / row['candidate']['ns']['median']
        result.append(row)
    return result


def acceptance(summary):
    require(len(summary) == len(CASES)*len(PHASES) and {r['key'] for r in summary} == {k for k, _ in SLOTS}, 'incomplete summary')
    for row in summary:
        if not row['key'].endswith('/admission'):
            require(row['speedup'] >= 1/1.1, 'European latency regression: '+row['key'])
            require(row['candidate']['allocation']['median'] <= 1.1 * row['baseline']['allocation']['median'], 'European allocation regression: '+row['key'])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version', action='version', version='enclosure-consumers-v1')
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    builds = {v: json.loads(getattr(args, v).read_text()) for v in ('baseline', 'candidate')}

    def guards():
        for v, build in builds.items():
            guard(build, current=v == 'candidate')
            require(sha(build['binaries']['certified']['path']) == build['binaries']['certified']['sha256'], 'certified binary changed')
        require(builds['baseline']['compiler'] == builds['candidate']['compiler'], 'different compilers')
        require(builds['baseline']['source_sha256']['bench/certified_scalar.ml'] == builds['candidate']['source_sha256']['bench/certified_scalar.ml'], 'different certified drivers')

    guards(); args.output.mkdir(parents=True, exist_ok=False)
    report = dict(schema='enclosure-consumers-v1', complete=False, builds=builds, runs=[],
                  platform=platform.platform(), cpu_count=os.cpu_count(),
                  collector_sha256=sha(__file__), criteria='<=10% median latency/allocation regression per price/end-to-end case',
                  aggregation='median of five process means, each retaining five inner samples of 40 calls')
    if platform.system() == 'Darwin':
        report['hardware'] = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
    def save():
        (args.output/'results.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n')
    try:
        expected = None
        for round_ in range(5):
            for variant in (('baseline', 'candidate') if round_ % 2 == 0 else ('candidate', 'baseline')):
                command = [builds[variant]['binaries']['certified']['path']]
                before = os.getloadavg()
                raw, usage = sample(command, args.output/f'{round_}-{variant}', timeout=300)
                data = decode(raw)
                if expected is None: expected = data['checks']
                same_checks(expected, data['checks'])
                report['runs'].append(dict(variant=variant, round=round_, command=command, sample=data, usage=usage,
                                          load_before=before, load_after=os.getloadavg(), completed_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())))
                save()
            print('finished European pair', round_+1, flush=True)
        guards(); report['summary'] = summarize(report['runs']); acceptance(report['summary']); report['complete'] = True
    except BaseException as error:
        report['failure'] = str(error)
        raise
    finally:
        save()


if __name__ == '__main__': main()
