"""Reproduce Greek references with pinned, prebuilt optional research dependencies."""
import argparse
import copy
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import struct
import time
from american_piecewise_reference import number, protocol
from american_reference_data import capture, require
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'docs/evidence/american-greeks'
word=lambda v:struct.pack('>d',float(v)).hex()


def shifted(row, quantity, h):
    r=copy.deepcopy(row)
    def change(w, amount):
        exact=Fraction(number(w))+Fraction(amount)
        v=float(exact)
        require(math.isfinite(v) and Fraction(v)==exact,'reference shift not representable')
        return word(v)
    if quantity in ('vega','rho'):
        field='volatility' if quantity=='vega' else 'rate'
        r['inputs'][field]=change(r['inputs'][field],h)
        for e in r['curves'][field]:e['level']=change(e['level'],h)
        if field=='volatility':require(number(r['inputs'][field])>=0 and all(number(e['level'])>=0 for e in r['curves'][field]),'negative volatility bump')
    else:
        require(number(r['inputs']['time'])>h,'roll reaches expiry')
        require(not any(number(e['time'])==0 for e in r['cash']),'valuation cash event')
        require(not r['exercise'] or number(r['exercise'][0]['time'])>h,'valuation/passed exercise right')
        for field in ('time','opens'):
            if field=='opens' and number(r['inputs'][field])==0:continue
            require(number(r['inputs'][field])>h,'roll crosses opening')
            r['inputs'][field]=change(r['inputs'][field],-h)
        for e in [*r['cash'],*(r['exercise'] or []),*(e for c in r['curves'].values() for e in c)]:
            require(number(e['time'])>h,'roll crosses event')
            e['time']=change(e['time'],-h)
    return r


def families(rows):
    out=[];excluded=[]
    for row in rows:
        for q in ('vega','rho','theta'):
            family=[]
            try:
                for j in range(3):
                    h=2**(-10-j)
                    for sign in ([1] if q=='theta' else [-1,1]):
                        r=shifted(row,q,sign*h);r['id']=row['id']+'_'+q+'_'+str(j)+'_'+('plus' if sign==1 else 'minus')
                        family.append(r)
                out.extend(family)
            except ValueError as e:excluded.append(dict(id=row['id'],quantity=q,reason=str(e)))
    return out,excluded


def sources():
    files=[BASE/'cases-v1.json',BASE/'protocol.md',BASE/'protocol-addendum.md',BASE/'frozen.json',BASE/'canonical-addendum.md',Path(__file__),ROOT/'scripts/generate_american_greeks_canonical.py',
           *ROOT.glob('scripts/american_greeks*'),*ROOT.glob('scripts/american_piecewise*'),
           ROOT/'scripts/american_runner_io.hpp',ROOT/'scripts/american_cash_io.hpp',ROOT/'scripts/bermudan_io.hpp',ROOT/'scripts/american_reference_data.py']
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file()}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='generate-american-greeks 1')
    for name in ('quantlib','quadrature','price-quadrature','mpmath-python','output'):p.add_argument('--'+name,type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    rows=json.loads((BASE/'cases-v1.json').read_text())['rows'];family,excluded=families(rows)
    (a.output/'families.json').write_text(json.dumps(dict(rows=family,excluded=excluded),indent=2)+'\n')
    binaries=[a.quantlib,a.quadrature,a.price_quadrature]
    guard=sources();identities={str(x.resolve()):hashlib.sha256(x.read_bytes()).hexdigest() for x in binaries}
    manifest=dict(sources=guard,binaries=identities,runs=[],complete=False)
    def run(command,name,data=''):
        start=time.time()
        try:
            text=capture(command,data,a.output/name,timeout=1800)
        finally:
            manifest['runs'].append(dict(command=command,name=name,seconds=time.time()-start))
            (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        return text
    for precision in (80,160):run([str(a.mpmath_python.absolute()),str(ROOT/'scripts/american_greeks_reference.py'),'--precision',str(precision)],f'analytic-{precision}.jsonl')
    for label,exe,levels,data_rows in [('quantlib',a.quantlib,[128,256,512],rows),('quadrature',a.quadrature,[256,512,1024],rows),('prices',a.price_quadrature,[256,512,1024],rows+family)]:
        for n in levels:
            outputs=[]
            for batch,start in enumerate(range(0,len(data_rows),256)):
                data=''.join(protocol(r,n)+'\n' for r in data_rows[start:start+256])
                (a.output/f'{label}-{n}-{batch}.input').write_text(data)
                outputs.append(run([str(exe.resolve())],f'{label}-{n}-{batch}.tsv',data))
            (a.output/f'{label}-{n}.tsv').write_text(''.join(outputs))
            print(label,n,'complete',flush=True)
    require(guard==sources(),'reference source drift')
    require(identities=={str(x.resolve()):hashlib.sha256(x.read_bytes()).hexdigest() for x in binaries},'reference binary drift')
    manifest['complete']=True
    (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')

if __name__=='__main__':main()
