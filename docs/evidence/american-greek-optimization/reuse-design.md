# Request-owned boundary reuse derivation

Baseline Memprof samples of the unchanged all-five driver attribute 61.0% of
piecewise and 49.8% of cash sampled allocation to zero/top boundary exponentials;
stencil preparation is 24.5%/14.5%. Constant coefficients have a different
profile. Sampling is separate from acceptance timing. Each profiled driver run
includes its warmup and measured calls; profiler-inflated allocation counters
and elapsed times are not unprofiled measurements.

For a fixed contract, side and configuration, the zero-stock boundary is a
function of the original rate curve, permitted future exercise instants and
strike. The upper-stock cap uses the original rate curve for puts or yield
curve for calls, the original expiry and top/strike. Neither boundary depends
on volatility or on interior policy iterates. Cash amounts and ordering,
coefficient knots, exercise rights and the spatial/time grids remain fixed
under this API's parallel volatility shifts. Slab/time-index identities retain
original endpoint words, next exercise right, time-step count and upper stock;
a rounded intermediate time is not a cache key.

The Greek owner optionally retains one boundary cache. Before sharing it, it
checks original scalar rate/yield words and physical identity of the immutable
rate/yield curves and slab partition. `shift_greek` changes only the selected
coefficient, preserving the other admitted contract and event objects. A rate
shift fails this guard; discard the shared cache before running that price.
This also makes request order safe and avoids retaining an old cache while an
incompatible solve spends the same surplus on another one. No matrix, factor,
spatial bands, interior solution or exercise classification crosses a price.

A reusable slot holds both the successful finite value and its original
arithmetic indicator. On each hit, the receiving context rechecks its local
allowance and updates its own maximum boundary indicator. Successful previous
arithmetic does not transfer an entire price's diagnostics: cash mapping and
other boundary work still execute normally. Only successful slots are stored;
NaN marks empty private storage, never a public numerical result. Thus original
arithmetic order/results are reused, rather than replaced by a recurrence,
rounded exponent or library approximation. Logical step/row visits and their
cancellation checkpoints are unchanged.

The existing price reservation covers live solver arrays and metadata. Reuse
spends only the same surplus workspace. A reusable entry is charged 256 bytes
of headers/keys plus 16 bytes per time index (value and error); ordinary price
entries keep the original 8-byte payload. The fixed header charge covers the
key/list/entry/slot records, boxed original words/options and array headers on
the supported 64-bit runtime. Boundary entries maintain their own byte total;
at a later price, previous stencil snapshots are unreachable and their charge
is released. Within a price, stencil charges still consume the same remaining
surplus. Insufficient room leaves the original evaluator active, including
failure semantics. The cache is inaccessible outside one Greek invocation.

Qualification compares identified perturbation prices against cold public
requests, excluding only the explicitly additional observer row visits. It also
compares complete Greek outcomes across request ordering and a derived
cache-disabled workspace budget, checks input ownership and cancellation, and
challenges missing rate identity and lost arithmetic indicators with compiled
faults. Full historical output/row-count replay and independent reference
scoring remain separate obligations in the frozen protocol.
