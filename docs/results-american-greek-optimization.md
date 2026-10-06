# Scalar Greek allocation and residual optimization (#119)

The Greek owner now reuses validated boundary arithmetic across volatility
perturbations, while preserving per-price diagnostics, work, failures and
request-owned storage. Rate shifts discard the shared cache. The
[derivation](evidence/american-greek-optimization/reuse-design.md) specifies the
fixed inputs, original slab keys, arithmetic-indicator replay and byte charges.
No operator, factor, interior solution or exercise decision is reused across
prices. A bounded native residual kernel also executes the original arithmetic
graph with separately rounded products, explicit FMAs and unchanged finite
checks. Its [operation and safety argument](evidence/american-greek-optimization/native-residual-design.md)
covers borrowing, block bounds, callback ordering and failure accounting.
[Greek capability and uncertainty](american-greeks.md) are unchanged.

## Frozen comparison and attribution

The [protocol](evidence/american-greek-optimization/protocol.md) was committed
before profiling or runtime changes. Baseline is the #115 implementation on
integration at `169c4b367f9a186973768a218668e38dadfc0794`; its tree equals PR #138
head `1122699`. Every measured baseline source hash matches the retained #115
release binaries built at `09cde8d`. The baseline profile was collected before
rebasing the protocol-only commit onto that identical integration tree; the
source-identity record preserves both revisions.

Baseline Memprof samples attribute about 61.0% of varying no-cash all-five
allocation and 49.8% with cash to boundary exponentials; stencil preparation is
24.5% and 14.5%. Sampling uses rate 0.0001 and depth 32 around the unchanged
benchmark's two calls. Profiler-inflated counters/times are not acceptance
measurements. Boundary-only candidate allocation profiles and CPU samples
are retained too;
the latter overlapped correctness replay and are not controlled timing evidence.

Only successful boundary values and their individual arithmetic indicators
cross compatible solves. Each receiving context rechecks its allowance and
reconstructs its own maximum. Immutable rate/yield objects and original slab
partitions must match. Volatility does not enter these boundary formulas. The
cache consumes existing surplus, charging 16 bytes per index plus bounded
headers; stencil storage from a completed price is released. A mismatched
shift discards old storage before allocating another cache, so simultaneous
retained caches cannot spend the same allowance twice.

## Numerical and operational checks

Candidate `e9f5cb9` is identified by the source and binary manifests in the
retained evidence. Qualification preserves **all 572 complete historical price
outcomes and all 920 requested Greek rows**, with identical independent and
supplementary canonical classifications.
Every base and perturbed price, error/diagnostic field, work count and refusal
is compared with the baseline. The instrumented baseline consumer links the
unchanged installed #115 library; both drivers serialize complete public
outcomes with sharing-independent snapshots. Original #115 printed rows also
agree, so the instrumented comparison does not replace prior evidence.

Refined loose still returns 153 estimates (80 independent passes and 73
unresolved independent references) and 77 declined quantities. The separate
canonical comparison still supports 110 estimates. Strict-target failures,
reference gaps and estimated-only assurance are preserved.

Development/release ordinary suites and formatting pass. Focused native and
bytecode checks compare identified perturbation prices to cold public requests,
complete outcomes in both quantity orders, a derived cache-disabled workspace,
input ownership and cancellation. The cold-price comparison excludes only the
additional observer row visits; full campaign snapshots retain work fields.

**Twelve affected compiled mutants were killed after a clean baseline:** missing
cross-shift input identity, missing arithmetic-indicator replay, original
slab/next-right and upper-stock keys, stencil key/ownership, coefficient changes,
slab matrix preparation, all-level parallel shifts and one-sided kink checks.
Two of these twelve faults remove an explicit residual FMA and halve its
roundoff screen. The catalog now contains 130 mechanisms; the default seven
core mutants and
five PR CI jobs are unchanged.

Native and bytecode residual controls independently execute the former OCaml
operation graph on ordinary and adversarial arrays, subnormals, signed zeros,
non-finite values and overflow. They compare intermediate failure state, first
worst-row selection and exact indicators across block sizes 1/7/255/256, check
borrowed input preservation, and reject malformed shapes/ranges. All 54 public
work traces match complete outcomes and callback counts around
row-budget and cancellation boundaries against the unchanged installed baseline,
in both native and bytecode clients. The initial bytecode harness omitted the
stub loader path; that setup failure and its correction are retained. Local
arm64 object inspection shows three explicit fused operations per residual and
separate products/additions for the roundoff screen. The object hash and
disassembly accompany the source/build manifests.

## Controlled performance

The first complete 90-process boundary-only campaign **failed** the unchanged
latency criterion: piecewise all-five fell from 8.620 to 8.259 seconds (4.2%)
and cash from 5.236 to 5.074 seconds (3.1%). Allocation fell 29.3% and 23.8%.
Its source/build manifests, complete replay and every sample remain retained.
CPU evidence motivated the residual operation-graph experiment; neither
acceptance limits nor numerical targets changed.

