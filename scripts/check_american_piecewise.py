"""Score piecewise prices against frozen references; unavailable is never a pass."""
import argparse
import collections
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import struct
import tempfile
from american_piecewise_reference import number, protocol
from american_reference_data import capture, require, score_price
BASE=Path(__file__).resolve().parents[1]/'docs/evidence/american-piecewise'


def request(case,mode):
    parts=protocol(case,32).split(' | ')
    raw=parts[0].split(); scale=max(number(case['inputs'][k]) for k in ('spot','strike'))
    epsilon=scale*(2**-16 if mode=='primary' else 0.01)
    parts[0]=' '.join(raw[:2]+raw[4:11]+[struct.pack('>d',epsilon).hex()]+raw[11:])
    return ' | '.join(parts)


def classify(raw,cases,refs,mode):
    lines=raw.splitlines();require(len(lines)==len(cases)==len(refs),'missing or extra piecewise rows')
    out=[]
    for line,case,ref in zip(lines,cases,refs):
        fields=line.split('\t');require(len(fields)==4,'malformed piecewise runtime row')
        id,status,value,detail=fields;require(id==case['id']==ref['id'],'piecewise row identity/order')
        require(status in ('estimated','unavailable') and bool(detail),'piecewise outcome/detail')
        row=dict(id=id,outcome=status,detail=detail)
        if status=='unavailable':
            require(value=='-' and detail.startswith(('resource:','arithmetic:','accuracy:','nonconvergence:','cancelled','unrepresentable')),'invalid piecewise failure')
            row['comparison']=dict(status='runtime_unavailable')
        else:
            value=float.fromhex(value);require(math.isfinite(value) and value>=0,'invalid piecewise price')
            center=Fraction(float.fromhex(ref['value']));radius=Fraction(float.fromhex(ref['radius']))
            reference=dict(status='resolved',kind='empirical',lower=str(center-radius),upper=str(center+radius))
            epsilon=max(number(case['inputs'][k]) for k in ('spot','strike'))*(2**-16 if mode=='primary' else .01)
            row.update(value=value,comparison=score_price(reference,value,epsilon))
        out.append(row)
    return out


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='piecewise-score 1')
    p.add_argument('--executable',type=Path,required=True)
    p.add_argument('--refined',action='store_true')
    p.add_argument('--mode',choices=('primary','loose'),default='primary')
    p.add_argument('--output',type=Path)
    a=p.parse_args();cases=json.loads((BASE/'cases-v1.json').read_text())['rows'];refs=json.loads((BASE/'references-v1.json').read_text())['rows']
    if a.output:a.output.mkdir(parents=True,exist_ok=False)
    with tempfile.TemporaryDirectory() as temp:
        dest=a.output or Path(temp);inp=dest/'input.txt';inp.write_text(''.join(request(c,a.mode)+'\n' for c in cases))
        raw=capture([str(a.executable.resolve()),'--refined-corpus' if a.refined else '--corpus',str(inp.resolve())],'',dest/'stdout.tsv',timeout=1800)
        rows=classify(raw,cases,refs,a.mode);counts=dict(collections.Counter(r['comparison']['status'] for r in rows))
        report=dict(schema=1,complete=True,mode=a.mode,configuration='refined' if a.refined else 'initial',counts=counts,rows=rows,binary_sha256=hashlib.sha256(a.executable.read_bytes()).hexdigest())
        (dest/'results.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
        require(counts.get('fail',0)==0,'piecewise independent accuracy failure')
        for row,ref in zip(rows,refs):
            if ref['analytical_digits'] is not None:require(row['comparison']['status']=='pass','piecewise analytical capability: '+row['id'])
    print(json.dumps({k:v for k,v in report.items() if k not in ('rows','binary_sha256')}))

if __name__=='__main__':main()
