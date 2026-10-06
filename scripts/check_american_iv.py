#!/usr/bin/env python3
"""Offline integrity and independent inverse-reference export."""
import argparse,hashlib,json
from fractions import Fraction as F
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'docs/evidence/american-iv/reference-v1'
def require(x,message):
 if not x:raise ValueError(message)
def validate(d):
 rows=d['rows'];require(len(rows)==30,'incomplete corpus');require(len({r['id'] for r in rows})==30,'duplicate case')
 for r in rows:
  require(r['style'] in ['american','bermudan'] and r['side'] in ['call','put'],'invalid identity')
  require(F(r['lower'])<=F(r['upper']),'reversed interval')
  require(.05<=F(r['lower'])<=F(r['upper'])<=.6,'reference outside search range')
  require(r['resolved'] is True,'unresolved reference')
  require(float.fromhex(r['quote'])>=0,'invalid quote')
  require(len(r['attempts'])==2,'missing independent refinement')
  if r['route']=='arb':require({a['bits'] for a in r['attempts']}=={256,512},'precision identity')
  else:require({a['engine'] for a in r['attempts']}=={'lattice','quantlib'},'engine identity')
 w=d['cash_put_counterexample'];require(len(w)==3,'counterexample incomplete')
 require(F(w[0]['lower'])>F(w[1]['upper']) and F(w[2]['lower'])>F(w[1]['upper']),'nonmonotone counterexample lost')
 return rows

def emit(rows):
 return ''.join(' '.join([r['id'],r['style'],r['side'],*[float(r[k]).hex() for k in ['s','k','r','q','t','opens','cash']],r['quote'],r['lower'],r['upper'],r['route']])+'\n' for r in rows)

def validate_negative(rows):
 require(len(rows)==2 and {r['side'] for r in rows}=={'call','put'},'negative-yield corpus incomplete')
 for r in rows:
  require(r['q']<0 and r['opens']==r['t']==1.,'negative-yield identity')
  require(F(r['lower'])<=F(r['upper']),'negative-yield reversed interval')
  require({a['bits'] for a in r['attempts']}=={256,512},'negative-yield precision identity')
 return rows

def load(check_fixture=True):
 m=json.loads((BASE/'manifest.json').read_text())
 for name,digest in m['sources'].items():require(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'generator drift')
 for name,digest in m['files'].items():require(hashlib.sha256((BASE/name).read_bytes()).hexdigest()==digest,'reference drift')
 negative=BASE.parent/'negative-yield'
 nm=json.loads((negative/'manifest.json').read_text())
 for name,digest in nm['sources'].items():require(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'negative-yield generator drift')
 for name,digest in nm['files'].items():require(hashlib.sha256((negative/name).read_bytes()).hexdigest()==digest,'negative-yield reference drift')
 nr=validate_negative(json.loads((negative/'references.json').read_text()))
 nt=''.join(' '.join([r['side'],r['r'].hex(),r['q'].hex(),r['quote'],r['lower'],r['upper']])+'\n' for r in nr)
 require((negative/'references.tsv').read_text()==nt,'negative-yield export mismatch')
 rows=validate(json.loads((BASE/'references.json').read_text()))
 if check_fixture:require((BASE.parent/'references.tsv').read_text()==emit(rows),'exported fixture identity mismatch')
 return rows

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--emit',action='store_true');ap.add_argument('--version',action='version',version='american-iv-check 1');args=ap.parse_args();rows=load(not args.emit)
 if args.emit:print(emit(rows),end='')
 else:print('30 complete independent inverse references and cash-put counterexample verified')
if __name__=='__main__':main()
