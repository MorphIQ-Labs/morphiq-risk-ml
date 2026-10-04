#!/usr/bin/env python3
"""Generate/check bounded numerical challenges; see numerical-campaign-protocol.md."""
import argparse
from collections import Counter, defaultdict
from fractions import Fraction as F
import gzip
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import time
from numerical_cases import cases, bits, word, wire, fingerprint, VERSION, SEED, MAX_ROWS

ROOT=Path(__file__).resolve().parents[1]
SOURCE_NAMES=['scripts/numerical_cases.py','scripts/numerical_reference.py',
              'scripts/arb_reference_campaign.py','scripts/arb_greek_audit.py',
              'scripts/arb_iv_audit.py','scripts/fixture_catalog.py',
              'oracle/common.py','oracle/gen_iv.py','oracle/price_rounding.py']
FAILURES={'numerical_failure','non_convergence','accuracy_exceeded'}
STATUSES=FAILURES|{'value','root','certificate','invalid_input','invalid_accuracy','unsupported_expiry','unsupported_zero_variance','payoff_kink','below_intrinsic','above_maximum','below_smallest','expiry'}


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_bytes(path,data):
    path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile('wb',dir=path.parent,delete=False) as stream:
        name=stream.name; stream.write(data)
    try: os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)


def save(path,report): atomic_bytes(path,(json.dumps(report,indent=2,allow_nan=False)+'\n').encode())


def worker(path):
    from numerical_reference import fill_quote, reference
    rows=json.loads(path.read_text())
    for row in rows:
        try:
            fill_quote(row)
            row['reference']=reference(row)
        except ArithmeticError as error:
            if str(error).startswith('reference serialization exponent limit'):
                row['reference']=dict(status='unresolved',reason=str(error))
            else: row['reference']=dict(status='reference_error',reason=str(error))
        except Exception as error:
            row['reference']=dict(status='reference_error',reason=type(error).__name__+': '+str(error))
    print(json.dumps(rows,allow_nan=False))


def generate(lane,output):
    from flint import __FLINT_VERSION__
    rows=cases(lane); completed=[]; started=time.monotonic()
    with tempfile.TemporaryDirectory(prefix='numerical-reference-') as directory:
        path=Path(directory)/'requests.json'
        for start in range(0,len(rows),64):
            group=rows[start:start+64]; path.write_text(json.dumps(group))
            try:
                result=subprocess.run([sys.executable,str(Path(__file__).resolve()),'worker',str(path)],capture_output=True,text=True,timeout=60)
                if result.returncode: raise RuntimeError(result.stderr)
                chunk=json.loads(result.stdout)
                if [r['id'] for r in chunk]!=[r['id'] for r in group]: raise ValueError('reference row identity/count mismatch')
            except (OSError,ValueError,RuntimeError,subprocess.TimeoutExpired) as error:
                chunk=[dict(r,reference=dict(status='reference_error',reason=str(error))) for r in group]
            completed.extend(chunk)
            print(f'references {len(completed)}/{len(rows)}',flush=True)
    report=dict(schema=VERSION,lane=lane,seed=SEED,rows=completed,
                counts=dict(Counter(r['reference']['status'] for r in completed)),
                source_sha256={name:sha(ROOT/name) for name in SOURCE_NAMES},
                tools=dict(python=platform.python_version(),python_flint=importlib.metadata.version('python-flint'),
                           flint=__FLINT_VERSION__,mpmath=importlib.metadata.version('mpmath')),
                limits=dict(rows=MAX_ROWS,reference_batch=64,batch_seconds=60,precisions=[256,512,1024,2048,4096]),
                elapsed_seconds=time.monotonic()-started)
    data=gzip.compress((json.dumps(report,separators=(',',':'),allow_nan=False)+'\n').encode(),mtime=0)
    atomic_bytes(output,data)
    save(Path(str(output)+'.manifest.json'),dict(schema=VERSION,sha256=hashlib.sha256(data).hexdigest(),rows=len(completed)))
    print(json.dumps(report['counts']))
    if report['counts'].get('reference_error',0): raise SystemExit(1)


