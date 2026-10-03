"""Exact one-sided rounding for tiny positive time value at intrinsic midpoints.

Only rational inequalities enter acceptance; no measured numerical envelope or
mpmath precision agreement is a premise. See docs/oracle-midpoint-rounding.md.
"""
from fractions import Fraction as F
import math


def power2(n):
    return F(1 << n) if n >= 0 else F(1, 1 << -n)


# Positive atanh series plus its geometric tail: rigorous ln(2) upper bound.
z = F(1, 3)
log2_upper = 2*(z + z**3/3) + 2*z**5/(5*(1-z*z))
assert log2_upper < F(7, 10) and 1100*log2_upper < 800


def positive_tail_bound(c, sigma):
    if (c.model not in ('bsm','black76','displaced','bachelier') or
        not all(math.isfinite(x) for x in (c.s,c.k,c.t,c.r,c.q,c.shift,sigma)) or
        c.t <= 0 or sigma <= 0 or c.r != 0 or (c.model == 'bsm' and c.q != 0)):
        return None
    s,k = F(c.s),F(c.k)
    if c.model == 'displaced':
        s,k = s+F(c.shift),k+F(c.shift)
    intrinsic = max((1 if c.call else -1)*(s-k), F(0))
    exponent = math.frexp(c.t)[1]
    total_upper = F(sigma)*power2((exponent+1)//2)
    if c.model == 'bachelier':
        if abs(s-k) < 40*total_upper: return None
        bound = total_upper*power2(-1100)
    else:
        if min(s,k) <= 0: return None
        log_lower = 2*abs(s-k)/(s+k)
        if log_lower < 40*total_upper + total_upper**2/2: return None
        bound = min(s,k)*power2(-1100)
    return intrinsic,bound


def endpoints(candidate):
    if not math.isfinite(candidate): return None
    before,after = math.nextafter(candidate,-math.inf),math.nextafter(candidate,math.inf)
    if not (math.isfinite(before) and math.isfinite(after)): return None
    return (F(before)+F(candidate))/2, (F(candidate)+F(after))/2


def tiny_time_value_rounding(c, sigma):
    bracket = positive_tail_bound(c,sigma)
    if bracket is None: return None
    intrinsic,bound = bracket
    try: candidate = float(intrinsic)
    except OverflowError: return None
    cell = endpoints(candidate)
    if cell is None: return None
    if intrinsic == cell[1]:
        candidate = math.nextafter(candidate,math.inf)
        cell = endpoints(candidate)
        if cell is None: return None
    if intrinsic >= cell[0] and intrinsic+bound <= cell[1]:
        return candidate
    return None


def price_reference(c, sigma, refine):
    """Use the exact tail proof where it decides; retain the caller's fallback."""
    certified = tiny_time_value_rounding(c, sigma)
    return refine() if certified is None else certified
