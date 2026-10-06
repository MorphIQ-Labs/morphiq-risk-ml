#!/usr/bin/env python3
"""Offline reference integrity and exact feasibility witnesses for #116."""
import argparse
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'docs/evidence/american-certification/reference-v2'

def require(condition,message):
    if not condition: raise ValueError(message)

def validate(cases,lines,manifest):
    rows=cases['rows']
    require(len(rows)==manifest['rows']==354,'incomplete reference corpus')
    require(len({r['id'] for r in rows})==len(rows),'duplicate case ID')
    require(len(lines)==len(rows),'incomplete reference rows')
    for row,line in zip(rows,lines):
        cells=line.split()
        require(len(cells)==14,'malformed reference row')
        require(cells[:12]==[row['id'],row['kind'],row['side'],*row['words'],row['expected']],'reference identity mismatch')
        lo,hi=cells[12:]
        if row['expected']=='ok':require(F(lo)<=F(hi),'reversed reference interval')
        else:require(lo==hi=='-','unsupported row misclassified as reference')
    return rows

def load():
    m=json.loads((EVIDENCE/'manifest.json').read_text())
    for name,digest in m['sources'].items():
        require(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'reference generator drift')
    for name,digest in m['files'].items():
        require(hashlib.sha256((EVIDENCE/name).read_bytes()).hexdigest()==digest,'reference payload drift')
    c=json.loads((EVIDENCE/'cases.json').read_text());lines=(EVIDENCE/'references.tsv').read_text().splitlines()
    return c,lines,m,validate(c,lines,m)

def feasibility():
    _,lines,_,rows=load()
    chosen=[(r,line) for r,line in zip(rows,lines) if r['kind']=='american' and r['side']=='call'
        and list(map(float.fromhex,r['words'][:7]))==[100.,100.,0.,0.,.8,1.,0.]]
    require(len(chosen)==1,'missing independent continuum witness')
    row,line=chosen[0];lo,hi=map(F,line.split()[-2:]);variance=F(.8)**2
    diagonal=1+variance;rhs=50*variance;discrete=rhs/diagonal
    residual=diagonal*discrete-rhs
    require(residual==0 and discrete>0,'exact discrete LCP witness')
    require(lo>discrete,'discrete residual promoted to continuum bound')
    # w(s)=(s-K)+ is linear/zero on its two smooth patches when r=q=0.
    # It dominates payoff/terminal data but has a convex derivative jump of 1.
    patch_defect=F(0);join_jump=F(1);at_strike=F(0)
    require(lo>at_strike and patch_defect==0 and join_jump>0,'unverified supersolution join')
    radius=F(50);refinement_target=F(100,65536);request=F(100)*F(2)**-36
    require(radius>refinement_target and radius>request,'coarse cap mistaken for useful accuracy')
    return dict(sources={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ['scripts/check_american_certification.py','docs/evidence/american-certification/reference-v2/manifest.json']},
        scope='Original mathematical experiments, not a runtime price failure or impossibility proof.',
        continuum_reference=dict(case=row['id'],lower=str(lo),upper=str(hi)),
        discrete=dict(nodes=[0,100,200],time_step='1',upper_boundary='100',diagonal=str(diagonal),rhs=str(rhs),value=str(discrete),residual=str(residual),continuum_gap_lower=str(lo-discrete),note='Exact one-step discrete LCP; boundary, space and time errors deliberately remain unqualified.'),
        supersolution=dict(candidate='positive_part(s-100)',off_kink_pde_defect=str(patch_defect),derivative_jump=str(join_jump),candidate_at_strike=str(at_strike),contradicted_by_positive_continuum_lower_bound=True),
        coarse_bound=dict(lower='0',upper='100',midpoint_radius=str(radius),engineering_refinement_target=str(refinement_target),explicit_test_error_limit=str(request)),
        disposition='Exact reductions may use the existing original-input enclosure; general stopping remains estimated-only.')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--version',action='version',version='american-certification-check 1');p.parse_args()
    print(json.dumps(feasibility(),indent=2))
if __name__=='__main__':main()
