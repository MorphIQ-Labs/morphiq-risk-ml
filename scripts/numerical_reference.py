"""Independent bounded reference construction; optional pinned Arb/mpmath lane."""
from fractions import Fraction as F
import math
from pathlib import Path
import sys
from flint import arb, ctx
from numerical_cases import bits, word
from arb_reference_campaign import price, positive_tail, classify, classify_positive_tail
from arb_greek_audit import derivative
from arb_iv_audit import certify as certify_iv

PRECISIONS = (256,512,1024,2048,4096)
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'oracle'))
from common import Contract
from gen_iv import root_word
from price_rounding import tiny_time_value_rounding


def unpack(row): return {k:word(v) for k,v in row['inputs'].items()}


def admitted(row, v):
    fields=['s','k','t','r']
    if row['model']=='bsm': fields.append('q')
    if row['model']=='displaced': fields.append('shift')
    if not all(math.isfinite(v[k]) for k in fields) or v['t']<0: return False
    if row['model'] in ('bsm','black76') and min(v['s'],v['k'])<=0: return False
    if row['model']=='displaced' and v['t']>0:
        for key in ('s','k'):
            value=F(v[key])+F(v['shift'])
            if value<=0: return False
            try:
                if not math.isfinite(float(value)): return False
            except OverflowError: return False
    if row['quantity']=='iv': return math.isfinite(v['quote']) and v['quote']>=0
    return math.isfinite(v['sigma']) and v['sigma']>=0


def exact_interval(value):
    text=str(value)
    return dict(status='interval', lower=text, upper=text, precision=0, method='exact rational identity')


def dyadic(value):
    # Bound serialization rather than allocating integers with astronomical
    # exponents. Such references remain unresolved and retain their inputs.
    mantissa, exponent = value.man_exp()
    exponent=int(exponent)
    if abs(exponent)>20000: raise ArithmeticError('reference serialization exponent limit')
    return F(int(mantissa))*(F(2)**exponent)


def interval(value, precision):
    if not value.is_finite(): raise ArithmeticError('nonfinite Arb enclosure')
    if value.is_exact():
        lower=upper=dyadic(value)
    elif abs(value)<arb(2)**-4096:
        lower,upper=-F(1,2**4096),F(1,2**4096)
    else: lower,upper=dyadic(value.lower()),dyadic(value.upper())
    return dict(status='interval',lower=str(lower),upper=str(upper),precision=precision,method='Arb enclosure')


def boundary_greek(row,v):
    name=row['quantity']; model=row['model']; th=1 if row['side']=='call' else -1
    s,k,t,r,q,shift=map(arb,[v['s'],v['k'],v['t'],v['r'],v['q'],v['shift']])
    if model!='bsm': q=r
    if v['t']==0:
        if v['s']==v['k']:
            return arb(0) if name in ('vega','rho','volga') else 'payoff_kink'
        itm=th*(F(v['s'])-F(v['k']))>0
        if not itm: return arb(0)
        if name=='delta': return arb(th)
        if name=='theta': return th*(q*s-r*k)/365
        if name=='charm': return th*q/365
        return arb(0)
    if model=='displaced': s,k=s+shift,k+shift
    a=s*(-q*t).exp(); cash=k*(-r*t).exp()
    difference=th*(a-cash)
    if v['s']==v['k'] and (model!='bsm' or v['r']==v['q']): difference=arb(0)
    if difference==0:
        if name in ('delta','gamma','vanna','charm','color'): return 'payoff_kink'
        if name=='rho': return 'payoff_kink' if model=='bsm' else arb(0)
        if name in ('theta','volga'): return arb(0)
        weight=arb(1) if model=='bachelier' else s
        coefficient=weight*(-r*t).exp()/(2*arb.pi()).sqrt()
        if name=='vega': return coefficient*t.sqrt()
        if name=='veta': return coefficient*(r*t-arb(1)/2)/(365*t.sqrt())
    if difference<0: return arb(0)
    if not difference>0: return None
    delta=th*(-q*t).exp()
    if name=='delta': return delta
    if name=='rho': return th*k*t*(-r*t).exp() if model=='bsm' else -t*difference
    if name=='theta': return th*(q*a-r*cash)/365
    if name=='charm': return q*delta/365
    return arb(0)


def fill_quote(row):
    if not row['region'].startswith('iv_cell_'): return
    v=unpack(row)
    with ctx.workprec(256):
        sigma=(arb(v['sigma'])+arb(math.nextafter(v['sigma'],-math.inf)))/2
        inputs=[v[k] for k in ('s','k','t','r','q','sigma','shift')]
        inputs[5]=sigma
        value=price(row['model'],row['side'],inputs)
        quote=float(value.mid())
        if classify(value,quote)!='certified': raise ArithmeticError('unresolved midpoint-derived quote')
        step=int(row['region'].rsplit('_',1)[1])
        if step: quote=math.nextafter(quote, math.inf if step>0 else -math.inf)
        row['inputs']['quote']=bits(quote)