def load_reference(path):
    manifest=json.loads(Path(str(path)+'.manifest.json').read_text())
    data=path.read_bytes()
    if hashlib.sha256(data).hexdigest()!=manifest['sha256']: raise ValueError('reference artifact fingerprint mismatch')
    report=json.loads(gzip.decompress(data))
    expected=cases(report['lane']); rows=report['rows']
    if report['schema']!=VERSION or report['seed']!=SEED or len(rows)!=len(expected) or len(rows)!=manifest['rows']:
        raise ValueError('reference membership/version mismatch')
    for actual,original in zip(rows,expected):
        # Independent quote construction changes only the designated quote word.
        structural={k:v for k,v in actual.items() if k!='reference'}
        if actual['region'].startswith('iv_cell_'):
            structural=dict(structural,inputs=dict(structural['inputs'],quote=original['inputs']['quote']))
        if structural!=original: raise ValueError('reference original inputs changed: '+original['id'])
    if set(report['source_sha256'])!=set(SOURCE_NAMES): raise ValueError('incomplete reference provenance')
    if dict(Counter(r['reference']['status'] for r in rows))!=report['counts']:
        raise ValueError('inconsistent reference accounting')
    for row in rows:
        ref=row['reference']
        if ref['status'] not in ('interval','root','class','unresolved'): raise ValueError('invalid reference outcome')
        if ref['status']=='interval' and F(ref['lower'])>F(ref['upper']): raise ValueError('inverted reference interval')
    for name,digest in report['source_sha256'].items():
        if sha(ROOT/name)!=digest: raise ValueError('stale reference source: '+name)
    if report['counts'].get('reference_error',0): raise ValueError('reference generation incomplete')
    return report


def parse_results(text,rows):
    results={}; expected={r['id']:r for r in rows}
    for line in text.splitlines():
        fields=line.split()
        if len(fields)!=5: raise ValueError('malformed runtime row')
        ident,digest,status,value,radius=fields
        if ident not in expected or ident in results: raise ValueError('unknown/duplicate runtime row')
        if digest!=fingerprint(expected[ident]) or status not in STATUSES: raise ValueError('mismatched request/status')
        if status in ('value','root','certificate'):
            if len(value)!=16: raise ValueError('malformed value word')
            word(value)
        elif value!='-': raise ValueError('failure has usable payload')
        if status=='certificate':
            if len(radius)!=16: raise ValueError('malformed radius word')
            word(radius)
        elif radius!='-': raise ValueError('unexpected radius')
        results[ident]=dict(status=status,value=value,radius=radius)
    if set(results)!=set(expected): raise ValueError('missing runtime rows')
    return results


def ulps(a,b):
    def rank(x):
        encoded=int(bits(x),16); magnitude=encoded&((1<<63)-1)
        return -magnitude if encoded>>63 else magnitude
    if not math.isfinite(a) or not math.isfinite(b): return None
    return abs(rank(a)-rank(b))


def score(row,result,budgets):
    ref=row['reference']; status=result['status']; mode=row['mode']; quantity=row['quantity']
    if status in FAILURES:
        if row['region']=='greek_zeros': return 'availability_regression',dict(reason='fixed central regression subset requires success')
        if ref['status']=='class' and ref['expected'] in ('invalid_input','invalid_accuracy','unsupported_expiry','unsupported_zero_variance','payoff_kink'):
            return 'wrong_class',dict(expected=ref['expected'])
        return 'availability_failure',{}
    if ref['status']=='class':
        return ('class_checked' if status==ref['expected'] else 'wrong_class'),dict(expected=ref['expected'])
    if status not in ('value','root','certificate'):
        if ref['status']=='unresolved': return 'reference_unresolved',{}
        return 'wrong_class',{}
    expected_success='root' if quantity=='iv' else ('certificate' if mode in ('production','enclosure') else 'value')
    if status!=expected_success: return 'invalid_success',{}
    value=word(result['value'])
    if not math.isfinite(value):
        if mode=='fast' and quantity=='price': return 'nonfinite_fast_price',{}
        return 'invalid_success',{}
    if status=='certificate':
        radius=word(result['radius']); limit=word(row['inputs']['limit'])
        if not math.isfinite(radius) or radius<0 or radius>limit: return 'invalid_success',{}
    if ref['status']=='unresolved': return 'reference_unresolved',{}
    if ref['status']=='root':
        return ('value_checked' if status=='root' and result['value']==ref['word'] else 'wrong_value'),dict(expected=ref['word'])
    if ref['status']!='interval': return 'reference_error',{}
    lo,hi=F(ref['lower']),F(ref['upper']); got=F(value)
    if status=='certificate':
        radius=word(result['radius']); limit=word(row['inputs']['limit'])
        if not math.isfinite(radius) or radius<0 or radius>limit: return 'invalid_success',{}
        lower,upper=got-F(radius),got+F(radius)
        if lower<=lo<=hi<=upper: return 'value_checked',{}
        if upper<lo or lower>hi: return 'wrong_value',dict(reference=ref)
        return 'reference_unresolved',dict(reason='enclosures overlap without proving containment')
    if 'rounded' not in ref:
        if lo==hi:
            try: reference=float(lo)
            except OverflowError: return 'quality_excursion',dict(reason='finite output for unrepresentable real value')
        else: return 'reference_unresolved',{}
    else: reference=word(ref['rounded'])
    distance=ulps(value,reference)
    normal=row['model']=='bachelier'
    budget=budgets[('bachelier' if normal else 'black')+' '+quantity]
    if distance is None or distance>budget or (reference==0. and value!=0.):
        return 'quality_excursion',dict(ulps=distance,budget=budget,expected=bits(reference))
    return 'value_checked',dict(ulps=distance,budget=budget)


