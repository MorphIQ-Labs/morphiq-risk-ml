#!/usr/bin/env python3
"""Manual paired campaign for the frozen scalar American allocation protocol."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
MODES = ('none', 'zero', 'cash', 'multiple')
PHASES = ('admission', 'price', 'diagnostics')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sample(command, output, timeout=120):
    """Retain raw output even on failure; reap resource usage from this child."""
    with output.with_suffix('.stdout').open('wb') as stdout, output.with_suffix('.stderr').open('wb') as stderr:
        try:
            process = subprocess.Popen(command, stdout=stdout, stderr=stderr)
        except OSError as error:
            raise ValueError('benchmark failed to start') from error
        deadline = time.monotonic() + timeout
        expired = False
        while True:
            pid, status, usage = os.wait4(process.pid, os.WNOHANG)
            if pid:
                break
            if time.monotonic() >= deadline:
                expired = True
                try:
                    os.kill(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                _, status, usage = os.wait4(process.pid, 0)
                break
            time.sleep(0.005)
        process.returncode = os.waitstatus_to_exitcode(status)
    resources = dict(returncode=process.returncode, timed_out=expired,
                     peak_rss_bytes=usage.ru_maxrss * (1 if platform.system() == 'Darwin' else 1024),
                     user_seconds=usage.ru_utime, system_seconds=usage.ru_stime)
    output.with_suffix('.resources.json').write_text(json.dumps(resources, indent=2)+'\n')
    require(not expired, 'benchmark timeout')
    require(process.returncode == 0, 'benchmark child failed')
    return output.with_suffix('.stdout').read_text(), resources


def decode(raw, mode, phase, calls):
    try:
        value = json.loads(raw)
    except (ValueError, TypeError) as error:
        raise ValueError('malformed benchmark output') from error
    require(type(value) is dict, 'benchmark record must be an object')
    require((value.get('mode'), value.get('phase'), value.get('calls')) == (mode, phase, calls),
            'benchmark workload mismatch')
    for key in ('seconds_per_call', 'allocated_bytes_per_call'):
        number = value.get(key)
        require(type(number) in (float, int) and math.isfinite(number) and number > 0,
                'invalid benchmark metric: '+key)
    for key in ('minor_collections', 'major_collections', 'heap_words_after', 'live_words_after'):
        require(type(value.get(key)) is int and value[key] >= 0, 'invalid GC metric: '+key)
    return value


def guard(build, current=False):
    require(build['status'] == '', 'dirty build source')
    for name, digest in build['source_sha256'].items():
        content = subprocess.check_output(['git', '-C', str(ROOT), 'show', build['revision']+':'+name])
        require(hashlib.sha256(content).hexdigest() == digest, 'build source hash mismatch: '+name)
        if current:
            require(sha(ROOT/name) == digest, 'current source changed: '+name)
    if current:
        paths = ['lib', 'bench', 'dune', 'dune-project', 'morphiq_risk_ml.opam.locked']
        status = subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain',
                                          '--untracked-files=all', '--', *paths], text=True)
        require(not status, 'staged, unstaged or untracked measurement source')
    require(sha(build['binaries']['bench']['path']) == build['binaries']['bench']['sha256'],
            'benchmark binary changed')


def summarize(runs, rounds=5):
    result = []
    for mode in MODES:
        for phase in PHASES:
            row = dict(mode=mode, phase=phase)
            for variant in ('baseline', 'candidate'):
                values = [r for r in runs if (r['variant'], r['sample']['mode'], r['sample']['phase']) ==
                          (variant, mode, phase)]
                require(len(values) == rounds and {r['round'] for r in values} == set(range(rounds)),
                        'incomplete or duplicate campaign')
                row[variant] = {key: dict(median=statistics.median(v['sample'][key] for v in values),
                                         min=min(v['sample'][key] for v in values),
                                         max=max(v['sample'][key] for v in values))
                                for key in ('seconds_per_call', 'allocated_bytes_per_call',
                                            'minor_collections', 'major_collections')}
            row['allocation_reduction'] = 1 - row['candidate']['allocated_bytes_per_call']['median'] / row['baseline']['allocated_bytes_per_call']['median']
            row['speedup'] = row['baseline']['seconds_per_call']['median'] / row['candidate']['seconds_per_call']['median']
            result.append(row)
    return result


def acceptance(summary, reduction=0.9, regression=0.1):
    require(math.isfinite(reduction) and 0 <= reduction <= 1 and
            math.isfinite(regression) and regression >= 0, 'invalid acceptance criteria')
    require(len(summary) == len(MODES)*len(PHASES) and
            {(r['mode'], r['phase']) for r in summary} == {(m, p) for m in MODES for p in PHASES},
            'incomplete acceptance summary')
    for row in summary:
        if row['mode'] in ('none', 'zero', 'cash') and row['phase'] in ('price', 'diagnostics'):
            require(row['allocation_reduction'] >= reduction, 'allocation criterion failed')
            require(row['speedup'] >= 1/(1+regression), 'latency criterion failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='american-allocation-v1')
    parser.add_argument('--baseline', type=Path, required=True, help='Recorded clean baseline build manifest')
    parser.add_argument('--candidate', type=Path, required=True, help='Recorded clean candidate build manifest')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--minimum-allocation-reduction', type=float, default=0.9,
                        help='Fraction frozen in the campaign protocol before runtime edits')
    parser.add_argument('--maximum-latency-regression', type=float, default=0.1)
    args = parser.parse_args()
    require(math.isfinite(args.minimum_allocation_reduction) and 0 <= args.minimum_allocation_reduction <= 1 and
            math.isfinite(args.maximum_latency_regression) and args.maximum_latency_regression >= 0,
            'invalid acceptance criteria')
    builds = {variant: json.loads(getattr(args, variant).read_text()) for variant in ('baseline', 'candidate')}
    for variant, build in builds.items():
        guard(build, current=variant == 'candidate')
    require(builds['baseline']['compiler'] == builds['candidate']['compiler'], 'different compilers')
    require(builds['baseline']['source_sha256']['bench/american_allocation.ml'] ==
            builds['candidate']['source_sha256']['bench/american_allocation.ml'], 'different drivers')
    args.output.mkdir(parents=True, exist_ok=False)
    report = dict(schema='american-allocation-v1', complete=False, builds=builds, runs=[],
                  platform=platform.platform(), cpu_count=os.cpu_count(), collector_sha256=sha(__file__),
                  warmup='one operation then full major GC; three measured calls or 100000 admissions',
                  flags='Dune release, library and driver -O3; no profiling during timing')
    report['criteria'] = dict(minimum_allocation_reduction=args.minimum_allocation_reduction,
                             maximum_latency_regression=args.maximum_latency_regression)
    if platform.system() == 'Darwin':
        report['hardware'] = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()

    def save():
        (args.output/'results.json').write_text(json.dumps(report, indent=2, allow_nan=False)+'\n')

    try:
        for round_ in range(5):
            for mode in MODES:
                for phase in PHASES:
                    for variant in (('baseline', 'candidate') if round_ % 2 == 0 else ('candidate', 'baseline')):
                        build = builds[variant]
                        calls = 100000 if phase == 'admission' else 3
                        command = [build['binaries']['bench']['path'], '--measure', '--mode', mode,
                                   '--phase', phase, '--calls', str(calls)]
                        entry = dict(variant=variant, round=round_, command=command,
                                     started_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                                     load_before=os.getloadavg())
                        raw, usage = sample(command, args.output/f'{round_}-{mode}-{phase}-{variant}')
                        entry.update(sample=decode(raw, mode, phase, calls), usage=usage,
                                     load_after=os.getloadavg())
                        report['runs'].append(entry)
                        save()
            print('finished round', round_+1, flush=True)
        for variant, build in builds.items():
            guard(build, current=variant == 'candidate')
        report['summary'] = summarize(report['runs'])
        acceptance(report['summary'], args.minimum_allocation_reduction, args.maximum_latency_regression)
        report['complete'] = True
    except BaseException as error:
        report['failure'] = str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    main()