def inverse(row,v):
    if v['t']==0: return dict(status='class',expected='expiry',method='expiry identity')
    if v['r']!=0 or (row['model']=='bsm' and v['q']!=0):
        return dict(status='unresolved',reason='nonzero-rate inverse boundary outside rational scope')
    th=1 if row['side']=='call' else -1
    intrinsic=max(th*(F(v['s'])-F(v['k'])),F(0)); quote=F(v['quote'])
    if row['model']!='bachelier':
        maximum=F(v['s'] if th>0 else v['k'])
        if row['model']=='displaced': maximum+=F(v['shift'])
        if quote>=maximum: return dict(status='class',expected='above_maximum',method='exact supremum comparison')
    if quote==intrinsic or (quote<intrinsic and float(intrinsic)==v['quote']):
        return dict(status='root',word=bits(0.),precision=0,method='exact intrinsic/rounded-bound convention')
    if quote<intrinsic: return dict(status='class',expected='below_intrinsic',method='exact intrinsic comparison')
    if row['model']=='bachelier':
        inputs=[v[k] for k in ('s','k','t','r','q','sigma','shift')]
        for precision in PRECISIONS:
            with ctx.workprec(precision):
                inputs[5]=2.**-1074
                if price(row['model'],row['side'],inputs)>arb(v['quote']):
                    return dict(status='class',expected='below_smallest',precision=precision,method='independent smallest-volatility price comparison')
                inputs[5]=float.fromhex('0x1.fffffffffffffp+1023')
                if price(row['model'],row['side'],inputs)<arb(v['quote']):
                    return dict(status='class',expected='above_maximum',precision=precision,method='independent largest-volatility price comparison')
                break
    c=Contract(row['model'],th>0,v['s'],v['k'],v['t'],v['r'],v['q'],v['shift'])
    root=root_word(c,v['quote'],0)
    if root is None or not math.isfinite(root) or root<=0:
        return dict(status='unresolved',reason='bounded independent root proposal unavailable')
    inputs=[v[k] for k in ('s','k','t','r','q','sigma','shift','quote')]
    precision=certify_iv(row['model'],row['side'],inputs,root)
    if precision is None: return dict(status='unresolved',reason='independent root cell undecided')
    return dict(status='root',word=bits(root),precision=precision,method='mpmath proposal independently certified by Arb residual signs')


def reference(row):
    v=unpack(row); model=row['model']; quantity=row['quantity']
    if model=='primitive':
        if row['mode']=='enclosure': return exact_interval(F(v['s'])+F(v['k']))
        midpoint=(F(v['s'])+F(v['k']))/2
        return dict(status='root',word=bits(float(midpoint)),precision=0,method='exact rational midpoint ties-to-even')
    if not admitted(row,v): return dict(status='class',expected='invalid_input',method='original-input admission contract')
    if row['mode']=='production' and quantity!='iv':
        if not math.isfinite(v['limit']) or v['limit']<0:
            return dict(status='class',expected='invalid_accuracy',method='accuracy input contract')
        if quantity!='price' and v['t']==0:
            return dict(status='class',expected='unsupported_expiry',method='declared production exclusion')
        if quantity!='price' and v['sigma']==0:
            return dict(status='class',expected='unsupported_zero_variance',method='declared production exclusion')
    if quantity=='iv': return inverse(row,v)
    inputs=[v[k] for k in ('s','k','t','r','q','sigma','shift')]
    if quantity=='price' and v['t']==0:
        th=1 if row['side']=='call' else -1
        return exact_interval(max(th*(F(v['s'])-F(v['k'])),F(0)))
    if abs(F(v['r'])*F(v['t']))>4096 or (model=='bsm' and abs(F(v['q'])*F(v['t']))>4096):
        return dict(status='unresolved',reason='reference exponential argument resource limit')
    last=None
    for precision in PRECISIONS:
        with ctx.workprec(precision):
            if quantity=='price': value=price(model,row['side'],inputs)
            elif v['t']==0 or v['sigma']==0: value=boundary_greek(row,v)
            else: value=derivative(model,row['side'],inputs,quantity)
            if value is None: continue
            if isinstance(value,str): return dict(status='class',expected=value,method='coordinate boundary identity')
            last=interval(value,precision)
            try: rounded=float(value.mid())
            except OverflowError: rounded=math.copysign(math.inf,float(value.sgn()))
            if math.isfinite(rounded) and classify(value,rounded)=='certified':
                last['rounded']=bits(rounded)
            elif quantity=='price':
                c=Contract(model,row['side']=='call',v['s'],v['k'],v['t'],v['r'],v['q'],v['shift'])
                rounded=tiny_time_value_rounding(c,v['sigma'])
                if rounded is not None and classify_positive_tail(positive_tail(model,row['side'],inputs),rounded)=='certified':
                    last['rounded']=bits(rounded)
                    last['rounding_method']='independent rational and Arb one-sided tails'
            width=F(last['upper'])-F(last['lower'])
            scale=max(abs(F(last['upper'])),abs(F(last['lower'])),F(1,2**1074))
            if width<=scale*F(1,2**180) and ('rounded' in last or row['mode']=='production'):
                return last
    return last or dict(status='unresolved',reason='bounded reference escalation inconclusive')
