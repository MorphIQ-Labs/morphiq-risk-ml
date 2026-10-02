#!/usr/bin/env python3
"""Greek references, this project's own: two independent routes per value.

Route 1 is the closed form, written directly in mpmath.
Route 2 differentiates the mpmath price itself with mpmath.diff, including
the mixed and third-order partials. A value is resolved only when the
routes agree to 1e-25 relative (or absolutely, against the contract's scale,
for a value near zero). The reference is route 1 refined until two
precisions round alike (common.agreed).

Conventions (docs/model-contracts.md):
- time Greeks are -d/dT / 365;
- vega is per unit volatility in the model's coordinate;
- forward models' rho is d/dr with the forward fixed (-T V).

At expiry and at zero variance the contract defines the limits. The
reference gives those values, or `kink` where the payoff has one.

Output lines:
  <model> <side> <greek> <status> <s> <k> <t> <r> <q> <sigma> <shift> <reference>
status: resolved | below_binary64 | above_binary64 | kink | unresolved
"""
import math
import random
import sys

import mpmath
from mpmath import mp, mpf

from common import Contract, agreed, bits, ncdf

GREEKS = ("delta", "gamma", "theta", "vega", "rho", "vanna", "volga", "charm", "veta", "color")
NAN = bits(math.nan)
DAY = 365


def closed_form(c, sigma):
    """Route 1, at the current precision."""
    th = c.theta
    t, r, sig = mpf(c.t), mpf(c.r), mpf(sigma)
    rt = mpmath.sqrt(t)
    disc = mpmath.exp(-r * t)
    if c.model == "bachelier":
        sd = sig * rt
        d = (mpf(c.s) - mpf(c.k)) / sd
        dens = disc * mpmath.npdf(d)
        delta = th * disc * ncdf(th * d)
        gamma = dens / sd
        vega = dens * rt
        price = c.price(sigma)
        return dict(delta=delta, gamma=gamma, theta=(r * price - dens * sig / (2 * rt)) / DAY, vega=vega,
                    rho=-t * price, vanna=-dens * d / sig, volga=vega * d * d / sig,
                    charm=(r * delta + dens * d / (2 * t)) / DAY, veta=vega * (r - (1 + d * d) / (2 * t)) / DAY,
                    color=gamma * (r + (1 - d * d) / (2 * t)) / DAY)
    s, k = mpf(c.s) + mpf(c.shift), mpf(c.k) + mpf(c.shift)
    q = mpf(c.q) if c.model == "bsm" else r
    dq = mpmath.exp(-q * t)
    a, cc = s * dq, k * disc
    sd = sig * rt
    x = mpmath.log(s / k) + (r - q) * t
    d1 = x / sd + sd / 2
    d2 = d1 - sd
    n1 = mpmath.npdf(d1)
    delta = th * dq * ncdf(th * d1)
    gamma = dq * n1 / (s * sd)
    vega = a * n1 * rt
    theta = th * (q * a * ncdf(th * d1) - r * cc * ncdf(th * d2)) - a * n1 * sig / (2 * rt)
    rho = th * cc * t * ncdf(th * d2) if c.model == "bsm" else -t * c.price(sigma)
    dd1 = (2 * (r - q) * t - d2 * sd) / (2 * t * sd)
    return dict(delta=delta, gamma=gamma, theta=theta / DAY, vega=vega, rho=rho,
                vanna=-dq * n1 * d2 / sig, volga=vega * d1 * d2 / sig,
                charm=(q * delta - dq * n1 * dd1) / DAY, veta=vega * (q + d1 * dd1 - 1 / (2 * t)) / DAY,
                color=gamma * (q + d1 * dd1 + 1 / (2 * t)) / DAY)


def differentiated(c, sigma):
    """Route 2: partial derivatives of the mpmath price, at the current precision."""
    s0, t0, r0, v0 = mpf(c.s), mpf(c.t), mpf(c.r), mpf(sigma)
    V = lambda s, v, t, r: c.price(v, t=t, r=r, s=s)
    d = lambda orders: mpmath.diff(lambda s, v, t: V(s, v, t, r0), (s0, v0, t0), orders)
    return dict(delta=d((1, 0, 0)), gamma=d((2, 0, 0)), theta=-d((0, 0, 1)) / DAY, vega=d((0, 1, 0)),
                rho=mpmath.diff(lambda r: V(s0, v0, t0, r), r0), vanna=d((1, 1, 0)), volga=d((0, 2, 0)),
                charm=-d((1, 0, 1)) / DAY, veta=-d((0, 1, 1)) / DAY, color=-d((2, 0, 1)) / DAY)


