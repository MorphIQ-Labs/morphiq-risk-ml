#!/usr/bin/env python3
"""Implied-volatility references: this project's own, for all four models.

For each contract the quote is its exact price at σ, correctly rounded.
The quote is then taken as an exact number (docs/model-contracts.md) and
classified:

  expiry_not_identifiable        T = 0
  zero_volatility_limit          quote = the exact discounted intrinsic
  rounded_zero_volatility_bound  quote < intrinsic, = its correctly rounded value
  below_exact_intrinsic          quote < intrinsic otherwise
  no_finite_inverse              quote >= the maximum (Black family)
  root                           the exact root σ*, correctly rounded
  root_outside_binary64          σ* above the largest binary64

For a root, the rounding cell [σ_lo, σ_hi] is every σ whose exact price
rounds to the quote: the exact roots at the quote's two rounding midpoints
(0 where a midpoint falls below the intrinsic, inf where it reaches the
maximum). Roots are solved in log σ by the Illinois method to 1e-50
relative, and kept when two precisions round them alike.

Output lines (the scorer's format):
  <model> <side> <status> <param> <s> <k> <t> <r> <q> <sigma> <shift> <quote> <cell_lo> <cell_hi> <root> <nan>
"""
import math
import random
import sys

import mpmath
from mpmath import mp, mpf

from common import Contract, agreed, bits, round_binary64

NAN = bits(math.nan)
INF = bits(math.inf)


def solve(contract, target, dps):
    """The σ with price(σ) = target, at dps digits: Illinois in u = ln σ."""
    with mp.workdps(dps):
        target = mpf(target)
        f = lambda u: contract.price(mpmath.exp(u)) - target
        lo, hi = mpf(-5), mpf(1)
        flo, fhi = f(lo), f(hi)
        for _ in range(4000):
            if flo < 0:
                break
            lo -= 10
            flo = f(lo)
        for _ in range(4000):
            if fhi > 0:
                break
            hi += 2
            fhi = f(hi)
            if hi > 800:
                return mpf("inf")
        # Illinois, with a bisection step whenever an iteration fails to halve
        # the bracket, so convergence is guaranteed; failing to converge is
        # reported (None), never returned as a guess.
        side = 0
        tol = mpf(10) ** (-(dps - 15))
        for _ in range(2000):
            width = hi - lo
            if width <= tol * max(1, abs(lo)):
                return mpmath.exp((lo + hi) / 2)
            u = (lo * fhi - hi * flo) / (fhi - flo)
            if not (lo < u < hi):
                u = (lo + hi) / 2
            fu = f(u)
            if fu == 0:
                return mpmath.exp(u)
            if (fu < 0) == (flo < 0):
                lo, flo = u, fu
                if side == -1:
                    fhi /= 2
                side = -1
            else:
                hi, fhi = u, fu
                if side == 1:
                    flo /= 2
                side = 1
            if hi - lo > width / 2:
                mid = (lo + hi) / 2
                fm = f(mid)
                if fm == 0:
                    return mpmath.exp(mid)
                if (fm < 0) == (flo < 0):
                    lo, flo = mid, fm
                else:
                    hi, fhi = mid, fm
        return None


def root_word(contract, target, extra):
    """The exact root, correctly rounded, if two precisions agree."""
    roots = [solve(contract, target, 60 + extra + 20 * i) for i in (0, 1)]
    if any(r is None for r in roots):
        return None
    words = [round_binary64(r) for r in roots]
    return words[0] if bits(words[0]) == bits(words[1]) else None


