"""Score all requested Greeks, retaining failures and unresolved references."""
import argparse
from collections import Counter
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import tempfile
from american_reference_data import capture, require, strict_json
from check_american_piecewise import request
from collect_american_greeks import BASE, QUANTITIES, TARGETS, finite


def classify(raw,cases,references,mode):
    expected=[(c['id'],q) for c in cases for q in QUANTITIES]
    require([(r['id'],r['quantity']) for r in references]==expected,'reference Greek identity/order')
    lines=raw.splitlines();require(len(lines)==len(expected),'missing/extra runtime Greeks')
    out=[]
    for line,key,ref in zip(lines,expected,references):
        f=line.split('\t');require(len(f)==6,'malformed/truncated runtime Greek')
        id,q,status,value,detail,price=f
        require((id,q)==key,'runtime Greek identity/order')
        require(status in ('estimated','unavailable','unresolved','failure','price_failure') and detail,'runtime Greek status/detail')
        row=dict(id=id,quantity=q,outcome=status,detail=detail)
        if status!='price_failure':require(finite(price)>=0,'invalid base price')
        else:require(price=='-','price failure has value')
        if status!='estimated':
            require(value=='-','failed Greek has a value');row['comparison']='runtime_unavailable'
        else:
            v=finite(value);row['value']=v.hex()
            if ref['status']!='finite' or not ref['resolved'][mode]:row['comparison']='unresolved_reference'
            else:
                target=Fraction(TARGETS[mode][q]);radius=Fraction(finite(ref['radius']))
                discrepancy=abs(Fraction(v)-Fraction(finite(ref['value'])))
                require(radius>=0,'negative reference uncertainty')
                require(radius<=target/8,'reference resolution flag exceeds target budget')
                row.update(comparison='pass' if discrepancy+radius<=target else 'fail',absolute_discrepancy=float(discrepancy),reference_radius=float(radius),target=float(target))
        out.append(row)
    return out


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='check-american-greeks 1')
    p.add_argument('--executable',type=Path,required=True)
    p.add_argument('--references',type=Path,default=BASE/'references-v1.json')
    p.add_argument('--mode',choices=TARGETS,default='loose')
    p.add_argument('--refined',action='store_true');p.add_argument('--output',type=Path)
    a=p.parse_args();cases=strict_json((BASE/'cases-v1.json').read_text())['rows'];refs=strict_json(a.references.read_text())['rows']
    if a.output:a.output.mkdir(parents=True,exist_ok=False)
    identity=hashlib.sha256(a.executable.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory() as tmp:
        dest=a.output or Path(tmp);inp=dest/'input.txt';inp.write_text(''.join(request(c,a.mode)+'\n' for c in cases))
        raw=capture([str(a.executable.resolve()),'--refined-corpus' if a.refined else '--corpus',str(inp.resolve()),a.mode],'',dest/'stdout.tsv',1800)
        require(identity==hashlib.sha256(a.executable.read_bytes()).hexdigest(),'runtime binary drift')
        rows=classify(raw,cases,refs,a.mode);counts=dict(Counter(r['comparison'] for r in rows))
        report=dict(schema=1,complete=True,mode=a.mode,refined=a.refined,counts=counts,rows=rows,binary_sha256=identity)
        (dest/'results.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
        require(counts.get('fail',0)==0,'independent Greek accuracy failure')
    print(json.dumps({k:v for k,v in report.items() if k!='rows'}))

if __name__=='__main__':main()