def limits(c, sigma):
    """The contract's values at expiry and at zero variance (docs/model-contracts.md)."""
    th = c.theta
    if c.t == 0:
        if c.s == c.k:
            return dict(delta="kink", gamma="kink", theta="kink", vega=0.0, rho=0.0, vanna="kink",
                        volga=0.0, charm="kink", veta="kink", color="kink")
        itm = th * (c.s - c.k) > 0
        q = c.q if c.model == "bsm" else c.r
        with mp.workdps(80):
            theta = th * (mpf(q) * mpf(c.s) - mpf(c.r) * mpf(c.k)) / DAY if itm else 0
            charm = th * mpf(q) / DAY if itm else 0
        return dict(delta=float(th) if itm else 0.0, gamma=0.0, theta=theta, vega=0.0, rho=0.0, vanna=0.0,
                    volga=0.0, charm=charm, veta=0.0, color=0.0)
    return None  # zero variance at T > 0: scored only off the forward, below


def rows(c, sigma):
    """(greek, status, reference) for one contract."""
    lim = limits(c, sigma)
    if lim is not None:
        for g in GREEKS:
            v = lim[g]
            if v == "kink":
                yield g, "kink", None
            else:
                yield g, "resolved", float(mpmath.mpf(v)) if not isinstance(v, float) else v
        return
    if sigma == 0:
        return  # zero-variance limits are covered by test/consistency.ml and the price oracle
    extra = c.digits(sigma)
    with mp.workdps(60 + extra):
        one = closed_form(c, sigma)
        two = differentiated(c, sigma)
        scale = abs(c.price(sigma)) + abs(mpf(c.s)) + abs(mpf(c.k))
    for g in GREEKS:
        a, b = one[g], two[g]
        tol = mpf(10) ** -25 * max(abs(a), mpf(10) ** -30 * scale)
        if abs(a - b) > tol:
            yield g, "unresolved", None
            continue
        ref = agreed(lambda: closed_form(c, sigma)[g], extra)
        if ref is None:
            yield g, "unresolved", None
        elif ref == 0.0 and a != 0:
            yield g, "below_binary64", 0.0
        elif math.isinf(ref):
            yield g, "above_binary64", None
        else:
            yield g, "resolved", ref


def catalog(rng):
    for model in ("bsm", "black76", "displaced", "bachelier"):
        for m in (-5.0, -1.0, -0.1, -1e-3, 0.0, 1e-3, 0.1, 1.0, 5.0):
            for t in (0.0, 1e-6, 1 / 365, 0.25, 1.0, 5.0, 30.0):
                for sigma in (1e-4, 0.05, 0.2, 0.8, 3.0):
                    for r, q in ((0.02, 0.02), (0.05, 0.01)):
                        for call in (True, False):
                            if model == "bachelier":
                                yield Contract(model, call, 0.01 + m * 0.01, 0.01, t, r), sigma * 0.01
                            elif model == "displaced":
                                yield Contract(model, call, 0.03 * math.exp(m) - 0.02, 0.01, t, r, 0.0, 0.02), sigma
                            else:
                                yield Contract(model, call, 100.0 * math.exp(m), 100.0, t, r, q), sigma
    for _ in range(400):
        call = rng.random() < 0.5
        t = math.exp(rng.uniform(math.log(1e-3), math.log(10.0)))
        sigma = math.exp(rng.uniform(math.log(0.01), math.log(1.5)))
        s = math.exp(rng.uniform(math.log(1.0), math.log(1000.0)))
        k = s * math.exp(rng.gauss(0.0, 1.0) * sigma * math.sqrt(t) * 1.5)
        r, q = rng.uniform(-0.02, 0.08), rng.uniform(-0.02, 0.08)
        yield Contract("bsm", call, s, k, t, r, q), sigma
        yield Contract("black76", call, s, k, t, r), sigma
        yield Contract("displaced", call, rng.uniform(-0.01, 0.06), rng.uniform(-0.01, 0.06), t, r, 0.0, 0.02), sigma
        yield Contract("bachelier", call, rng.uniform(-0.05, 0.1), rng.uniform(-0.05, 0.1), t, r), sigma * 0.01


def main(out):
    rng = random.Random(20261005)
    counts = {}
    with open(out, "w") as w:
        w.write(f"# morphiq-risk-ml Greek oracle (closed form vs mpmath.diff), mpmath {mpmath.__version__}\n")
        for c, sigma in catalog(rng):
            for g, status, ref in rows(c, sigma):
                counts[status] = counts.get(status, 0) + 1
                fields = [c.model, "call" if c.call else "put", g, status]
                fields += [bits(v) for v in (c.s, c.k, c.t, c.r, c.q, sigma, c.shift)]
                fields.append(bits(ref) if ref is not None else NAN)
                w.write(" ".join(fields) + "\n")
    print(counts, file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