The final 90-process campaign passes all frozen criteria. Five alternating
fresh-process pairs per model/request use the unchanged 128/128 driver, one
warmup and one measured call, release OCaml 5.3.0 Flambda on an Apple M1 Pro
(10 CPUs), macOS 27.0 arm64. All owned builds, tests, references and profiles
finished before timing. Every complete outcome digest and base price agrees.
Values below are medians; MB means decimal cumulative allocation, not live
workspace or RSS.

| Workload | Request | Baseline ms | Candidate ms | Latency change | Baseline MB | Candidate MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| constant | price | 129.5 | 104.2 | -19.54% | 12.909 | 12.911 |
| constant | spatial | 130.1 | 103.5 | -20.50% | 13.089 | 13.091 |
| constant | all | 1,705.2 | 1,348.6 | -20.91% | 170.180 | 170.206 |
| piecewise | price | 671.9 | 543.2 | -19.17% | 127.025 | 127.027 |
| piecewise | spatial | 676.6 | 547.4 | -19.09% | 127.205 | 127.207 |
| piecewise | all | 8,771.5 | 6,836.2 | -22.06% | 1,653.811 | 1,168.689 |
| cash | price | 409.1 | 334.2 | -18.30% | 87.051 | 87.053 |
| cash | spatial | 408.8 | 335.4 | -17.96% | 87.283 | 87.285 |
| cash | all | 5,336.1 | 4,171.9 | -21.82% | 1,134.716 | 864.927 |

Both varying all-five workloads exceed the required 20% allocation and 10%
latency reductions: **29.33% / 22.06%** without cash and **23.78% / 21.82%**
with cash. Every simpler control passes its 5% allocation / 10% latency
regression ceiling. Constant all-five allocation rises only 26,032 bytes
(0.016%); the fixed residual wrapper is retained per solver, not per row.
Constant requests still decline delta at the frozen conservative screen:
spatial gives 2/3 estimates and all-five 4/5, while varying workloads give all
requested estimates. These are request costs, not five certified outputs.

Shared-host one-minute load ranged 8.35–66.71; the initial
high preflight load and subsequent decline are retained. Piecewise all-five
baseline samples range 8.760–8.811 seconds and candidate 6.785–6.879 seconds;
cash ranges 5.325–5.351 versus 4.164–4.200 seconds. All raw samples remain
available. This is engineering evidence on a shared machine, not isolated-host
or deployment-tail latency. Candidate per-process peak RSS ranges
7.67–8.86 MB across the nine workloads, separate from cumulative
allocation. Piecewise all-five minor/major collections fall 808/46 → 574/40;
cash falls 567/66 → 437/63.

The separate standalone campaign executes 60 fresh processes after the Greek
campaign, five alternating pairs for each American/Bermudan/piecewise cash/no-cash
price. Each process warms once and measures three calls. All six pass the
predeclared 5% allocation / 10% latency regression limits:

| Family | Cash | Baseline ms | Candidate ms | Latency change | Allocation change |
| --- | --- | ---: | ---: | ---: | ---: |
| american | none | 129.8 | 103.4 | -20.34% | +0.0156% |
| american | cash | 375.3 | 300.2 | -20.00% | +0.0062% |
| bermudan | none | 265.5 | 207.8 | -21.75% | +0.0050% |
| bermudan | cash | 388.5 | 305.3 | -21.42% | +0.0041% |
| piecewise | none | 676.8 | 539.8 | -20.23% | +0.0011% |
| piecewise | cash | 407.9 | 329.9 | -19.11% | +0.0027% |

## Decision and remaining scope

Adopt bounded boundary reuse and the operation-preserving residual kernel for
this measured scalar workload. No additional dependency or approximate
transcendental is introduced; the native code is original project work under
the existing license. Kernel finite-state controls, complete replay and
compiled faults support this change over their exercised domains, not a proof
for every admitted floating-point input.

The remaining **1.169 GB / 0.865 GB** of cumulative allocation per varying
all-five request is still substantial. Vega and rho still require six perturbed
prices each. This pass does not establish an acceptable deployment budget or
finish #119. Differentiated methods need their own derivation, kink/event and
independent-reference qualification; compiled workloads, tridiagonal backend
comparisons, alternative-engine evaluation and deployment acceptance remain
separate open work. #120 owns final source-artifact/multiplatform qualification.

The [evidence index](evidence/american-greek-optimization/README.md) identifies
original profiles, failed attempts, complete snapshots, validation, manifests
and reproducible collectors. The [archive](evidence/american-greek-optimization/raw-evidence.tar.gz)
has a [SHA-256 and size record](evidence/american-greek-optimization/archive.json)
and an internal manifest checked against every payload.
