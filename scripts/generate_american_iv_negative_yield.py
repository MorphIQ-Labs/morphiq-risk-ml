#!/usr/bin/env python3
"""Supplement the frozen primary inverse corpus with negative-yield witnesses."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
from fractions import Fraction as F
from generate_american_iv import value, inverse, ctx, __version__, __FLINT_VERSION__
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--version',action='version',version='negative-yield-inverse 1')
    args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    rows=[];lines=[]
    for side,r in [('call',-.05),('put',.05)]:
        p=dict(side=side,s=100.,k=100.,r=r,q=-.02,t=1.,opens=1.,cash=0.)
        with ctx.workprec(512):quote=float(value(p,F(.2)))
        ranges=[inverse(p,quote,b) for b in [256,512]]
        assert max(a for a,b in ranges)<=min(b for a,b in ranges)
        lo=min(a for a,b in ranges);hi=max(b for a,b in ranges)
        row=dict(**p,quote=quote.hex(),lower=str(lo),upper=str(hi),attempts=[dict(bits=bits,lower=str(a),upper=str(b)) for bits,(a,b) in zip([256,512],ranges)])
        rows.append(row)
        lines.append(' '.join([side,r.hex(),p['q'].hex(),quote.hex(),str(lo),str(hi)])+'\n')
    (args.output/'references.json').write_text(json.dumps(rows,indent=2)+'\n')
    (args.output/'references.tsv').write_text(''.join(lines))
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    sources=['scripts/generate_american_iv.py','scripts/generate_american_iv_negative_yield.py']
    (args.output/'manifest.json').write_text(json.dumps(dict(python=platform.python_version(),python_flint=__version__,flint=__FLINT_VERSION__,sources={s:sha(ROOT/s) for s in sources},files={s:sha(args.output/s) for s in ['references.json','references.tsv']}),indent=2)+'\n')
if __name__=='__main__':main()
