#!/usr/bin/env python3
"""Score the frozen cash campaign without turning missing prices into passes."""
import argparse, collections, hashlib, json, math, pathlib, struct, tempfile
from fractions import Fraction as F
from american_reference_data import score_price, require, strict_json, capture
BASE=pathlib.Path(__file__).resolve().parents[1]/'docs/evidence/american-cash'
FIELDS=('spot','strike','rate','yield_','volatility','time','opens')
def decode(s):return struct.unpack('>d',bytes.fromhex(s))[0]
def tolerance(row,mode):return decode(row['epsilon']) if mode=='primary' else max(decode(row['inputs']['spot']),decode(row['inputs']['strike']))/100

def reference(row):
    if 'radius' not in row:return {'status':'unresolved','reason':'reference unavailable'}
    value,radius=F(row['value']),F(row['radius'])
    return {'status':'resolved','kind':'empirical','lower':str(value-radius),'upper':str(value+radius)}

def classify(raw,cases,refs,mode):
    lines=raw.splitlines();require(len(lines)==len(cases)==len(refs),'missing or extra cash rows')
    out=[]
    for line,case,ref in zip(lines,cases,refs):
        fields=line.split('\t');require(len(fields)==4,'malformed cash runtime row')
        name,status,value,detail=fields;require(name==case['id']==ref['id'],'cash row identity/order')
        require(status in ('estimated','unavailable') and bool(detail),'cash outcome/detail')
        entry=dict(id=name,outcome=status,detail=detail)
        if status=='unavailable':
            require(value=='-' and detail.startswith(('resource:','arithmetic:','accuracy:','nonconvergence:','cancelled','unrepresentable')),'invalid cash failure')
            entry['comparison']={'status':'runtime_unavailable'}
        else:
            value=float.fromhex(value);require(math.isfinite(value) and value>=0,'invalid cash price')
            entry['value']=value;entry['comparison']=score_price(reference(ref),value,tolerance(case,mode))
            entry['primary_comparison']=score_price(reference(ref),value,tolerance(case,'primary'))
        out.append(entry)
    return out

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--version',action='version',version='american-cash-score 1')
    ap.add_argument('--executable',type=pathlib.Path,required=True);ap.add_argument('--refined',action='store_true');ap.add_argument('--mode',choices=['primary','loose'],default='primary');ap.add_argument('--output',type=pathlib.Path)
    args=ap.parse_args();cases=strict_json((BASE/'cases-v1.json').read_text())['rows'];refs=strict_json((BASE/'references.json').read_text())['rows']
    request=''.join(' '.join([r['id'],r['side'],*[r['inputs'][k] for k in FIELDS],struct.pack('>d',tolerance(r,args.mode)).hex(),*[str(r[k]) for k in ('valuation_side','opening_side','expiry_side')],str(len(r['cash'])),*[v for e in r['cash'] for v in (e['time'],e['amount'])]])+'\n' for r in cases)
    if args.output:args.output.mkdir(parents=True,exist_ok=False)
    with tempfile.TemporaryDirectory() as temp:
        destination=args.output or pathlib.Path(temp);path=destination/'input.txt';path.write_text(request)
        raw=capture([str(args.executable.resolve()),'--refined-corpus' if args.refined else '--corpus',str(path.resolve())],'',destination/'stdout.tsv',timeout=1200)
        rows=classify(raw,cases,refs,args.mode)
        counts=dict(collections.Counter(r['comparison']['status'] for r in rows))
        report=dict(schema=1,complete=True,mode=args.mode,configuration='refined' if args.refined else 'initial',counts=counts,rows=rows,binary_sha256=hashlib.sha256(args.executable.read_bytes()).hexdigest())
        (destination/'results.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
        require(counts.get('fail',0)==0,'cash independent accuracy failure')
        for row,ref in zip(rows,refs):
            if row['id'].startswith(('deterministic-','zero-stock','zero-strike','call-zero-time','put-zero-time')):require(row['comparison']['status']=='pass','cash analytical capability: '+row['id'])
    print(json.dumps({k:v for k,v in report.items() if k not in ('rows','binary_sha256')}))
if __name__=='__main__':main()
