#!/usr/bin/env python3
"""Collect the frozen American workload/worker campaign without changing pricing."""
import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import time

CASES = ('call', 'flat', 'cash', 'bermudan', 'piecewise', 'piecewise-cash',
         'greeks', 'curve-greeks', 'iv', 'certified', 'hard', 'mixed')
SUCCESS = {'estimated', 'estimated-iv', 'certified'}
STATUS = SUCCESS | {'unavailable', 'resource-limit', 'cancelled',
                   'arithmetic-unresolved', 'unrepresentable', 'nonconvergence',
                   'accuracy-not-demonstrated', 'iv-resource-limit', 'iv-cancelled',
                   'iv-arithmetic-unresolved', 'iv-unrepresentable', 'iv-nonconvergence',
                   'iv-accuracy-not-demonstrated', 'iv-price-uncertainty',
                   'iv-evaluation-limit', 'iv-refusal', 'certificate-refusal',
                   'post-expiry', 'admission-refusal'}
HEX = re.compile(r'[0-9a-f]{64}\Z')


def configurations(size):
    return [(1, 1)] if size == 1 else [(t, w) for t in (1, 2, 4) for w in (1, 2, 4)]


def methods(size):
    return {('admission', 0, 1), ('end-to-end', 0, 1), ('scalar', 0, 1), ('batch', 0, 1)} | {
        ('planner', t, w) for t, w in configurations(size)}


def number(word, positive=False):
    value = float(word)
    if not math.isfinite(value) or value < 0 or (positive and value == 0):
        raise ValueError('invalid numeric measurement')
    return value


def parse(text, case, size, phase):
    if case not in CASES or size not in (1, 4) or phase not in ('check', 'time', 'memory', 'cancel'):
        raise ValueError('invalid requested matrix')
    expected_rows = 1 if size == 1 else 8
    row_data, samples, compilation, cancellation = {}, {}, {}, {}
    check = None
    for line in text.splitlines():
        f = line.split('\t')
        tag = f[0]
        if tag == 'ROW' and len(f) == 4:
            index = int(f[1]); statuses = f[3].split(',')
            if index in row_data or not 0 <= index < expected_rows or not HEX.fullmatch(f[2]):
                raise ValueError('invalid/duplicate row')
            if len(statuses) != (2 if case in ('greeks', 'curve-greeks') else 1) or not set(statuses) <= STATUS:
                raise ValueError('invalid status classification')
            row_data[index] = dict(digest=f[2], statuses=statuses)
        elif tag == 'CHECK' and len(f) == 8:
            if check is not None or f[1] != case or int(f[2]) != size or int(f[3]) != expected_rows or not HEX.fullmatch(f[7]):
                raise ValueError('invalid/duplicate check')
            check = dict(rows=int(f[3]), accepted=int(f[4]), failed=int(f[5]), unavailable=int(f[6]), digest=f[7])
        elif tag in ('TIME', 'MEMORY') and len(f) == (7 if tag == 'TIME' else 8):
            if phase != ('time' if tag == 'TIME' else 'memory'):
                raise ValueError('unexpected sample phase')
            key = f[1], int(f[2]), int(f[3])
            if key not in methods(size) or key in samples:
                raise ValueError('invalid/duplicate method')
            if tag == 'TIME':
                value = dict(wall_s=number(f[4]), cpu_s=number(f[5]), first_row_s=number(f[6]))
                if key[0] == 'planner' and value['first_row_s'] <= 0:
                    raise ValueError('missing first row')
            else:
                value = dict(total_bytes=number(f[4]), coordinator_bytes=number(f[5]),
                             minor_collections=int(f[6]), major_collections=int(f[7]))
                if value['total_bytes'] < value['coordinator_bytes'] or min(value['minor_collections'], value['major_collections']) < 0:
                    raise ValueError('inconsistent allocation scope')
            samples[key] = value
        elif tag == 'COMPILE' and len(f) == 4:
            key = f[1], int(f[2])
            if phase != 'time' or key in compilation or key not in ({('batch', 0)} | {('planner', t) for t, _ in configurations(size)}):
                raise ValueError('invalid/duplicate compilation')
            compilation[key] = number(f[3], True)
        elif tag == 'CANCEL' and len(f) == 8:
            key = int(f[1]), int(f[2])
            if phase != 'cancel' or case != 'flat' or size != 4 or key not in configurations(size) or key in cancellation:
                raise ValueError('invalid/duplicate cancellation')
            issued = number(f[4]); latency = float(f[5]); rows, slots = int(f[6]), int(f[7])
            if not math.isfinite(latency) or not 0 <= rows == slots <= expected_rows:
                raise ValueError('invalid cancellation prefix')
            if f[3] == 'cancelled':
                if latency < 0: raise ValueError('cancelled before issuance')
            elif f[3] != 'complete' or rows != expected_rows:
                raise ValueError('invalid cancellation stop')
            cancellation[key] = dict(stop=f[3], issued_s=issued, controller_delay_s=issued-.005,
                                     return_after_issue_s=latency, rows=rows, slots=slots)
        else:
            raise ValueError('malformed/unknown record')
    if check is None or len(row_data) != expected_rows:
        raise ValueError('incomplete replay evidence')
    statuses = [x for row in row_data.values() for x in row['statuses']]
    if (sum(x in SUCCESS for x in statuses), sum(x not in SUCCESS and x != 'unavailable' for x in statuses), statuses.count('unavailable')) != (check['accepted'], check['failed'], check['unavailable']):
        raise ValueError('classification totals differ')
    if set(samples) != (methods(size) if phase in ('time', 'memory') else set()):
        raise ValueError('incomplete measurement matrix')
    if set(compilation) != (({('batch', 0)} | {('planner', t) for t, _ in configurations(size)}) if phase == 'time' else set()):
        raise ValueError('incomplete compilation matrix')
    if set(cancellation) != (set(configurations(size)) if phase == 'cancel' else set()):
        raise ValueError('incomplete cancellation matrix')
    encode = lambda key: '/'.join(map(str, key))
    return dict(check=check, rows=row_data, samples={encode(k): v for k, v in samples.items()},
                compilation={encode(k): v for k, v in compilation.items()}, cancellation={encode(k): v for k, v in cancellation.items()})


