"""Supplementary canonical comparison, separate from independent quadrature scoring."""
import argparse
import json
import math
from pathlib import Path
from collect_american_greeks import BASE, QUANTITIES, TARGETS, parse
from american_reference_data import require, strict_json


def assemble(root,cases):
    family=strict_json((root/'families.json').read_text());ids=[r['id'] for r in cases]+[r['id'] for r in family['rows']]
    raw={n:parse((root/f'canonical-family-{n}.tsv').read_text(),ids,n,'quantlib') for n in (128,256,512)}
    exclusions={(r['id'],r['quantity']):r['reason'] for r in family['excluded']};result=[]
    for row in cases:
        id=row['id']
        for q in QUANTITIES:
            refinements=[];indicators=[];reason=None
            for n in (128,256,512):
                base=raw[n][id]
                if base['status']!='finite':reason=base['reason'];break
                if q in ('delta','gamma'):
                    value=base['values'][1 if q=='delta' else 2];bump=0.
                else:
                    if (id,q) in exclusions:reason=exclusions[id,q];break
                    vs=[]
                    for j in range(3):
                        plus=raw[n][id+'_'+q+'_'+str(j)+'_plus'];minus=base if q=='theta' else raw[n][id+'_'+q+'_'+str(j)+'_minus']
                        if plus['status']!='finite' or minus['status']!='finite':reason='canonical perturbed price unavailable';break
                        h=2**(-10-j);denom=365*h if q=='theta' else 2*h
                        vs.append((plus['values'][0]-minus['values'][0])/denom)
                    if reason:break
                    value=vs[-1];bump=max(abs(vs[1]-vs[0]),abs(vs[2]-vs[1]))
                refinements.append(value);indicators.append(bump+256*2**-53*n*max(1,abs(value)))
            r=dict(id=id,quantity=q,refinements=refinements)
            if reason or len(refinements)!=3:r.update(status='unavailable',reason=reason or 'missing canonical refinement')
            else:
                radius=4*max(abs(refinements[1]-refinements[0]),abs(refinements[2]-refinements[1]))+indicators[-1]
                require(math.isfinite(radius) and all(map(math.isfinite,refinements)),'nonfinite canonical derivative')
                r.update(status='finite',value=refinements[-1].hex(),radius=radius.hex(),resolved={mode:radius<=targets[q]/8 for mode,targets in TARGETS.items()})
            result.append(r)
    return dict(schema=1,method='supplementary QuantLib empirical derivative refinement; not independent quadrature replacement',rows=result)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='collect-american-greeks-canonical 1')
    p.add_argument('--raw',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();cases=strict_json((BASE/'cases-v1.json').read_text())['rows'];data=assemble(a.raw,cases)
    a.output.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n')
    print('canonical resolved',{mode:sum(r.get('resolved',{}).get(mode,False) for r in data['rows']) for mode in TARGETS})

if __name__=='__main__':main()
