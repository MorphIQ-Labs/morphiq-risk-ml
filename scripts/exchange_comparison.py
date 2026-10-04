#!/usr/bin/env python3
"""Retain per-case QuantLib errors against independent closed-form intervals."""
import argparse
import json
from pathlib import Path
from flint import arb, ctx
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'docs/evidence/exchange-implementation'
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='exchange-comparison 1')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    ctx.prec=4096
    refs={r['id']:r for r in json.loads((BASE/'references-v2.json').read_text())['rows']}
    rows=[]
    for line in (BASE/'quantlib-v1.tsv').read_text().splitlines():
        fields=line.split('\t');id,rate,status=fields[:3]
        row=dict(id=id,common_rate=rate,comparator_status=status,detail=fields[3:])
        ref=refs[id]['reference'];row['reference_status']=ref['status']
        if status=='finite' and ref['status']=='interval':
            value=float.fromhex(fields[3]); n,d=value.as_integer_ratio()
            error=abs(arb(n)/arb(d)-arb(ref['closed']))
            row['absolute_error_interval']=error.str(40,more=True)
            row['explanation']=('QuantLib Instrument marks same-date exercise expired; NPV=0 is not this API expiry payoff'
                if id.startswith('expiry-') else
                'same exact date-mapped inputs; binary64 covariance, discount and CDF arithmetic differ')
        elif ref['status'].startswith('invalid'):
            row['explanation']='typed API control; comparator has no accuracy-limit request and differing admission'
        elif status=='nonfinite':
            row['explanation']='canonical engine returned nonfinite; no accuracy comparison'
        elif status=='excluded':
            row['explanation']='input/date mapping unavailable; no accuracy comparison'
        else:
            row['explanation']='independent reference unresolved; no accuracy pass'
        rows.append(row)
    args.output.write_text(json.dumps(dict(schema=1,rows=rows),indent=2)+'\n')
if __name__=='__main__': main()
