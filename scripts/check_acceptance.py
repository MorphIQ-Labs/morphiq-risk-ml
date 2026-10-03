#!/usr/bin/env python3
"""Read-only acceptance dossier integrity gate; does not authenticate approvers or release artifacts."""
import argparse
from datetime import date
import hashlib
import json
from pathlib import Path
import re

EVIDENCE = {'domain','model_contract','reference_provenance','independent_review','shadow','performance','installation','platform_ci','full_mutations','rollback'}
ROLES = {'model_validation','engineering_release'}


def check(record,root,artifact_root):
    errors=[]
    commit=record.get('candidate_commit')
    if not isinstance(commit,str) or not re.fullmatch('[0-9a-f]{40}',commit): errors.append('exact candidate SHA missing')
    if record.get('status')!='accepted': errors.append('acceptance decision is pending')
    if not record.get('intended_use'): errors.append('approved intended use missing')
    if not re.fullmatch(r'\d+\.\d+\.\d+',record.get('package_version','')): errors.append('package version missing')
    if record.get('blockers')!=[]: errors.append('unresolved blockers remain')
    def evidence_file(item,base):
        path=item.get('path','');digest=item.get('sha256','')
        resolved=(base/path).resolve()
        if not path or not resolved.is_relative_to(base.resolve()) or not resolved.is_file():
            errors.append('missing/outside evidence file: '+path);return
        if hashlib.sha256(resolved.read_bytes()).hexdigest()!=digest: errors.append('evidence hash mismatch: '+path)
        if item.get('candidate_commit')!=commit: errors.append('evidence candidate mismatch: '+path)
    evidence=record.get('evidence',{})
    if set(evidence)!=EVIDENCE: errors.append('incomplete or unknown evidence categories')
    for item in evidence.values(): evidence_file(item,root)
    decisions=record.get('decisions',{})
    if set(decisions)!=ROLES: errors.append('designated owner decisions missing')
    for role,item in decisions.items():
        if item.get('decision')!='accept' or not item.get('name','').strip(): errors.append('unsigned owner decision: '+role)
        if item.get('candidate_commit')!=commit: errors.append('owner decision candidate mismatch: '+role)
        try:
            approved=date.fromisoformat(item['date'])
            if approved>date.today(): errors.append('future owner decision: '+role)
        except (KeyError,ValueError,TypeError): errors.append('invalid owner decision date: '+role)
        evidence_file(item,root)
    artifacts=record.get('artifacts',[])
    if not artifacts: errors.append('release artifact checksums missing')
    for item in artifacts: evidence_file(item,artifact_root)
    return errors


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('record',type=Path)
    parser.add_argument('--root',type=Path,default=Path('.'))
    parser.add_argument('--artifact-root',type=Path,required=True)
    args=parser.parse_args()
    try: errors=check(json.loads(args.record.read_text()),args.root,args.artifact_root)
    except (OSError,ValueError,TypeError,AttributeError) as e: errors=['invalid dossier: '+str(e)]
    print(json.dumps(dict(accepted=not errors,errors=errors),indent=2))
    raise SystemExit(1 if errors else 0)


if __name__=='__main__': main()
