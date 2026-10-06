# Greek cost protocol

Frozen before timing at candidate `09cde8d056ad8ee2dd5ef8ca70ef2158e68b7319`,
against baseline `a980d1bfdc42a664a2f1bc11cd28263745cb2b98`.

Existing standalone price workloads: American, Bermudan and piecewise, each
with/without cash. Five fresh-process paired rounds, alternating order; one
warmup and three measured calls. Require median cumulative allocation no more
than 1.05 times baseline and median latency no more than 1.10 times baseline
for every workload. Drivers and compiler must match. The archived wrapper
adapts the previous piecewise optimization collector's criteria to these
regression limits; its exact source and hash are retained.

New Greek API: `scripts/benchmark_american_greeks.py`, five fresh-process rounds
for constant, piecewise and cash models, alternating price/spatial/all order.
One warmup and one measured call per process. Record full outcome digests,
estimate/unavailable/rejection counts, GC, cumulative bytes, child peak RSS,
load, compiler, source and executable hashes. Price must agree across requests.
This is cost characterization with no invented deployment target.

Complete all owned builds, tests and reference work before timing; run the two
campaigns sequentially. The host remains shared. Retain all attempts, including
failures, and do not mistake cumulative allocation for live memory.
