"""Independent qualification reference with retained currency-tail resolution."""
from fractions import Fraction
import math
from exchange_reference import value, PRECISIONS, QUADRATURE


def reference(row):
    from flint import arb, acb, ctx
    p = {k: value(v) for k, v in row['inputs'].items()}
    if (any(not math.isfinite(x) for k, x in p.items() if k != 'limit')
        or any(p[k] < 0 for k in ('s1', 's2', 'sigma1', 'sigma2', 'time')) or abs(p['rho']) > 1):
        return dict(status='invalid_input')
    if not math.isfinite(p['limit']) or p['limit'] < 0:
        return dict(status='invalid_accuracy')
    f = {k: Fraction(x) for k, x in p.items()}
    v = f['time'] * ((f['sigma1']-f['sigma2'])**2 + 2*f['sigma1']*f['sigma2']*(1-f['rho']))
    def ball(q):
        return arb(q.numerator) / arb(q.denominator)
    attempts = []
    for precision in PRECISIONS:
        ctx.prec = precision
        try:
            t = ball(f['time'])
            a = ball(f['s1']) * (-ball(f['q1'])*t).exp()
            b = ball(f['s2']) * (-ball(f['q2'])*t).exp()
            if f['time'] == 0:
                closed = integral = ball(max(f['s1']-f['s2'], 0))
                route = 'exact-expiry'
            elif f['s1'] == 0:
                closed = integral = arb(0)
                route = 'exact-zero-receive'
            elif f['s2'] == 0 or v == 0:
                delta = a-b
                if f['s1'] == f['s2'] and f['q1'] == f['q2']:
                    closed = integral = arb(0)
                elif delta >= 0:
                    closed = integral = delta
                elif delta <= 0:
                    closed = integral = arb(0)
                else:
                    raise ValueError('unresolved deterministic sign')
                route = 'independent-discount-boundary'
            else:
                variance = ball(v)
                s = variance.sqrt()
                log_ratio = (ball(f['s1'])/ball(f['s2'])).log() + (ball(f['q2'])-ball(f['q1']))*t
                d1 = log_ratio/s+s/2
                d2 = d1-s
                phi = lambda z: (-z/arb(2).sqrt()).erfc()/2
                closed = a*phi(d1)-b*phi(d2)
                norm = (2*arb.pi()).sqrt()
                def mills_tail(x):
                    return (-x*x/2).exp()/(x*norm)
                if v >= 6400:
                    deficit = (a+b)*mills_tail(arb(40))
                    integral = a+arb(0,deficit.upper())
                    route = 'payoff-deficit-Mills-bound'
                elif -d1 >= 42:
                    integral = arb(0,(a*mills_tail(arb(42))).upper())
                    route = 'positive-payoff-Mills-bound'
                else:
                    # Entire integrand; max() is NEVER passed to analytic quadrature.
                    z0 = (-log_ratio+variance/2)/s
                    L = s.upper()+math.ceil(math.sqrt(2*precision))
                    lo, hi = max(z0.lower(), -L), min(z0.upper(), L)
                    start = max(-L, min(z0.upper(), L))
                    norm = (2*arb.pi()).sqrt()
                    def positive_branch(z, analytic):
                        return ((-variance/2+s*z).exp()-b/a)*(-z*z/2).exp()/norm
                    integral = acb.integral(positive_branch, start, L,
                        rel_tol=arb(2)**(-min(precision//2,1280)), abs_tol=arb(2)**(-min(precision//2,1280)), **QUADRATURE).real * a
                    strip = arb(0)
                    if hi > lo:
                        strip = (hi-lo)*a*(-variance/2+s*hi).exp()/norm
                    def mills_tail(x):
                        return (-x*x/2).exp()/(x*norm)
                    tail = a*(mills_tail(L-s)+mills_tail(L+s))
                    integral += arb(0, (strip+tail).upper())
                    route = 'positive-payoff-quadrature'
            if not closed.is_finite() or not integral.is_finite():
                raise ValueError('nonfinite reference')
            if not closed.overlaps(integral):
                return dict(status='route_disagreement', precision=precision,
                            closed=closed.str(1400, more=True), integral=integral.str(1400, more=True))
            # A reference goal, not a runtime certificate tolerance.
            goal = a.abs_upper() * arb(2)**(-1200)
            if closed.is_zero():
                goal = arb(0)
            if closed.rad() <= goal and integral.rad() <= goal:
                return dict(status='interval', precision=precision, route=route,
                            closed=closed.str(1400, more=True), integral=integral.str(1400, more=True))
            attempts.append(dict(precision=precision, reason='reference width'))
        except (ValueError, OverflowError) as exc:
            attempts.append(dict(precision=precision, reason=str(exc)))
    return dict(status='unresolved', attempts=attempts)
