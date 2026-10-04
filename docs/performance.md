# Performance evidence and limits

## Certified IV baseline

The first runtime-certified IV implementation prioritizes an enforced exact-model
rounding guarantee. Its scalar cost is much larger than the proposal-only solver:
about 4–17 milliseconds per call on this host, versus about 4–8 microseconds.
This is a material regression, not a high-throughput production acceptance.
Both paths used OCaml 5.3.0 with Flambda and `-O3`; changing to a different compiler
is not a response to the measured numerical workload.

[Raw A/B/B/A evidence](evidence/certified-iv-bench.json) records the source hashes,
Apple M1 Pro/macOS host, load averages, batch timing summaries for each run,
allocation/GC fields, sampled request percentiles and all IV outcome counts.
A is `8e3b6ba`; B is the four-word runtime certificate. A and B have different
accuracy guarantees. This measures the cost of the changed contract; it is not
an equal-accuracy algorithm comparison. All 768 cases returned positive roots
in each of the four runs. Separate reference tests establish accuracy.

The range is the pair of run medians. Allocated MB are cumulative allocation
per call (8-byte words on this host), not resident memory.

| Model | Regime | A IV µs/call | B IV ms/call | B allocated MB/call |
| --- | --- | ---: | ---: | ---: |
| bsm | atm | 4.14–5.73 | 6.66–6.70 | 87.9 |
| bsm | otm | 3.72–4.16 | 16.19–16.44 | 214.6 |
| bsm | itm | 3.69–3.70 | 5.64–5.75 | 76.0 |
| black76 | atm | 3.70–3.72 | 5.89–5.99 | 78.7 |
| black76 | otm | 3.70–3.94 | 15.93–16.19 | 212.7 |
| black76 | itm | 3.64–3.80 | 6.17–6.18 | 79.4 |
| displaced | atm | 3.91–4.00 | 6.27–6.39 | 82.6 |
| displaced | otm | 3.69–3.86 | 16.29–16.38 | 216.0 |
| displaced | itm | 3.66–3.67 | 6.02–6.09 | 78.4 |
| bachelier | atm | 6.41–6.84 | 5.30–5.45 | 69.9 |
| bachelier | otm | 7.30–7.78 | 8.85–8.88 | 117.0 |
| bachelier | itm | 7.33–7.34 | 4.47–4.48 | 58.6 |

## Adaptive certificate comparison

The [adaptive enclosure](adaptive-certification.md) comparison uses identical
exact-model IV acceptance on both sides: A is `bd1562d`, the full-only
certificate; B first tries two words and refines unresolved decisions to four.
The [raw A/B/B/A report](evidence/adaptive-iv-bench.json) retains source hashes,
all outcomes and the same measurement fields as the earlier baseline.
All 768 cases succeed in all four runs, and the ordinary suite separately
confirms unchanged rounding and replay. No computational test/profile ran
alongside this measurement; this remains a shared workstation, not an isolated
production host. One-minute load averages were about 2.3–2.6.

| Model | Regime | Full-only ms/call | Adaptive ms/call | Adaptive allocated MB/call |
| --- | --- | ---: | ---: | ---: |
| bsm | atm | 6.66–6.66 | 0.653–0.654 | 9.64 |
| bsm | otm | 16.28–16.39 | 1.020–1.021 | 15.36 |
| bsm | itm | 5.73–5.75 | 0.507–0.509 | 7.52 |
| black76 | atm | 5.98–5.98 | 0.581–0.586 | 8.62 |
| black76 | otm | 16.12–16.36 | 1.009–1.012 | 15.20 |
| black76 | itm | 5.99–5.99 | 0.534–0.536 | 7.89 |
| displaced | atm | 6.26–6.33 | 0.608–0.608 | 9.02 |
| displaced | otm | 16.38–16.44 | 1.024–1.029 | 15.41 |
| displaced | itm | 5.92–6.00 | 0.522–0.524 | 7.75 |
| bachelier | atm | 5.30–5.32 | 0.500–0.502 | 7.34 |
| bachelier | otm | 8.87–8.87 | 0.578–0.582 | 8.67 |
| bachelier | itm | 4.41–4.43 | 0.386–0.387 | 5.66 |

The ranges are pairs of warm-run medians. Allocation is cumulative, not RSS.
The improvement follows less expansion/series work and fewer temporary boxes;
it does not weaken the required certificate. Sub-millisecond scalar calls still
need workload-level assessment before any high-throughput production claim.
Reproduce with the command below, the full-only baseline binary, and
`--baseline-revision bd1562d --same-contract`.

## Reproduction and measurement contract

```sh
opam exec --switch=morphiq-risk-ml -- dune build bench/assurance.exe
python3 scripts/benchmark_assurance.py \
  --baseline /path/to/baseline/assurance.exe --baseline-revision 8e3b6ba \
  --candidate _build/default/bench/assurance.exe \
  --count 64 --runs 5 --output /tmp/iv-bench.json
```

Build both binaries from the same benchmark source and switch. The fixed seed
is in `bench/assurance.ml`. It times admission, price, IV, all Greeks and an
end-to-end admission/price/IV/Greek call separately. Pre-timing IV outcome
validation includes every case; mathematical classes and computational failures
are never dropped from the timing denominator.

Timing uses benchmark-only `CLOCK_MONOTONIC` C code. The public numerical library
has no clock dependency. An empty dispatch/clock row measures overhead without
subtracting it. Small scalar timings and 64-sample request percentiles are
noisy; batch-average ns/op is not request tail latency. Five warm batches follow
the first batch; the latter follows validation and is **not** cold-process latency.

