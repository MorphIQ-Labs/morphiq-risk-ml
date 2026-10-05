#!/usr/bin/env python3
"""Score the frozen cash campaign without turning missing prices into passes."""
import argparse, collections, hashlib, json, math, pathlib, struct, tempfile
from fractions import Fraction as F
from american_reference_data import score_price, require, strict_json, capture
from check_american_cash import FIELDS, decode, tolerance, reference, classify
BASE=pathlib.Path(__file__).resolve().parents[1]/'docs/evidence/bermudan'

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--version',action='version',version='bermudan-score 1')
    ap.add_argument('--executable',type=pathlib.Path,required=True);ap.add_argument('--refined',action='store_true');ap.add_argument('--mode',choices=['primary','loose'],default='primary');ap.add_argument('--output',type=pathlib.Path)
    args=ap.parse_args();cases=strict_json((BASE/'cases-v1.json').read_text())['rows'];refs=strict_json((BASE/'references.json').read_text())['rows']
    request=''.join(' '.join([r['id'],r['side'],*[r['inputs'][k] for k in FIELDS],struct.pack('>d',tolerance(r,args.mode)).hex(),*[str(r[k]) for k in ('valuation_side','opening_side','expiry_side')],str(len(r['cash'])),*[v for e in r['cash'] for v in (e['time'],e['amount'])]])+' | '+str(len(r['exercise']))+' '+' '.join(e['time']+' '+str(e['side']) for e in r['exercise'])+'\n' for r in cases)
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
            if ref['reference_kind']=='precision-refined-analytical' and not row['id'].startswith('terminal-cash-'):require(row['comparison']['status']=='pass','cash analytical capability: '+row['id'])
    print(json.dumps({k:v for k,v in report.items() if k not in ('rows','binary_sha256')}))
if __name__=='__main__':main()
