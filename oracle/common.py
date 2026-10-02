"""Shared definitions for this project's oracle generators.

Each model is written directly from its definition (docs/model-contracts.md)
in mpmath, independently of the library's algorithms. A reference value is
accepted when two consecutive working precisions (escalating from 60 to 960
digits) round it to the same binary64.
"""
import math
import struct

import mpmath
from mpmath import mp, mpf



def bits(x):
    return struct.pack(">d", x).hex()


def word(h):
    return struct.unpack(">d", bytes.fromhex(h))[0]


def round_binary64(v):
    """Nearest binary64, ties to even, subnormals exact."""
    if v == 0:
        return 0.0
    sign, man, e, bc = v._mpf_
    top = e + bc - 1
    if top >= 1024:
        return -math.inf if sign else math.inf
    if top < -1076:
        return -0.0 if sign else 0.0
    quantum = max(top - 52, -1074)
    shift = quantum - e
    if shift <= 0:
        n = int(man) << (-shift)
    else:
        n, rem = int(man) >> shift, int(man) & ((1 << shift) - 1)
        half = 1 << (shift - 1)
        if rem > half or (rem == half and n & 1):
            n += 1
    r = math.ldexp(float(n), quantum)
    return -r if sign else r


def agreed(f, extra_digits=0):
    """f() refined from 60 + extra_digits, doubling, until two consecutive
    precisions round to the same binary64. Returns that value, or None.

    Agreement alone cannot catch an error both precisions share. A
    difference below both precisions can make both compute exactly 0. So the
    starting precision is raised by the contract's decades of smallness
    (extra_digits; see Contract.digits), and an agreed zero is accepted only
    once it has survived to at least 480 digits."""
    previous = None
    dps = 60 + extra_digits
    for _ in range(6):
        with mp.workdps(dps):
            current = round_binary64(mpf(f()))
        if previous is not None and bits(previous) == bits(current):
            if current != 0 or dps >= 480:
                return current
        previous = current
        dps *= 2
    return None


def ncdf(z):
    """Φ(z). Past |z| = 1e4, mpmath's erfc cannot run its own series check
    (it overflows a float), so the tail is the asymptotic series
    φ(z)/|z| Σ (-1)^k (2k-1)!!/z^(2k). Its terms fall by 1/z^2 <= 1e-8 each,
    so 40 terms are far below any working precision. mpmath's exponential has
    no exponent range, so φ(z) is exact even where it is 10^-(10^580)."""
    z = mpf(z)
    if abs(z) <= 10000:
        return mpmath.ncdf(z)
    w = abs(z)
    term, total = mpf(1), mpf(1)
    for k in range(1, 40):
        term *= -(2 * k - 1) / (w * w)
        total += term
    tail = mpmath.exp(-w * w / 2) / mpmath.sqrt(2 * mpmath.pi) / w * total
    return tail if z < 0 else 1 - tail


