#!/usr/bin/env python3
"""Per-case canonical differences, retaining exclusions and boundary conventions."""
import argparse,gzip,json
from pathlib import Path
from flint import arb,ctx

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='exchange-qualification-canonical 1')
    p.add_argument('--references',type=Path,required=True);p.add_argument('--canonical',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();ctx.prec=4096
    refs={r['id']:r for r in json.loads(gzip.decompress(a.references.read_bytes()))['rows']};rows=[]
    for line in a.canonical.read_text().splitlines():
        id,rate,status,*detail=line.split('\t');ref=refs[id]['reference']
        row=dict(id=id,rate=rate,status=status,detail=detail,reference_status=ref['status'])
        if status=='finite' and ref['status']=='interval':
            n,d=float.fromhex(detail[0]).as_integer_ratio();error=abs(arb(n)/arb(d)-arb(ref['closed']))
            row['absolute_error_interval']=error.str(50,more=True)
            row['disposition']='same-date Instrument expiry convention differs' if id.startswith('expiry-') else 'binary64 covariance/discount/CDF comparator difference; not truth or certificate'
        else:row['disposition']='retained nonfinite, invalid-control or date-mapping exclusion; no accuracy pass'
        rows.append(row)
    a.output.write_text(json.dumps(dict(rows=rows),indent=2)+'\n')
if __name__=='__main__':main()
