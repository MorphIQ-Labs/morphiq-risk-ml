#!/usr/bin/env python3
"""Optional exhaustive interval audit of committed price and smooth Greek references.

Arb erfc-based prices and formal price-series derivatives are independent of
mpmath refinement and the OCaml elementary/normal arithmetic. Boundary Greeks
are reported as excluded from the analytic series scope, not passed.
"""
import argparse
from collections import Counter
import io
from fixture_catalog import verified_text
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import struct
import time
from flint import arb, ctx, __FLINT_VERSION__
from arb_greek_audit import derivative
from arb_iv_audit import price as positive_price


def word(x):
    return struct.unpack('>d',bytes.fromhex(x.zfill(16)))[0]


def price(model,side,inputs):
    s,k,t,r,q,sigma,shift=map(arb,inputs)
    theta=1 if side=='call' else -1
    if inputs[2] == 0:
        x=theta*(s-k)
        return (x+abs(x))/2
    if inputs[5] == 0:
        if model=='displaced': s,k=s+shift,k+shift
        if model!='bsm' or inputs[3]==inputs[4]:
            x=theta*(s-k)*(-r*t).exp()
        else:
            x=theta*(s*(-q*t).exp()-k*(-r*t).exp())
        return (x+abs(x))/2
    return positive_price(model,side,[*inputs,0.],sigma)


def cell(reference):
    q=arb(reference)
    if reference == math.inf or reference == -math.inf:
        raise ValueError('infinite cell handled separately')
    previous=math.nextafter(reference,-math.inf)
    following=math.nextafter(reference,math.inf)
    lower=(arb(previous)+q)/2 if math.isfinite(previous) else q-arb(2)**970
    upper=(arb(following)+q)/2 if math.isfinite(following) else q+arb(2)**970
    even=struct.unpack('>Q',struct.pack('>d',reference))[0]&1 == 0
    return lower,upper,even


def classify(value,reference):
    if math.isinf(reference):
        threshold=arb(float.fromhex('0x1.fffffffffffffp+1023'))+arb(2)**970
        value=value if reference>0 else -value
        if value >= threshold: return 'certified'
        if value < threshold: return 'wrong'
        return 'unresolved'
    lower,upper,even=cell(reference)
    if (value>lower or (even and value==lower)) and (value<upper or (even and value==upper)):
        return 'certified'
    if value<lower or value>upper or (not even and (value==lower or value==upper)):
        return 'wrong'
    return 'unresolved'


def positive_tail(model,side,inputs):
    # Independent interval argument; no import from the rational oracle helper.
    if inputs[2] <= 0 or inputs[5] <= 0 or inputs[3] != 0 or (model=='bsm' and inputs[4] != 0):
        return None
    s,k,t,_r,_q,sigma,shift=map(arb,inputs)
    if model=='displaced': s,k=s+shift,k+shift
    total=sigma*t.sqrt()
    delta=(1 if side=='call' else -1)*(s-k)
    if delta>=0: intrinsic=delta
    elif delta<0: intrinsic=arb(0)
    else: return None
    phi40=arb(-800).exp()/(2*arb.pi()).sqrt()
    if model=='bachelier':
        if not abs(s-k)/total >= 40: return None
        bound=total*phi40
    else:
        if not (s>0 and k>0): return None
        z=abs((s/k).log())/total-total/2
        if not z>=40: return None
        if s<=k: small=s
        elif k<s: small=k
        else: return None
        bound=small*phi40/40
    return intrinsic,bound


def classify_positive_tail(bracket,reference):
    if bracket is None or not math.isfinite(reference): return 'unresolved'
    intrinsic,bound=bracket
    lower,upper,_=cell(reference)
    if intrinsic>=upper or intrinsic+bound<=lower: return 'wrong'
    if intrinsic>=lower and bound<=upper-intrinsic: return 'certified'
    return 'unresolved'


