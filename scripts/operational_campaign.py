#!/usr/bin/env python3
"""Optional synchronized multi-process planner campaign; never a deployment approval."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import selectors
import signal
import statistics
import subprocess
import time

SCHEMA = 'planner-operational-v1'
ROOT = Path(__file__).resolve().parents[1]
LIMITS = {'warm_p95_ms', 'min_requests_per_second', 'max_process_rss_bytes',
          'max_failure_fraction', 'max_cancel_observation_ms'}
ERRORS = {'post_expiry', 'invalid_input', 'invalid_accuracy', 'unsupported',
          'numerical_failure', 'accuracy_exceeded'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite(x):
    return type(x) in (float, int) and math.isfinite(x)


def integer(x, low=1):
    return type(x) is int and low <= x <= (1 << 53) - 1


def decode(text):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON key: ' + key)
            result[key] = value
        return result
    def invalid(value):
        raise ValueError('nonfinite JSON: ' + value)
    return json.loads(text, object_pairs_hook=pairs, parse_constant=invalid)


def validate(config):
    require(type(config) is dict, 'configuration object required')
    require(set(config) == {'schema', 'scope', 'repetitions', 'warmups', 'requests',
                            'timeout_seconds', 'cases'}, 'unknown/missing configuration fields')
    require(config['schema'] == SCHEMA, 'configuration schema')
    require(isinstance(config['scope'], str) and config['scope'].strip(), 'scope required')
    for key in ('repetitions', 'requests'):
        require(integer(config[key]), key)
    require(integer(config['warmups'], 0), 'warmups')
    require(finite(config['timeout_seconds']) and config['timeout_seconds'] > 0, 'timeout')
    require(type(config['cases']) is list and config['cases'], 'cases required')
    names = set()
    for case in config['cases']:
        require(type(case) is dict, 'case object required')
        require(set(case) == {'name', 'positions', 'days', 'mode', 'outputs', 'allowance',
                             'workers', 'tile_rows', 'buffer_slots', 'concurrency',
                             'policy', 'sink', 'cancel_after_ms', 'requirements'}, 'case fields')
        require(isinstance(case['name'], str) and re.fullmatch('[a-z0-9][a-z0-9_-]*', case['name']), 'case name')
        require(case['name'] not in names, 'duplicate case name')
        names.add(case['name'])
        for key in ('positions', 'workers', 'tile_rows', 'buffer_slots', 'concurrency'):
            require(integer(case[key]), key)
        require(type(case['days']) is list and case['days'] and
                all(type(x) is int and 0 <= x <= 1000000000 for x in case['days']), 'days')
        require(case['mode'] in ('fast', 'certified'), 'mode')
        require(case['outputs'] in ('price', 'all'), 'outputs')
        require(case['mode'] != 'fast' or case['outputs'] == 'price', 'fast price only')
        require(case['policy'] in ('reuse', 'recompile'), 'policy')
        require(case['sink'] in ('count', 'digest'), 'sink')
        require(finite(case['allowance']) and case['allowance'] > 0, 'allowance')
        delay = case['cancel_after_ms']
        require(delay is None or (finite(delay) and 0 <= delay < config['timeout_seconds'] * 1000), 'cancel delay')
        require(type(case['requirements']) is dict and set(case['requirements']) == LIMITS, 'requirement fields')
        for name, value in case['requirements'].items():
            require(value is None or (finite(value) and value >= 0), 'invalid requirement: ' + name)
        failure = case['requirements']['max_failure_fraction']
        require(failure is None or failure <= 1, 'failure fraction')
        count = 1 if case['outputs'] == 'price' else 11
        require(case['positions'] * len(case['days']) * count <= (1 << 53) - 1, 'workload overflow')
    return config


def record(value, kind, case):
    require(type(value) is dict and value.get('kind') == kind, 'unexpected worker record')
    count = 1 if case['outputs'] == 'price' else 11
    total_rows = case['positions'] * len(case['days'])
    fields = {
        'ready': {'kind', 'plan_id', 'rows', 'calculations', 'tiles', 'buffered_results', 'initial_compile_ms'},
        'check': {'kind', 'digest'},
        'request': {'kind', 'stop', 'rows', 'calculations', 'served', 'errors', 'summaries',
                    'request_ms', 'prepare_ms', 'execute_ms', 'cpu_ms', 'first_row_ms',
                    'cancel_observation_ms', 'cancel_issued_ms', 'cancel_schedule_lateness_ms',
                    'coordinator_bytes', 'minor_collections', 'major_collections', 'digest'},
    }
    require(set(value) == fields[kind], 'worker protocol fields')
    if kind == 'ready':
        tiles = ((case['positions'] + case['tile_rows'] - 1) // case['tile_rows']) * len(case['days'])
        require(value['tiles'] == tiles, 'tile count')
        expected_slots = min(case['positions'], case['tile_rows']) * min(case['workers'], tiles) * count
        require(value['buffered_results'] == expected_slots, 'explained slot count')
        require(finite(value['initial_compile_ms']) and value['initial_compile_ms'] >= 0, 'initial compile metric')
        require(value.get('rows') == total_rows and value.get('calculations') == total_rows * count,
                'ready workload mismatch')
        require(integer(value.get('buffered_results'), 0) and value['buffered_results'] <= case['buffer_slots'], 'buffer bound')
        require(isinstance(value.get('plan_id'), str) and re.fullmatch('[0-9a-f]{64}', value['plan_id']), 'plan identity')
    elif kind == 'check':
        require(isinstance(value.get('digest'), str) and re.fullmatch('[0-9a-f]{64}', value['digest']), 'replay digest')
    else:
        for key in ('rows', 'calculations', 'served', 'summaries', 'minor_collections', 'major_collections'):
            require(integer(value.get(key), 0), 'invalid worker counter: ' + key)
        require(type(value.get('errors')) is dict and set(value['errors']) <= ERRORS and
                all(integer(x) for x in value['errors'].values()), 'invalid error counts')
        require(value['served'] + sum(value['errors'].values()) == value['calculations'], 'outcome accounting')
        require(value['calculations'] == value['rows'] * count and value['rows'] <= total_rows, 'row accounting')
        require(value.get('stop') in ('complete', 'cancelled'), 'unexpected execution stop')
        if value['stop'] == 'complete':
            require(value['rows'] == total_rows, 'incomplete success')
        if case['cancel_after_ms'] is None:
            require(value['stop'] == 'complete' and value.get('cancel_observation_ms') is None, 'unexpected cancellation')
        for key in ('request_ms', 'prepare_ms', 'execute_ms', 'cpu_ms', 'coordinator_bytes'):
            require(finite(value.get(key)) and value[key] >= 0, 'invalid worker metric: ' + key)
        for key in ('first_row_ms', 'cancel_observation_ms', 'cancel_issued_ms', 'cancel_schedule_lateness_ms'):
            require(value.get(key) is None or (finite(value[key]) and value[key] >= 0), 'invalid optional metric')
        require((value.get('first_row_ms') is None) == (value['rows'] == 0), 'first-row accounting')
        require(value['rows'] != 0 or value['served'] == 0, 'empty served result')
        digest = value.get('digest')
        require((digest is None and case['sink'] == 'count') or
                (case['sink'] == 'digest' and isinstance(digest, str) and re.fullmatch('[0-9a-f]{64}', digest)), 'sink digest')
    return value


def argv(binary, case):
    names = {'positions': 'size', 'tile_rows': 'tile-rows', 'buffer_slots': 'buffer-slots'}
    args = [str(binary)]
    for key in ('positions', 'mode', 'outputs', 'allowance', 'workers', 'tile_rows', 'buffer_slots', 'policy', 'sink'):
        args += ['--' + names.get(key, key), str(case[key])]
    return args + ['--days', ','.join(map(str, case['days']))]


class Client:
    def __init__(self, command, directory, index):
        self.error = (directory / f'client-{index}.stderr').open('wb')
        self.raw = (directory / f'client-{index}.jsonl').open('wb')
        self.started = time.monotonic()
        try:
            self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=self.error, bufsize=0, start_new_session=True)
        except BaseException:
            self.error.close()
            self.raw.close()
            raise
        self.buffer = b''
        self.index = index
        self.sent = self.started
        self.usage = None

    def send(self, command):
        self.sent = time.monotonic()
        self.process.stdin.write((command + '\n').encode())

    def close(self, timeout, force=False):
        if force:
            try:
                os.kill(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + timeout
        while self.process.returncode is None:
            pid, status, usage = os.wait4(self.process.pid, os.WNOHANG)
            if pid:
                self.process.returncode = os.waitstatus_to_exitcode(status)
                self.usage = dict(peak_rss_bytes=usage.ru_maxrss * (1 if platform.system() == 'Darwin' else 1024),
                                  user_seconds=usage.ru_utime, system_seconds=usage.ru_stime,
                                  returncode=self.process.returncode)
            elif time.monotonic() >= deadline:
                os.kill(self.process.pid, signal.SIGKILL)
                # Reap the killed child in this owner, preserving per-child RSS.
                _, status, usage = os.wait4(self.process.pid, 0)
                self.process.returncode = os.waitstatus_to_exitcode(status)
                self.usage = dict(peak_rss_bytes=usage.ru_maxrss * (1 if platform.system() == 'Darwin' else 1024),
                                  user_seconds=usage.ru_utime, system_seconds=usage.ru_stime,
                                  returncode=self.process.returncode)
            else:
                time.sleep(0.005)
        self.process.stdin.close()
        self.process.stdout.close()
        self.error.close()
        self.raw.close()
        return self.usage


def receive(clients, kind, case, timeout):
    deadline = time.monotonic() + timeout
    result = []
    with selectors.DefaultSelector() as selector:
        for client in clients:
            selector.register(client.process.stdout, selectors.EVENT_READ, client)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            require(remaining > 0, 'worker response timeout')
            for key, _ in selector.select(remaining):
                client = key.data
                chunk = os.read(key.fd, 65536)
                require(bool(chunk), 'worker EOF before ' + kind)
                client.raw.write(chunk)
                client.raw.flush()
                client.buffer += chunk
                require(len(client.buffer) <= 65536, 'worker protocol record too large')
                if b'\n' in client.buffer:
                    line, rest = client.buffer.split(b'\n', 1)
                    require(not rest, 'unsolicited worker output')
                    client.buffer = rest
                    value = record(decode(line), kind, case)
                    received = time.monotonic()
                    result.append(dict(client=client.index, sent_monotonic_s=client.sent,
                                       received_monotonic_s=received, transport_ms=(received-client.sent)*1000,
                                       result=value))
                    selector.unregister(key.fileobj)
    return sorted(result, key=lambda x: x['client'])


def percentile(values, q):
    require(bool(values), 'empty metric population')
    return sorted(values)[max(0, math.ceil(q * len(values)) - 1)]


def summarize(case, runs):
    warm = [x for run in runs for wave in run['waves'] if wave['phase'] == 'measured' for x in wave['responses']]
    duration = sum(w['elapsed_seconds'] for run in runs for w in run['waves'] if w['phase'] == 'measured')
    cancellations = [x['result']['cancel_observation_ms'] for x in warm
                     if x['result']['stop'] == 'cancelled' and x['result']['cancel_observation_ms'] is not None]
    served = sum(x['result']['served'] for x in warm)
    failures = sum(sum(x['result']['errors'].values()) for x in warm)
    cold = [x for run in runs for w in run['waves'] if w['phase'] == 'cold' for x in w['responses']]
    summary = dict(samples=len(warm), cold_samples=len(cold),
                   cold_median_ms=statistics.median(x['transport_ms'] for x in cold),
                   warm_median_ms=statistics.median(x['transport_ms'] for x in warm),
                   warm_p95_ms=percentile([x['transport_ms'] for x in warm], .95),
                   requests_per_second=sum(x['result']['stop'] == 'complete' for x in warm)/duration,
                   responses_per_second=len(warm)/duration,
                   max_process_rss_bytes=max(c['peak_rss_bytes'] for run in runs for c in run['children']),
                   served=served, failed=failures,
                   failure_fraction=failures/(served+failures) if served+failures else None,
                   completed_requests=sum(x['result']['stop'] == 'complete' for x in warm),
                   uncommitted_calculations=len(warm)*case['positions']*len(case['days'])*(1 if case['outputs']=='price' else 11)-served-failures,
                   cancelled=sum(x['result']['stop'] == 'cancelled' for x in warm),
                   max_cancel_observation_ms=max(cancellations) if cancellations else None)
    metrics = {'min_requests_per_second': 'requests_per_second', 'max_failure_fraction': 'failure_fraction'}
    summary['criteria'] = {}
    for key, target in case['requirements'].items():
        actual = summary[metrics.get(key, key)]
        status = 'pending' if target is None or actual is None else (
            'pass' if (actual >= target if key.startswith('min_') else actual <= target) else 'fail')
        summary['criteria'][key] = dict(target=target, observed=actual, status=status)
    return summary


def run_case(binary, case, config, directory):
    directory.mkdir()
    clients = []
    run = dict(complete=False, command=argv(binary, case), load_before=os.getloadavg(), waves=[], checks=[], children=[])
    failed = True
    try:
        for i in range(case['concurrency']):
            clients.append(Client(argv(binary, case), directory, i))
        run['ready'] = receive(clients, 'ready', case, config['timeout_seconds'])
        phases = ['cold'] + ['warmup'] * config['warmups'] + ['measured'] * config['requests']
        for index, phase in enumerate(phases):
            started = time.monotonic()
            command = 'run' if case['cancel_after_ms'] is None else f"cancel {case['cancel_after_ms']}"
            for client in clients:
                client.send(command)
            responses = receive(clients, 'request', case, config['timeout_seconds'])
            run['waves'].append(dict(index=index, phase=phase, responses=responses,
                                     elapsed_seconds=time.monotonic()-started))
        # Pricing replay happens after timing, so it cannot warm the cold request.
        for client in clients:
            client.send('check')
        run['checks'] = receive(clients, 'check', case, config['timeout_seconds'])
        digests = {x['result']['digest'] for x in run['checks']}
        require(len(digests) == 1, 'concurrent client replay differs')
        expected = next(iter(digests))
        for wave in run['waves']:
            for response in wave['responses']:
                value = response['result']
                if case['sink'] == 'digest' and value['stop'] == 'complete':
                    require(value['digest'] == expected, 'request/check replay differs')
        for client in clients:
            client.send('quit')
        failed = False
    except BaseException as error:
        run['error'] = str(error)
        raise
    finally:
        for client in clients:
            run['children'].append(client.close(config['timeout_seconds'], force=failed))
        run['complete'] = not failed and all(c['returncode'] == 0 for c in run['children'])
        run['load_after'] = os.getloadavg()
        (directory / 'run.json').write_text(json.dumps(run, indent=2) + '\n')
    require(all(child['returncode'] == 0 for child in run['children']), 'worker exit failure')
    return run


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def capture(args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def collect(config_path, binary, output):
    raw = config_path.read_bytes()
    config = validate(decode(raw))
    require(platform.system() in ('Linux', 'Darwin'), 'per-child RSS units require Linux or macOS')
    # Creating a new directory claims this destination; partial artifacts remain
    # after any failure. The final report replaces only this run's own temp file.
    output.mkdir(parents=True, exist_ok=False)
    (output / 'config.json').write_bytes(raw)
    report = dict(schema=SCHEMA, complete=False, deployment_accepted=False,
                  scope=config['scope'], config_sha256=hashlib.sha256(raw).hexdigest(),
                  binary_sha256=sha(binary), source_commit=capture(['git', 'rev-parse', 'HEAD']),
                  library_tree=capture(['git', 'rev-parse', 'HEAD:lib']),
                  library_diff=capture(['git', 'diff', 'HEAD', '--', 'lib']),
                  platform=platform.platform(), logical_cpus=os.cpu_count(),
                  hardware=capture(['sysctl', '-n', 'machdep.cpu.brand_string']) if platform.system() == 'Darwin' else platform.machine(),
                  compiler_config=capture(['opam', 'exec', '--switch=morphiq-risk-ml', '--', 'ocamlopt', '-config']),
                  source_hashes={}, cases={}, started_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
    for name in ('bench/planner_load.ml', 'bench/assurance_clock.c', 'scripts/operational_campaign.py'):
        report['source_hashes'][name] = sha(ROOT/name)
    try:
        require(not report['library_diff'], 'library differs from recorded source commit')
        for case in config['cases']:
            runs = []
            for repetition in range(config['repetitions']):
                report['active_run'] = f'{case["name"]}-{repetition}'
                runs.append(run_case(binary, case, config, output/report['active_run']))
            digests = {x['result']['digest'] for run in runs for x in run['checks']}
            require(len(digests) == 1, 'cross-process repetition replay differs')
            report['cases'][case['name']] = dict(summary=summarize(case, runs), replay_digest=next(iter(digests)), runs=runs)
        require(sha(binary) == report['binary_sha256'], 'binary changed during measurement')
        require(sha(config_path) == report['config_sha256'], 'configuration changed during measurement')
        require(all(sha(ROOT/name) == digest for name,digest in report['source_hashes'].items()),
                'measurement source changed during collection')
        require(not capture(['git', 'diff', 'HEAD', '--', 'lib']), 'library changed during measurement')
        report.pop('active_run', None)
        report['complete'] = True
    except BaseException as error:
        report['error'] = str(error)
        raise
    finally:
        report['finished_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        temporary = output/'report.tmp'
        temporary.write_text(json.dumps(report, indent=2) + '\n')
        temporary.replace(output/'report.json')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version=SCHEMA)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        report = collect(args.config.resolve(), args.binary.resolve(), args.output.resolve())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(2, f'campaign failed; retain partial output: {error}\n')
    failed = any(x['status'] == 'fail' for case in report['cases'].values() for x in case['summary']['criteria'].values())
    print(json.dumps({name: case['summary'] for name, case in report['cases'].items()}, indent=2))
    raise SystemExit(1 if failed else 0)


if __name__ == '__main__':
    main()
