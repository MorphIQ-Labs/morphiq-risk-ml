#!/usr/bin/env python3
"""Build/install/smoke-test a pinned source artifact; never tag or release it.

Requires Python >=3.12 and the existing OCaml project opam switch. Output lives
outside the repository. Source archives are deterministic; compiled artifacts
are verified on this host, not claimed bit-identical across builds/platforms.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tarfile


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def run(args,**kwargs):
    try: return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT,**kwargs).strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"command failed ({e.returncode}): {args}\n{e.output}") from e


def verify_origin(found,prefix):
    if Path(found).resolve()!=prefix.resolve()/'lib/morphiq_risk_ml':
        raise RuntimeError('smoke used an unintended package')


def verify_notices(source,prefix):
    paths=['LICENSE','NOTICE','THIRD_PARTY_NOTICES.md','SECURITY.md']
    paths += [str(p.relative_to(source)) for p in sorted((source/'LICENSES').glob('*')) if p.is_file()]
    results={}
    for name in paths:
        original=source/name
        installed=prefix/'doc/morphiq_risk_ml'/name
        if not installed.is_file() or installed.read_bytes()!=original.read_bytes():
            raise RuntimeError('missing or changed installed notice: '+name)
        results[name]=sha(installed)
    return results


EXCHANGE_FIELDS = ('s1','s2','q1','q2','sigma1','sigma2','rho','time','limit')


def exchange_input(rows,expected):
    """Freeze membership/order before executing either installed consumer."""
    lines=[];ids=[]
    for row in rows:
        name=row['id'];inputs=row['inputs']
        if not isinstance(name,str) or not re.fullmatch(r'\S+',name):
            raise RuntimeError('invalid exchange case ID')
        if set(inputs)!=set(EXCHANGE_FIELDS) or any(
                not isinstance(inputs[k],str) or not re.fullmatch('[0-9a-f]{16}',inputs[k])
                for k in EXCHANGE_FIELDS):
            raise RuntimeError('invalid exchange original words')
        ids.append(name);lines.append(' '.join([name,*[inputs[k] for k in EXCHANGE_FIELDS]]))
    reference=[line.split() for line in expected.splitlines()]
    if not ids or len(ids)!=len(set(ids)) or [r[0] if r else None for r in reference]!=ids:
        raise RuntimeError('exchange case membership/order mismatch')
    statuses={'served':4,'numerical_failure':2,'accuracy_exceeded':2,
              'invalid_input':2,'invalid_accuracy':2}
    if any(len(r)<2 or len(r)!=statuses.get(r[1]) for r in reference):
        raise RuntimeError('invalid exchange reference outcome')
    return '\n'.join(lines)+'\n'


def verify_exchange_replay(expected,observed):
    if observed.splitlines()!=expected.splitlines():
        raise RuntimeError('installed exchange replay differs from qualified outcomes')
    return dict(Counter(line.split()[1] for line in expected.splitlines()))


def exchange_replay(source,consumer,consumer_opam,env):
    cases=source/'docs/evidence/exchange-qualification/cases-v1.json'
    reference=source/'docs/evidence/exchange-qualification/runtime-v1.txt'
    corpus=json.loads(cases.read_text())
    if corpus['schema']!=1 or len(corpus['rows'])!=649:
        raise RuntimeError('expected frozen 649-row exchange corpus')
    expected=reference.read_text();wire=exchange_input(corpus['rows'],expected)
    program=consumer/'exchange.ml'
    program.write_bytes((source/'bench/exchange_campaign.ml').read_bytes())
    reports={}
    for compiler,mode in [('ocamlopt','native'),('ocamlc','bytecode')]:
        exe=consumer/('exchange-'+mode)
        run(consumer_opam+['ocamlfind',compiler,'-package','morphiq_risk_ml','-linkpkg',
                          '-o',str(exe),str(program)],cwd=consumer,env=env)
        observed=run([str(exe)],cwd=consumer,env=env,input=wire,timeout=900)
        counts=verify_exchange_replay(expected,observed)
        output=consumer/('exchange-'+mode+'.txt');output.write_text(observed+'\n')
        reports[mode]=dict(rows=649,counts=counts,output_sha256=sha(output),
                           matches_qualified=True)
    return dict(cases_sha256=sha(cases),reference_sha256=sha(reference),
                consumer_sha256=sha(program),modes=reports,
                scope='Installed public API replay of qualified values, radii and failures; '
                      'references are reused, not independently regenerated here.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='candidate artifact schema 1')
    parser.add_argument('--commit',required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--switch',default='morphiq-risk-ml')
    args=parser.parse_args()
    if not re.fullmatch('[0-9a-f]{40}',args.commit): parser.error('commit must be a full immutable SHA')
    if args.output.exists(): parser.error('output directory already exists; use a fresh destination')
    commit=run(['git','rev-parse',args.commit+'^{commit}'])
    args.output.mkdir(parents=True)
    destination=args.output.resolve()
    archive=destination/'source.tar.gz'
    tar=subprocess.check_output(['git','archive','--format=tar','--prefix=source/',commit])
    with archive.open('wb') as raw:
        with gzip.GzipFile(fileobj=raw,filename='',mtime=0,mode='wb') as compressed: compressed.write(tar)
    # A second independent git archive invocation detects source/export drift.
    second=subprocess.check_output(['git','archive','--format=tar','--prefix=source/',commit])
    if second!=tar: raise RuntimeError('source archive not reproducible')
    with tarfile.open(archive) as stream: stream.extractall(destination,filter='data')
    source=destination/'source';prefix=destination/'install'
    if sha(__file__)!=sha(source/'scripts/candidate_artifact.py'):
        raise RuntimeError('artifact tool differs from candidate source')
    opam=['opam','exec','--switch='+args.switch,'--']
    ocaml=run(opam+['ocamlopt','-version'])
    flambda=run(opam+['ocamlopt','-config-var','flambda'])
    if ocaml!='5.3.0' or flambda!='true': raise RuntimeError('candidate requires OCaml 5.3.0 Flambda')
    declared=re.search(r'\(version ([0-9]+\.[0-9]+\.[0-9]+)\)',(source/'dune-project').read_text())
    if not declared: raise RuntimeError('missing candidate package version')
    declared=declared.group(1)
    for metadata in ['morphiq_risk_ml.opam','morphiq_risk_ml.opam.locked']:
        if not re.search(r'^version: "'+re.escape(declared)+r'"$',(source/metadata).read_text(),re.M):
            raise RuntimeError('inconsistent package version: '+metadata)
    logs=[]
    for cmd in [['dune','build','@install','-j','2'],['dune','install','--prefix',str(prefix)]]:
        logs.append(run(opam+cmd,cwd=source))
    # This separate consumer cannot see the source/build library through Dune.
    consumer=destination/'consumer';consumer.mkdir()
    smoke=consumer/'smoke.ml'
    smoke.write_bytes((source/'test/installed_consumer.ml').read_bytes())
    env=dict(os.environ,OCAMLPATH=str(prefix/'lib'),CAML_LD_LIBRARY_PATH=str(prefix/'lib/stublibs'))
    consumer_opam=opam+['env','OCAMLPATH='+env['OCAMLPATH'],'CAML_LD_LIBRARY_PATH='+env['CAML_LD_LIBRARY_PATH']]
    found=run(consumer_opam+['ocamlfind','query','morphiq_risk_ml'],cwd=consumer,env=env)
    verify_origin(found,prefix)
    notice_hashes=verify_notices(source,prefix)
    versions={}
    for compiler,name in [('ocamlopt','native'),('ocamlc','bytecode')]:
        exe=consumer/name
        logs.append(run(consumer_opam+['ocamlfind',compiler,'-package','morphiq_risk_ml','-linkpkg','-o',str(exe),str(smoke)],cwd=consumer,env=env))
        versions[name]=run([str(exe)],cwd=consumer,env=env)
    if versions['native']!=versions['bytecode']: raise RuntimeError('installed versions differ')
    if versions['native']!=declared: raise RuntimeError('installed version differs from source declaration')
    exchange=exchange_replay(source,consumer,consumer_opam,env)
    files={str(p.relative_to(destination)):sha(p) for p in sorted(prefix.rglob('*')) if p.is_file()}
    (destination/'build.log').write_text('\n'.join(logs)+'\n')
    report=dict(commit=commit,tree=run(['git','rev-parse',commit+'^{tree}']),package_version=versions['native'],
                source_archive_sha256=sha(archive),source_tar_sha256=hashlib.sha256(tar).hexdigest(),
                archive_bytes=archive.stat().st_size,source_tar_reproduced=True,
                installed_files_sha256=files,installed_notices_sha256=notice_hashes,consumer_sha256=sha(smoke),consumer_contract='Exchange price, exact expiry and accuracy rejection; four-model compiled Fast batch price and certified Batch price/Delta/IV; Scenario paired/cartesian; certified and fast Planner limits, expiry, partial totals, cancellation, sink failure, worker replay',smoke_native=True,smoke_bytecode=True,package_path=str(found),
                platform=platform.platform(),machine=platform.machine(),ocaml=ocaml,flambda=flambda,
                ocaml_config=run(opam+['ocamlopt','-config']),
                installed_packages=run(['opam','list','--switch='+args.switch,'--installed','--columns=name,version','--short']),
                lock_sha256=sha(source/'morphiq_risk_ml.opam.locked'),tool_sha256=sha(__file__),
                exchange_replay=exchange,
                scope='Candidate artifact validation from pinned source; no release/tag, human acceptance, or cross-platform binary reproducibility claim.')
    (destination/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(commit=commit,archive=str(archive),report=str(destination/'report.json'),version=versions['native'])))


if __name__=='__main__': main()