def controls():
    with ctx.workprec(256):
        midpoint=arb(1)+arb(2)**-53
        if not (classify(midpoint,1.)=='certified'):
            raise ArithmeticError('rounding/uncertainty control failed')
        if not (classify(midpoint,math.nextafter(1.,math.inf))=='wrong'):
            raise ArithmeticError('rounding/uncertainty control failed')
        if not (classify(arb(2)**-1075,0.)=='certified'):
            raise ArithmeticError('rounding/uncertainty control failed')
        if not (classify(arb(2)**-1075,2.**-1074)=='wrong'):
            raise ArithmeticError('rounding/uncertainty control failed')
        if not (classify(arb(1,arb(2)**-40),1.)=='unresolved'):
            raise ArithmeticError('rounding/uncertainty control failed')
        inputs=[math.nextafter(1.,math.inf),2.**-53,1.,0.,0.,1e-4,0.]
        for model in ('bsm','black76','displaced','bachelier'):
            bracket=positive_tail(model,'call',inputs)
            if not (classify_positive_tail(bracket,1.)=='wrong'):
                raise ArithmeticError('rounding/uncertainty control failed')
            if not (classify_positive_tail(bracket,math.nextafter(1.,math.inf))=='certified'):
                raise ArithmeticError('rounding/uncertainty control failed')


def audit(evaluate,reference,tail=None):
    if math.isnan(reference): return 'unresolved',None,'nonfinite reference','interval'
    for precision in (256,512,1024,2048,4096):
        with ctx.workprec(precision):
            value=evaluate()
            status=classify(value,reference)
            if status!='unresolved': return status,precision,str(value),'interval'
            if tail is not None:
                bracket=tail()
                status=classify_positive_tail(bracket,reference)
                if status!='unresolved':
                    return status,precision,f'{bracket[0]} < price < intrinsic + {bracket[1]}','positive_time_value'
    return 'unresolved',4096,str(value),'interval'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--fixtures',type=Path,default=Path('oracle/fixtures'))
    args=parser.parse_args()
    controls()
    reports={}; discrepancies=[]; unresolved=[]; one_sided=[]; control=False
    paths=[args.fixtures/(name+'.txt.gz') for name in ('european','displaced','greeks')]
    started=time.monotonic()
    for path in paths:
        counts,precisions,exclusions=Counter(),Counter(),Counter()
        with io.StringIO(verified_text(path, names=('european', 'displaced', 'greeks'))) as stream:
            for index,line in enumerate(stream,1):
                if not line.strip() or line.startswith('#'): continue
                f=line.split();model,side=f[:2]
                inputs=list(map(word,f[4:11]));reference=word(f[11])
                counts['total']+=1
                if path.stem.startswith('greeks'):
                    if inputs[2] <= 0 or inputs[5] <= 0:
                        exclusions['boundary/'+f[3]]+=1
                        continue
                    evaluate=lambda: derivative(model,side,inputs,f[2])
                    tail=None
                else:
                    evaluate=lambda: price(model,side,inputs)
                    tail=lambda: positive_tail(model,side,inputs)
                status,precision,value,method=audit(evaluate,reference,tail)
                counts[status]+=1
                if precision is not None: precisions[precision]+=1
                record=dict(fixture=path.name,line=index,input=line.strip(),precision=precision,interval=value,method=method)
                if method=='positive_time_value': one_sided.append(record)
                if status=='wrong': discrepancies.append(record)
                elif status=='unresolved': unresolved.append(record)
                elif not control and reference != 0 and math.isfinite(reference):
                    wrong,_,_,_=audit(evaluate,math.nextafter(reference,math.inf),tail)
                    if wrong!='wrong': raise ArithmeticError('adjacent wrong reference control failed')
                    control=True
        if counts['total'] != counts['certified']+counts['wrong']+counts['unresolved']+sum(exclusions.values()):
            raise ArithmeticError('incomplete outcome accounting')
        reports[path.name]=dict(counts=counts,precision_counts=precisions,exclusions=exclusions)
        print(path.name,json.dumps(reports[path.name]),flush=True)
    sources=paths+[Path(__file__).with_name('fixture_catalog.py'),Path(__file__),Path('scripts/arb_greek_audit.py'),Path('scripts/arb_iv_audit.py')]
    report=dict(method='Independent Arb exact-reference rounding cells; erfc prices and formal price-series Greeks',
                python_flint=importlib.metadata.version('python-flint'),flint=__FLINT_VERSION__,
                source_sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
                datasets=reports,discrepancies=discrepancies,unresolved=unresolved,one_sided_certificates=one_sided,
                exact_rounding_and_one_sided_controls=True,
                adjacent_wrong_reference_rejected=control,elapsed_seconds=time.monotonic()-started,
                scope='Finite committed corpus audit, with boundary Greeks excluded explicitly. Zero cells certify the real rounded number, not an extra signed-zero convention. No human-review or production-availability claim.')
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    if discrepancies or unresolved or not control: raise SystemExit(1)


if __name__=='__main__': main()
