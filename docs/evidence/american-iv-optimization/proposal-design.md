# Safeguarded inverse proposals

Written after baseline profiling and before runtime edits. Original baseline
Memprof samples attribute 50.3% of put allocation to stencil preparation and
36.0% to slab work. Cash-call samples attribute 54.8% to cash interpolation,
19.7% to stencil preparation and 13.8% to slab work. The put CPU sample's largest
leaf is the slab solver (367 samples versus 37 in the native residual kernel).
Both inverses perform nine prices. These sampled attributions are diagnostics,
not exact allocation accounting or universal workload shares.

A stencil depends on sigma; a cash interpolation applies to a candidate-specific
value vector. Reusing their solved values would change the problem. The existing
Greek boundary pool is disabled for these constant American put/call shapes,
and boundary arithmetic is only 2.6%/1.1% of sampled allocation. Start with
fewer full price evaluations; retain unchanged price kernels and no new cache.

For current strict opposite-sign observations (a,Pa),(b,Pb), form positive point
price gaps L=quote-Pa and R=Pb-quote. Scale both by max(L,R), then use weight
(L/scale)/((L/scale)+(R/scale)). This avoids overflow in L+R. Propose the binary64
point a+(b-a)*weight only when every intermediate is finite and it lies strictly
inside (a,b). This is only an affine interpolation guess, not a bound or a vega
estimate. Invalid, flat, collapsed or endpoint proposals fall back to the existing
representable midpoint. Every third main proposal is a midpoint regardless of
interpolation history; unbounded regula-falsi stagnation cannot occur. Existing
maximum attempted price calls remain an independent termination bound.

A price observation changes a bracket only through the original full uncertainty
band's strict sign. Price failures remain failures. Initial financial/capability
checks, endpoint evaluation, observed monotonicity checks and full-width success
are unchanged. There is no residual-based root acceptance and no strictness,
uniqueness or nearest-even claim.

At the first quote-overlapping interior observation only, try two local points
at candidate sigma plus/minus requested_width/4, provided both are representable
and strictly inside their respective halves. The nominal total span is half the
requested width, leaving room for rounding; this does not bypass the owner's
outward full-width check. Each point is priced independently and checked against
its neighboring observations. Strict signs may tighten the bracket; overlapping
bands never become endpoints. If these probes cannot improve it, use the original
quarter-probe fallback. Attempt this local pair at most once per request, so a
hard/flat case incurs at most two speculative price calls. No local interval is
accepted merely because it surrounds the interpolated guess.

Every recursion retains ordered strict opposite endpoints or reports failure.
All new sigmas come through the existing typed constructor. Ordinary proposal
rounding is allowed because proposal placement defines no mathematical claim;
acceptance comparisons still use outward arithmetic and the original exact
quote. The midpoint phase and fallback give progress when strict signs are
available; otherwise explicit uncertainty, representability or budget failures
remain. No callback exception is converted to a numerical outcome. Bounds and
work partitions cover all attempted probes, including failed speculative calls.

Estimated endpoints and evaluation counts intentionally change. Requalify their
independent containment and all success/failure guards. Price/Greek/European
operations themselves remain unchanged; no historical exact inverse bits are a
compatibility promise for this intentional estimated-search improvement.

## Rejected first candidate and endpoint safeguard

The first candidate preserves 24/6 initial and 30/0 refined/tight corpus outcomes,
but the tight benchmark cases take 22/6/14 evaluations (analytical/put/cash),
versus 9 each before. It is rejected before timing: the analytical and cash
work counts would defeat the frozen adoption criteria. Near a strict endpoint,
point interpolation can repeatedly improve its location without reducing the
full interval; price uncertainty is not required to trigger this stagnation.

Before a second runtime edit, add a placement safeguard: clip a finite secant
proposal to stay at least min(width/4, bracket_span/4) from either endpoint,
provided the clipped point remains strictly interior. A proposal closer than
this margin spends a full price evaluation improving an already-sufficient
endpoint precision while the opposite side still determines acceptance. The
margin requests a useful opposite-side probe without assuming its sign.
It is a placement heuristic, never a new accuracy threshold: unchanged outward
width and full-band signs remain authoritative. Invalid/collapsed placements
use the midpoint. Every third main proposal and bounded overlap fallback remain.
The first candidate's runtime commit and complete corpus logs are retained;
no quote, price tolerance, grid, requested width or adoption target changes.
