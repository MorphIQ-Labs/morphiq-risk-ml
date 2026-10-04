#!/usr/bin/env python3
"""Exact-rational error bounds for the generated Gaussian-integral polynomials."""
from fractions import Fraction as F
from math import factorial
import erf_coefficients as gen

U=F(1,2**53)
H=1/(1-100000*U)


def verify():
    data=gen.check()
    c_lo,c_hi=gen.constant()
    radius=F(1,8)
    # Complete monotonicity bounds every 17th derivative by its value at 0.
    remainder=max(map(abs,gen.series_coefficients(17)[17]))*radius**17
    local_approx=local_total=F(0)
    for i,row in enumerate(data['local']):
        center=F(2*i+1,8)
        intervals=gen.local_coefficients(center)
        lower=gen.anchor(center+radius)[0]
        assert lower>F(1,25)
        coefficients=[F(x) for x in row]
        coefficients[0]+=F(data['local_low'][i])
        ce=sum((max(abs(a-lo),abs(a-hi))*radius**k for k,(a,(lo,hi)) in enumerate(zip(coefficients,intervals))),F(0))
        # Compensated leading coefficient: at most k+2 roundings per term.
        rounding=U*sum((F(k+2)*abs(a)*radius**k for k,a in enumerate(coefficients)),F(0))*H
        argument=(2*c_hi*radius*U*H) if i==0 else F(0)
        local_approx=max(local_approx,(ce+remainder)/lower)
        local_total=max(local_total,(ce+remainder+rounding+argument)/lower*H)
    assert local_total<6*U
    w=F(1,144)
    exact=gen.tail_coefficients();stored=[F(x) for x in data['tail']]
    next_term=abs(exact[-1])*F(25,2)*w**13
    lower=1-w/2
    ce=sum((abs(a-b)*w**k for k,(a,b) in enumerate(zip(stored,exact))),F(0))
    # w=RN(RN(1/x)^2), relative argument error <=3u+O(u²).
    sensitivity=sum((k*abs(a)*w**k for k,a in enumerate(stored)),F(0))
    horner=sum(((k+1)*abs(a)*w**k for k,a in enumerate(stored)),F(0))
    cs=F(data['inv_sqrt_pi'][0]);constant=max(abs(cs-c_lo),abs(cs-c_hi))/c_lo
    tail_approx=(next_term+ce)/lower+constant
    # Two final operations: c * polynomial / x; include argument and FMA.
    tail_total=(tail_approx+U*((horner+3*sensitivity)/lower+2))*H
    assert tail_total<6*U
    omitted=F(1,2*(2**27)**2)
    asymptote=(constant+U+omitted)/(1-omitted)*H
    v=F(1,4);small=[F(x) for x in data['small']]
    intervals=gen.small_coefficients()
    ce=sum((max(abs(a-lo),abs(a-hi))*v**k for k,(a,(lo,hi)) in enumerate(zip(small,intervals))),F(0))
    remainder=2*c_hi*v**14/F(factorial(14)*29)
    # coefficient k: k uses of squared-argument error, k+1 FMA errors,
    # and the final product. We conservatively charge 2k+2 in total.
    rounding=U*sum(((2*k+2)*abs(a)*v**k for k,a in enumerate(small)),F(0))*H
    erf_total=(ce+remainder+rounding)/(2*c_lo*(1-v))*H
    assert erf_total<26*U
    return dict(erfcx_local_approx=local_approx,erfcx_local_total=local_total,
                erfcx_tail_approx=tail_approx,erfcx_tail_total=tail_total,
                erfcx_asymptote_total=asymptote,erf_small_total=erf_total)


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='erf_certificates 1')
    parser.parse_args()
    for name,value in verify().items():print(name, float(value/U),'u')