`Gc.counters` supplies current-domain allocated words: minor + major - promoted.
`Gc.quick_stat` supplies sampled collection counts and heap size. Its allocation
counters are delayed until collection on OCaml 5, so they must not be used for
short-batch allocation deltas. A known-allocation control detects that mistake.
CPU time includes GC; this harness does not isolate GC time. Heap samples are
not peak RSS. A shared workstation, load averages and repeated runs do not
establish a quiet-host SLA, cold-start behavior or a production latency distribution.

## Remaining work

A separate two-second, 1 ms sampling run of the 16-case/one-run harness
collected 1,590 main-thread samples. Expansion accumulation (`go`) and TwoSum
accounted for 552 and 364 top-of-stack samples respectively: about 58% together.
This is evidence for reducing expansion work and allocation, rather than a
compiler/build bottleneck. [The profile summary](evidence/certified-iv-profile.json)
retains the exact command, binary/source hashes and top-of-stack counts. The
profiled run is excluded from timing comparisons; it is a short workload sample,
not a complete profile of every pricing regime.

#8 still owns profiling-guided optimization and controlled operational
measurement; #16 owns portfolios and integration overhead. Current evidence
supports investigating expansion arithmetic and allocation, not weakening
rounding acceptance. Any faster path must carry its own rigorous enclosure,
fall back when its bound cannot decide, and preserve all existing successful
reference cases and classifications. A finite observed failure rate does not
establish a universal availability claim. Requirements and economic materiality
must be fixed before institutional acceptance, not fitted to these timings.

The [scalar shadow campaign](results-shadow.md) now supplies cold-process and
per-row latency, cumulative allocation, peak child RSS, exact-input replay and
canonical comparison evidence for the enforced production adapter. Its cost
is material and its synthetic workload is not a production SLA. It does not
replace the historical like-for-like A/B/B/A kernel measurements above.

## Separate GC trace

An out-of-process OCaml 5.3 `Runtime_events` reader now profiles the captured
258-row shadow workload separately from ordinary timing. [The retained trace
summary](evidence/shadow-gc-profile.json) has zero lost events and zero unpaired
spans, and the worker's numerical results exactly match the uninstrumented
replay. The reader computes a per-domain union to avoid double-counting nested
minor/major work. Reproduce after building `bench/gc_trace.exe` with:

```sh
python scripts/profile_shadow_gc.py --output /tmp/shadow-gc-profile.json
```

The instrumented whole-worker sample takes about 2.068 seconds. It records
13,797 minor spans totaling 19.04 ms (p99 5.00 us, max 233.88 us), and 13,796
major-work spans totaling 11.28 ms (p99 6.83 us, max 122.33 us). Major-work spans
are incremental slices, not full collection counts. Their per-domain union
is 30.23 ms, about 1.5% of the sampled duration. This includes startup and output
work and is not a per-request pause bound or a service-level guarantee.

The collector spans account for a small fraction of this sample despite the
large cumulative allocation. Together with the earlier expansion/TwoSum profile,
this supports investigating arithmetic/boxing and repeated preparation rather
than assuming stop-the-world GC dominates. Profiling is optional, adds no
pricing-library dependency, and its instrumented time is excluded from the
ordinary throughput/latency evidence.

Timestamp units follow OCaml 5.3's
[runtime event producer](https://github.com/ocaml/ocaml/blob/5.3/runtime/runtime_events.c)
and [platform counter](https://github.com/ocaml/ocaml/blob/5.3/runtime/unix.c):
`caml_time_counter` supplies nanoseconds, using the raw uptime clock on this
macOS build. The reader uses runtime span names rather than interpreting a
collection counter as elapsed time.

## Canonical generated workload and candidate validation

The [720-row canonical qualification](results-canonical-dataset.md) extends the
scalar workload with a pre-scoring frozen grid and nine repetitions. All
7,920 price/Greek certificates and 720 IV rounding cells are independently
checked. Median complete-row latency is 10.46–10.60 ms, with about 155 MB
cumulative allocation per row on its recorded M1 Pro; this is not resident
memory or a deployment SLA. The [0.2.0 dossier](candidate-0.2.0.md) additionally
retains matching numerical replay on all three supported platforms. These
results preserve the earlier kernel comparisons and separate GC profile above.


## Expansion allocation optimization

The [private-buffer optimization](results-certificate-allocation.md) preserves
the enclosure arithmetic and measured value/radius bits. Against `bea4620`,
the paired shared-host exchange runs reduce allocation 65–74% and evaluation
time 14–22%. The four-model IV workload allocates 46–52% less; its smaller
observed timing differences are not deployment guarantees. Full samples,
reference replay, failure outcomes and limits are retained in that report.

## Certified scalar sum optimization

The [measured exact-sum optimization](results-certified-expansion-sums.md) records
price-only, admission and end-to-end costs for all four models, plus portfolio,
Exchange and IV consumer comparisons. The representative BSM price-only median
is 1.022 ms on the recorded shared M1 Pro host; it is a runtime-certified price,
not the fast scalar API or a network request. Bounds and failure contracts are
unchanged. The measurements retain that revision's multi-MB allocation and
roughly millisecond cost; #8 still owns target-environment qualification.

## Packed certification storage

The [allocation optimization](results-certification-allocation.md) reduces
representative certified BSM allocation from 5.71 to 1.31 MB per price and
paired time from 1.005 to 0.890 ms. Minor collections fall from 108 to 24 per
forty-price batch. Other live scalar prices, portfolios and Exchange also
allocate substantially less. IV allocation falls 69–72%, but timing is mixed,
including modest regressions; the report retains this tradeoff and all samples.
Ordinary fast pricing is unchanged, while the existing Black-family fallback
for severe coordinate cancellation uses the optimized enclosure implementation.
Remaining allocation consists mainly of immutable intermediate records and
bounded private buffers. These shared-host results are not an operational SLA.