class Contract:
    """A European contract under one model, with exact inputs.

    model: bsm | black76 | displaced | bachelier
    Black family: s is the spot (bsm) or forward; q is used by bsm only;
    shift is displaced Black's d. Bachelier: s is the forward.
    """

    def __init__(self, model, call, s, k, t, r, q=0.0, shift=0.0):
        self.model, self.call = model, call
        self.s, self.k, self.t, self.r, self.q, self.shift = s, k, t, r, q, shift
        self.theta = 1 if call else -1

    def legs(self):
        """Discounted forward and strike legs (A, C) at the current precision."""
        t, r = mpf(self.t), mpf(self.r)
        disc = mpmath.exp(-r * t)
        if self.model == "bachelier":
            return mpf(self.s) * disc, mpf(self.k) * disc
        s, k = mpf(self.s) + mpf(self.shift), mpf(self.k) + mpf(self.shift)
        q = mpf(self.q) if self.model == "bsm" else r
        return s * mpmath.exp(-q * t), k * disc

    def price(self, sigma, t=None, r=None, s=None):
        """The model price at volatility sigma; t, r, s override the inputs."""
        t = mpf(self.t if t is None else t)
        r = mpf(self.r if r is None else r)
        s = mpf(self.s if s is None else s)
        k = mpf(self.k)
        sigma = mpf(sigma)
        th = self.theta
        if t == 0:
            return max(th * (s - k), mpf(0))
        disc = mpmath.exp(-r * t)
        if self.model == "bachelier":
            sd = sigma * mpmath.sqrt(t)
            dist = th * (s - k)
            if sd == 0:
                return disc * max(dist, mpf(0))
            d = dist / sd
            return disc * (dist * ncdf(d) + sd * mpmath.npdf(d))
        s, k = s + mpf(self.shift), k + mpf(self.shift)
        q = mpf(self.q) if self.model == "bsm" else r
        # x = ln(A/C) from its exact parts: ln(S/K) is exactly 0 at the money
        # and (r - q)T is an exact product, so x keeps its full relative
        # precision however small it is.
        x = mpmath.log(s / k) + (r - q) * t
        a, c = s * mpmath.exp(-q * t), k * disc
        if sigma == 0:
            # A - C = C (e^x - 1): exact in relative terms at any precision.
            return max(th * c * mpmath.expm1(x), mpf(0))
        sd = sigma * mpmath.sqrt(t)
        d1 = x / sd + sd / 2
        return th * (a * ncdf(th * d1) - c * ncdf(th * (d1 - sd)))

    def digits(self, sigma):
        """Decimal digits a cancellation in this contract can reach, so the
        first working precision already exceeds it:
        - decades(|x|), with x = ln(A/C), for the legs A and C cancelling
          (x is tiny at the forward, or when T is tiny);
        - plus decades(σ√T) near the money in σ units (|x| < 40 σ√T), where
          Φ(d1) and Φ(d2) cancel. Further out the analytic tail bound or the
          intrinsic dominates, so σ√T's smallness costs no digits."""
        def decades(v):
            return 0 if v == 0 or v >= 1 else int(-math.log10(v)) + 1
        if self.t == 0:
            return 0
        if self.model == "bachelier":
            dist = abs(self.s - self.k)
            scale = max(abs(self.s), abs(self.k), 1e-300)
            sd = sigma * math.sqrt(self.t)
            extra = decades(dist / scale) if dist else 0
            return extra + (decades(sd / scale) if sd > 0 and dist < 40 * sd else 0)
        with mp.workdps(40):
            s, k = mpf(self.s) + mpf(self.shift), mpf(self.k) + mpf(self.shift)
            q = mpf(self.q) if self.model == "bsm" else mpf(self.r)
            x = abs(float(mpmath.log(s / k) + (mpf(self.r) - q) * mpf(self.t)))
        sd = sigma * math.sqrt(self.t)
        extra = decades(x) if x else 0
        if sd > 0 and x < 40 * sd:
            extra += decades(sd)
        return extra

    def below_binary64(self, sigma):
        """True if an analytic upper bound puts the value below 2^-1100, so it
        rounds to 0 with no refinement. Out of the money, with z the tail
        argument (d1 for a call, -d2 for a put) at z < -30:
        value <= leg Φ(z) <= leg φ(z)/|z| (FerroRisk's oracle uses the same
        bound). Bachelier: value <= D s φ(d)."""
        if sigma == 0 or self.t == 0:
            return False
        with mp.workdps(30):
            t, r = mpf(self.t), mpf(self.r)
            sd = mpf(sigma) * mpmath.sqrt(t)
            if self.model == "bachelier":
                dist = self.theta * (mpf(self.s) - mpf(self.k))
                if dist >= 0:
                    return False
                d = abs(dist) / sd
                if d < 30:
                    return False
                log_bound = mpmath.log(mpmath.exp(-r * t) * sd) - d * d / 2
            else:
                s, k = mpf(self.s) + mpf(self.shift), mpf(self.k) + mpf(self.shift)
                q = mpf(self.q) if self.model == "bsm" else r
                x = mpmath.log(s / k) + (r - q) * t
                if self.theta * x > 0:
                    return False
                d1 = x / sd + sd / 2
                z = d1 if self.call else -(d1 - sd)
                if z > -30:
                    return False
                leg = s * mpmath.exp(-q * t) if self.call else k * mpmath.exp(-r * t)
                log_bound = mpmath.log(leg) - z * z / 2 - mpmath.log(-z)
            return log_bound / mpmath.log(2) < -1100

    def intrinsic(self):
        """The discounted zero-volatility price, before flooring at 0."""
        if self.model == "bachelier":
            a, c = self.legs()
            return self.theta * (a - c)
        t, r = mpf(self.t), mpf(self.r)
        s, k = mpf(self.s) + mpf(self.shift), mpf(self.k) + mpf(self.shift)
        q = mpf(self.q) if self.model == "bsm" else r
        x = mpmath.log(s / k) + (r - q) * t
        return self.theta * k * mpmath.exp(-r * t) * mpmath.expm1(x)

    def maximum(self):
        """The price as volatility goes to infinity (None for Bachelier)."""
        if self.model == "bachelier":
            return None
        a, c = self.legs()
        return a if self.call else c

    def fields(self):
        return [self.s, self.k, self.t, self.r, self.q, self.shift]


def region(contract, sigma, value):
    """FerroRisk #440's regions, from the exact contract."""
    if sigma == 0:
        return "zero_variance"
    if contract.model in ("bsm", "black76") and not 1e-100 <= contract.k <= 1e100:
        return "extreme_scale"
    with mp.workdps(40):
        a, c = contract.legs()
        intrinsic = contract.theta * (a - c)
        if contract.model == "bachelier":
            x = (a - c) / c if c != 0 else mpf(1)
            sd = mpf(sigma) * mpmath.sqrt(mpf(contract.t)) * mpmath.exp(-mpf(contract.r) * mpf(contract.t)) / (abs(c) if c else 1)
        else:
            x = mpmath.log(a / c)
            sd = mpf(sigma) * mpmath.sqrt(mpf(contract.t))
        if abs(x) <= mpf("1e-2") and sd <= mpf("1e-4"):
            return "near_atm_tiny_variance"
        if intrinsic > 0:
            return "deep_itm" if intrinsic >= mpf(value) / 2 else "itm"
    return "otm"
