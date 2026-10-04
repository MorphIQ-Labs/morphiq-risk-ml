#!/usr/bin/env python3
"""Reconcile downloaded evidence for the fixed #102 candidate; no approval grant.

Run from any checkout containing the candidate Git object. Inputs are original
GitHub downloads and `gh run view --json` metadata retained with this record.
This is a campaign-specific reproduction tool, not a new default CI gate.
"""
import argparse
import copy
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
from collections import Counter

COMMIT = 'f703546ea736d456f64e74be6ef9d2da2c10ef88'
RUN = 37238843530
CI_RUN = 37238293731
PLATFORMS = ('ubuntu-24.04', 'ubuntu-24.04-arm', 'macos-15')
ROOT = Path(__file__).resolve().parents[3]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(ok, message):
    if not ok:
        raise ValueError(message)


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def source(name):
    return git('show', COMMIT+':'+name)


def one(folder, name):
    paths = list(folder.rglob(name))
    require(len(paths) == 1, 'expected exactly one '+name)
    return paths[0]


def workflow(report, run, event, names):
    require(report['databaseId'] == run and report['headSha'] == COMMIT, 'workflow identity')
    require(report['status'] == 'completed' and report['conclusion'] == 'success', 'workflow incomplete')
    require(report['event'] == event, 'workflow event')
    require(len(report['jobs']) == len(names) and {j['name'] for j in report['jobs']} == names, 'job coverage')
    require(all(j['status'] == 'completed' and j['conclusion'] == 'success' for j in report['jobs']), 'failed job')


def artifact(report, outputs):
    require(report['commit'] == COMMIT and report['package_version'] == '0.3.0', 'artifact identity')
    require(report['tree'] == git('rev-parse', COMMIT+'^{tree}').decode().strip(), 'source tree')
    require(report['source_tar_reproduced'] is True and report['smoke_native'] is True
            and report['smoke_bytecode'] is True, 'missing installed mode')
    require(report['ocaml'] == '5.3.0' and report['flambda'] == 'true', 'toolchain')
    for key, name in [('tool_sha256','scripts/candidate_artifact.py'),
                      ('consumer_sha256','test/installed_consumer.ml'),
                      ('lock_sha256','morphiq_risk_ml.opam.locked')]:
        require(report[key] == sha(source(name)), 'changed '+name)
    names = ['LICENSE', 'NOTICE', 'THIRD_PARTY_NOTICES.md', 'SECURITY.md']
    names += git('ls-tree','-r','--name-only',COMMIT,'LICENSES').decode().splitlines()
    expected_notices = {n:sha(source(n)) for n in names}
    require(len(names) == 10 and report['installed_notices_sha256'] == expected_notices, 'notice inventory')
    for name, digest in expected_notices.items():
        require(report['installed_files_sha256']['install/doc/morphiq_risk_ml/'+name] == digest, 'installed notice hash')
    replay = report['exchange_replay']
    expected = source('docs/evidence/exchange-qualification/runtime-v1.txt')
    counts = dict(Counter(line.split()[1] for line in expected.decode().splitlines()))
    require(replay['reference_sha256'] == sha(expected), 'exchange reference')
    require(replay['cases_sha256'] == sha(source('docs/evidence/exchange-qualification/cases-v1.json')), 'exchange membership')
    require(replay['consumer_sha256'] == sha(source('bench/exchange_campaign.ml')), 'exchange consumer')
    require(set(replay['modes']) == {'native','bytecode'} and set(outputs) == {'native','bytecode'}, 'missing exchange mode')
    for mode, data in outputs.items():
        r = replay['modes'][mode]
        require(data == expected and r['output_sha256'] == sha(data), 'changed exchange output')
        require(r['rows'] == 649 and r['counts'] == counts and r['matches_qualified'] is True, 'exchange accounting')