def classify(contract, sigma):
    if contract.t == 0:
        q = agreed(lambda: contract.price(sigma))
        return "expiry_not_identifiable", q, NAN, NAN, NAN
    extra = contract.digits(sigma)
    quote = agreed(lambda: contract.price(sigma), extra)
    if quote is None or not math.isfinite(quote):
        return None
    with mp.workdps(120 + extra):
        target = mpf(quote)
        iota = contract.intrinsic()
        maximum = contract.maximum()
        if iota > 0 and target < iota:
            status = "rounded_zero_volatility_bound" if bits(quote) == bits(round_binary64(iota)) else "below_exact_intrinsic"
            return status, quote, NAN, NAN, bits(0.0) if status.startswith("rounded") else NAN
        if target == max(iota, mpf(0)):
            return "zero_volatility_limit", quote, NAN, NAN, bits(0.0)
        if maximum is not None and target >= maximum:
            return "no_finite_inverse", quote, NAN, NAN, NAN
        lower_mid = (target + mpf(math.nextafter(quote, -math.inf))) / 2
        upper_mid = (target + mpf(math.nextafter(quote, math.inf))) / 2
        lower_bound_zero = lower_mid <= max(iota, mpf(0))
        upper_unbounded = maximum is not None and upper_mid >= maximum
    root = root_word(contract, quote, extra)
    if root is None:
        return None
    if root == math.inf:
        return "root_outside_binary64", quote, NAN, NAN, INF
    lo = bits(0.0) if lower_bound_zero else (lambda w: bits(w) if w is not None else NAN)(root_word(contract, lower_mid, extra))
    hi = INF if upper_unbounded else (lambda w: bits(w) if w is not None else NAN)(root_word(contract, upper_mid, extra))
    return "root", quote, lo, hi, bits(root)


def catalog(rng):
    times = (0.0, 1 / 31536000, 1 / 365, 1 / 12, 1.0, 5.0, 30.0)
    sigmas = (0.0, 1e-6, 0.01, 0.2, 1.0, 5.0)
    for model in ("bsm", "black76", "displaced"):
        shift = 2.0 if model == "displaced" else 0.0
        for x in (-20.0, -2.0, -0.1, 0.0, 0.1, 2.0, 20.0):
            for t in times:
                for sigma in sigmas:
                    for call in (True, False):
                        yield Contract(model, call, math.exp(x) - shift, 1.0 - shift, t, 0.02, 0.02, shift), sigma
    for distance in (-2.0, -0.1, -2**-20, 0.0, 2**-20, 0.1, 2.0):
        for t in times:
            for sigma in (0.0, 1e-8, 1e-3, 0.2, 5.0):
                for call in (True, False):
                    yield Contract("bachelier", call, distance, 0.0, t, 0.02), sigma
    for _ in range(1500):
        call = rng.random() < 0.5
        t = math.exp(rng.uniform(math.log(1e-3), math.log(10.0)))
        sigma = math.exp(rng.uniform(math.log(1e-3), math.log(2.0)))
        s = math.exp(rng.uniform(math.log(0.01), math.log(100.0)))
        k = s * math.exp(rng.gauss(0.0, 1.0) * sigma * math.sqrt(t) * 2.0)
        r, q = rng.uniform(-0.02, 0.08), rng.uniform(-0.02, 0.08)
        yield Contract("bsm", call, s, k, t, r, q), sigma
        yield Contract("black76", call, s, k, t, r), sigma
        d = rng.uniform(0.005, 0.05)
        yield Contract("displaced", call, rng.uniform(-d / 2, 0.06), rng.uniform(-d / 2, 0.06), t, r, 0.0, d), sigma
        yield Contract("bachelier", call, rng.uniform(-0.05, 0.1), rng.uniform(-0.05, 0.1), t, r), sigma * 0.01


def invalid():
    base = (1.0, 1.0, 1.0, 0.02, 0.01)
    names = ("spot", "strike", "time_to_expiry", "rate", "dividend_yield")
    for model in ("bsm", "black76", "displaced", "bachelier"):
        for i, name in enumerate(names):
            for bad in (math.nan, math.inf, -math.inf):
                p = list(base)
                p[i] = bad
                yield model, name, p


def main(out):
    rng = random.Random(20261004)
    kept = dropped = 0
    with open(out, "w") as w:
        w.write(f"# morphiq-risk-ml implied volatility oracle, mpmath {mpmath.__version__}\n")
        for c, sigma in catalog(rng):
            result = classify(c, sigma)
            if result is None:
                dropped += 1
                continue
            status, quote, lo, hi, root = result
            fields = [c.model, "call" if c.call else "put", status, "-"]
            fields += [bits(v) for v in (c.s, c.k, c.t, c.r, c.q, sigma, c.shift, quote)]
            fields += [lo, hi, root, NAN]
            w.write(" ".join(fields) + "\n")
            kept += 1
        for model, name, p in invalid():
            fields = [model, "call", "invalid_input", name] + [bits(v) for v in p] + [bits(0.2), bits(0.1 if model == "displaced" else 0.0), bits(0.1), NAN, NAN, NAN, NAN]
            w.write(" ".join(fields) + "\n")
    print(f"kept {kept}, dropped {dropped}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
