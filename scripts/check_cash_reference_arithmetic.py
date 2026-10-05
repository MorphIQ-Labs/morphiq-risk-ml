#!/usr/bin/env python3
"""Supplementary exact cash and precision-refined discrete quadrature checks."""
import bisect, json, pathlib
from fractions import Fraction as F
import mpmath as mp
from american_cash_references import analytical, decode, exact

def quadrature(row,dps):
    with mp.workdps(dps):
        s,k,r,q,vol,t,opens=[exact(row['inputs'][key]) for key in ('spot','strike','rate','yield_','volatility','time','opens')]
        n=8;scale=max(s,k);zero=mp.mpf(0)
        x=sorted(set([zero,s,k,*[scale*mp.power(2,-14+mp.mpf(19)*i/(16*n)) for i in range(16*n+1)]]))
        payoff=lambda stock:max(stock-k if row['side']=='call' else k-stock,zero)
        cash={}
        for e in row['cash']:
            time=exact(e['time']);cash[time]=cash.get(time,zero)+exact(e['amount'])
        def eligible(time,phase):return (time>opens or (time==opens and phase>=row['opening_side'])) and (time<t or(time==t and phase<=row['expiry_side']))
        values=[payoff(a) for a in x]
        def interpolate(stock,time):
            if stock>=x[-1]:return (stock if row['side']=='call' else k)*mp.exp(max(-q if row['side']=='call' else -r,zero)*(t-time))
            j=bisect.bisect_right(x,stock)
            if j==0:return values[0]
            w=(stock-x[j-1])/(x[j]-x[j-1]);return (1-w)*values[j-1]+w*values[j]
        later=t
        for time in sorted(set([zero,opens,t,*cash]),reverse=True):
            if time<later:
                h=(later-time)/n;d=mp.exp(-r*h);a=mp.exp((r-q-vol*vol/2)*h);b=mp.exp(vol*mp.sqrt(3*h))
                for j in range(1,n+1):
                    now=later-j*h
                    mapped=[d*(interpolate(stock*a/b,now+h)+4*interpolate(stock*a,now+h)+interpolate(stock*a*b,now+h))/6 for stock in x]
                    values=[max(v,payoff(stock)) if eligible(now,2) else v for stock,v in zip(x,mapped)]
            if time in cash and not(time==t and row['expiry_side']==1) and not(time==0 and row['valuation_side']==2):
                if eligible(time,2):values=[max(v,payoff(stock)) for stock,v in zip(x,values)]
                mapped=[interpolate(max(stock-cash[time],zero),time) for stock in x]
                values=[max(v,payoff(stock)) if eligible(time,1) else v for stock,v in zip(x,mapped)]
            later=time
        return mp.nstr(values[x.index(s)],dps)

def main():
    base=pathlib.Path('docs/evidence/american-cash');rows=json.loads((base/'cases-v1.json').read_text())['rows'];out={'scope':'Supplementary arithmetic agreement for a fixed N=8 discrete problem; no continuum accuracy claim.','mpmath':mp.__version__,'quadrature':[],'exact_rational':[]}
    for row in rows:
        if row['id'] in ('call-single','put-coincident'):
            a,b=quadrature(row,80),quadrature(row,160)
            with mp.workdps(180):assert abs(mp.mpf(a)-mp.mpf(b))<mp.mpf('1e-70')
            out['quadrature'].append({'id':row['id'],'precision_80':a,'precision_160':b})
        if row['id'] in ('deterministic-joint','deterministic-rounded-sum','unrepresentable-joint'):
            s,k=F(decode(row['inputs']['spot'])),F(decode(row['inputs']['strike']))
            total=sum((F(decode(e['amount'])) for e in row['cash']),F(0));value=max(k-max(s-total,0),0)
            with mp.workdps(180):assert abs(mp.mpf(analytical(row,160))-mp.mpf(value.numerator)/value.denominator)<mp.mpf('1e-150')
            out['exact_rational'].append({'id':row['id'],'value':str(value),'joint_amount':str(total)})
    (base/'arithmetic.json').write_text(json.dumps(out,indent=2)+'\n')
if __name__=='__main__':main()