def check(path,runner,output,contracts_only=False):
    report=load_reference(path); rows=report['rows']; started=time.monotonic()
    budget_process=subprocess.run([str(runner.resolve()),'--budgets'],check=True,capture_output=True,text=True,timeout=10)
    budgets={}
    for line in budget_process.stdout.splitlines():
        family,quantity,value=line.split(); budgets[family+' '+quantity]=float(value)
    if len(budgets)!=22 or not all(math.isfinite(v) and v>=0 for v in budgets.values()):
        raise ValueError('incomplete/invalid quality budgets')
    with tempfile.TemporaryDirectory(prefix='numerical-runtime-') as directory:
        inputs=Path(directory)/'input.txt';inputs.write_text('\n'.join(map(wire,rows))+'\n')
        try:
            process=subprocess.run([str(runner.resolve()),str(inputs)],capture_output=True,text=True,timeout=180)
            if process.returncode: raise RuntimeError(f'runtime exit {process.returncode}: {process.stderr}')
            results=parse_results(process.stdout,rows)
        except (ValueError,OSError,RuntimeError,subprocess.TimeoutExpired) as error:
            save(output,dict(complete=False,tool_error=str(error)))
            raise SystemExit(2)
    outcomes=[]; regions=defaultdict(Counter); totals=Counter()
    for row in rows:
        outcome,detail=score(row,results[row['id']],budgets);totals[outcome]+=1
        key='/'.join(row[k] for k in ('region','model','mode','quantity'))
        regions[key][outcome]+=1
        outcomes.append(dict(id=row['id'],reference_status=row['reference']['status'],outcome=outcome,result=results[row['id']],detail=detail))
    violations=sum(totals[k] for k in ('wrong_value','wrong_class','invalid_success','reference_error','availability_regression'))
    try: revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    except subprocess.CalledProcessError: revision='unavailable'
    answer=dict(schema=VERSION,complete=True,source_commit=revision,reference_sha256=sha(path),
                runner_sha256=sha(runner),scorer_sha256=sha(Path(__file__)),
                rows=len(rows),totals=dict(totals),regions={k:dict(v) for k,v in sorted(regions.items())},
                outcomes=outcomes,contract_violations=violations,quality_excursions=totals['quality_excursion'],
                contract_gate_passed=violations==0,clean_accuracy_campaign=violations==0 and totals['quality_excursion']==0,
                contracts_only=contracts_only,elapsed_seconds=time.monotonic()-started,
                scope='Failures/uncertainty are availability/reference outcomes, never successful accuracy checks. Fast Greek budgets and family-maximum price diagnostics remain empirical; existing regional/derived price gates remain unchanged.')
    save(output,answer);print(json.dumps(dict(rows=len(rows),totals=totals,contract_violations=violations)))
    if violations or (totals['quality_excursion'] and not contracts_only): raise SystemExit(1)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='numerical-campaign 1')
    sub=parser.add_subparsers(dest='command',required=True)
    p=sub.add_parser('worker');p.add_argument('input',type=Path)
    p=sub.add_parser('generate');p.add_argument('--lane',choices=('smoke','full'),required=True);p.add_argument('--output',type=Path,required=True)
    p=sub.add_parser('check');p.add_argument('--reference',type=Path,required=True);p.add_argument('--runner',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--contracts-only',action='store_true')
    args=parser.parse_args()
    if args.command=='worker': worker(args.input)
    elif args.command=='generate': generate(args.lane,args.output)
    else: check(args.reference,args.runner,args.output,args.contracts_only)


if __name__=='__main__': main()
