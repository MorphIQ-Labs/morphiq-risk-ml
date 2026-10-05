#!/usr/bin/env python3
"""Exact-rational witnesses for #109; not a pricing engine or continuum oracle.

Original project implementation. Policy equations are attributed in the design.
Run from any directory; stdout is deterministic JSON, failed witnesses exit nonzero.
"""
import argparse
from fractions import Fraction as F
from itertools import product
import hashlib
import json
from pathlib import Path


def require(ok, message):
    if not ok:
        raise ValueError(message)


def matvec(a, x):
    return [sum(v * y for v, y in zip(row, x)) for row in a]


def dense_solve(a, b):
    """Independent small-system Gaussian elimination with row pivoting."""
    rows = [list(row) + [v] for row, v in zip(a, b)]
    n = len(b)
    for j in range(n):
        p = max(range(j, n), key=lambda i: abs(rows[i][j]))
        require(rows[p][j] != 0, 'singular matrix')
        rows[j], rows[p] = rows[p], rows[j]
        scale = rows[j][j]
        rows[j] = [v / scale for v in rows[j]]
        for i in range(n):
            if i != j:
                factor = rows[i][j]
                rows[i] = [v - factor * w for v, w in zip(rows[i], rows[j])]
    return [row[-1] for row in rows]


def guarded_thomas(a, b):
    n = len(b)
    for i, row in enumerate(a):
        require(all(v == 0 for j, v in enumerate(row) if abs(j-i) > 1),
                'not tridiagonal')
        require(all(v <= 0 for j, v in enumerate(row) if i != j),
                'positive offdiagonal')
        require(row[i] > sum(abs(v) for j, v in enumerate(row) if i != j),
                'no strict row dominance')
    d = [a[i][i] for i in range(n)]
    rhs = list(b)
    for i in range(1, n):
        require(d[i-1] > 0, 'nonpositive pivot')
        factor = a[i][i-1] / d[i-1]
        d[i] -= factor * a[i-1][i]
        rhs[i] -= factor * rhs[i-1]
    x = [F(0)] * n
    for i in reversed(range(n)):
        require(d[i] > 0, 'nonpositive pivot')
        x[i] = (rhs[i] - (a[i][i+1] * x[i+1] if i+1 < n else 0)) / d[i]
    return x


def policy_system(a, b, g, mask):
    n = len(g)
    return ([list(a[i]) if mask[i] else [F(i == j) for j in range(n)]
             for i in range(n)], [b[i] if mask[i] else g[i] for i in range(n)])


def residual(a, b, g, x):
    p = [v-w for v, w in zip(matvec(a, x), b)]
    h = [v-w for v, w in zip(x, g)]
    return max(abs(min(v, w)) for v, w in zip(p, h))


def policy_solve(a, b, g):
    x = list(g)
    for count in range(1, len(g) + 2):
        p = [v-w for v, w in zip(matvec(a, x), b)]
        mask = tuple(v <= z-w for v, z, w in zip(p, x, g))
        rows, rhs = policy_system(a, b, g, mask)
        x = guarded_thomas(rows, rhs)
        require(x == dense_solve(rows, rhs), 'linear routes disagree')
        if residual(a, b, g, x) == 0:
            return x, count
    raise ValueError('policy cap')


def all_policy_solutions(a, b, g):
    found = set()
    for mask in product((False, True), repeat=len(g)):
        rows, rhs = policy_system(a, b, g, mask)
        x = dense_solve(rows, rhs)
        if residual(a, b, g, x) == 0:
            found.add(tuple(x))
    return found


def coefficients(s, hm, hp, r, q, sigma):
    diffusion = sigma * sigma * s * s / 2
    drift = (r-q) * s
    left = (2 * diffusion - drift * hp) / (hm * (hm+hp))
    right = (2 * diffusion + drift * hm) / (hp * (hm+hp))
    central = left >= 0 and right >= 0
    if not central:
        left = 2 * diffusion / (hm * (hm+hp)) + max(-drift, 0) / hm
        right = 2 * diffusion / (hp * (hm+hp)) + max(drift, 0) / hp
    return left, right, central


def operators(grid, r, q, sigma, dt, theta):
    require(theta * dt * max(-r, 0) <= F(1, 2), 'negative-rate step guard')
    n = len(grid)-2
    a = [[F(0) for _ in range(n)] for _ in range(n)]
    b = [[F(0) for _ in range(n)] for _ in range(n)]
    switches = 0
    for i, s in enumerate(grid[1:-1]):
        lm, lp, central = coefficients(s, s-grid[i], grid[i+2]-s, r, q, sigma)
        switches += not central
        require(lm >= 0 and lp >= 0, 'generator sign')
        # Polynomial actions check consistency independently of the coefficient form.
        require(lm + (-lm-lp-r) + lp == -r, 'constant consistency')
        require(lm*grid[i] + (-lm-lp-r)*s + lp*grid[i+2] == -q*s,
                'linear consistency')
        if central:
            require(lm*grid[i]**2 + (-lm-lp-r)*s**2 + lp*grid[i+2]**2
                    == (sigma*sigma+r-2*q)*s*s, 'quadratic consistency')
        a[i][i] = 1 + theta * dt * (lm+lp+r)
        b[i][i] = 1 - (1-theta) * dt * (lm+lp+r)
        require(b[i][i] >= 0, 'explicit-side positivity')
        if i:
            a[i][i-1] = -theta*dt*lm
            b[i][i-1] = (1-theta)*dt*lm
        if i+1 < n:
            a[i][i+1] = -theta*dt*lp
            b[i][i+1] = (1-theta)*dt*lp
    return a, b, switches


