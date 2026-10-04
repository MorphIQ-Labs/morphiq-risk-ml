#!/usr/bin/env python3
"""Rational checks for the inverse-normal domain, safeguards and error recurrence.

These coarse analytical allowances are not the tighter 4/8-ULP quality gates.
They depend on the qualified forward/DD/elementary component contracts.
"""
import argparse
from fractions import Fraction as F
from pathlib import Path
import re
from kernel_certificates import inverse_sqrt_pi


def verify():
    u=F(1,2**53); inflation=1/(1-100000*u)
    c_lo,c_hi=inverse_sqrt_pi()
    assert F(56,100)<c_lo<c_hi<F(57,100)
    # erf(t)>t on (0,1/2]; erf(y)<2y supplies the other endpoint.
    assert 2*c_lo*F(11,12)>1 and 2*c_hi<2
    # exp(1/4)<4/3, by a geometric majorant of its power series.
    central_a=F(2,3)
    # Derivative >=2c exp(-1/4)>=3c/2. Forward 26u, denominator
    # perturbation <16u, division and subtraction leave generous margin.
    derivative=3*c_lo/2
    central_noise=((32*F(113,100)+16*F(1,2))/derivative
                   +2*(1+F(1,2)/derivative))*inflation
    assert central_noise<128
    assert 26/(1-26*u)<32
    # erfcx(y)>1/64 on [0,28], from the lower Mills inequality.
    assert 2*c_lo/57>F(1,64) and 28**2+2<29**2
    lower_ln2=2*sum((F(1,3)**(2*k+1)/F(2*k+1) for k in range(100)),F(0))
    upper_ln2=lower_ln2+2*F(1,3)**201/(201*(1-F(1,9)))
    assert 1073*upper_ln2<744<28**2 and 6*upper_ln2<5
    # Final DD correction: conservative seed, density and absolute allowances.
    seed=(F(1415,1000)*4100+12)*u
    assert seed<F(1,10**12)
    assert 27*lower_ln2>F('18.00000000001')
    assert c_lo/F('1.415')>F('0.39')>F(1,4)
    assert 4*seed**2+576*u*u*2**29+7*u<8*u
    # Small-exponent scalar-log recombination: the high product is exact,
    # reduced log has its existing 0.14u + final-rounding bound, and the
    # split constant contributes <u/8 even at exponent six.
    scalar_hi=F(float.fromhex('0x1.62e42feep-1'))
    scalar_lo=F(float.fromhex('0x1.a39ef35793c76p-33'))
    assert 6*max(abs(scalar_hi+scalar_lo-lower_ln2),abs(scalar_hi+scalar_lo-upper_ln2))<u/8
    assert (F(114,100)*F(347,1000)+F(35,100)+F(1,8))*inflation<4
    # Residual error <=8u|R|+96u(1+|log f|), so the 128u guard is safe.
    assert 40/(1-40*u)<41
    assert 32*u*744<1
    assert 96/(1-8*u)<128
    # For |e|<=.6, G'<=58 and hence |G(y)-T|<35. The derivative
    # ratio error (<64u), residual and scalar operations fit in 4096u.
    tail_noise=((96*6+8*35)/(2*c_lo)+64*35/(2*c_lo)
                +2*(28+35/(2*c_lo)))*inflation
    assert tail_noise<4096
    assert 1/(2*c_lo)<F(9,10)
    source=(Path(__file__).resolve().parent.parent/'lib/normal.ml').read_text()
    steps=int(re.search(r'let inverse_steps = (\d+)',source).group(1))
    central=F(1,2);tail=F(57,100)
    ideal_central=central;ideal_tail=tail
    for _ in range(steps):
        central=central_a*F(1,2)*central**2+128*u
        tail=F(9,10)*tail**2+4096*u
        ideal_central=central_a*F(1,2)*ideal_central**2
        ideal_tail=F(9,10)*ideal_tail**2
        assert central<F(1,2) and tail<F(3,5)
    assert ideal_central<F(1,2**63) and ideal_tail<F(1,2**60)
    assert central<129*u and tail<4100*u
    return dict(steps=steps,central_error_over_t_u=float(central/u),
                tail_absolute_error_u=float(tail/u),
                central_operation_allowance_u=float(central_noise),
                tail_operation_allowance_u=float(tail_noise))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='inverse_normal_bounds 1')
    p.parse_args()
    for name,value in verify().items():print(name,value)
