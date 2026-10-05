"""Precision replay of the fixed N=8 positive quadrature problem, not continuum truth."""
import argparse
import bisect
import json
from pathlib import Path
import mpmath as mp
from american_piecewise_reference import number


def solve(row, precision):
    mp.mp.dps=precision
    def exact(w):
        n,d=number(w).as_integer_ratio();return mp.mpf(n)/d
    p={k:exact(v) for k,v in row['inputs'].items()}
    if p['spot']==0 or p['strike']==0 or p['time']==0 or all(exact(e['level'])==0 for e in row['curves']['volatility']) and p['volatility']==0:
        return None
    n=8;T=p['time'];scale=max(p['spot'],p['strike'])
    curves={k:[(mp.mpf(0),p[k])]+[(exact(e['time']),exact(e['level'])) for e in row['curves'][k]] for k in ('rate','yield','volatility')}
    cash={}
    for e in row['cash']:
        t=exact(e['time']);cash[t]=cash.get(t,mp.mpf(0))+exact(e['amount'])
    rights=None if row['exercise'] is None else [(exact(e['time']),e['side']) for e in row['exercise']]
    def eligible(t,phase):
        return (t,phase) in rights if rights is not None else (t,phase)>=(p['opens'],row['opening_side']) and (t,phase)<=(T,row['expiry_side'])
    def level(k,t):return next(v for u,v in reversed(curves[k]) if u<=t)
    def payoff(s):return max(s-p['strike'] if row['side']=='call' else p['strike']-s,mp.mpf(0))
    grid=sorted({mp.mpf(0),p['spot'],p['strike'],*(scale*mp.power(2,-14+mp.mpf(19)*i/(16*n)) for i in range(16*n+1))})
    vals=[payoff(s) for s in grid]
    def interp(s):
        j=bisect.bisect_right(grid,s)
        if j==0:return vals[0]
        if j==len(grid):return mp.mpf(0)
        w=(s-grid[j-1])/(grid[j]-grid[j-1]);return (1-w)*vals[j-1]+w*vals[j]
    times=sorted({mp.mpf(0),p['opens'],T,*cash,*(t for c in curves.values() for t,_ in c),*(t for t,_ in (rights or []))},reverse=True)
    later=T
    for t in times:
        if t<later:
            r,q,v=(level(k,t) for k in ('rate','yield','volatility'))
            dt=(later-t)/n;discount=mp.exp(-r*dt);a=mp.exp((r-q-v*v/2)*dt);b=mp.exp(v*mp.sqrt(3*dt))
            stencils=[]
            for s in grid:
                samples=[]
                for dest in (s*a/b,s*a,s*a*b):
                    j=bisect.bisect_right(grid,dest)
                    samples.append((j,(dest-grid[j-1])/(grid[j]-grid[j-1]) if 0<j<len(grid) else 0))
                stencils.append(samples)
            for step in range(1,n+1):
                now=t if step==n else later-step*dt
                new=[]
                for i,samples in enumerate(stencils):
                    out=[]
                    for j,w in samples:
                        out.append(vals[0] if j==0 else mp.mpf(0) if j==len(grid) else (1-w)*vals[j-1]+w*vals[j])
                    value=discount*(out[0]+4*out[1]+out[2])/6
                    if rights is None and step<n and now>=p['opens']:value=max(value,payoff(grid[i]))
                    new.append(value)
                vals=new
        if t in cash and not(t==T and row['expiry_side']==1) and not(t==0 and row['valuation_side']==2):
            if eligible(t,2):vals=[max(v,payoff(s)) for s,v in zip(grid,vals)]
            mapped=[interp(max(s-cash[t],mp.mpf(0))) for s in grid]
            if eligible(t,1):mapped=[max(v,payoff(s)) for s,v in zip(grid,mapped)]
            vals=mapped
        else:
            phase=0 if t not in cash else 2 if t==0 and row['valuation_side']==2 else 1
            if eligible(t,phase):vals=[max(v,payoff(s)) for s,v in zip(grid,vals)]
        later=t
    return vals[grid.index(p['spot'])]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='piecewise-discrete 1')
    parser.add_argument('--precision',type=int,choices=(80,160),required=True)
    args=parser.parse_args()
    for row in json.loads(Path('docs/evidence/american-piecewise/cases-v1.json').read_text())['rows']:
        v=solve(row,args.precision)
        print(json.dumps(dict(id=row['id'],precision=args.precision,value=None if v is None else mp.nstr(v,args.precision))),flush=True)

if __name__=='__main__':main()