def must_reject(fn, expected):
    try:
        fn()
    except ValueError as error:
        require(str(error) == expected, f'wrong rejection: {error}')
    else:
        raise ValueError(f'missed rejection: {expected}')


def run():
    grids = [list(map(F, (0, 1, 2, 3, 4))),
             [F(0), F(1, 2), F(3, 2), F(3), F(5)]]
    count = switches = largest = 0
    for grid, r, q, sigma, dt, theta in product(
            grids, (F(-1, 4), F(0), F(1, 4)),
            (F(-1, 8), F(0), F(1, 8)),
            (F(0), F(1, 100), F(1, 2)),
            (F(1, 64), F(1, 8)), (F(1), F(1, 2))):
        a, b, n_switch = operators(grid, r, q, sigma, dt, theta)
        switches += n_switch
        for call in (False, True):
            g = [max((s-2) if call else (2-s), F(0)) for s in grid[1:-1]]
            # Arbitrary nonnegative data; these are not option reference prices.
            for previous in (g, [F(0), F(3), F(0)], [F(3), F(0), F(3)]):
                rhs = matvec(b, previous)
                x, iterations = policy_solve(a, rhs, g)
                require(all_policy_solutions(a, rhs, g) == {tuple(x)}, 'LCP not unique')
                require(residual(a, rhs, g, x) == 0, 'LCP residual')
                count += 1
                largest = max(largest, iterations)
    # Deliberately force a policy change after the first exact solve.
    changing = [[F(3), F(-1), F(0)], [F(-1), F(3), F(-1)],
                [F(0), F(-1), F(3)]]
    changing_b, changing_g = list(map(F, (1, 0, 36))), list(map(F, (2, 1, 0)))
    changed_x, changed_count = policy_solve(changing, changing_b, changing_g)
    require(changed_count > 1, 'policy-change witness lost')
    require(all_policy_solutions(changing, changing_b, changing_g) == {tuple(changed_x)},
            'policy-change enumeration disagrees')
    # A post-solve max is not an implicit American LCP solution.
    a = [[F(2), F(-1)], [F(-1), F(2)]]
    b, g = [F(0), F(0)], [F(1), F(0)]
    clipped = [max(x, y) for x, y in zip(dense_solve(a, b), g)]
    exact, _ = policy_solve(a, b, g)
    require(exact == [F(1), F(1, 2)], 'obstacle witness changed')
    require(residual(a, b, g, clipped) == 1, 'clipping failure not detected')
    must_reject(lambda: guarded_thomas([[F(1), F(1)], [F(0), F(1)]], b),
                'positive offdiagonal')
    must_reject(lambda: operators(grids[0], F(-1), F(0), F(0), F(1), F(1)),
                'negative-rate step guard')
    must_reject(lambda: operators(grids[0], F(0), F(0), F(2), F(1), F(1, 2)),
                'explicit-side positivity')
    # A pivoted general solve can succeed outside the specialized kernel's domain.
    pivot_case = [[F(0), F(1)], [F(1), F(1)]]
    require(dense_solve(pivot_case, [F(1), F(2)]) == [F(1), F(1)],
            'pivoted boundary witness')
    must_reject(lambda: guarded_thomas(pivot_case, [F(1), F(2)]),
                'positive offdiagonal')
    perturbed = [exact[0], exact[1] + F(1, 1000)]
    require(residual(a, b, g, perturbed) > 0, 'corrupted solve not detected')
    # Full-domain put cap at r=0 cannot resolve an ATM request at 2^-16*K.
    k, target = F(100), F(100, 65536)
    require(k/2 > target, 'coarse cap unexpectedly informative')
    # Convex interpolation is order preserving; nodes alone do not prove accuracy.
    values = [F(4), F(1)]
    mapped = F(3, 4)*values[0] + F(1, 4)*values[1]
    require(min(values) <= mapped <= max(values), 'interpolation positivity')
    return dict(schema=1, scope='Exact discrete algebra only; no continuum prices, '
                'binary64 qualification, LAPACK execution or timings.',
                script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                lcp_cases=count, policy_masks_per_case=8,
                maximum_grid_case_policy_solves=largest, upwind_rows=switches,
                policy_change_witness_solves=changed_count,
                exact_lcp_crosscheck='all exercise policies via dense pivoted elimination',
                clipping_counterexample=dict(projected=list(map(str, clipped)),
                    solution=list(map(str, exact)), projected_residual='1'),
                rejection_controls=['positive offdiagonal', 'negative-rate step guard',
                                    'explicit-side positivity'],
                coarse_atm_put_bound=dict(lower='0', upper=str(k),
                    midpoint_radius=str(k/2), requested_estimate=str(target)),
                status='pass')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='version', version='american-solver-design 1')
    parser.add_argument('arguments', nargs='*', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.arguments:
        parser.error('unrecognized arguments: ' + ' '.join(args.arguments))
    print(json.dumps(run(), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