def platform_identity(report, platform):
    machines = {'ubuntu-24.04':'x86_64', 'ubuntu-24.04-arm':'aarch64', 'macos-15':'arm64'}
    prefix = 'macOS-15.' if platform == 'macos-15' else 'Linux-'
    require(report['machine'] == machines[platform] and report['platform'].startswith(prefix), 'artifact platform mismatch')


def canonical(report):
    require(report['candidate_commit'] == COMMIT and report['rows'] == 720
            and report['matched_price_greek_iv_outcomes'] == 8640, 'canonical membership')
    require(report['campaign_sha256'] == sha(source('docs/evidence/canonical-shadow.json.gz')), 'canonical reference')
    require(report['replay_tool_sha256'] == sha(source('scripts/replay_canonical.py')), 'canonical tool')


def mutations(raw):
    catalog_source = source('scripts/mutation/mutation.ml').decode().split('let core_ids =')[0]
    catalog = dict(re.findall(r'id = "([^"]+)";.*?killer = "([^"]+)";',catalog_source,re.S))
    kills = re.findall(r'^killed\s+(\S+) by (\S+)\s*$',raw,re.M)
    require(len(catalog) == len(kills) == 96 and dict(kills) == catalog, 'mutation membership/guards')
    require(re.search(r'^baseline passes \(\d+ s\)$',raw,re.M) is not None, 'mutation baseline')
    require(raw.rstrip().endswith('96 of 96 mutants killed as catalogued'), 'mutation completion')
    require(not re.search(r'^(INVALID|STALE|SURVIVED)\s',raw,re.M), 'mutation failure')
    return sorted(catalog)


