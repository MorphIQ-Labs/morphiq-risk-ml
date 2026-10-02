#!/usr/bin/env python3
"""Three-word Greek references, including adjacent inputs around Greek zeros.

The original Greek catalog already cross-checks differentiation. Here every
selected nonzero live value is checked again at 110 and 220 digits; the zero
neighborhoods additionally cross-check differentiation at 110 digits.
"""
import math
import random
import sys
from mpmath import mp
from common import Contract, bits
from gen_greeks import catalog, closed_form, differentiated, GREEKS

def expansion(v):
    m,e=mp.frexp(v) if v else (mp.mpf(0),0)
    h=float(m);l=float(m-h);tail=float(m-h-mp.mpf(l))
    return int(e),bits(h),bits(l),bits(tail)

def cases():
    for i,(c,sigma) in enumerate(catalog(random.Random(20261005))):
        if i%23==0 and c.t>0: yield c,sigma,False
    # Bracket zeros of the exact formulas in log spot (Black) or distance
    # (Bachelier), then exercise the rounded input and its two neighbors.
    for model in ['bsm','bachelier']:
        for greek in ['theta','charm','veta','color','vanna','volga']:
            r,q=(.03,.07) if greek=='theta' else ((.62,.6) if greek=='veta' else (.03,.01))
            sigma=.3
            def contract(x):
                s=mp.exp(x) if model=='bsm' else x
                return Contract(model,True,s,1. if model=='bsm' else 0.,1.,r,q)
            def value(x): return closed_form(contract(x),sigma)[greek]
            with mp.workdps(110):
                previous=mp.mpf(-4); vp=value(previous); roots=[]
                for j in range(-79,81):
                    x=mp.mpf(j)/20;vx=value(x)
                    if vx==0 or vp*vx<0:
                        lo,hi=previous,x
                        for _ in range(220):
                            mid=(lo+hi)/2;vm=value(mid)
                            if vp*vm<=0:hi=mid
                            else:lo=mid;vp=vm
                        roots.append((lo+hi)/2)
                    previous,vp=x,vx
                for x in roots:
                    s=float(contract(x).s)
                    for s in [math.nextafter(s,-math.inf),s,math.nextafter(s,math.inf)]:
                        yield Contract(model,True,s,1. if model=='bsm' else 0.,1.,r,q),sigma,True

def main(path):
    count=0;zeros=0
    with open(path,'w') as w:
        w.write('# model side greek s k t r q sigma shift reference_exponent reference_hi reference_lo reference_tail\n')
        for c,sigma,near_zero in cases():
            extra=c.digits(sigma)
            references=[]
            for precision in [110,220]:
                with mp.workdps(precision+extra):
                    values=closed_form(c,sigma)
                    references.append({g:expansion(v) for g,v in values.items() if v and math.isfinite(float(v)) and float(v)!=0.})
            if references[0]!=references[1]:
                raise ArithmeticError(f'precision disagreement {c.__dict__} {sigma}')
            if near_zero:
                zeros+=1
                with mp.workdps(110+extra):
                    exact=closed_form(c,sigma); independent=differentiated(c,sigma)
                    for g in references[0]:
                        assert abs(exact[g]-independent[g]) <= mp.mpf('1e-70')*max(abs(exact[g]),mp.mpf('1e-40'))
            for greek,ref in references[0].items():
                e,h,l,tail=ref
                inputs=[bits(v) for v in [c.s,c.k,c.t,c.r,c.q,sigma,c.shift]]
                w.write(' '.join([c.model,'call' if c.call else 'put',greek,*inputs,str(e),h,l,tail])+'\n')
                count+=1
    assert zeros>=12
    print(f'{count} extended Greek references; {zeros} zero-neighborhood contracts',file=sys.stderr)

if __name__=='__main__':main(sys.argv[1])
