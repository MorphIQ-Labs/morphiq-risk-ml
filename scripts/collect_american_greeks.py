"""Strictly assemble precision/refinement evidence; unresolved references stay explicit."""
import argparse
from decimal import Decimal, localcontext
import hashlib
import json
import math
from pathlib import Path
from american_piecewise_reference import number
from american_reference_data import require, strict_json
BASE=Path(__file__).resolve().parents[1]/'docs/evidence/american-greeks'
QUANTITIES=('delta','gamma','vega','rho','theta')
TARGETS={'primary':dict(zip(QUANTITIES,[.001,.0001,.05,.05,.0001])),
         'loose':dict(zip(QUANTITIES,[.02,.002,1.,1.,.005]))}


def finite(token):
    require(isinstance(token,str) and '0x' in token.lower(),'reference number must be hexadecimal')
    try:v=float.fromhex(token)
    except (ValueError,OverflowError) as e:raise ValueError('malformed reference number') from e
    require(math.isfinite(v),'nonfinite reference number')
    return v


def parse(raw, ids, n, kind):
    result={};lines=raw.splitlines()
    require(len(lines)==len(ids),'missing/extra reference rows')
    for line,id in zip(lines,ids):
        f=line.split('\t');require(len(f)>=3 and f[0]==id and f[1]==str(n),'reference row identity/order')
        require(id not in result,'duplicate reference row')
        if f[2]=='finite':
            require(len(f)=={'quantlib':7,'quadrature':13,'prices':5}[kind],'truncated/extra finite reference columns')
            values=[None if kind=='quantlib' and i==6 and t=='-' else finite(t) for i,t in enumerate(f[3:],3)]
            if kind!='quantlib':require(0<=values[0]<=values[1],'reversed/negative reference price pair')
            result[id]=dict(status='finite',values=values)
        else:
            require(f[2] in ('unavailable','exception'),'invalid reference status')
            require(len(f)=={'quantlib':7,'quadrature':4,'prices':5}[kind] and bool(f[-1]),'missing reference failure detail')
            result[id]=dict(status='unavailable',reason=f[-1])
    return result


def assemble(root,cases):
    ids=[r['id'] for r in cases]
    family=strict_json((root/'families.json').read_text());familyids=ids+[r['id'] for r in family['rows']]
    excluded={(r['id'],r['quantity']):r['reason'] for r in family['excluded']}
    raw={kind:{n:parse((root/f'{kind}-{n}.tsv').read_text(),familyids if kind=='prices' else ids,n,kind) for n in levels}
         for kind,levels in [('quantlib',[128,256,512]),('quadrature',[256,512,1024]),('prices',[256,512,1024])]}
    analytic=[]
    for digits in (80,160):
        xs=[strict_json(s) for s in (root/f'analytic-{digits}.jsonl').read_text().splitlines()]
        require([r['id'] for r in xs]==ids and all(r['precision']==digits for r in xs),'analytic identity/precision')
        analytic.append({r['id']:r for r in xs})
    results=[]
    for case in cases:
        id=case['id'];scale=max(number(case['inputs'][k]) for k in ('spot','strike'));spot=number(case['inputs']['spot'])
        for q in QUANTITIES:
            out=dict(id=id,quantity=q,canonical=[raw['quantlib'][n][id] for n in (128,256,512)])
            a,b=[x[id]['greeks'][q] for x in analytic]
            require(a['status']==b['status'],'analytic availability changed with precision')
            if b['status']=='finite':
                with localcontext() as ctx:
                    ctx.prec=180;x,y=Decimal(a['value']),Decimal(b['value'])
                    require(x.is_finite() and y.is_finite(),'nonfinite analytic reference')
                    require(abs(x-y)<=Decimal('1e-70')*max(Decimal(1),abs(y)),'analytical precision unresolved')
                value=float(y);radius=2**-50*max(1,abs(value));out.update(method=b['method'],digits=b['value'])
            else:
                values=[];indicators=[];details=[];reason=None
                if q in ('delta','gamma'):
                    for n in (256,512,1024):
                        row=raw['quadrature'][n][id]
                        if row['status']!='finite':reason=row['reason'];break
                        xs=row['values'];j=0 if q=='delta' else 1
                        lo,hi=xs[2+j],xs[6+j];h=min(spot/4,scale/n**.75)
                        radius=max(xs[4+j],xs[8+j])+abs(hi-lo)/2+256*2**-53*n*scale/h**(1 if q=='delta' else 2)
                        values.append((lo+hi)/2);indicators.append(radius);details.append(dict(n=n,lower_derivative=lo,upper_derivative=hi,stencil=max(xs[4+j],xs[8+j])))
                elif (id,q) in excluded:reason=excluded[id,q]
                else:
                    for n in (256,512,1024):
                        base=raw['prices'][n][id]
                        if base['status']!='finite':reason=base['reason'];break
                        estimates=[];bounds=[]
                        for j in range(3):
                            h=2**(-10-j);plus=raw['prices'][n][id+'_'+q+'_'+str(j)+'_plus']
                            minus=base if q=='theta' else raw['prices'][n][id+'_'+q+'_'+str(j)+'_minus']
                            if plus['status']!='finite' or minus['status']!='finite':reason='perturbed quadrature unavailable';break
                            av,bv=minus['values'],plus['values'];denom=365*h if q=='theta' else 2*h
                            estimates.append(((bv[0]+bv[1])-(av[0]+av[1]))/(2*denom))
                            bounds.append(((bv[1]-bv[0])+(av[1]-av[0]))/(2*denom)+512*2**-53*n*scale/denom)
                        if reason:break
                        bump=max(abs(estimates[1]-estimates[0]),abs(estimates[2]-estimates[1]))
                        values.append(estimates[-1]);indicators.append(bump+max(bounds));details.append(dict(n=n,bumps=estimates,bump_indicator=bump,arithmetic_boundary=max(bounds)))
                out['refinements']=details
                if reason or len(values)!=3:
                    out.update(status='unavailable',reason=reason or 'incomplete reference refinement');results.append(out);continue
                value=values[-1];radius=4*max(abs(values[1]-values[0]),abs(values[2]-values[1]))+indicators[-1]
                out.update(method='independent quadrature derivative refinement')
            require(math.isfinite(value) and math.isfinite(radius) and radius>=0,'invalid assembled reference')
            out.update(status='finite',value=value.hex(),radius=radius.hex(),resolved={mode:radius<=targets[q]/8 for mode,targets in TARGETS.items()})
            results.append(out)
    return dict(schema=1,rows=results,sources={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.iterdir()) if p.is_file() and p.suffix in ('.tsv','.jsonl','.json')})


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='collect-american-greeks 1')
    p.add_argument('--raw',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();cases=strict_json((BASE/'cases-v1.json').read_text())['rows']
    data=assemble(a.raw,cases);a.output.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n')
    print('references',len(data['rows']),'resolved', {mode:sum(r.get('resolved',{}).get(mode,False) for r in data['rows']) for mode in TARGETS})

if __name__=='__main__':main()