def same_replay(previous, current):
    if previous['check'] != current['check'] or previous['rows'] != current['rows']:
        raise ValueError('changed complete replay or status')


def child(command, stdout, stderr, timeout):
    if platform.system() not in ('Darwin', 'Linux'):
        raise ValueError('unsupported RSS units')
    started = time.monotonic(); timed_out = False
    load = os.getloadavg()
    with stdout.open('w') as out, stderr.open('w') as err:
        process = subprocess.Popen(command, stdout=out, stderr=err, start_new_session=True)
        try:
            while True:
                pid, status, usage = os.wait4(process.pid, os.WNOHANG)
                if pid: break
                if time.monotonic() - started > timeout:
                    timed_out = True
                    os.killpg(process.pid, signal.SIGKILL)
                    _, status, usage = os.wait4(process.pid, 0)
                    break
                time.sleep(.01)
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            os.wait4(process.pid, 0)
            process.returncode = -signal.SIGKILL
            raise
        process.returncode = os.waitstatus_to_exitcode(status)
    return dict(command=command, pid=process.pid, exit=process.returncode, timed_out=timed_out,
                wall_s=time.monotonic()-started, load_before=load, load_after=os.getloadavg(),
                peak_rss_bytes=usage.ru_maxrss * (1 if platform.system() == 'Darwin' else 1024),
                user_cpu_s=usage.ru_utime, system_cpu_s=usage.ru_stime)


def require_child(record):
    if record['timed_out']: raise RuntimeError('child timed out and was reaped')
    if record['exit']: raise RuntimeError('child exited unsuccessfully')


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, cwd): return subprocess.check_output(args, cwd=cwd, text=True).strip()


def source_snapshot(root):
    files = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    return {p: sha(root/p) for p in sorted(set(files)-{''}) if (root/p).is_file()}


def atomic_json(path, data):
    temporary = path.with_name(path.name + '.' + str(os.getpid()) + '.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', action='version', version='american-workloads-collector 1')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    binary = args.binary.resolve(); destination = args.output.resolve()
    if destination.is_relative_to(root): parser.error('output must be outside the source tree')
    destination.mkdir(parents=True, exist_ok=False)
    snapshot = source_snapshot(root); binary_hash = sha(binary)
    manifest = dict(schema=1, source_commit=command(['git','rev-parse','HEAD'],root),
                    status=command(['git','status','--porcelain'],root), files=snapshot,
                    binary_sha256=binary_hash, driver_sha256=sha(Path(__file__)),
                    platform=platform.platform(), logical_cpus=os.cpu_count(),
                    hardware=command(['sysctl','-n','machdep.cpu.brand_string'],root) if platform.system()=='Darwin' else platform.machine(),
                    compiler=command(['opam','exec','--switch=morphiq-risk-ml','--','ocamlopt','-config'],root),
                    started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    atomic_json(destination/'source.json', manifest)
    replay = {}; records = []
    jobs = [(case, size, phase) for case in CASES for size in (1,4) for phase in ('time','memory')]
    jobs.append(('flat',4,'cancel'))
    for round_index in range(5):
        for case, size, phase in (list(reversed(jobs)) if round_index%2 else jobs):
            if source_snapshot(root)!=snapshot or sha(binary)!=binary_hash:
                raise RuntimeError('source or binary changed during campaign')
            name=f'{round_index}-{case}-{size}-{phase}'
            args=[str(binary),'--case',case,'--size',str(size),'--phase',phase]+(['--reverse'] if round_index%2 else [])
            record=dict(round=round_index,case=case,size=size,phase=phase,
                        **child(args,destination/(name+'.log'),destination/(name+'.stderr'),600))
            atomic_json(destination/(name+'.json'),record)
            require_child(record)
            parsed=parse((destination/(name+'.log')).read_text(),case,size,phase)
            key=case,size
            if key in replay: same_replay(replay[key],parsed)
            else: replay[key]=parsed
            record.update(parsed);records.append(record)
            atomic_json(destination/(name+'.json'),record)
            atomic_json(destination/'progress.json',dict(completed=len(records),expected=5*len(jobs),last=name))
            print(name,'pass',round(record['wall_s'],3),flush=True)
    if source_snapshot(root)!=snapshot or sha(binary)!=binary_hash:
        raise RuntimeError('source or binary changed during campaign')
    atomic_json(destination/'complete.json',dict(complete=True,processes=len(records),source_unchanged=True,finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))


if __name__ == '__main__':
    main()