def reject(name, fn, controls):
    try:
        fn()
    except (ValueError, KeyError):
        controls.append(name)
        return
    raise ValueError('failure control survived: '+name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='fast-candidate-collector-v1')
    parser.add_argument('--artifacts',type=Path,required=True)
    parser.add_argument('--workflow',type=Path,required=True)
    parser.add_argument('--ci-workflow',type=Path,required=True)
    parser.add_argument('--ci-log',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    run = json.loads(args.workflow.read_text()); ci = json.loads(args.ci_workflow.read_text())
    names = {'identity','candidate full mutation catalog',*[f'candidate artifact ({p})' for p in PLATFORMS]}
    workflow(run,RUN,'workflow_dispatch',names)
    workflow(ci,CI_RUN,'push',{'format','mutation',*[f'test ({p})' for p in PLATFORMS]})
    for job in ci['jobs']:
        if job['name'].startswith('test ('):
            steps = [s for s in job['steps'] if s['name'] == 'Release build and tests']
            require(len(steps) == 1 and steps[0]['conclusion'] == 'success', 'release checks absent')
    retained = {'workflow.json':args.workflow.read_bytes(), 'ci-workflow.json':args.ci_workflow.read_bytes(),
                'ci.log.gz':gzip.compress(args.ci_log.read_bytes(),mtime=0)}
    controls = []
    bad = copy.deepcopy(run); bad['headSha'] = '0'*40
    reject('wrong workflow commit',lambda:workflow(bad,RUN,'workflow_dispatch',names),controls)
    bad = copy.deepcopy(run); bad['jobs'].pop()
    reject('missing platform job',lambda:workflow(bad,RUN,'workflow_dispatch',names),controls)
    tar = git('archive','--format=tar','--prefix=source/',COMMIT)
    archive_hashes = set(); platforms = {}
    for platform in PLATFORMS:
        folder = args.artifacts/f'candidate-{COMMIT}-{platform}'
        report_path = one(folder,'report.json'); report = json.loads(report_path.read_text())
        outputs = {m:one(folder,'exchange-'+m+'.txt').read_bytes() for m in ('native','bytecode')}
        artifact(report,outputs)
        platform_identity(report,platform)
        archive = one(folder,'source.tar.gz').read_bytes()
        require(sha(archive) == report['source_archive_sha256'] and len(archive) == report['archive_bytes'], 'archive hash/size')
        require(gzip.decompress(archive) == tar and sha(tar) == report['source_tar_sha256'], 'archive source mismatch')
        archive_hashes.add(sha(archive))
        replay_path = one(folder,'candidate-replay.json'); replay = json.loads(replay_path.read_text()); canonical(replay)
        retained[platform+'-artifact.json'] = report_path.read_bytes()
        retained[platform+'-canonical.json'] = replay_path.read_bytes()
        for mode, data in outputs.items():
            retained[platform+'-exchange-'+mode+'.txt.gz'] = gzip.compress(data,mtime=0)
        for name in ('candidate-build.log','candidate-tests.log','candidate-artifact.log','candidate-replay.log','build.log'):
            retained[platform+'-'+name+'.gz'] = gzip.compress(one(folder,name).read_bytes(),mtime=0)
        platforms[platform] = dict(exchange_rows_per_mode=649,canonical_rows=720,canonical_outcomes=8640,
                                   installed_native=True,installed_bytecode=True,source_archive_sha256=sha(archive))
        if platform == PLATFORMS[0]:
            bad = copy.deepcopy(report); bad['machine'] = 'wrong-machine'
            reject('swapped platform report',lambda:platform_identity(bad,platform),controls)
            bad = copy.deepcopy(report); bad['smoke_bytecode'] = False
            reject('missing installed bytecode',lambda:artifact(bad,outputs),controls)
            bad = copy.deepcopy(report); bad['exchange_replay']['modes'].pop('bytecode')
            reject('missing Exchange bytecode',lambda:artifact(bad,outputs),controls)
            bad = copy.deepcopy(report); bad['exchange_replay']['modes']['native']['rows'] = 648
            reject('wrong Exchange count',lambda:artifact(bad,outputs),controls)
            bad = copy.deepcopy(report); bad['installed_notices_sha256'].pop('NOTICE')
            reject('missing notice',lambda:artifact(bad,outputs),controls)
            altered = dict(outputs,native=outputs['native']+outputs['native'])
            reject('duplicated Exchange outputs',lambda:artifact(report,altered),controls)
            bad = copy.deepcopy(replay); bad['matched_price_greek_iv_outcomes'] = 8639
            reject('truncated canonical replay',lambda:canonical(bad),controls)
    require(len(archive_hashes) == 1, 'platform archives differ')
    raw = one(args.artifacts/f'candidate-mutations-{COMMIT}','candidate-mutations.log').read_bytes()
    ids = mutations(raw.decode()); retained['full-mutations.log.gz'] = gzip.compress(raw,mtime=0)
    lines = raw.decode().splitlines()
    first = next(line for line in lines if line.startswith('killed'))
    reject('missing mutant',lambda:mutations(raw.decode().replace(first+'\n','',1)),controls)
    reject('duplicate mutant',lambda:mutations(raw.decode()+'\n'+first),controls)
    reject('wrong designated guard',lambda:mutations(raw.decode().replace(first,first.rsplit(' ',1)[0]+' wrong_guard',1)),controls)
    receipt = dict(schema=1,candidate_commit=COMMIT,package_version='0.3.0',workflow_run=RUN,workflow_url=run['url'],
                   ci_run=CI_RUN,ci_url=ci['url'],runtime_tree=git('rev-parse',COMMIT+':lib').decode().strip(),
                   source_archive_sha256=next(iter(archive_hashes)),platforms=platforms,
                   mutant_ids=ids,mutants_killed=len(ids),collector_sha256=sha(Path(__file__).read_bytes()),
                   rejected_failure_controls=controls,
                   scope='Exact-source experimental qualification; no reference regeneration, human review or release/deployment approval.')
    retained['receipt.json'] = (json.dumps(receipt,indent=2)+'\n').encode()
    # Validate every input before publishing; unique campaign output is required.
    args.output.mkdir(parents=True,exist_ok=False)
    for name, data in retained.items():
        (args.output/name).write_bytes(data)
    print(json.dumps(receipt,indent=2))


if __name__ == '__main__':
    main()
