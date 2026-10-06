# American Greek qualification (#115)

Qualification is in progress on the American integration branch. The runtime
adds estimates with separate per-Greek acceptance; it does not add a certificate.
The [capability](american-greeks.md) defines coordinates, outcomes and exclusions.

## Frozen evidence

Baseline is `a980d1bfdc42a664a2f1bc11cd28263745cb2b98`. The
[protocol](evidence/american-greeks/protocol.md) freezes 46 original-word contracts,
five quantities, primary/loose absolute targets and initial/refined numerical
configurations. All 40 #114 cases remain, including cash and exercise events,
signed coefficients, zero-volatility segments and deterministic boundaries.
The additions cover expiry kinks, deep exercise, near-exercise stocks, the
no-early-exercise call reduction and valuation Bermudan rights.

Independent references use mpmath 1.3.0 at 80/160 digits and original Gaussian
quadrature at 256/512/1024 with derivative stencils, parallel parameter families
and fixed-future-event valuation rolls. Of 230 quantity rows, 61 references
resolve at the primary target and 105 at the loose target. These empirical
resolution classifications do not establish a universal error bound.

The [separate canonical campaign](evidence/american-greeks/canonical-addendum.md)
uses QuantLib `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c`, log-grid spline
spatial derivatives and price perturbations at 128/256/512. It resolves 32
primary and 124 loose rows. Canonical agreement never replaces an unresolved
independent reference. The initial finite theta sentinel and irrelevant calendar
round-trip exclusion were corrected; earlier raw attempts remain archived.

The [reference manifest](evidence/american-greeks/reference-provenance.json)
links original inputs, protocols, assembled references, raw output and exact
adapter/generator snapshots. Public reproduction needs the optional pinned
QuantLib build and mpmath environment; public builds/CI read committed evidence
and need no private research access.

## Runtime, compatibility and cost

Final runtime scoring, complete existing-price replay, full local checks,
compiled mutation witnesses and controlled cost characterization are pending.
This document will record their exact revisions and outcomes before the PR lands.
