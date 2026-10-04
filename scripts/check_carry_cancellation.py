#!/usr/bin/env python3
"""Check #76 values against independent rounding cells; retain all refusals."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
import math
from pathlib import Path
import subprocess
from numerical_cases import wire,word
from numerical_campaign import parse_results,ulps,SOURCE_NAMES
from carry_cancellation_reference import cases

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='carry-cancellation-check 1')
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--runner',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--record-only',action='store_true')
    p.add_argument('--runner-source',help='Known source commit of a separately built runner')
    args=p.parse_args()
    data=args.reference.read_bytes()
    manifest=json.loads(Path(str(args.reference)+'.manifest.json').read_text())
    if hashlib.sha256(data).hexdigest()!=manifest['sha256']: raise ValueError('fixture hash')
    ref=json.loads(gzip.decompress(data));rows=ref['rows']
    if len(rows)!=manifest['rows'] or [{k:v for k,v in r.items() if k!='reference'} for r in rows]!=cases():
        raise ValueError('fixture membership')
    if set(ref['source_sha256']) != set(SOURCE_NAMES+['scripts/carry_cancellation_reference.py']): raise ValueError('incomplete reference provenance')
    for name,digest in ref['source_sha256'].items():
        if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest: raise ValueError('stale reference: '+name)
    import tempfile
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory)/'rows.txt';path.write_text('\n'.join(map(wire,rows))+'\n')
        process=subprocess.run([str(args.runner.resolve()),str(path)],capture_output=True,text=True,timeout=120,check=True)
    results=parse_results(process.stdout,rows);counts=Counter();outcomes=[];failures=0
    for row in rows:
        actual=results[row['id']];expected=row['reference']
        if actual['status']!='value':
            outcome='wrong_status';failures+=1;distance=None
        elif not math.isfinite(word(actual['value'])):
            outcome='unavailable';distance=None
        elif expected['status']!='interval' or 'rounded' not in expected:
            outcome='reference_unresolved';distance=None
        else:
            distance=ulps(word(actual['value']),word(expected['rounded']))
            # Existing maximum price diagnostics: no tolerance fitting to this corpus.
            outcome='value_checked' if distance <= 32 else 'quality_excursion'
            if outcome=='quality_excursion': failures+=1
        # The exact discovered case is a mandatory availability and correct-rounding regression.
        inp=row['inputs']
        required=(row['model']=='bsm' and row['side']=='call'
                  and inp['s']=='3ff0000000000001' and inp['k']=='3ff0000000000000'
                  and inp['t']=='3ff0000000000000' and inp['r']=='bcafffffffffffff'
                  and inp['sigma']=='0000000000000000' and inp['q']=='0000000000000000')
        if required and (outcome!='value_checked' or distance!=0): failures+=1
        if row['inputs']['sigma']=='0000000000000000' and outcome!='value_checked': failures+=1
        counts[outcome]+=1
        outcomes.append(dict(id=row['id'],outcome=outcome,result=actual,ulps=distance,required=required))
    if sum(r['required'] for r in outcomes)!=1: raise ValueError('missing required case')
    try: revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True,stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError: revision='unavailable'
    report=dict(scorer_source_commit=revision,runner_source_commit=args.runner_source or revision,reference_sha256=manifest['sha256'],
                runner_sha256=hashlib.sha256(args.runner.read_bytes()).hexdigest(),
                counts=dict(counts),failures=failures,outcomes=outcomes)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(counts=dict(counts),failures=failures)))
    if failures and not args.record_only: raise SystemExit(1)

if __name__=='__main__': main()
