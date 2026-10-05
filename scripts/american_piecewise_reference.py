"""Original piecewise-model reference helpers; original binary64 inputs are exact."""
import argparse
import json
import struct
from pathlib import Path


def number(word):
    return struct.unpack('>d', bytes.fromhex(word))[0]


def protocol(row, n):
    p = row['inputs']
    fields = [row['id'], row['side'], str(n), '0']
    fields += [p[k] for k in ('spot', 'strike', 'rate', 'yield', 'volatility', 'time', 'opens')]
    fields += [str(row[k + '_side']) for k in ('valuation', 'opening', 'expiry')]
    fields += [str(len(row['cash']))]
    fields += [v for e in row['cash'] for v in (e['time'], e['amount'])]
    rights = row['exercise'] or []
    sections = [' '.join(fields), ' '.join([str(len(rights))] + [v for e in rights for v in (e['time'], str(e['side']))])]
    for name in ('rate', 'yield', 'volatility'):
        changes = row['curves'][name]
        sections.append(' '.join([str(len(changes))] + [v for e in changes for v in (e['time'], e['level'])]))
    return ' | '.join(sections)


def evaluate(row, dps):
    import mpmath as mp
    mp.mp.dps = dps
    def exact(w):
        n, d = number(w).as_integer_ratio()
        return mp.mpf(n) / d
    p = {k: exact(v) for k, v in row['inputs'].items()}
    curves = {k: [(mp.mpf(0), p[k])] + [(exact(e['time']), exact(e['level'])) for e in row['curves'][k]] for k in ('rate', 'yield', 'volatility')}
    cash = {}
    for e in row['cash']:
        t = exact(e['time']); cash[t] = cash.get(t, mp.mpf(0)) + exact(e['amount'])
    rights = None if row['exercise'] is None else [(exact(e['time']), e['side']) for e in row['exercise']]
    T, opening = p['time'], p['opens']
    def level(k, t):
        return next(a for u, a in reversed(curves[k]) if u <= t)
    def integral(k, lo, hi, power=1):
        ts = [lo] + [t for t, _ in curves[k] if lo < t < hi] + [hi]
        return mp.fsum((b-a)*level(k,a)**power for a,b in zip(ts,ts[1:]))
    def permitted(t, side):
        if rights is not None:
            return (t,side) in rights
        return (t,side) >= (opening,row['opening_side']) and (t,side) <= (T,row['expiry_side'])
    def payoff(s):
        return max((s-p['strike']) if row['side']=='call' else (p['strike']-s),mp.mpf(0))
    times = sorted({mp.mpf(0), opening, T, *cash, *(t for c in curves.values() for t,_ in c), *(t for t,_ in (rights or []))})
    if T == 0:
        s=p['spot']; best=payoff(s) if permitted(0,row['valuation_side']) else mp.mpf(0)
        if row['valuation_side']==1 and row['expiry_side']==2:
            s=max(s-cash.get(T,0),mp.mpf(0))
            if permitted(T,2):best=max(best,payoff(s))
        return best, 'expiry'
    if p['spot']==0 or (p['strike']==0 and not cash):
        if row['side']=='call' and p['spot']==0 or row['side']=='put' and p['strike']==0:
            return mp.mpf(0), 'absorbing'
        k='rate' if row['side']=='put' else 'yield'
        candidates=[t for t,_ in rights] if rights else [opening,T]+[t for t,_ in curves[k] if t>=opening]
        factor=p['strike'] if row['side']=='put' else p['spot']
        return factor*max(mp.exp(-integral(k,0,t)) for t in candidates), 'discount optimum'
    if all(a==0 for _,a in curves['volatility']):
        s=p['spot']; best=mp.mpf(0)
        for i,t in enumerate(times):
            if i:
                a=times[i-1]; r=level('rate',a);q=level('yield',a)
                if rights is None and s!=0 and r!=q and q!=0 and r*p['strike']/(q*s)>0:
                    u=mp.log(r*p['strike']/(q*s))/(r-q)
                    if 0<u<t-a and a+u>=opening:
                        best=max(best,mp.exp(-integral('rate',0,a+u))*payoff(s*mp.exp((r-q)*u)))
                s*=mp.exp(integral('rate',a,t)-integral('yield',a,t))
            discount=mp.exp(-integral('rate',0,t))
            phase=1 if t in cash else 0
            if t==0 and row['valuation_side']==2:phase=2
            if permitted(t,phase):best=max(best,discount*payoff(s))
            if t in cash and not (t==0 and row['valuation_side']==2) and not (t==T and row['expiry_side']==1):
                s=max(s-cash[t],mp.mpf(0))
                if permitted(t,2):best=max(best,discount*payoff(s))
        return best,'deterministic trajectory'
    if opening==T and not cash:
        R=integral('rate',0,T);Q=integral('yield',0,T);A=integral('volatility',0,T,2)
        X=p['spot']*mp.exp(-Q);Y=p['strike']*mp.exp(-R)
        d1=(mp.log(X/Y)+A/2)/mp.sqrt(A);d2=d1-mp.sqrt(A)
        cdf=lambda x:mp.erfc(-x/mp.sqrt(2))/2
        return (X*cdf(d1)-Y*cdf(d2) if row['side']=='call' else Y*cdf(-d2)-X*cdf(-d1)), 'integrated European'
    return None, 'stochastic early exercise: use discrete refinement'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version',version='piecewise-reference 1')
    parser.add_argument('--cases',type=Path,default=Path('docs/evidence/american-piecewise/cases-v1.json'))
    parser.add_argument('--protocol',type=int)
    parser.add_argument('--precision',type=int,choices=(80,160),default=80)
    args=parser.parse_args()
    rows=json.loads(args.cases.read_text())['rows']
    for row in rows:
        if args.protocol:
            print(protocol(row,args.protocol))
        else:
            import mpmath as mp
            v,method=evaluate(row,args.precision)
            print(json.dumps(dict(id=row['id'],precision=args.precision,value=None if v is None else mp.nstr(v,args.precision),method=method)))

if __name__=='__main__':main()
