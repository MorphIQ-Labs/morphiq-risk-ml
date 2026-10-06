"""Precision-refined analytical Greek references, independent price differentiation."""
import argparse
import copy
import json
from pathlib import Path
from american_piecewise_reference import evaluate, number


def analytical(row, dps):
    import mpmath as mp
    mp.mp.dps=dps
    p=row['inputs'];r=copy.deepcopy(row)
    # Proven no-early-exercise call reduction, then differentiate the terminal formula.
    no_early=(r['side']=='call' and not r['cash'] and number(p['yield'])==0
              and all(number(e['level'])==0 for e in r['curves']['yield'])
              and number(p['rate'])>=0 and all(number(e['level'])>=0 for e in r['curves']['rate']))
    if no_early:
        r['inputs']['opens']=p['time'];r['exercise']=[dict(time=p['time'],side=r['expiry_side'])]
    base,method=evaluate(r,dps)
    result={}
    for quantity,key,order in [('delta','spot_shift',1),('gamma','spot_shift',2),('vega','volatility_shift',1),('rho','rate_shift',1),('theta','valuation_roll',1)]:
        reason=None
        if base is None: reason='stochastic early exercise: numerical reference required'
        elif number(p['time'])==0: reason='expiry boundary: explicit separate contract controls'
        elif quantity=='vega' and (number(p['volatility'])==0 or any(number(e['level'])==0 for e in r['curves']['volatility'])): reason='zero volatility boundary'
        elif quantity in ('delta','gamma') and number(p['spot'])==0: reason='zero spot boundary'
        elif quantity=='theta' and (r['cash'] or r['inputs']['opens']!=p['time']): reason='analytical roll not implemented for this stopping regime'
        if reason: result[quantity]=dict(status='unavailable',reason=reason);continue
        def f(z):
            value,_=evaluate(r,dps,**{key:z})
            if value is None:raise ValueError('missing shifted analytical reference')
            return value
        # Finite complex-free step differentiation with extra precision. evaluate
        # must not reset mp precision below mp.diff's working precision.
        def f_precise(z):
            value,_=evaluate(r,mp.mp.dps,**{key:z})
            return value
        value=mp.diff(f_precise,mp.mpf(0),order)
        if quantity=='theta':value/=365
        result[quantity]=dict(status='finite',value=mp.nstr(value,dps),method=method)
    return dict(id=row['id'],precision=dps,greeks=result)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='american-greeks-reference 1')
    p.add_argument('--precision',type=int,choices=(80,160),default=80)
    p.add_argument('--cases',type=Path,default=Path('docs/evidence/american-greeks/cases-v1.json'))
    args=p.parse_args()
    import mpmath as mp
    if mp.__version__!='1.3.0':raise RuntimeError('mpmath 1.3.0 required')
    for row in json.loads(args.cases.read_text())['rows']:
        print(json.dumps(analytical(row,args.precision),allow_nan=False),flush=True)

if __name__=='__main__':main()
